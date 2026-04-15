import Foundation
import SwiftSoup
import CryptoKit

/// Extracts all SEO-relevant signals from a parsed HTML document.
/// Operates on a SwiftSoup `Document` — completely stateless.
struct ContentExtractor {

    // MARK: — Main Entry Point

    struct ExtractionResult {
        var title: String?
        var titleLength: Int?
        var metaDescription: String?
        var metaDescriptionLength: Int?
        var h1: String?
        var h1Count: Int
        var h2Count: Int
        var canonicalURL: String?
        var robotsDirectives: RobotsDirectives
        var hreflangTags: [HreflangTag]
        var openGraphTitle: String?
        var openGraphDescription: String?
        var structuredDataTypes: [String]
        var wordCount: Int
        var imageCount: Int
        var contentHash: String
    }

    /// Extract all signals from a parsed document.
    static func extract(document: Document, responseHeaders: [String: String], pageURL: URL) -> ExtractionResult {
        let title = extractTitle(document)
        let metaDescription = extractMetaDescription(document)
        let (h1, h1Count) = extractH1(document)
        let h2Count = extractH2Count(document)
        let canonical = extractCanonical(document, pageURL: pageURL)
        let robotsDirectives = extractRobotsDirectives(document, headers: responseHeaders)
        let hreflang = extractHreflang(document, pageURL: pageURL)
        let (ogTitle, ogDesc) = extractOpenGraph(document)
        let structuredDataTypes = extractStructuredDataTypes(document)
        let wordCount = estimateWordCount(document)
        let imageCount = countImages(document)
        let contentHash = hashBodyContent(document)

        return ExtractionResult(
            title: title,
            titleLength: title?.count,
            metaDescription: metaDescription,
            metaDescriptionLength: metaDescription?.count,
            h1: h1,
            h1Count: h1Count,
            h2Count: h2Count,
            canonicalURL: canonical,
            robotsDirectives: robotsDirectives,
            hreflangTags: hreflang,
            openGraphTitle: ogTitle,
            openGraphDescription: ogDesc,
            structuredDataTypes: structuredDataTypes,
            wordCount: wordCount,
            imageCount: imageCount,
            contentHash: contentHash
        )
    }

    // MARK: — Title

    private static func extractTitle(_ doc: Document) -> String? {
        guard let title = try? doc.title() else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: — Meta Description

    private static func extractMetaDescription(_ doc: Document) -> String? {
        // Standard: <meta name="description" content="...">
        if let el = (try? doc.select("meta[name~=(?i)^description$]").first()),
           let content = try? el.attr("content") {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        // OG fallback not used for indexability — only for display
        return nil
    }

    // MARK: — Headings

    private static func extractH1(_ doc: Document) -> (String?, Int) {
        guard let h1Elements = try? doc.select("h1") else { return (nil, 0) }
        let count = h1Elements.count
        let first = h1Elements.first().flatMap { try? $0.text() }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (first?.isEmpty == false ? first : nil, count)
    }

    private static func extractH2Count(_ doc: Document) -> Int {
        (try? doc.select("h2").count) ?? 0
    }

    // MARK: — Canonical

    private static func extractCanonical(_ doc: Document, pageURL: URL) -> String? {
        // <link rel="canonical" href="...">
        if let el = try? doc.select("link[rel~=(?i)canonical]").first(),
           let href = try? el.attr("href") {
            let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return URL(string: trimmed, relativeTo: pageURL)?.absoluteString ?? trimmed
            }
        }
        return nil
    }

    // MARK: — Robots Directives

    private static func extractRobotsDirectives(
        _ doc: Document,
        headers: [String: String]
    ) -> RobotsDirectives {
        var directives = RobotsDirectives()

        // Parse <meta name="robots" content="...">
        let metaContent = metaRobotsContent(doc)
        // Parse X-Robots-Tag header (takes precedence for non-HTML resources)
        let headerContent = headers["x-robots-tag"]

        let rawDirectives = [metaContent, headerContent].compactMap { $0 }.joined(separator: ",")
        if rawDirectives.isEmpty { return directives }

        let parts = rawDirectives.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }

        directives.noindex = parts.contains("noindex") || parts.contains("none")
        directives.nofollow = parts.contains("nofollow") || parts.contains("none")
        directives.noarchive = parts.contains("noarchive")
        directives.nosnippet = parts.contains("nosnippet")
        directives.noimageindex = parts.contains("noimageindex")
        directives.source = headerContent != nil ? "header" : "meta"

        // unavailable_after: YYYY-MM-DD
        if let ua = parts.first(where: { $0.hasPrefix("unavailable_after:") }) {
            let dateStr = ua.replacingOccurrences(of: "unavailable_after:", with: "").trimmingCharacters(in: .whitespaces)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            directives.unavailableAfter = formatter.date(from: dateStr)
        }

        return directives
    }

    /// Collect all <meta name="robots"> and <meta name="googlebot"> content values.
    private static func metaRobotsContent(_ doc: Document) -> String? {
        let selectors = [
            "meta[name~=(?i)^robots$]",
            "meta[name~=(?i)^googlebot$]",
            "meta[name~=(?i)^bingbot$]",
        ]
        let combined = selectors.compactMap { sel -> String? in
            guard let el = try? doc.select(sel).first(),
                  let content = try? el.attr("content") else { return nil }
            return content.isEmpty ? nil : content
        }.joined(separator: ",")
        return combined.isEmpty ? nil : combined
    }

    // MARK: — Hreflang

    private static func extractHreflang(_ doc: Document, pageURL: URL) -> [HreflangTag] {
        guard let elements = try? doc.select("link[rel~=(?i)alternate][hreflang]") else { return [] }
        return elements.compactMap { el -> HreflangTag? in
            guard let href = try? el.attr("href"),
                  let lang = try? el.attr("hreflang"),
                  !href.isEmpty, !lang.isEmpty else { return nil }
            let resolvedURL = URL(string: href, relativeTo: pageURL)?.absoluteString ?? href
            let parts = lang.components(separatedBy: "-")
            return HreflangTag(
                lang: parts.first ?? lang,
                url: resolvedURL,
                region: parts.count > 1 ? parts.dropFirst().joined(separator: "-") : nil
            )
        }
    }

    // MARK: — Open Graph

    private static func extractOpenGraph(_ doc: Document) -> (String?, String?) {
        let title = extractMeta(doc, property: "og:title")
        let desc = extractMeta(doc, property: "og:description")
        return (title, desc)
    }

    private static func extractMeta(_ doc: Document, property: String) -> String? {
        let sel = "meta[property~=(?i)^\(NSRegularExpression.escapedPattern(for: property))$]"
        guard let el = try? doc.select(sel).first(),
              let content = try? el.attr("content") else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: — Structured Data

    /// Returns the @type values found in JSON-LD scripts.
    private static func extractStructuredDataTypes(_ doc: Document) -> [String] {
        guard let scripts = try? doc.select("script[type~=(?i)application/ld\\+json]") else { return [] }
        var types: [String] = []
        for script in scripts {
            guard let json = try? script.data(),
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            collectTypes(from: obj, into: &types)
        }
        return Array(Set(types)).sorted()
    }

    private static func collectTypes(from obj: Any, into types: inout [String]) {
        if let dict = obj as? [String: Any] {
            if let t = dict["@type"] as? String { types.append(t) }
            if let arr = dict["@type"] as? [String] { types.append(contentsOf: arr) }
            for value in dict.values { collectTypes(from: value, into: &types) }
        } else if let arr = obj as? [Any] {
            for item in arr { collectTypes(from: item, into: &types) }
        }
    }

    // MARK: — Word Count

    private static func estimateWordCount(_ doc: Document) -> Int {
        // Extract text from body, excluding nav/header/footer/script/style
        let exclusions = "script, style, nav, header, footer, [aria-hidden=true]"
        guard let body = doc.body() else { return 0 }
        if let excluded = try? body.select(exclusions) {
            try? excluded.remove()
        }
        let text = (try? body.text()) ?? ""
        // Split on whitespace and filter empty strings
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    // MARK: — Image Count

    private static func countImages(_ doc: Document) -> Int {
        (try? doc.select("img").count) ?? 0
    }

    // MARK: — Content Hash (for duplicate detection)

    /// SHA-256 of normalised body text — used for exact-duplicate detection.
    private static func hashBodyContent(_ doc: Document) -> String {
        let text = normaliseBodyText(doc)
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func normaliseBodyText(_ doc: Document) -> String {
        guard let body = doc.body(),
              let text = try? body.text() else { return "" }
        // Collapse whitespace and lowercase for comparison
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
