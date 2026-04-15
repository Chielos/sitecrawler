import Foundation

// MARK: — Redirect Chain

struct RedirectChainCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "redirect_chain",
        severity: .warning,
        category: .redirect,
        title: "Redirect Chain",
        description: "This URL passes through more than one redirect before reaching its destination. Redirect chains waste crawl budget and dilute link equity.",
        remediation: "Update internal links to point directly to the final destination URL and reduce intermediate redirects."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard url.redirectChain.count >= 2 else { return nil }
        let chain = url.redirectChain.map { "\($0.fromURL) → [\($0.statusCode)] → \($0.toURL)" }.joined(separator: "\n")
        return issue(for: url, data: [
            "chainLength": "\(url.redirectChain.count)",
            "chain": chain,
        ])
    }
}

// MARK: — Redirect Loop

struct RedirectLoopCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "redirect_loop",
        severity: .error,
        category: .redirect,
        title: "Redirect Loop",
        description: "This URL is involved in a redirect loop — it eventually redirects back to itself or creates a cycle.",
        remediation: "Trace the redirect chain and fix the server-side redirect rules to eliminate the cycle."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard url.fetchError == .tooManyRedirects else { return nil }
        let hops = url.redirectChain.map(\.fromURL)
        let unique = Set(hops)
        let isLoop = hops.count != unique.count
        guard isLoop else { return nil }
        return issue(for: url, data: ["chainLength": "\(url.redirectChain.count)"])
    }
}
