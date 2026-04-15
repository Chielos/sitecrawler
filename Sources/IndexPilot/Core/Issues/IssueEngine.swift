import Foundation

/// Evaluates all registered issue checks against crawled URLs.
/// Checks are data-driven: each is one `IssueDefinition` + a closure.
/// Adding a new check = one struct + one `register()` call. No other changes.
struct IssueEngine {

    // MARK: — Check Registration

    private let perURLChecks: [AnyPerURLCheck]
    private let aggregateChecks: [AnyAggregateCheck]

    init() {
        perURLChecks = IssueRegistry.perURLChecks()
        aggregateChecks = IssueRegistry.aggregateChecks()
    }

    // MARK: — Per-URL Evaluation

    /// Evaluate all per-URL checks against a single CrawledURL.
    /// Called immediately after each URL is fetched.
    func evaluate(_ url: CrawledURL) -> [Issue] {
        perURLChecks.compactMap { check in
            check.evaluate(url)
        }
    }

    // MARK: — Aggregate Evaluation

    /// Post-crawl checks that require querying the full dataset.
    /// Called once after the crawl loop completes.
    func evaluateAggregate(sessionID: UUID, db: DatabaseManager) -> [Issue] {
        aggregateChecks.flatMap { check in
            check.evaluate(sessionID: sessionID, db: db)
        }
    }
}

// MARK: — Type-Erased Check Wrappers

struct AnyPerURLCheck {
    private let _evaluate: (CrawledURL) -> Issue?
    let definition: IssueDefinition

    init<C: PerURLCheck>(_ check: C) {
        self.definition = check.definition
        self._evaluate = { url in check.evaluate(url) }
    }

    func evaluate(_ url: CrawledURL) -> Issue? { _evaluate(url) }
}

struct AnyAggregateCheck {
    private let _evaluate: (UUID, DatabaseManager) -> [Issue]
    let definition: IssueDefinition

    init<C: AggregateCheck>(_ check: C) {
        self.definition = check.definition
        self._evaluate = { id, db in check.evaluate(sessionID: id, db: db) }
    }

    func evaluate(sessionID: UUID, db: DatabaseManager) -> [Issue] {
        _evaluate(sessionID, db)
    }
}

// MARK: — Check Protocols

protocol PerURLCheck {
    var definition: IssueDefinition { get }
    func evaluate(_ url: CrawledURL) -> Issue?
}

protocol AggregateCheck {
    var definition: IssueDefinition { get }
    func evaluate(sessionID: UUID, db: DatabaseManager) -> [Issue]
}

// MARK: — Issue Registry

enum IssueRegistry {

    static func perURLChecks() -> [AnyPerURLCheck] {
        [
            // HTTP errors
            AnyPerURLCheck(HTTP4xxCheck()),
            AnyPerURLCheck(HTTP5xxCheck()),
            // Redirects
            AnyPerURLCheck(RedirectChainCheck()),
            AnyPerURLCheck(RedirectLoopCheck()),
            // Titles
            AnyPerURLCheck(MissingTitleCheck()),
            AnyPerURLCheck(TitleTooShortCheck()),
            AnyPerURLCheck(TitleTooLongCheck()),
            // Meta description
            AnyPerURLCheck(MissingMetaDescriptionCheck()),
            AnyPerURLCheck(MetaDescriptionTooLongCheck()),
            // Headings
            AnyPerURLCheck(MissingH1Check()),
            AnyPerURLCheck(MultipleH1Check()),
            // Canonicals
            AnyPerURLCheck(CanonicalToNonIndexableCheck()),
            AnyPerURLCheck(BrokenCanonicalCheck()),
            // Indexability
            AnyPerURLCheck(NoindexInSitemapCheck()),
            AnyPerURLCheck(BlockedByRobotsButLinkedCheck()),
            // Content
            AnyPerURLCheck(ThinContentCheck()),
            // Depth
            AnyPerURLCheck(ExcessiveCrawlDepthCheck()),
            // Security
            AnyPerURLCheck(InsecureCanonicalCheck()),
            // Images
            AnyPerURLCheck(MissingAltOnAnchorImageCheck()),
        ]
    }

    static func aggregateChecks() -> [AnyAggregateCheck] {
        [
            AnyAggregateCheck(DuplicateTitleCheck()),
            AnyAggregateCheck(DuplicateMetaDescriptionCheck()),
            AnyAggregateCheck(DuplicateContentHashCheck()),
        ]
    }
}

// MARK: — Convenience Issue Builder

extension PerURLCheck {
    func issue(for url: CrawledURL, data: [String: String] = [:]) -> Issue {
        Issue(sessionID: url.sessionID, url: url.normalizedURL, definition: definition, data: data)
    }
    func noIssue() -> Issue? { nil }
}
