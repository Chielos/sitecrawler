import Foundation

// MARK: — Crawl Events

/// Events the engine emits over its AsyncStream. Consumed by the UI layer.
enum CrawlEvent: Sendable {
    case started(sessionID: UUID)
    case urlDiscovered(url: String, depth: Int)
    case urlFetched(CrawledURL)
    case urlSkipped(url: String, reason: SkipReason)
    case statsUpdated(CrawlStats)
    case checkpointSaved
    case paused
    case resumed
    case completed(stats: CrawlStats)
    case failed(error: String)

    enum SkipReason: String, Sendable {
        case robots = "Blocked by robots.txt"
        case outOfScope = "Out of crawl scope"
        case maxDepth = "Exceeds max depth"
        case maxURLs = "URL limit reached"
        case alreadyCrawled = "Already crawled"
        case contentTypeFiltered = "Content type filtered"
    }
}

// MARK: — Crawl Engine

/// The main crawl actor. Coordinates the frontier, robots cache, fetcher pool,
/// parser, extractor, issue runner, and database writes.
///
/// Progress is published via an `AsyncStream<CrawlEvent>` that the UI subscribes to.
/// All state mutations happen inside actor-isolated methods.
actor CrawlEngine {

    // MARK: — Dependencies

    private let db: DatabaseManager
    private let config: CrawlConfiguration

    private var frontier: URLFrontier!
    private var robotsCache: RobotsCache!
    private var fetcher: Fetcher
    private var rateLimiter: HostRateLimiter
    private var normalizer: URLNormalizer
    private var issueEngine: IssueEngine

    // MARK: — State

    private var sessionID: UUID?
    private var seedURLObjects: [URL] = []
    private var status: CrawlSessionStatus = .idle
    private var stats = CrawlStats()
    private var urlsCrawledThisBatch: Int = 0
    private var crawlStartDate: Date?
    private var isCancelled = false

    private var continuation: AsyncStream<CrawlEvent>.Continuation?

    enum CrawlSessionStatus {
        case idle, running, paused, completed, failed
    }

    // MARK: — Init

    init(db: DatabaseManager, config: CrawlConfiguration) {
        self.db = db
        self.config = config
        self.fetcher = Fetcher(configuration: config)
        self.rateLimiter = HostRateLimiter(requestsPerSecond: config.requestsPerSecondPerHost)
        self.normalizer = URLNormalizer(configuration: config)
        self.issueEngine = IssueEngine()
    }

    // MARK: — Public API

    /// Start a new crawl session for the given project and return the event stream.
    func start(projectID: UUID, seedURLs: [String]) -> AsyncStream<CrawlEvent> {
        let (stream, continuation) = AsyncStream<CrawlEvent>.makeStream()
        self.continuation = continuation

        Task {
            await runCrawl(projectID: projectID, seedURLs: seedURLs)
        }

        return stream
    }

    /// Resume a previously paused or interrupted session.
    func resume(session: CrawlSession) -> AsyncStream<CrawlEvent> {
        let (stream, continuation) = AsyncStream<CrawlEvent>.makeStream()
        self.continuation = continuation

        Task {
            await resumeCrawl(session: session)
        }

        return stream
    }

    func pause() {
        guard status == .running else { return }
        status = .paused
        emit(.paused)
    }

    func cancel() {
        isCancelled = true
        status = .completed
    }

    // MARK: — Core Crawl Loop

    private func runCrawl(projectID: UUID, seedURLs: [String]) async {
        do {
            try await setupSession(projectID: projectID, seedURLs: seedURLs)
            await executeCrawlLoop()
        } catch {
            emit(.failed(error: error.localizedDescription))
            status = .failed
        }
    }

    private func resumeCrawl(session: CrawlSession) async {
        do {
            sessionID = session.id
            stats = session.stats
            frontier = URLFrontier(sessionID: session.id, db: db, normalizer: normalizer)
            robotsCache = RobotsCache(sessionID: session.id, db: db)

            // Restore frontier state from checkpoint
            if let checkpoint = session.frontierCheckpoint {
                await frontier.restore(from: checkpoint)
            }

            // Mark already-crawled URLs as seen to prevent re-fetching
            let alreadyCrawled = try db.fetchURLs(sessionID: session.id, limit: 100_000)
            for u in alreadyCrawled {
                await frontier.markSeen(u.normalizedURL)
            }

            // Parse seed URLs for scope checking
            seedURLObjects = session.seedURLs.compactMap { URL(string: $0) }

            try db.updateSessionStatus(session.id, status: .running)
            emit(.resumed)
            await executeCrawlLoop()
        } catch {
            emit(.failed(error: error.localizedDescription))
        }
    }

    private func setupSession(projectID: UUID, seedURLs: [String]) async throws {
        let id = UUID()
        sessionID = id

        var session = CrawlSession(
            id: id,
            projectID: projectID,
            seedURLs: seedURLs,
            configuration: config
        )
        session.status = .running
        try db.insertSession(session)

        frontier = URLFrontier(sessionID: id, db: db, normalizer: normalizer)
        robotsCache = RobotsCache(sessionID: id, db: db)
        seedURLObjects = seedURLs.compactMap { URL(string: $0) }
        crawlStartDate = Date()

        // Optionally import sitemap.xml at start
        if config.importSitemapAtStart, let firstSeed = seedURLObjects.first {
            await importSitemap(baseURL: firstSeed)
        }

        await frontier.seed(urls: seedURLs, depth: 0)
        emit(.started(sessionID: id))
    }

    private func executeCrawlLoop() async {
        guard let sessionID = sessionID else { return }
        status = .running

        await withTaskGroup(of: Void.self) { group in
            let concurrency = config.maxConcurrentRequests

            for _ in 0..<concurrency {
                group.addTask { [weak self] in
                    await self?.workerLoop()
                }
            }

            await group.waitForAll()
        }

        // Post-crawl aggregate analysis
        await runAggregateIssueChecks(sessionID: sessionID)

        let finalStatus: CrawlSession.Status = isCancelled ? .cancelled : .completed
        try? db.updateSessionStatus(sessionID, status: finalStatus, completedAt: Date())
        stats.crawlRateURLsPerSecond = 0
        emit(.completed(stats: stats))
        status = .completed
        continuation?.finish()
    }

    // MARK: — Worker Loop

    private func workerLoop() async {
        guard let sessionID = sessionID else { return }
        let config = self.config  // local copy to avoid actor hops in tight loop

        while !isCancelled {
            // Pause handling
            while status == .paused && !isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms
            }
            guard !isCancelled else { break }

            // Check URL limit
            if config.maxURLs > 0 && stats.totalURLsCrawled >= config.maxURLs {
                break
            }

            // Dequeue next URL
            guard let pending = await frontier.next() else {
                // No URLs right now — brief backoff then try again
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
                guard await frontier.isEmpty else { continue }
                break
            }

            // Depth check
            if config.maxDepth >= 0 && pending.depth > config.maxDepth {
                emit(.urlSkipped(url: pending.url, reason: .maxDepth))
                continue
            }

            // Scope check
            if let pageURL = URL(string: pending.url) {
                let inScope = seedURLObjects.contains { normalizer.isInScope(pageURL, seedURL: $0) }
                if !inScope {
                    emit(.urlSkipped(url: pending.url, reason: .outOfScope))
                    continue
                }
            }

            // Robots check
            if config.obeyRobots, let pageURL = URL(string: pending.url) {
                let allowed = await robotsCache.isAllowed(pageURL, userAgent: config.userAgent)
                if !allowed {
                    let crawledURL = makeBlockedURL(pending: pending, sessionID: sessionID)
                    try? db.insertCrawledURL(crawledURL)
                    emit(.urlSkipped(url: pending.url, reason: .robots))
                    continue
                }
            }

            // Rate limiting
            if let host = URL(string: pending.url)?.host {
                await rateLimiter.waitAndMark(host: host)
            }

            // Fetch
            let fetchResult = await fetcher.fetch(pending.url)
            let crawledURL = await processFetchResult(fetchResult, pending: pending, sessionID: sessionID)

            // Write to DB
            try? db.insertCrawledURL(crawledURL)

            // Update in-link counts for discovered outlinks
            // (done in batch after crawl to avoid contention)

            // Emit event
            emit(.urlFetched(crawledURL))

            // Update stats
            updateStats(for: crawledURL)
            emit(.statsUpdated(stats))

            // Checkpoint every 500 URLs
            urlsCrawledThisBatch += 1
            if urlsCrawledThisBatch % 500 == 0 {
                let checkpoint = await frontier.checkpoint()
                try? db.saveCheckpoint(sessionID, checkpoint: checkpoint)
                try? db.updateSessionStats(sessionID, stats: stats)
                emit(.checkpointSaved)
            }

            // Run per-URL issue checks
            let issues = issueEngine.evaluate(crawledURL)
            try? db.insertIssues(issues)
        }
    }

    // MARK: — Fetch Result Processing

    private func processFetchResult(
        _ result: Fetcher.FetchResult,
        pending: PendingURL,
        sessionID: UUID
    ) async -> CrawledURL {
        let isInternal = isInternalURL(result.finalURL)
        var crawledURL = CrawledURL(
            sessionID: sessionID,
            url: result.originalURL,
            normalizedURL: pending.normalizedURL,
            discoveredAt: Date(),
            crawlDepth: pending.depth,
            source: .crawl,
            isInternal: isInternal
        )

        crawledURL.fetchedAt = Date()
        crawledURL.statusCode = result.error != nil ? nil : result.statusCode
        crawledURL.contentType = result.contentType
        crawledURL.finalURL = result.finalURL == result.originalURL ? nil : result.finalURL
        crawledURL.redirectChain = result.redirectChain
        crawledURL.responseTimeMs = result.responseTimeMs
        crawledURL.contentSizeBytes = result.contentSizeBytes
        crawledURL.fetchError = result.error

        // Determine indexability from HTTP status
        if let statusCode = crawledURL.statusCode {
            if (400...599).contains(statusCode) {
                crawledURL.isIndexable = false
                crawledURL.indexabilityReason = .httpError
            } else if (300...399).contains(statusCode) {
                crawledURL.isIndexable = false
                crawledURL.indexabilityReason = .redirect
            }
        }
        if result.error != nil {
            crawledURL.isIndexable = false
            crawledURL.indexabilityReason = .httpError
        }

        // Parse HTML if we have a body
        guard let body = result.body,
              let pageURL = URL(string: result.finalURL) else {
            return crawledURL
        }

        // Parse content type
        let ct = result.contentType ?? ""
        guard ct.lowercased().contains("text/html") || ct.lowercased().contains("xhtml") else {
            crawledURL.isIndexable = false
            crawledURL.indexabilityReason = .nonHTMLContent
            return crawledURL
        }

        let parseResult = HTMLParser.parse(html: body, baseURL: pageURL)
        guard let document = parseResult.document else { return crawledURL }

        // Extract SEO signals
        let extraction = ContentExtractor.extract(
            document: document,
            responseHeaders: result.responseHeaders,
            pageURL: pageURL
        )
        apply(extraction: extraction, to: &crawledURL)

        // Determine final indexability from directives
        if crawledURL.robotsDirectives.noindex {
            crawledURL.isIndexable = false
            crawledURL.indexabilityReason = .noindex
        }
        let selfCanonical = crawledURL.canonicalURL == nil ||
            crawledURL.canonicalURL == crawledURL.normalizedURL ||
            crawledURL.canonicalURL == crawledURL.finalURL
        if !selfCanonical {
            crawledURL.isIndexable = false
            crawledURL.indexabilityReason = .canonicalizedElsewhere
        }

        // Feed discovered links into frontier
        let newLinks = parseResult.links.filter {
            $0.tag == .anchor
            && !$0.url.hasPrefix("javascript:")
            && !$0.url.hasPrefix("mailto:")
        }

        var linkRecords: [Link] = []
        var discoveredURLs: [(String, Int)] = []

        for link in newLinks {
            guard let normalized = normalizer.normalize(link.url, relativeTo: pageURL) else { continue }
            let isInt = isInternalURL(normalized.absoluteString)

            linkRecords.append(Link(
                sessionID: sessionID,
                sourceURL: crawledURL.normalizedURL,
                targetURL: normalized.absoluteString,
                anchorText: link.anchorText,
                rel: LinkRel(rawRel: link.rel),
                tagName: .anchor,
                isInternal: isInt
            ))

            if isInt {
                crawledURL.internalOutlinkCount += 1
                discoveredURLs.append((normalized.absoluteString, pending.depth + 1))
            } else {
                crawledURL.externalOutlinkCount += 1
            }
        }

        // Persist link graph
        try? db.insertLinks(linkRecords)

        // Enqueue newly discovered internal URLs
        await frontier.enqueue(urls: discoveredURLs)
        for (url, _) in discoveredURLs {
            emit(.urlDiscovered(url: url, depth: pending.depth + 1))
        }

        return crawledURL
    }

    // MARK: — Helpers

    private func apply(extraction: ContentExtractor.ExtractionResult, to url: inout CrawledURL) {
        url.title = extraction.title
        url.titleLength = extraction.titleLength
        url.metaDescription = extraction.metaDescription
        url.metaDescriptionLength = extraction.metaDescriptionLength
        url.h1 = extraction.h1
        url.h1Count = extraction.h1Count
        url.h2Count = extraction.h2Count
        url.canonicalURL = extraction.canonicalURL
        url.robotsDirectives = extraction.robotsDirectives
        url.hreflangTags = extraction.hreflangTags
        url.openGraphTitle = extraction.openGraphTitle
        url.openGraphDescription = extraction.openGraphDescription
        url.structuredDataTypes = extraction.structuredDataTypes
        url.wordCount = extraction.wordCount
        url.imageCount = extraction.imageCount
        url.contentHash = extraction.contentHash
    }

    private func makeBlockedURL(pending: PendingURL, sessionID: UUID) -> CrawledURL {
        var u = CrawledURL(
            sessionID: sessionID,
            url: pending.url,
            normalizedURL: pending.normalizedURL,
            discoveredAt: Date(),
            crawlDepth: pending.depth,
            source: .crawl,
            isInternal: true
        )
        u.isBlockedByRobots = true
        u.isIndexable = false
        u.indexabilityReason = .blockedByRobots
        return u
    }

    private func isInternalURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return seedURLObjects.contains { normalizer.isInScope(url, seedURL: $0) }
    }

    private func updateStats(for url: CrawledURL) {
        if let status = url.statusCode { stats.record(statusCode: status) }
        else { stats.totalURLsCrawled += 1 }

        if let start = crawlStartDate {
            let elapsed = Date().timeIntervalSince(start)
            stats.crawlRateURLsPerSecond = elapsed > 0
                ? Double(stats.totalURLsCrawled) / elapsed : 0
        }
    }

    private func importSitemap(baseURL: URL) async {
        let sitemapURL: URL
        if var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
            components.path = "/sitemap.xml"
            components.query = nil
            components.fragment = nil
            sitemapURL = components.url ?? baseURL
        } else {
            return
        }

        let result = await SitemapParser.fetchAndParse(url: sitemapURL)
        let sitemapURLStrings = result.urls.map { ($0.loc, 0) }
        await frontier.enqueue(urls: sitemapURLStrings)
        stats.totalURLsDiscovered += result.urls.count
    }

    private func runAggregateIssueChecks(sessionID: UUID) async {
        guard let sessionID = self.sessionID else { return }
        let issues = issueEngine.evaluateAggregate(sessionID: sessionID, db: db)
        try? db.insertIssues(issues)
    }

    private func emit(_ event: CrawlEvent) {
        continuation?.yield(event)
    }
}
