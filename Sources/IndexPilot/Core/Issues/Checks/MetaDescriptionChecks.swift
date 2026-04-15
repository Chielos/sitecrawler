import Foundation
import GRDB

struct MissingMetaDescriptionCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "missing_meta_description",
        severity: .warning,
        category: .metaDescription,
        title: "Missing Meta Description",
        description: "This page has no meta description tag. While not a direct ranking factor, meta descriptions influence click-through rates in search results.",
        remediation: "Add a concise, compelling <meta name=\"description\"> tag (120–158 characters) summarising the page's content."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isIndexableHTML(url), url.metaDescription == nil else { return nil }
        return issue(for: url)
    }
}

struct MetaDescriptionTooLongCheck: PerURLCheck {
    static let maxLength = 160
    let definition = IssueDefinition(
        key: "meta_description_too_long",
        severity: .opportunity,
        category: .metaDescription,
        title: "Meta Description Too Long",
        description: "The meta description exceeds \(maxLength) characters and will likely be truncated in search results.",
        remediation: "Shorten the meta description to under \(maxLength) characters while retaining its key message."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isIndexableHTML(url),
              let length = url.metaDescriptionLength, length > Self.maxLength else { return nil }
        return issue(for: url, data: [
            "length": "\(length)",
            "description": String((url.metaDescription ?? "").prefix(200)),
        ])
    }
}

// MARK: — Aggregate: Duplicate Meta Descriptions

struct DuplicateMetaDescriptionCheck: AggregateCheck {
    let definition = IssueDefinition(
        key: "duplicate_meta_description",
        severity: .warning,
        category: .metaDescription,
        title: "Duplicate Meta Description",
        description: "Multiple pages share the same meta description. Duplicate descriptions reduce the uniqueness of your SERP snippets.",
        remediation: "Write a unique meta description for each page that accurately reflects its content."
    )

    func evaluate(sessionID: UUID, db: DatabaseManager) -> [Issue] {
        guard let rows = try? db.pool.read({ db in
            try Row.fetchAll(db, sql: """
                SELECT normalized_url, meta_description FROM crawled_urls
                WHERE session_id = ? AND meta_description IS NOT NULL AND is_indexable = 1
                AND LOWER(TRIM(meta_description)) IN (
                    SELECT LOWER(TRIM(meta_description))
                    FROM crawled_urls
                    WHERE session_id = ? AND meta_description IS NOT NULL AND is_indexable = 1
                    GROUP BY LOWER(TRIM(meta_description))
                    HAVING COUNT(*) > 1
                )
            """, arguments: [sessionID.uuidString, sessionID.uuidString])
        }) else { return [] }

        return rows.compactMap { row -> Issue? in
            guard let url: String = row["normalized_url"],
                  let desc: String = row["meta_description"] else { return nil }
            return Issue(sessionID: sessionID, url: url, definition: definition, data: ["description": desc])
        }
    }
}
