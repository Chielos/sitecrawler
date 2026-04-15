import Foundation

struct MissingTitleCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "missing_title",
        severity: .error,
        category: .titles,
        title: "Missing Title Tag",
        description: "This page has no <title> tag. Title tags are a primary on-page SEO signal and are displayed in SERPs.",
        remediation: "Add a descriptive, unique <title> tag to the page's <head> section."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isIndexableHTML(url), url.title == nil else { return nil }
        return issue(for: url)
    }
}

struct TitleTooShortCheck: PerURLCheck {
    static let minLength = 10
    let definition = IssueDefinition(
        key: "title_too_short",
        severity: .warning,
        category: .titles,
        title: "Title Tag Too Short",
        description: "The title tag has fewer than \(minLength) characters. Short titles may not adequately describe the page's content or keyword intent.",
        remediation: "Expand the title to be more descriptive of the page's primary topic."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isIndexableHTML(url),
              let length = url.titleLength, length > 0, length < Self.minLength else { return nil }
        return issue(for: url, data: ["length": "\(length)", "title": url.title ?? ""])
    }
}

struct TitleTooLongCheck: PerURLCheck {
    static let maxLength = 65
    let definition = IssueDefinition(
        key: "title_too_long",
        severity: .opportunity,
        category: .titles,
        title: "Title Tag Too Long",
        description: "The title tag exceeds \(maxLength) characters. Long titles are typically truncated in search results.",
        remediation: "Trim the title to its most important keywords, keeping it under \(maxLength) characters."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isIndexableHTML(url),
              let length = url.titleLength, length > Self.maxLength else { return nil }
        return issue(for: url, data: ["length": "\(length)", "title": url.title ?? ""])
    }
}

// MARK: — Aggregate: Duplicate Titles

struct DuplicateTitleCheck: AggregateCheck {
    let definition = IssueDefinition(
        key: "duplicate_title",
        severity: .warning,
        category: .titles,
        title: "Duplicate Title Tag",
        description: "Multiple pages share the same title tag. Duplicate titles make it harder for search engines to differentiate pages.",
        remediation: "Ensure each page has a unique, descriptive title that reflects its specific content."
    )

    func evaluate(sessionID: UUID, db: DatabaseManager) -> [Issue] {
        guard let rows = try? db.pool.read(block: { db in
            try Row.fetchAll(db, sql: """
                SELECT title, COUNT(*) as cnt
                FROM crawled_urls
                WHERE session_id = ? AND title IS NOT NULL AND is_indexable = 1
                GROUP BY LOWER(TRIM(title))
                HAVING cnt > 1
            """, arguments: [sessionID.uuidString])
        }) else { return [] }

        let duplicateTitles = Set(rows.compactMap { $0["title"] as String? }.map { $0.lowercased() })
        guard !duplicateTitles.isEmpty else { return [] }

        guard let affectedURLs = try? db.pool.read(block: { db in
            try Row.fetchAll(db, sql: """
                SELECT normalized_url, title FROM crawled_urls
                WHERE session_id = ? AND is_indexable = 1
                AND LOWER(TRIM(title)) IN (\(duplicateTitles.map { _ in "?" }.joined(separator: ",")))
            """, arguments: StatementArguments([sessionID.uuidString.databaseValue] + duplicateTitles.map { $0.databaseValue }))
        }) else { return [] }

        return affectedURLs.compactMap { row -> Issue? in
            guard let url: String = row["normalized_url"],
                  let title: String = row["title"] else { return nil }
            return Issue(
                sessionID: sessionID,
                url: url,
                definition: definition,
                data: ["title": title]
            )
        }
    }
}
