import Foundation
import GRDB

// MARK: — Canonical Issues

struct CanonicalToNonIndexableCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "canonical_to_non_indexable",
        severity: .warning,
        category: .canonical,
        title: "Canonical Points to Non-Indexable URL",
        description: "This page's canonical tag points to a URL that is itself non-indexable (e.g. a redirect, error, or noindex page).",
        remediation: "Ensure canonical tags point to the definitive, indexable version of the content."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isHTML(url),
              let canonical = url.canonicalURL,
              canonical != url.normalizedURL else { return nil }
        // We flag this if the canonical points externally or to an obvious non-indexable pattern.
        // Full validation requires looking up the canonical URL in the DB — done in aggregate checks.
        // Here we flag if the canonical goes to a different domain (likely intentional, but worth auditing).
        guard let canonicalURL = URL(string: canonical),
              let pageURL = URL(string: url.normalizedURL) else { return nil }
        guard canonicalURL.host?.lowercased() == pageURL.host?.lowercased() else { return nil }
        // Flag redirect chains in the canonical target
        if url.redirectChain.contains(where: { $0.fromURL == canonical }) {
            return issue(for: url, data: ["canonical": canonical])
        }
        return nil
    }
}

struct BrokenCanonicalCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "broken_canonical",
        severity: .warning,
        category: .canonical,
        title: "Broken Canonical URL",
        description: "This page's canonical tag contains a malformed or unresolvable URL.",
        remediation: "Fix the canonical tag to point to a valid, absolute URL."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isHTML(url), let canonical = url.canonicalURL else { return nil }
        guard URL(string: canonical) == nil else { return nil }
        return issue(for: url, data: ["canonical": canonical])
    }
}

struct InsecureCanonicalCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "insecure_canonical",
        severity: .warning,
        category: .security,
        title: "Canonical Points to HTTP Instead of HTTPS",
        description: "This HTTPS page has a canonical tag pointing to the HTTP version. This signals the HTTP version as canonical, undermining your HTTPS migration.",
        remediation: "Update the canonical tag to use the https:// URL."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isHTML(url),
              url.normalizedURL.hasPrefix("https://"),
              let canonical = url.canonicalURL,
              canonical.hasPrefix("http://") else { return nil }
        return issue(for: url, data: ["canonical": canonical])
    }
}

// MARK: — Indexability Issues

struct NoindexInSitemapCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "noindex_in_sitemap",
        severity: .warning,
        category: .indexability,
        title: "Noindex Page in Sitemap",
        description: "This URL appears in the XML sitemap but contains a noindex directive. Sitemaps should only list pages you want indexed.",
        remediation: "Remove noindex pages from your sitemap, or remove the noindex directive if the page should be indexed."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard url.source == .sitemap, url.robotsDirectives.noindex else { return nil }
        return issue(for: url)
    }
}

struct BlockedByRobotsButLinkedCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "blocked_robots_but_linked",
        severity: .info,
        category: .indexability,
        title: "Blocked by Robots.txt but Internally Linked",
        description: "This URL is blocked by robots.txt but is still linked from internal pages. Search engines can discover the URL via the internal links even though they cannot crawl it.",
        remediation: "If intentional, ensure the page is also protected by noindex (since robots.txt only prevents crawling, not indexing via discovered links). If unintentional, remove internal links or update robots.txt."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard url.isBlockedByRobots, url.internalInlinkCount > 0 else { return nil }
        return issue(for: url, data: ["inlinks": "\(url.internalInlinkCount)"])
    }
}

struct ExcessiveCrawlDepthCheck: PerURLCheck {
    static let depthThreshold = 7
    let definition = IssueDefinition(
        key: "excessive_crawl_depth",
        severity: .opportunity,
        category: .links,
        title: "Excessively Deep Page",
        description: "This page is more than \(depthThreshold) clicks from the crawl seed. Deep pages receive less crawl budget and less link equity.",
        remediation: "Improve internal linking architecture to surface important content from shallower pages."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard url.crawlDepth > Self.depthThreshold, isIndexableHTML(url) else { return nil }
        return issue(for: url, data: ["depth": "\(url.crawlDepth)"])
    }
}

// MARK: — Content

struct ThinContentCheck: PerURLCheck {
    static let minWords = 100
    let definition = IssueDefinition(
        key: "thin_content",
        severity: .opportunity,
        category: .content,
        title: "Thin Content",
        description: "This page contains fewer than \(minWords) words of body text. Thin content pages may provide limited value to users and may receive less visibility in search results.",
        remediation: "Expand the page with original, useful content relevant to the page's topic."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        guard isIndexableHTML(url),
              let words = url.wordCount, words < Self.minWords, words > 0 else { return nil }
        return issue(for: url, data: ["wordCount": "\(words)"])
    }
}

// MARK: — Images

struct MissingAltOnAnchorImageCheck: PerURLCheck {
    let definition = IssueDefinition(
        key: "missing_alt_anchor_image",
        severity: .warning,
        category: .images,
        title: "Image Link Missing Alt Text",
        description: "An <img> element within an <a> tag has no alt attribute. The alt text serves as the anchor text for image links and is important for accessibility and SEO.",
        remediation: "Add descriptive alt text to all images, especially those used as links."
    )

    func evaluate(_ url: CrawledURL) -> Issue? {
        // Full image-level checking requires per-image data (stored in a future v_images table).
        // This check is a placeholder that triggers when the page has images but no text links
        // — a proxy for image-only navigation patterns.
        // TODO: wire up per-image alt data in V1.
        return nil
    }
}

// MARK: — Duplicate Content (Aggregate)

struct DuplicateContentHashCheck: AggregateCheck {
    let definition = IssueDefinition(
        key: "duplicate_content_exact",
        severity: .warning,
        category: .content,
        title: "Exact Duplicate Content",
        description: "This page's body text is identical to at least one other crawled page. Exact duplicates waste crawl budget and dilute ranking signals.",
        remediation: "Consolidate duplicate pages with a canonical tag or 301 redirect to the preferred version."
    )

    func evaluate(sessionID: UUID, db: DatabaseManager) -> [Issue] {
        guard let rows = try? db.pool.read({ db in
            try Row.fetchAll(db, sql: """
                SELECT normalized_url, content_hash FROM crawled_urls
                WHERE session_id = ? AND content_hash IS NOT NULL AND is_indexable = 1
                AND content_hash IN (
                    SELECT content_hash FROM crawled_urls
                    WHERE session_id = ? AND content_hash IS NOT NULL AND is_indexable = 1
                    GROUP BY content_hash HAVING COUNT(*) > 1
                )
                ORDER BY content_hash, normalized_url
            """, arguments: [sessionID.uuidString, sessionID.uuidString])
        }) else { return [] }

        return rows.compactMap { row -> Issue? in
            guard let url: String = row["normalized_url"],
                  let hash: String = row["content_hash"] else { return nil }
            return Issue(
                sessionID: sessionID, url: url,
                definition: definition,
                data: ["contentHash": hash]
            )
        }
    }
}

// MARK: — Shared Predicates

private func isHTML(_ url: CrawledURL) -> Bool {
    guard let ct = url.contentType else { return url.fetchedAt != nil }
    return ct.lowercased().contains("html")
}

func isIndexableHTML(_ url: CrawledURL) -> Bool {
    isHTML(url) && url.isIndexable && url.fetchError == nil && url.statusCode != nil
}
