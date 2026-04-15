import XCTest
@testable import IndexPilot

final class RobotsParserTests: XCTestCase {

    // MARK: — Basic Allow/Disallow

    func testAllowsAllWhenEmpty() {
        let robots = RobotsParser.parse("")
        XCTAssertTrue(RobotsParser.isAllowed(path: "/anything", robots: robots, userAgent: "IndexPilot"))
    }

    func testDisallowAll() {
        let content = """
        User-agent: *
        Disallow: /
        """
        let robots = RobotsParser.parse(content)
        XCTAssertFalse(RobotsParser.isAllowed(path: "/page", robots: robots, userAgent: "indexPilot"))
    }

    func testAllowsUnmatchedPath() {
        let content = """
        User-agent: *
        Disallow: /private/
        """
        let robots = RobotsParser.parse(content)
        XCTAssertTrue(RobotsParser.isAllowed(path: "/public/page", robots: robots, userAgent: "bot"))
        XCTAssertFalse(RobotsParser.isAllowed(path: "/private/secret", robots: robots, userAgent: "bot"))
    }

    // MARK: — Allow Overrides Disallow

    func testAllowOverridesDisallow() {
        let content = """
        User-agent: *
        Disallow: /private/
        Allow: /private/allowed.html
        """
        let robots = RobotsParser.parse(content)
        XCTAssertFalse(RobotsParser.isAllowed(path: "/private/secret", robots: robots, userAgent: "bot"))
        XCTAssertTrue(RobotsParser.isAllowed(path: "/private/allowed.html", robots: robots, userAgent: "bot"))
    }

    // MARK: — Specific UA Wins Over Wildcard

    func testSpecificUserAgentWins() {
        let content = """
        User-agent: *
        Disallow: /

        User-agent: IndexPilot
        Allow: /
        """
        let robots = RobotsParser.parse(content)
        XCTAssertTrue(RobotsParser.isAllowed(path: "/page", robots: robots, userAgent: "IndExpilot"))
        // Other bots are blocked
        XCTAssertFalse(RobotsParser.isAllowed(path: "/page", robots: robots, userAgent: "Googlebot"))
    }

    // MARK: — Wildcard Patterns

    func testWildcardMatchesMidPath() {
        let content = """
        User-agent: *
        Disallow: /search?q=*
        """
        let robots = RobotsParser.parse(content)
        XCTAssertFalse(RobotsParser.isAllowed(path: "/search?q=term", robots: robots, userAgent: "bot"))
        XCTAssertTrue(RobotsParser.isAllowed(path: "/search", robots: robots, userAgent: "bot"))
    }

    func testDollarAnchorsEnd() {
        let content = """
        User-agent: *
        Disallow: /*.pdf$
        """
        let robots = RobotsParser.parse(content)
        XCTAssertFalse(RobotsParser.isAllowed(path: "/document.pdf", robots: robots, userAgent: "bot"))
        XCTAssertTrue(RobotsParser.isAllowed(path: "/document.pdf.html", robots: robots, userAgent: "bot"))
    }

    // MARK: — Sitemap Extraction

    func testExtractsSitemaps() {
        let content = """
        User-agent: *
        Disallow:

        Sitemap: https://example.com/sitemap.xml
        Sitemap: https://example.com/sitemap2.xml
        """
        let robots = RobotsParser.parse(content)
        XCTAssertEqual(robots.sitemaps.count, 2)
        XCTAssertTrue(robots.sitemaps.contains("https://example.com/sitemap.xml"))
    }

    // MARK: — Comments and Blank Lines

    func testIgnoresComments() {
        let content = """
        # This is a comment
        User-agent: * # inline comment
        Disallow: /private/ # block this
        """
        let robots = RobotsParser.parse(content)
        XCTAssertFalse(RobotsParser.isAllowed(path: "/private/page", robots: robots, userAgent: "bot"))
    }

    func testGroupsSeperatedByBlankLine() {
        let content = """
        User-agent: Googlebot
        Disallow: /nogoogle/

        User-agent: *
        Disallow: /private/
        """
        let robots = RobotsParser.parse(content)
        XCTAssertFalse(RobotsParser.isAllowed(path: "/nogoogle/page", robots: robots, userAgent: "googlebot"))
        XCTAssertTrue(RobotsParser.isAllowed(path: "/nogoogle/page", robots: robots, userAgent: "otherbot"))
        XCTAssertFalse(RobotsParser.isAllowed(path: "/private/page", robots: robots, userAgent: "otherbot"))
    }

    // MARK: — 401/403 Handling

    func testEmptyRobotsAllowsAll() {
        let robots = RobotsParser.ParsedRobots.empty
        XCTAssertTrue(RobotsParser.isAllowed(path: "/page", robots: robots, userAgent: "bot"))
    }
}
