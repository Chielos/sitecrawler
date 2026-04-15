import Foundation

/// Exports crawl session data as structured JSON.
struct JSONExporter {

    struct CrawlExport: Codable {
        var exportedAt: Date
        var sessionID: String
        var stats: CrawlStats
        var urlCount: Int
        var issueCount: Int
        var urls: [CrawledURL]
        var issues: [Issue]
    }

    static func export(session: CrawlSession, db: DatabaseManager) async throws -> URL {
        let urls = try db.fetchURLs(sessionID: session.id, limit: 100_000)
        let issues = try db.fetchIssues(sessionID: session.id)

        let payload = CrawlExport(
            exportedAt: Date(),
            sessionID: session.id.uuidString,
            stats: session.stats,
            urlCount: urls.count,
            issueCount: issues.count,
            urls: urls,
            issues: issues
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawl_\(session.id.uuidString.prefix(8)).json")
        try data.write(to: fileURL)
        return fileURL
    }
}
