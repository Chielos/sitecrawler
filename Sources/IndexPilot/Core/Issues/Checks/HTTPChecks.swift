import Foundation

// MARK: — HTTP 4xx

struct HTTP4xxCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "http_4xx",
        severity: .error,
        category: .http,
        title: "4xx Client Error",
        description: "This URL returned a 4xx status code, meaning it could not be found or access was denied.",
        remediation: "Fix or remove internal links to this URL. If the page was moved, add a permanent redirect."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard let code = url.statusCode, (400...499).contains(code), url.isInternal else { return nil }
        return issue(for: url, data: ["statusCode": "\(code)"])
    }
}

// MARK: — HTTP 5xx

struct HTTP5xxCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "http_5xx",
        severity: .error,
        category: .http,
        title: "5xx Server Error",
        description: "The server returned a 5xx error for this URL. The page is inaccessible to crawlers and users.",
        remediation: "Investigate server logs. Ensure the application handles errors gracefully and the URL resolves correctly."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard let code = url.statusCode, (500...599).contains(code), url.isInternal else { return nil }
        return issue(for: url, data: ["statusCode": "\(code)"])
    }
}
