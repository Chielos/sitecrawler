import Foundation
import SwiftSoup

/// Parses an HTML document and extracts all navigable links and assets.
/// Separates raw discovery (what URLs exist) from semantic extraction (what they mean).
/// ContentExtractor handles the semantic layer.
struct HTMLParser {

    // MARK: — Result Types

    struct ParseResult {
        var links: [DiscoveredLink]
        var document: Document?
        var parseError: String?
    }

    struct DiscoveredLink {
        var url: String
        var tag: LinkTag
        var rel: String?
        var anchorText: String?
        var isNofollow: Bool
    }

    // MARK: — Public API

    static func parse(html: Data, baseURL: URL) -> ParseResult {
        guard let htmlString = String(data: html, encoding: .utf8)
                ?? String(data: html, encoding: .isoLatin1) else {
            return ParseResult(links: [], document: nil, parseError: "Could not decode HTML body")
        }
        return parse(htmlString: htmlString, baseURL: baseURL)
    }

    static func parse(htmlString: String, baseURL: URL) -> ParseResult {
        do {
            let doc = try SwiftSoup.parse(htmlString, baseURL.absoluteString)
            let links = extractLinks(from: doc, baseURL: baseURL)
            return ParseResult(links: links, document: doc, parseError: nil)
        } catch {
            return ParseResult(links: [], document: nil, parseError: error.localizedDescription)
        }
    }

    // MARK: — Link Extraction

    private static func extractLinks(from doc: Document, baseURL: URL) -> [DiscoveredLink] {
        var links: [DiscoveredLink] = []
        links.reserveCapacity(64)

        // <a href="...">
        if let anchors = try? doc.select("a[href]") {
            for el in anchors {
                guard let href = try? el.attr("href"), !href.isEmpty else { continue }
                let rel = (try? el.attr("rel")) ?? ""
                let text = (try? el.text()) ?? ""
                links.append(DiscoveredLink(
                    url: resolveURL(href, base: baseURL),
                    tag: .anchor,
                    rel: rel.isEmpty ? nil : rel,
                    anchorText: text.isEmpty ? nil : String(text.prefix(500)),
                    isNofollow: rel.lowercased().contains("nofollow")
                ))
            }
        }

        // <link rel="canonical">
        if let canonicals = try? doc.select("link[rel~=(?i)canonical]") {
            for el in canonicals {
                guard let href = try? el.attr("href"), !href.isEmpty else { continue }
                links.append(DiscoveredLink(
                    url: resolveURL(href, base: baseURL),
                    tag: .canonical, rel: "canonical",
                    anchorText: nil, isNofollow: false
                ))
            }
        }

        // <link rel="alternate" hreflang="...">
        if let hreflangs = try? doc.select("link[rel~=(?i)alternate][hreflang]") {
            for el in hreflangs {
                guard let href = try? el.attr("href"), !href.isEmpty else { continue }
                let lang = (try? el.attr("hreflang")) ?? ""
                links.append(DiscoveredLink(
                    url: resolveURL(href, base: baseURL),
                    tag: .hreflang, rel: "alternate hreflang=\(lang)",
                    anchorText: nil, isNofollow: false
                ))
            }
        }

        // <link rel="next">, <link rel="prev">
        if let pagination = try? doc.select("link[rel~=(?i)(next|prev|previous)]") {
            for el in pagination {
                guard let href = try? el.attr("href"), !href.isEmpty else { continue }
                let rel = (try? el.attr("rel")) ?? ""
                links.append(DiscoveredLink(
                    url: resolveURL(href, base: baseURL),
                    tag: .link, rel: rel,
                    anchorText: nil, isNofollow: false
                ))
            }
        }

        // <img src="...">
        if let images = try? doc.select("img[src]") {
            for el in images {
                guard let src = try? el.attr("src"), !src.isEmpty else { continue }
                links.append(DiscoveredLink(
                    url: resolveURL(src, base: baseURL),
                    tag: .image, rel: nil,
                    anchorText: (try? el.attr("alt")),
                    isNofollow: false
                ))
            }
        }

        // <script src="...">
        if let scripts = try? doc.select("script[src]") {
            for el in scripts {
                guard let src = try? el.attr("src"), !src.isEmpty else { continue }
                links.append(DiscoveredLink(
                    url: resolveURL(src, base: baseURL),
                    tag: .script, rel: nil,
                    anchorText: nil, isNofollow: false
                ))
            }
        }

        // <iframe src="..."> (shallow — not crawled, but recorded)
        if let iframes = try? doc.select("iframe[src]") {
            for el in iframes {
                guard let src = try? el.attr("src"), !src.isEmpty else { continue }
                links.append(DiscoveredLink(
                    url: resolveURL(src, base: baseURL),
                    tag: .iframe, rel: nil,
                    anchorText: nil, isNofollow: true
                ))
            }
        }

        return links
    }

    // MARK: — URL Resolution

    /// Resolve a potentially-relative URL string against the page base URL.
    /// Returns the raw string unchanged if resolution fails (caller will normalise later).
    private static func resolveURL(_ href: String, base: URL) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("javascript:") || trimmed.hasPrefix("mailto:")
            || trimmed.hasPrefix("tel:") || trimmed.hasPrefix("data:") {
            return trimmed
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteString ?? trimmed
    }
}
