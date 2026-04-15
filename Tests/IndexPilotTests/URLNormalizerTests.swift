import XCTest
@testable import IndexPilot

final class URLNormalizerTests: XCTestCase {

    private let normalizer = URLNormalizer()

    // MARK: — Basic Normalization

    func testLowercasesSchemeAndHost() {
        let result = normalizer.normalize("HTTPS://Example.COM/path")
        XCTAssertEqual(result?.absoluteString, "https://example.com/path")
    }

    func testStripsDefaultHTTPPort() {
        let result = normalizer.normalize("http://example.com:80/page")
        XCTAssertEqual(result?.absoluteString, "http://example.com/page")
    }

    func testStripsDefaultHTTPSPort() {
        let result = normalizer.normalize("https://example.com:443/page")
        XCTAssertEqual(result?.absoluteString, "https://example.com/page")
    }

    func testKeepsNonDefaultPort() {
        let result = normalizer.normalize("https://example.com:8080/page")
        XCTAssertEqual(result?.absoluteString, "https://example.com:8080/page")
    }

    func testStripsFragment() {
        let result = normalizer.normalize("https://example.com/page#section")
        XCTAssertEqual(result?.absoluteString, "https://example.com/page")
    }

    func testEmptyPathBecomesSlash() {
        let result = normalizer.normalize("https://example.com")
        XCTAssertEqual(result?.absoluteString, "https://example.com/")
    }

    // MARK: — Dot Segments

    func testResolvesDotSegments() {
        let result = normalizer.normalize("https://example.com/a/b/../c")
        XCTAssertEqual(result?.absoluteString, "https://example.com/a/c")
    }

    func testResolvesSingleDotSegments() {
        let result = normalizer.normalize("https://example.com/a/./b")
        XCTAssertEqual(result?.absoluteString, "https://example.com/a/b")
    }

    // MARK: — Trailing Slash

    func testStripsTrailingSlash() {
        var config = CrawlConfiguration()
        config.normalizeTrailingSlash = true
        let n = URLNormalizer(configuration: config)
        let result = n.normalize("https://example.com/about/")
        XCTAssertEqual(result?.absoluteString, "https://example.com/about")
    }

    func testPreservesRootSlash() {
        let result = normalizer.normalize("https://example.com/")
        XCTAssertEqual(result?.absoluteString, "https://example.com/")
    }

    // MARK: — Tracking Parameters

    func testStripsUTMParameters() {
        var config = CrawlConfiguration()
        config.stripTrackingParameters = true
        let n = URLNormalizer(configuration: config)
        let result = n.normalize("https://example.com/page?utm_source=google&utm_medium=cpc&id=123")
        XCTAssertEqual(result?.absoluteString, "https://example.com/page?id=123")
    }

    func testStripsGCLID() {
        var config = CrawlConfiguration()
        config.stripTrackingParameters = true
        let n = URLNormalizer(configuration: config)
        let result = n.normalize("https://example.com/?gclid=abc123&page=1")
        XCTAssertEqual(result?.absoluteString, "https://example.com/?page=1")
    }

    // MARK: — Scheme Filtering

    func testRejectsJavaScript() {
        XCTAssertNil(normalizer.normalize("javascript:void(0)"))
    }

    func testRejectsMailto() {
        XCTAssertNil(normalizer.normalize("mailto:test@example.com"))
    }

    func testRejectsDataURIs() {
        XCTAssertNil(normalizer.normalize("data:text/html,<h1>hi</h1>"))
    }

    func testRejectsNonHTTPScheme() {
        XCTAssertNil(normalizer.normalize("ftp://example.com/file.txt"))
    }

    // MARK: — Relative URL Resolution

    func testResolvesRelativeURL() {
        let base = URL(string: "https://example.com/section/page.html")!
        let result = normalizer.normalize("../other.html", relativeTo: base)
        XCTAssertEqual(result?.absoluteString, "https://example.com/other.html")
    }

    func testResolvesAbsolutePath() {
        let base = URL(string: "https://example.com/section/page.html")!
        let result = normalizer.normalize("/about", relativeTo: base)
        XCTAssertEqual(result?.absoluteString, "https://example.com/about")
    }

    // MARK: — Scope

    func testInScopeWithSameHost() {
        let config = CrawlConfiguration()
        let n = URLNormalizer(configuration: config)
        let url = URL(string: "https://example.com/page")!
        let seed = URL(string: "https://example.com")!
        XCTAssertTrue(n.isInScope(url, seedURL: seed))
    }

    func testOutOfScopeForDifferentHost() {
        let config = CrawlConfiguration()
        let n = URLNormalizer(configuration: config)
        let url = URL(string: "https://other.com/page")!
        let seed = URL(string: "https://example.com")!
        XCTAssertFalse(n.isInScope(url, seedURL: seed))
    }
}
