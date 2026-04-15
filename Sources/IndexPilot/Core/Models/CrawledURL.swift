import Foundation

/// The complete analysis record for one URL within a crawl session.
/// Written to the database after a URL is fetched and analyzed.
struct CrawledURL: Identifiable, Codable, Sendable {
    let id: UUID
    let sessionID: UUID

    // MARK: — Identity
    var url: String
    var normalizedURL: String
    var discoveredAt: Date
    var fetchedAt: Date?
    var crawlDepth: Int
    var source: URLSource

    // MARK: — HTTP Response
    var statusCode: Int?
    var contentType: String?
    var finalURL: String?
    var redirectChain: [RedirectHop]
    var responseTimeMs: Int?
    var contentSizeBytes: Int?

    // MARK: — Extracted Metadata
    var title: String?
    var titleLength: Int?
    var metaDescription: String?
    var metaDescriptionLength: Int?
    var h1: String?
    var h1Count: Int = 0
    var h2Count: Int = 0
    var canonicalURL: String?
    var robotsDirectives: RobotsDirectives
    var hreflangTags: [HreflangTag]
    var openGraphTitle: String?
    var openGraphDescription: String?
    var structuredDataTypes: [String]

    // MARK: — Link Counts (denormalized for fast table display)
    var internalInlinkCount: Int = 0
    var internalOutlinkCount: Int = 0
    var externalOutlinkCount: Int = 0
    var imageCount: Int = 0

    // MARK: — Content Analysis
    var wordCount: Int?
    var contentHash: String?
    var isInternal: Bool

    // MARK: — Indexability
    var isIndexable: Bool
    var indexabilityReason: IndexabilityReason?

    // MARK: — Crawl State
    var isBlockedByRobots: Bool = false
    var fetchError: FetchError?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        url: String,
        normalizedURL: String,
        discoveredAt: Date = Date(),
        crawlDepth: Int,
        source: URLSource,
        isInternal: Bool
    ) {
        self.id = id
        self.sessionID = sessionID
        self.url = url
        self.normalizedURL = normalizedURL
        self.discoveredAt = discoveredAt
        self.fetchedAt = nil
        self.crawlDepth = crawlDepth
        self.source = source
        self.redirectChain = []
        self.robotsDirectives = RobotsDirectives()
        self.hreflangTags = []
        self.structuredDataTypes = []
        self.isInternal = isInternal
        self.isIndexable = true
    }
}

// MARK: — Supporting Types

struct RedirectHop: Codable, Hashable, Sendable {
    var fromURL: String
    var toURL: String
    var statusCode: Int
}

struct RobotsDirectives: Codable, Hashable, Sendable {
    var noindex: Bool = false
    var nofollow: Bool = false
    var noarchive: Bool = false
    var nosnippet: Bool = false
    var noimageindex: Bool = false
    var unavailableAfter: Date? = nil
    /// Source: "meta" for <meta name="robots"> or "header" for X-Robots-Tag
    var source: String?

    var isIndexable: Bool { !noindex }
    var isFollowable: Bool { !nofollow }
}

struct HreflangTag: Codable, Hashable, Sendable {
    var lang: String
    var url: String
    var region: String?
}

enum URLSource: String, Codable, CaseIterable, Sendable {
    case crawl = "crawl"
    case sitemap = "sitemap"
    case seed = "seed"
    case imported = "imported"
}

enum IndexabilityReason: String, Codable, Sendable {
    case noindex = "noindex"
    case canonicalizedElsewhere = "canonical_elsewhere"
    case blockedByRobots = "blocked_robots"
    case httpError = "http_error"
    case redirect = "redirect"
    case nonHTMLContent = "non_html_content"
}

enum FetchError: Codable, Equatable, Sendable {
    case timeout
    case dnsFailure(String)
    case connectionRefused
    case tooManyRedirects
    case responseTooLarge
    case invalidURL
    case unknown(String)

    var displayString: String {
        switch self {
        case .timeout: return "Timeout"
        case .dnsFailure(let host): return "DNS failure: \(host)"
        case .connectionRefused: return "Connection refused"
        case .tooManyRedirects: return "Too many redirects"
        case .responseTooLarge: return "Response too large"
        case .invalidURL: return "Invalid URL"
        case .unknown(let msg): return msg
        }
    }
}
