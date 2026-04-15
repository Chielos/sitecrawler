import Foundation

/// Exports crawl data to CSV. Runs on a background Task to never block the UI.
struct CSVExporter {

    // MARK: — URL Export

    static func exportURLs(sessionID: UUID, db: DatabaseManager) async throws -> URL {
        let fileURL = tempExportURL(name: "urls_\(sessionID.uuidString.prefix(8))", ext: "csv")

        let headers = [
            "URL", "Status Code", "Redirect URL", "Redirect Chain Length",
            "Title", "Title Length", "Meta Description", "Meta Description Length",
            "H1", "H1 Count", "H2 Count",
            "Canonical URL", "Canonical Matches",
            "Noindex", "Nofollow",
            "Is Indexable", "Indexability Reason",
            "Blocked by Robots",
            "Internal Inlinks", "Internal Outlinks", "External Outlinks",
            "Images", "Word Count",
            "Content Type", "Response Time (ms)", "Content Size (bytes)",
            "Crawl Depth", "Source", "Discovered At",
        ]

        var output = csvRow(headers)

        var offset = 0
        let batchSize = 2000

        while true {
            let batch = try db.fetchURLs(sessionID: sessionID, limit: batchSize, offset: offset)
            guard !batch.isEmpty else { break }

            for u in batch {
                let canonical = u.canonicalURL ?? ""
                let canonicalMatches = canonical.isEmpty || canonical == u.normalizedURL ? "true" : "false"
                let row: [String] = [
                    u.normalizedURL,
                    u.statusCode.map(String.init) ?? "",
                    u.finalURL ?? "",
                    "\(u.redirectChain.count)",
                    u.title ?? "",
                    u.titleLength.map(String.init) ?? "",
                    u.metaDescription ?? "",
                    u.metaDescriptionLength.map(String.init) ?? "",
                    u.h1 ?? "",
                    "\(u.h1Count)",
                    "\(u.h2Count)",
                    canonical,
                    canonicalMatches,
                    u.robotsDirectives.noindex ? "true" : "false",
                    u.robotsDirectives.nofollow ? "true" : "false",
                    u.isIndexable ? "true" : "false",
                    u.indexabilityReason?.rawValue ?? "",
                    u.isBlockedByRobots ? "true" : "false",
                    "\(u.internalInlinkCount)",
                    "\(u.internalOutlinkCount)",
                    "\(u.externalOutlinkCount)",
                    "\(u.imageCount)",
                    u.wordCount.map(String.init) ?? "",
                    u.contentType ?? "",
                    u.responseTimeMs.map(String.init) ?? "",
                    u.contentSizeBytes.map(String.init) ?? "",
                    "\(u.crawlDepth)",
                    u.source.rawValue,
                    ISO8601DateFormatter().string(from: u.discoveredAt),
                ]
                output += csvRow(row)
            }

            offset += batchSize
            if batch.count < batchSize { break }
        }

        try output.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    // MARK: — Issues Export

    static func exportIssues(sessionID: UUID, db: DatabaseManager) async throws -> URL {
        let fileURL = tempExportURL(name: "issues_\(sessionID.uuidString.prefix(8))", ext: "csv")

        let headers = ["URL", "Issue Key", "Severity", "Category", "Title", "Description", "Remediation"]
        var output = csvRow(headers)

        let issues = try db.fetchIssues(sessionID: sessionID)
        for issue in issues {
            let row: [String] = [
                issue.url,
                issue.issueKey,
                issue.severity.rawValue,
                issue.category.rawValue,
                issue.title,
                issue.description,
                issue.remediation,
            ]
            output += csvRow(row)
        }

        try output.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    // MARK: — Helpers

    private static func csvRow(_ fields: [String]) -> String {
        fields.map { field in
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
                return "\"\(escaped)\""
            }
            return escaped
        }.joined(separator: ",") + "\r\n"
    }

    private static func tempExportURL(name: String, ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(ext)")
    }
}
