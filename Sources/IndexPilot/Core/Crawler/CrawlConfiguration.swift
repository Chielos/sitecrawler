import Foundation

/// All user-configurable parameters for a crawl session.
/// Snapshot-serialized into the database at crawl start so historical
/// crawls can be reproduced with the same settings.
struct CrawlConfiguration: Codable, Hashable {

    // MARK: — Scope

    /// Maximum crawl depth from seed URLs (0 = seeds only).
    var maxDepth: Int = 10
    /// Hard cap on total URLs to crawl. 0 = unlimited.
    var maxURLs: Int = 0
    /// Restrict crawling to these path prefixes (empty = entire domain).
    var allowedPaths: [String] = []
    /// Regex patterns for URLs to exclude.
    var excludePatterns: [String] = []
    /// Whether to stay within the seed's registered domain.
    var constrainToSeedDomain: Bool = true
    /// Whether to follow subdomains of the seed domain.
    var includeSubdomains: Bool = false
    /// Content types to crawl. Empty = ["text/html"].
    var allowedContentTypes: [String] = []

    // MARK: — Politeness

    /// Requests per second per host. 0 = no limit.
    var requestsPerSecondPerHost: Double = 1.0
    /// Maximum concurrent requests across all hosts.
    var maxConcurrentRequests: Int = 5
    /// Maximum concurrent requests to a single host.
    var maxConcurrentRequestsPerHost: Int = 1
    /// Request timeout in seconds.
    var timeoutSeconds: Double = 15.0
    /// Number of retries for transient errors.
    var maxRetries: Int = 2
    /// Whether to obey robots.txt.
    var obeyRobots: Bool = true

    // MARK: — Identity

    /// User-agent string sent with every request.
    var userAgent: String = "IndexPilot/1.0 (+https://indexpilot.app/bot)"
    /// Custom HTTP headers added to every request.
    var customHeaders: [String: String] = [:]

    // MARK: — Rendering

    /// Whether to use a JS rendering worker for qualifying pages.
    var useJSRendering: Bool = false
    /// Rendering engine to use when JS rendering is enabled.
    var renderingEngine: RenderingEngine = .wkWebView

    // MARK: — URL Handling

    /// Strip known tracking query parameters (utm_*, fbclid, etc.).
    var stripTrackingParameters: Bool = true
    /// Treat HTTP and HTTPS versions of the same URL as identical.
    var canonicalizeHTTPSvsHTTP: Bool = true
    /// Normalize trailing slashes so /about and /about/ are the same URL.
    var normalizeTrailingSlash: Bool = true
    /// Sort query parameters before deduplication.
    var sortQueryParameters: Bool = false

    // MARK: — Limits

    /// Maximum response body size in bytes. Responses larger than this are truncated.
    var maxResponseBodyBytes: Int = 5_000_000  // 5 MB

    // MARK: — Sitemap

    /// Fetch and parse sitemap.xml at crawl start.
    var importSitemapAtStart: Bool = true

    enum RenderingEngine: String, Codable, Hashable, CaseIterable {
        case wkWebView = "wkWebView"
        case playwright = "playwright"
    }
}

/// Known tracking query parameters that should be stripped during normalization.
let knownTrackingParameters: Set<String> = [
    "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
    "utm_id", "utm_source_platform", "utm_creative_format", "utm_marketing_tactic",
    "fbclid", "gclid", "gbraid", "wbraid", "msclkid", "dclid",
    "mc_cid", "mc_eid", "_hsenc", "_hsmi", "hs_email_id", "hs_ctct_key",
    "ref", "referrer", "source",
]
