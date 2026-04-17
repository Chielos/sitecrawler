import Foundation
import SwiftUI

struct CrawlIssue: Identifiable, Hashable, Sendable {
    let id: UUID
    let page: String
    let status: String
    let detail: String

    init(id: UUID = UUID(), page: String, status: String, detail: String) {
        self.id = id
        self.page = page
        self.status = status
        self.detail = detail
    }
}

struct CrawlProgress: Sendable {
    let scannedPages: Int
    let discoveredPages: Int
    let issues: [CrawlIssue]
    let activePage: String
}

actor SiteCrawlerEngine {
    private let session: URLSession
    private let maxPages = 40

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        configuration.httpShouldSetCookies = false
        self.session = URLSession(configuration: configuration)
    }

    func crawl(
        startingAt startURL: URL,
        maxDepth: Int,
        progress: @escaping @Sendable (CrawlProgress) async -> Void
    ) async throws -> CrawlProgress {
        let normalizedStart = normalize(startURL)
        var queue: [(url: URL, depth: Int)] = [(normalizedStart, 0)]
        var queued = Set([cacheKey(for: normalizedStart)])
        var scanned = Set<String>()
        var issues: [CrawlIssue] = []
        var scannedPages = 0
        let host = normalizedStart.host()?.lowercased()

        while !queue.isEmpty, scannedPages < maxPages {
            let current = queue.removeFirst()
            let key = cacheKey(for: current.url)
            guard scanned.insert(key).inserted else {
                continue
            }

            await progress(
                CrawlProgress(
                    scannedPages: scannedPages,
                    discoveredPages: queued.count,
                    issues: issues,
                    activePage: current.url.absoluteString
                )
            )

            let pageResult = try await fetchPage(at: current.url)
            scannedPages += 1

            if let issue = pageResult.redirectIssue {
                issues.append(issue)
            }

            issues.append(contentsOf: pageResult.issues)

            if current.depth < maxDepth, pageResult.isHTML {
                for link in pageResult.links {
                    let normalizedLink = normalize(link)
                    let linkHost = normalizedLink.host()?.lowercased()
                    let linkKey = cacheKey(for: normalizedLink)

                    guard linkHost == host else {
                        continue
                    }

                    if !queued.contains(linkKey) {
                        queued.insert(linkKey)
                        queue.append((normalizedLink, current.depth + 1))
                    }
                }
            }

            await progress(
                CrawlProgress(
                    scannedPages: scannedPages,
                    discoveredPages: queued.count,
                    issues: deduplicated(issues),
                    activePage: pageResult.finalURL.absoluteString
                )
            )
        }

        return CrawlProgress(
            scannedPages: scannedPages,
            discoveredPages: queued.count,
            issues: deduplicated(issues),
            activePage: scannedPages == 0 ? normalizedStart.absoluteString : "Crawl complete"
        )
    }

    private func fetchPage(at url: URL) async throws -> PageResult {
        let start = ContinuousClock.now
        let (data, response) = try await session.data(from: url)
        let duration = start.duration(to: .now)
        let elapsedSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CrawlError.invalidResponse(url.absoluteString)
        }

        let finalURL = normalize(httpResponse.url ?? url)
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let isHTML = contentType.contains("text/html")
        var issues: [CrawlIssue] = []

        if httpResponse.statusCode >= 400 {
            issues.append(
                CrawlIssue(
                    page: relativePath(for: finalURL),
                    status: "HTTP \(httpResponse.statusCode)",
                    detail: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                )
            )
        }

        if elapsedSeconds > 1.2 {
            issues.append(
                CrawlIssue(
                    page: relativePath(for: finalURL),
                    status: "Slow",
                    detail: "Response took \(elapsedSeconds.formatted(.number.precision(.fractionLength(2))))s"
                )
            )
        }

        var links: [URL] = []
        if isHTML, let html = String(data: data, encoding: .utf8) {
            if !hasMetaDescription(in: html) {
                issues.append(
                    CrawlIssue(
                        page: relativePath(for: finalURL),
                        status: "Missing Meta",
                        detail: "No meta description found"
                    )
                )
            }

            links = extractLinks(from: html, baseURL: finalURL)
        }

        let redirectIssue: CrawlIssue?
        if finalURL != normalize(url) {
            redirectIssue = CrawlIssue(
                page: relativePath(for: url),
                status: "Redirect",
                detail: "Resolved to \(relativePath(for: finalURL))"
            )
        } else {
            redirectIssue = nil
        }

        return PageResult(
            finalURL: finalURL,
            isHTML: isHTML,
            links: links,
            issues: issues,
            redirectIssue: redirectIssue
        )
    }

    private func extractLinks(from html: String, baseURL: URL) -> [URL] {
        let pattern = #"href\s*=\s*["']([^"'#>]+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..., in: html)

        return regex.matches(in: html, options: [], range: nsRange).compactMap { match in
            guard
                let range = Range(match.range(at: 1), in: html),
                let url = URL(string: String(html[range]), relativeTo: baseURL)?.absoluteURL
            else {
                return nil
            }

            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return nil
            }

            return stripFragment(from: url)
        }
    }

    private func hasMetaDescription(in html: String) -> Bool {
        let pattern = #"<meta[^>]*name\s*=\s*["']description["'][^>]*content\s*=\s*["'][^"']+["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        return regex.firstMatch(in: html, options: [], range: nsRange) != nil
    }

    private func stripFragment(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.fragment = nil
        return components.url ?? url
    }

    private func normalize(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if components.path.isEmpty {
            components.path = "/"
        }

        components.fragment = nil
        return components.url ?? url
    }

    private func cacheKey(for url: URL) -> String {
        normalize(url).absoluteString.lowercased()
    }

    private func relativePath(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        let path = components.path.isEmpty ? "/" : components.path
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        components.query = nil
        components.fragment = nil

        return path + query
    }

    private func deduplicated(_ issues: [CrawlIssue]) -> [CrawlIssue] {
        var seen = Set<String>()

        return issues.filter { issue in
            let key = "\(issue.page)|\(issue.status)|\(issue.detail)"
            return seen.insert(key).inserted
        }
    }
}

private struct PageResult {
    let finalURL: URL
    let isHTML: Bool
    let links: [URL]
    let issues: [CrawlIssue]
    let redirectIssue: CrawlIssue?
}

enum CrawlError: LocalizedError {
    case invalidURL
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid http or https URL."
        case .invalidResponse(let value):
            return "The server returned an invalid response for \(value)."
        }
    }
}

struct ContentView: View {
    @State private var siteURL = "https://example.com"
    @State private var crawlDepth = 2
    @State private var isCrawling = false
    @State private var pagesScanned = 0
    @State private var discoveredPages = 0
    @State private var issues: [CrawlIssue] = []
    @State private var statusMessage = "Ready to crawl"
    @State private var errorMessage: String?

    private let crawler = SiteCrawlerEngine()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.11, blue: 0.16),
                        Color(red: 0.11, green: 0.16, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    header
                    controls
                    summary
                    results
                }
                .padding(28)
            }
            .navigationTitle("SiteCrawler")
        }
        .frame(minWidth: 880, minHeight: 580)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crawl Smarter")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Inspect site structure, surface crawl issues, and keep indexable pages healthy.")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Site URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                TextField("https://example.com", text: $siteURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isCrawling)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Depth")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Picker("Depth", selection: $crawlDepth) {
                    ForEach(1...5, id: \.self) { depth in
                        Text("\(depth) levels").tag(depth)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .disabled(isCrawling)
            }

            Button(isCrawling ? "Crawling..." : "Start Crawl") {
                startCrawl()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isCrawling)
        }
        .padding(20)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var summary: some View {
        HStack(spacing: 16) {
            metricCard(title: "Pages Scanned", value: "\(pagesScanned)", accent: .cyan)
            metricCard(title: "Pages Found", value: "\(discoveredPages)", accent: .green)
            metricCard(title: "Issues Found", value: "\(issues.count)", accent: .orange)
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Findings")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(statusMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isCrawling ? .green : .white.opacity(0.72))
                    .lineLimit(1)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.bottom, 4)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if issues.isEmpty {
                        emptyState
                    } else {
                        ForEach(issues) { issue in
                            issueRow(issue)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isCrawling ? "Crawl in progress" : "No findings yet")
                .font(.headline)
                .foregroundStyle(.white)

            Text(isCrawling ? "Pages will appear here as the crawler discovers issues." : "Run a crawl to inspect live pages on the current host.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func issueRow(_ issue: CrawlIssue) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(color(for: issue.status))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.page)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(issue.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Text(issue.status.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(color(for: issue.status))
        }
        .padding(16)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metricCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            RoundedRectangle(cornerRadius: 999)
                .fill(accent.opacity(0.9))
                .frame(width: 44, height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func color(for status: String) -> Color {
        if status.contains("HTTP 4") || status.contains("HTTP 5") {
            return .red
        }

        switch status {
        case "Redirect":
            return .yellow
        case "Missing Meta":
            return .orange
        default:
            return .cyan
        }
    }

    private func startCrawl() {
        errorMessage = nil

        guard let normalizedURL = normalizedInputURL() else {
            isCrawling = false
            statusMessage = "Ready to crawl"
            errorMessage = CrawlError.invalidURL.localizedDescription
            return
        }

        isCrawling = true
        pagesScanned = 0
        discoveredPages = 1
        issues = []
        statusMessage = "Starting \(normalizedURL.host() ?? normalizedURL.absoluteString)"

        Task {
            do {
                let finalProgress = try await crawler.crawl(startingAt: normalizedURL, maxDepth: crawlDepth) { progress in
                    await MainActor.run {
                        pagesScanned = progress.scannedPages
                        discoveredPages = progress.discoveredPages
                        issues = progress.issues
                        statusMessage = "Scanning \(progress.activePage)"
                    }
                }

                await MainActor.run {
                    isCrawling = false
                    pagesScanned = finalProgress.scannedPages
                    discoveredPages = finalProgress.discoveredPages
                    issues = finalProgress.issues
                    statusMessage = "Completed \(finalProgress.scannedPages) pages"
                }
            } catch {
                await MainActor.run {
                    isCrawling = false
                    statusMessage = "Crawl failed"
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func normalizedInputURL() -> URL? {
        let trimmed = siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url
        }

        return URL(string: "https://\(trimmed)")
    }
}

#Preview {
    ContentView()
}
