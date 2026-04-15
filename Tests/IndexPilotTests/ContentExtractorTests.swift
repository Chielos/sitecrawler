import XCTest
import SwiftSoup
@testable import IndexPilot

final class ContentExtractorTests: XCTestCase {

    private func extract(_ html: String, url: String = "https://example.com/page") -> ContentExtractor.ExtractionResult {
        let doc = try! SwiftSoup.parse(html, url)
        return ContentExtractor.extract(document: doc, responseHeaders: [:], pageURL: URL(string: url)!)
    }

    // MARK: — Title

    func testExtractsTitle() {
        let r = extract("<html><head><title>My Page Title</title></head><body></body></html>")
        XCTAssertEqual(r.title, "My Page Title")
        XCTAssertEqual(r.titleLength, 13)
    }

    func testTrimsTitle() {
        let r = extract("<title>  Padded Title  </title>")
        XCTAssertEqual(r.title, "Padded Title")
    }

    func testNilTitleWhenMissing() {
        let r = extract("<html><head></head><body></body></html>")
        XCTAssertNil(r.title)
    }

    // MARK: — Meta Description

    func testExtractsMetaDescription() {
        let r = extract("""
        <html><head>
        <meta name="description" content="A great page about things.">
        </head><body></body></html>
        """)
        XCTAssertEqual(r.metaDescription, "A great page about things.")
    }

    func testCaseInsensitiveMetaName() {
        let r = extract("""
        <meta name="Description" content="Case insensitive">
        """)
        XCTAssertEqual(r.metaDescription, "Case insensitive")
    }

    // MARK: — Headings

    func testExtractsH1() {
        let r = extract("<body><h1>The Main Heading</h1></body>")
        XCTAssertEqual(r.h1, "The Main Heading")
        XCTAssertEqual(r.h1Count, 1)
    }

    func testCountsMultipleH1s() {
        let r = extract("<h1>First</h1><h1>Second</h1>")
        XCTAssertEqual(r.h1Count, 2)
        XCTAssertEqual(r.h1, "First")
    }

    func testCountsH2s() {
        let r = extract("<h2>A</h2><h2>B</h2><h2>C</h2>")
        XCTAssertEqual(r.h2Count, 3)
    }

    // MARK: — Canonical

    func testExtractsCanonical() {
        let r = extract("""
        <head><link rel="canonical" href="https://example.com/canonical-page"></head>
        """)
        XCTAssertEqual(r.canonicalURL, "https://example.com/canonical-page")
    }

    func testResolvesRelativeCanonical() {
        let r = extract("""
        <head><link rel="canonical" href="/canonical-page"></head>
        """, url: "https://example.com/some/deep/page")
        XCTAssertEqual(r.canonicalURL, "https://example.com/canonical-page")
    }

    // MARK: — Robots Directives

    func testNoindexMetaTag() {
        let r = extract("""
        <head><meta name="robots" content="noindex, nofollow"></head>
        """)
        XCTAssertTrue(r.robotsDirectives.noindex)
        XCTAssertTrue(r.robotsDirectives.nofollow)
    }

    func testNoneDirectiveImpliesNoindexNofollow() {
        let r = extract("""
        <head><meta name="robots" content="none"></head>
        """)
        XCTAssertTrue(r.robotsDirectives.noindex)
        XCTAssertTrue(r.robotsDirectives.nofollow)
    }

    func testRobotsHeaderDirective() {
        let doc = try! SwiftSoup.parse("<html></html>")
        let result = ContentExtractor.extract(
            document: doc,
            responseHeaders: ["x-robots-tag": "noindex"],
            pageURL: URL(string: "https://example.com/")!
        )
        XCTAssertTrue(result.robotsDirectives.noindex)
        XCTAssertEqual(result.robotsDirectives.source, "header")
    }

    // MARK: — Hreflang

    func testExtractsHreflangTags() {
        let r = extract("""
        <head>
        <link rel="alternate" hreflang="en" href="https://example.com/en/page">
        <link rel="alternate" hreflang="fr" href="https://example.com/fr/page">
        <link rel="alternate" hreflang="x-default" href="https://example.com/page">
        </head>
        """)
        XCTAssertEqual(r.hreflangTags.count, 3)
        XCTAssertTrue(r.hreflangTags.contains { $0.lang == "en" })
        XCTAssertTrue(r.hreflangTags.contains { $0.lang == "fr" })
    }

    // MARK: — Structured Data

    func testExtractsStructuredDataTypes() {
        let r = extract("""
        <head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Article","name":"Test"}
        </script>
        </head>
        """)
        XCTAssertTrue(r.structuredDataTypes.contains("Article"))
    }

    // MARK: — Word Count

    func testEstimatesWordCount() {
        let r = extract("<body><p>Hello world this is a test sentence with ten words.</p></body>")
        XCTAssertGreaterThan(r.wordCount, 5)
    }

    // MARK: — Content Hash

    func testContentHashIsConsistent() {
        let html = "<body><p>Same content</p></body>"
        let r1 = extract(html)
        let r2 = extract(html)
        XCTAssertEqual(r1.contentHash, r2.contentHash)
    }

    func testDifferentContentDifferentHash() {
        let r1 = extract("<body><p>Content A</p></body>")
        let r2 = extract("<body><p>Content B</p></body>")
        XCTAssertNotEqual(r1.contentHash, r2.contentHash)
    }
}
