import Foundation

struct MissingH1Check: PerURLCheck {
    let definition = IssueDefinition(
        key: "missing_h1",
        severity: .warning,
        category: .headings,
        title: "Missing H1 Tag",
        description: "This page has no H1 heading. The H1 communicates the page's primary topic to both users and search engines.",
        remediation: "Add one descriptive H1 tag that reflects the page's main keyword focus."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isIndexableHTML(url), url.h1Count == 0 else { return nil }
        return issue(for: url)
    }
}

struct MultipleH1Check: PerURLCheck {
    let definition = IssueDefinition(
        key: "multiple_h1",
        severity: .opportunity,
        category: .headings,
        title: "Multiple H1 Tags",
        description: "This page has more than one H1 tag. While not a hard rule, a single H1 provides a cleaner topical signal.",
        remediation: "Consolidate content under a single H1. Demote additional H1s to H2 or H3 as appropriate."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isIndexableHTML(url), url.h1Count > 1 else { return nil }
        return issue(for: url, data: ["h1Count": "\(url.h1Count)"])
    }
}
