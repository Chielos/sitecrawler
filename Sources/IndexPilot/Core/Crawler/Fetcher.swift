import Foundation

/// Performs individual HTTP fetches for the crawl engine.
/// Tracks redirects manually (disabling URLSession's automatic following)
/// so we capture the full redirect chain including status codes.
struct Fetcher {

    let configuration: CrawlConfiguration
    private let session: URLSession
    private let redirectDelegate = RedirectDelegate()

    // MARK: — Init

    init(configuration: CrawlConfiguration) {
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = configuration.timeoutSeconds
        config.timeoutIntervalForResource = configuration.timeoutSeconds * 3
        config.httpMaximumConnectionsPerHost = configuration.maxConcurrentRequestsPerHost
        config.httpAdditionalHeaders = Self.mergeHeaders(configuration)
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }

    private static func mergeHeaders(_ config: CrawlConfiguration) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": config.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Accept-Encoding": "gzip, deflate, br",
        ]
        for (k, v) in config.customHeaders { headers[k] = v }
        return headers
    }

    // MARK: — Public API

    struct FetchResult: Sendable {
        var originalURL: String
        var finalURL: String
        var statusCode: Int
        var contentType: String?
        var responseTimeMs: Int
        var contentSizeBytes: Int
        var body: Data?
        var responseHeaders: [String: String]
        var redirectChain: [RedirectHop]
        var error: FetchError?
    }

    /// Fetch `url`, following redirects manually up to `maxRedirects`.
    func fetch(_ rawURL: String) async -> FetchResult {
        let started = Date()

        guard let initialURL = URL(string: rawURL) else {
            return FetchResult(
                originalURL: rawURL, finalURL: rawURL,
                statusCode: 0, contentType: nil, responseTimeMs: 0,
                contentSizeBytes: 0, body: nil, responseHeaders: [:],
                redirectChain: [], error: .invalidURL
            )
        }

        var currentURL = initialURL
        var redirectChain: [RedirectHop] = []
        let maxRedirects = 10

        for _ in 0..<maxRedirects {
            let result = await performSingleFetch(url: currentURL)
            switch result {
            case .success(let (response, body)):
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let isRedirect = (300...399).contains(response.statusCode)

                if isRedirect, let location = response.value(forHTTPHeaderField: "Location") {
                    let hop = RedirectHop(
                        fromURL: currentURL.absoluteString,
                        toURL: location,
                        statusCode: response.statusCode
                    )
                    redirectChain.append(hop)
                    // Resolve relative redirect Location
                    if let nextURL = URL(string: location, relativeTo: currentURL)?.absoluteURL {
                        currentURL = nextURL
                    } else {
                        // Unresolvable redirect
                        return FetchResult(
                            originalURL: rawURL,
                            finalURL: currentURL.absoluteString,
                            statusCode: response.statusCode,
                            contentType: response.mimeType,
                            responseTimeMs: ms,
                            contentSizeBytes: body.count,
                            body: nil,
                            responseHeaders: extractHeaders(response),
                            redirectChain: redirectChain,
                            error: nil
                        )
                    }
                } else {
                    // Terminal response
                    let contentType = response.mimeType ?? response.value(forHTTPHeaderField: "Content-Type")
                    var bodyData: Data? = nil
                    if let ct = contentType, isHTMLContentType(ct),
                       body.count <= configuration.maxResponseBodyBytes {
                        bodyData = body
                    }
                    return FetchResult(
                        originalURL: rawURL,
                        finalURL: currentURL.absoluteString,
                        statusCode: response.statusCode,
                        contentType: contentType,
                        responseTimeMs: ms,
                        contentSizeBytes: body.count,
                        body: bodyData,
                        responseHeaders: extractHeaders(response),
                        redirectChain: redirectChain,
                        error: nil
                    )
                }

            case .failure(let error):
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                return FetchResult(
                    originalURL: rawURL,
                    finalURL: currentURL.absoluteString,
                    statusCode: 0,
                    contentType: nil,
                    responseTimeMs: ms,
                    contentSizeBytes: 0,
                    body: nil,
                    responseHeaders: [:],
                    redirectChain: redirectChain,
                    error: mapError(error)
                )
            }
        }

        // Too many redirects
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return FetchResult(
            originalURL: rawURL,
            finalURL: currentURL.absoluteString,
            statusCode: 0,
            contentType: nil,
            responseTimeMs: ms,
            contentSizeBytes: 0,
            body: nil,
            responseHeaders: [:],
            redirectChain: redirectChain,
            error: .tooManyRedirects
        )
    }

    // MARK: — Internals

    private func performSingleFetch(url: URL) async -> Result<(HTTPURLResponse, Data), Error> {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return .success((httpResponse, data))
        } catch {
            return .failure(error)
        }
    }

    private func extractHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k.lowercased()] = v
            }
        }
        return headers
    }

    private func isHTMLContentType(_ ct: String) -> Bool {
        let lower = ct.lowercased()
        return lower.contains("text/html") || lower.contains("application/xhtml")
    }

    private func mapError(_ error: Error) -> FetchError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .timeout
            case .cannotFindHost: return .dnsFailure(urlError.failingURL?.host ?? "unknown")
            case .cannotConnectToHost: return .connectionRefused
            default: return .unknown(urlError.localizedDescription)
            }
        }
        return .unknown(error.localizedDescription)
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// MARK: — Per-Host Rate Limiter

/// Enforces per-host crawl delays using an actor.
actor HostRateLimiter {

    private var lastRequestTimes: [String: Date] = [:]
    private let minimumInterval: TimeInterval  // seconds between requests per host

    init(requestsPerSecond: Double) {
        self.minimumInterval = requestsPerSecond > 0 ? 1.0 / requestsPerSecond : 0
    }

    /// Wait until it's polite to fetch from the given host, then mark the time.
    func waitAndMark(host: String) async {
        guard minimumInterval > 0 else { return }
        let now = Date()
        if let last = lastRequestTimes[host] {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minimumInterval {
                let delay = minimumInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        lastRequestTimes[host] = Date()
    }
}
