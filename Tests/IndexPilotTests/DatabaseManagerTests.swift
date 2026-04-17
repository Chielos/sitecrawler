import XCTest
import GRDB
@testable import IndexPilot

final class DatabaseManagerTests: XCTestCase {

    private var db: DatabaseManager!

    override func setUp() async throws {
        db = try DatabaseManager()  // In-memory database
    }

    // MARK: — Projects

    func testInsertAndFetchProject() throws {
        let project = Project(
            name: "Test Site",
            seedURLs: ["https://example.com"],
            configuration: CrawlConfiguration()
        )
        try db.insertProject(project)

        let projects = try db.fetchAllProjects()
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Test Site")
        XCTAssertEqual(projects[0].seedURLs, ["https://example.com"])
    }

    func testUpdateProject() throws {
        var project = Project(name: "Original", seedURLs: ["https://a.com"])
        try db.insertProject(project)

        project.name = "Updated"
        try db.updateProject(project)

        let projects = try db.fetchAllProjects()
        XCTAssertEqual(projects[0].name, "Updated")
    }

    func testDeleteProject() throws {
        let project = Project(name: "To Delete", seedURLs: ["https://a.com"])
        try db.insertProject(project)
        try db.deleteProject(id: project.id)
        XCTAssertEqual(try db.fetchAllProjects().count, 0)
    }

    // MARK: — Sessions

    func testInsertAndFetchSession() throws {
        let project = Project(name: "P", seedURLs: ["https://a.com"])
        try db.insertProject(project)

        let session = CrawlSession(projectID: project.id, seedURLs: ["https://a.com"], configuration: CrawlConfiguration())
        try db.insertSession(session)

        let fetched = try db.fetchSession(id: session.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.status, .queued)
    }

    func testUpdateSessionStatus() throws {
        let project = Project(name: "P", seedURLs: ["https://a.com"])
        try db.insertProject(project)
        let session = CrawlSession(projectID: project.id, seedURLs: [], configuration: CrawlConfiguration())
        try db.insertSession(session)

        try db.updateSessionStatus(session.id, status: .completed, completedAt: Date())
        let fetched = try db.fetchSession(id: session.id)
        XCTAssertEqual(fetched?.status, .completed)
        XCTAssertNotNil(fetched?.completedAt)
    }

    // MARK: — CrawledURLs

    func testInsertAndFetchCrawledURL() throws {
        let project = Project(name: "P", seedURLs: ["https://a.com"])
        try db.insertProject(project)
        let session = CrawlSession(projectID: project.id, seedURLs: [], configuration: CrawlConfiguration())
        try db.insertSession(session)

        var u = CrawledURL(
            sessionID: session.id,
            url: "https://a.com/page",
            normalizedURL: "https://a.com/page",
            crawlDepth: 1,
            source: .crawl,
            isInternal: true
        )
        u.statusCode = 200
        u.title = "The Page"
        try db.insertCrawledURL(u)

        let fetched = try db.fetchURL(sessionID: session.id, normalizedURL: "https://a.com/page")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.statusCode, 200)
        XCTAssertEqual(fetched?.title, "The Page")
    }

    func testBatchInsertPerformance() throws {
        let project = Project(name: "P", seedURLs: ["https://a.com"])
        try db.insertProject(project)
        let session = CrawlSession(projectID: project.id, seedURLs: [], configuration: CrawlConfiguration())
        try db.insertSession(session)

        let urls = (0..<500).map { i -> CrawledURL in
            CrawledURL(
                sessionID: session.id,
                url: "https://a.com/page-\(i)",
                normalizedURL: "https://a.com/page-\(i)",
                crawlDepth: 1,
                source: .crawl,
                isInternal: true
            )
        }

        measure {
            try? db.insertCrawledURLs(urls)
        }
    }

    // MARK: — Issues

    func testInsertAndFetchIssues() throws {
        let project = Project(name: "P", seedURLs: ["https://a.com"])
        try db.insertProject(project)
        let session = CrawlSession(projectID: project.id, seedURLs: [], configuration: CrawlConfiguration())
        try db.insertSession(session)

        let def = IssueDefinition(
            key: "missing_title",
            severity: .error,
            category: .titles,
            title: "Missing Title",
            description: "No title tag",
            remediation: "Add a title"
        )
        let issue = Issue(sessionID: session.id, url: "https://a.com/page", definition: def)
        try db.insertIssues([issue])

        let fetched = try db.fetchIssues(sessionID: session.id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].issueKey, "missing_title")
    }

    func testDuplicateIssueIgnored() throws {
        let project = Project(name: "P", seedURLs: ["https://a.com"])
        try db.insertProject(project)
        let session = CrawlSession(projectID: project.id, seedURLs: [], configuration: CrawlConfiguration())
        try db.insertSession(session)

        let def = IssueDefinition(key: "test_key", severity: .info, category: .http, title: "T", description: "D", remediation: "R")
        let issue = Issue(sessionID: session.id, url: "https://a.com/page", definition: def)
        try db.insertIssues([issue, issue])  // inserting twice

        let fetched = try db.fetchIssues(sessionID: session.id)
        XCTAssertEqual(fetched.count, 1)  // deduped by UNIQUE constraint
    }
}
