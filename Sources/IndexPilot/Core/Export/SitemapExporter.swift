import Foundation

/// Generates an XML sitemap from crawled, indexable URLs.
struct SitemapExporter {

    static func export(sessionID: UUID, baseURL: URL, db: DatabaseManager) async throws -> URL {
        let urls = try db.fetchURLs(sessionID: sessionID, limit: 100_000)
        let indexable = urls.filter { $0.isIndexable && $0.isInternal && $0.statusCode == 200 }

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        """

        for u in indexable {
            let loc = xmlEscape(u.normalizedURL)
            xml += "\n  <url>\n    <loc>\(loc)</loc>\n  </url>"
        }
        xml += "\n</urlset>\n"

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitemap_\(sessionID.uuidString.prefix(8)).xml")
        try xml.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
