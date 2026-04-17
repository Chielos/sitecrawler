import XCTest
@testable import IndexPilot

final class IssueEngineTests: XCTestCase {

    private let engine = IssueEngine()
    private let sessionID = UUID()

    private func makeURL(statusCode: Int? = 200, title: String? = "Good Title",
                         isIndexable: Bool = true, depth: Int = 2) -> CrawledURL {
        var u = CrawledURL(
            sessionID: sessionID,
            url: "https://example.com/page",
            normalizedURL: "https://example.com/page",
            crawlDepth: depth,
            source: .crawl,
            isInternal: true
        )
        u.statusCode = statusCode
        u.contentType = "text/html; charset=utf-8"
        u.fetchedAt = Date()
        u.title = title
        u.titleLength = title?.count
        u.h1 = "A Heading"
        u.h1Count = 1
        u.isIndexable = isIndexable
        return u
    }

    // MARK: — HTTP Checks

    func testDetects404() {
        var u = makeURL(statusCode: 404)
        u.isIndexable = false
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "http_4xx" })
    }

    func testDetects500() {
        var u = makeURL(statusCode: 500)
        u.isIndexable = false
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "http_5xx" })
    }

    func testNoHTTPIssueFor200() {
        let u = makeURL(statusCode: 200)
        let issues = engine.evaluate(u)
        XCTAssertFalse(issues.contains { $0.issueKey == "http_4xx" || $0.issueKey == "http_5xx" })
    }

    // MARK: — Title Checks

    func testDetectsMissingTitle() {
        let u = makeURL(title: nil)
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "missing_title" })
    }

    func testDetectsTitleTooShort() {
        let u = makeURL(title: "Hi")  // 2 chars
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "title_too_short" })
    }

    func testDetectsTitleTooLong() {
        let longTitle = String(repeating: "a", count: 70)
        let u = makeURL(title: longTitle)
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "title_too_long" })
    }

    func testGoodTitleNoIssue() {
        let u = makeURL(title: "A Good Page Title That Is Just Right")
        let issues = engine.evaluate(u)
        XCTAssertFalse(issues.contains { $0.issueKey == "missing_title" })
        XCTAssertFalse(issues.contains { $0.issueKey == "title_too_short" })
        XCTAssertFalse(issues.contains { $0.issueKey == "title_too_long" })
    }

    // MARK: — Heading Checks

    func testDetectsMissingH1() {
        var u = makeURL()
        u.h1 = nil
        u.h1Count = 0
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "missing_h1" })
    }

    func testDetectsMultipleH1() {
        var u = makeURL()
        u.h1Count = 3
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "multiple_h1" })
    }

    // MARK: — Redirect Checks

    func testDetectsRedirectChain() {
        var u = makeURL(statusCode: 200)
        u.redirectChain = [
            RedirectHop(fromURL: "https://example.com/a", toURL: "https://example.com/b", statusCode: 301),
            RedirectHop(fromURL: "https://example.com/b", toURL: "https://example.com/c", statusCode: 302),
        ]
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "redirect_chain" })
    }

    func testSingleRedirectNotChain() {
        var u = makeURL(statusCode: 200)
        u.redirectChain = [
            RedirectHop(fromURL: "https://example.com/old", toURL: "https://example.com/new", statusCode: 301),
        ]
        let issues = engine.evaluate(u)
        XCTAssertFalse(issues.contains { $0.issueKey == "redirect_chain" })
    }

    // MARK: — Depth

    func testDetectsExcessiveDepth() {
        let u = makeURL(depth: 10)
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "excessive_crawl_depth" })
    }

    // MARK: — Thin Content

    func testDetectsThinContent() {
        var u = makeURL()
        u.wordCount = 50
        let issues = engine.evaluate(u)
        XCTAssertTrue(issues.contains { $0.issueKey == "thin_content" })
    }

    func testSufficientContentNoIssue() {
        var u = makeURL()
        u.wordCount = 500
        let issues = engine.evaluate(u)
        XCTAssertFalse(issues.contains { $0.issueKey == "thin_content" })
    }

    // MARK: — Non-Indexable Pages Skip Certain Checks

    func testSkipsTitleCheckForNonIndexable() {
        var u = makeURL(statusCode: 301, title: nil, isIndexable: false)
        u.indexabilityReason = .redirect
        let issues = engine.evaluate(u)
        XCTAssertFalse(issues.contains { $0.issueKey == "missing_title" })
    }

    // MARK: — Issue Severity

    func testHTTPErrorIssueHasErrorSeverity() {
        let u = makeURL(statusCode: 404, isIndexable: false)
        let issues = engine.evaluate(u)
        let issue = issues.first { $0.issueKey == "http_4xx" }
        XCTAssertEqual(issue?.severity, .error)
    }
}
