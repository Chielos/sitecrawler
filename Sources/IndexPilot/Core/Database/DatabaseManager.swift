import GRDB
import Foundation

/// Single access point to IndexPilot's local SQLite database.
/// Uses GRDB DatabasePool for concurrent reads and serialized writes.
/// All write operations are performed on the write queue.
/// Read operations can safely run concurrently from any thread.
final class DatabaseManager: Sendable {

    let pool: DatabasePool

    // MARK: — Initialisation

    init(path: String) throws {
        var config = Configuration()
        config.label = "IndexPilot.DB"
        config.maximumReaderCount = 4
        pool = try DatabasePool(path: path, configuration: config)
        try migrate()
    }

    /// In-memory database for testing.
    init() throws {
        var config = Configuration()
        config.label = "IndexPilot.DB.InMemory"
        pool = try DatabasePool(path: ":memory:", configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        Migrations.register(in: &migrator)
        try migrator.migrate(pool)
    }

    // MARK: — Default Database Path

    static func defaultPath() throws -> String {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("IndexPilot", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("IndexPilot.sqlite").path
    }
}

// MARK: — Project Operations

extension DatabaseManager {

    func insertProject(_ project: Project) throws {
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO projects (id, name, seed_urls, config_json, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [
                project.id.uuidString,
                project.name,
                jsonString(project.seedURLs),
                jsonString(project.configuration),
                project.createdAt.timeIntervalSince1970,
                project.updatedAt.timeIntervalSince1970,
            ])
        }
    }

    func updateProject(_ project: Project) throws {
        try pool.write { db in
            try db.execute(sql: """
                UPDATE projects SET name = ?, seed_urls = ?, config_json = ?, updated_at = ?
                WHERE id = ?
            """, arguments: [
                project.name,
                jsonString(project.seedURLs),
                jsonString(project.configuration),
                Date().timeIntervalSince1970,
                project.id.uuidString,
            ])
        }
    }

    func fetchAllProjects() throws -> [Project] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM projects ORDER BY created_at DESC")
            return try rows.map { try projectFromRow($0) }
        }
    }

    func deleteProject(id: UUID) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM projects WHERE id = ?", arguments: [id.uuidString])
        }
    }

    private func projectFromRow(_ row: Row) throws -> Project {
        let config: CrawlConfiguration = try decodeJSON(row["config_json"])
        let urls: [String] = try decodeJSON(row["seed_urls"])
        return Project(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            seedURLs: urls,
            configuration: config,
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"])
        )
    }
}

// MARK: — CrawlSession Operations

extension DatabaseManager {

    func insertSession(_ session: CrawlSession) throws {
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO crawl_sessions
                    (id, project_id, status, seed_urls, config_json, started_at, stats_json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                session.id.uuidString,
                session.projectID.uuidString,
                session.status.rawValue,
                jsonString(session.seedURLs),
                jsonString(session.configuration),
                session.startedAt.timeIntervalSince1970,
                jsonString(session.stats),
            ])
        }
    }

    func updateSessionStatus(_ sessionID: UUID, status: CrawlSession.Status, completedAt: Date? = nil) throws {
        try pool.write { db in
            try db.execute(sql: """
                UPDATE crawl_sessions SET status = ?, completed_at = ? WHERE id = ?
            """, arguments: [
                status.rawValue,
                completedAt?.timeIntervalSince1970,
                sessionID.uuidString,
            ])
        }
    }

    func updateSessionStats(_ sessionID: UUID, stats: CrawlStats) throws {
        try pool.write { db in
            try db.execute(sql: """
                UPDATE crawl_sessions SET stats_json = ? WHERE id = ?
            """, arguments: [jsonString(stats), sessionID.uuidString])
        }
    }

    func saveCheckpoint(_ sessionID: UUID, checkpoint: FrontierCheckpoint) throws {
        try pool.write { db in
            try db.execute(sql: """
                UPDATE crawl_sessions SET frontier_checkpoint_json = ? WHERE id = ?
            """, arguments: [jsonString(checkpoint), sessionID.uuidString])
        }
    }

    func fetchSessions(forProject projectID: UUID) throws -> [CrawlSession] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM crawl_sessions WHERE project_id = ? ORDER BY started_at DESC",
                arguments: [projectID.uuidString]
            )
            return try rows.map { try sessionFromRow($0) }
        }
    }

    func fetchSession(id: UUID) throws -> CrawlSession? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM crawl_sessions WHERE id = ?",
                arguments: [id.uuidString]
            ) else { return nil }
            return try sessionFromRow(row)
        }
    }

    private func sessionFromRow(_ row: Row) throws -> CrawlSession {
        let config: CrawlConfiguration = try decodeJSON(row["config_json"])
        let seedURLs: [String] = try decodeJSON(row["seed_urls"])
        let stats: CrawlStats = try decodeJSON(row["stats_json"])
        var session = CrawlSession(
            id: UUID(uuidString: row["id"])!,
            projectID: UUID(uuidString: row["project_id"])!,
            seedURLs: seedURLs,
            configuration: config,
            startedAt: Date(timeIntervalSince1970: row["started_at"])
        )
        session.status = CrawlSession.Status(rawValue: row["status"]) ?? .failed
        session.stats = stats
        if let completedTS: Double = row["completed_at"] {
            session.completedAt = Date(timeIntervalSince1970: completedTS)
        }
        if let checkpointJSON: String = row["frontier_checkpoint_json"] {
            session.frontierCheckpoint = try? JSONDecoder().decode(
                FrontierCheckpoint.self,
                from: Data(checkpointJSON.utf8)
            )
        }
        return session
    }
}

// MARK: — CrawledURL Operations

extension DatabaseManager {

    /// Batch-insert crawled URLs within a single transaction.
    /// Caller should batch ≈50 URLs per call to balance transaction size vs write latency.
    func insertCrawledURLs(_ urls: [CrawledURL]) throws {
        guard !urls.isEmpty else { return }
        try pool.write { db in
            for u in urls {
                try insertCrawledURL(u, db: db)
            }
        }
    }

    func insertCrawledURL(_ u: CrawledURL) throws {
        try pool.write { db in
            try insertCrawledURL(u, db: db)
        }
    }

    private func insertCrawledURL(_ u: CrawledURL, db: Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO crawled_urls (
                id, session_id, url, normalized_url, discovered_at, fetched_at,
                crawl_depth, source, is_internal,
                status_code, content_type, final_url, redirect_chain_json,
                response_time_ms, content_size_bytes, fetch_error,
                title, title_length, meta_description, meta_description_length,
                h1, h1_count, h2_count,
                canonical_url, robots_directives_json, hreflang_json,
                og_title, og_description, structured_data_types,
                internal_inlink_count, internal_outlink_count,
                external_outlink_count, image_count,
                word_count, content_hash,
                is_indexable, indexability_reason, is_blocked_by_robots
            ) VALUES (
                ?,?,?,?,?,?,  ?,?,?,  ?,?,?,?,  ?,?,?,
                ?,?,?,?,  ?,?,?,  ?,?,?,  ?,?,?,  ?,?,?,?,  ?,?,  ?,?,?
            )
        """, arguments: [
            u.id.uuidString, u.sessionID.uuidString, u.url, u.normalizedURL,
            u.discoveredAt.timeIntervalSince1970, u.fetchedAt?.timeIntervalSince1970,
            u.crawlDepth, u.source.rawValue, u.isInternal ? 1 : 0,
            u.statusCode, u.contentType, u.finalURL,
            jsonString(u.redirectChain),
            u.responseTimeMs, u.contentSizeBytes,
            u.fetchError.map { $0.displayString },
            u.title, u.titleLength,
            u.metaDescription, u.metaDescriptionLength,
            u.h1, u.h1Count, u.h2Count,
            u.canonicalURL,
            jsonString(u.robotsDirectives), jsonString(u.hreflangTags),
            u.openGraphTitle, u.openGraphDescription,
            jsonString(u.structuredDataTypes),
            u.internalInlinkCount, u.internalOutlinkCount,
            u.externalOutlinkCount, u.imageCount,
            u.wordCount, u.contentHash,
            u.isIndexable ? 1 : 0,
            u.indexabilityReason?.rawValue,
            u.isBlockedByRobots ? 1 : 0,
        ])
    }

    func incrementInlinkCount(sessionID: UUID, targetURL: String) throws {
        try pool.write { db in
            try db.execute(sql: """
                UPDATE crawled_urls SET internal_inlink_count = internal_inlink_count + 1
                WHERE session_id = ? AND normalized_url = ?
            """, arguments: [sessionID.uuidString, targetURL])
        }
    }

    func fetchURLs(sessionID: UUID, limit: Int = 500, offset: Int = 0) throws -> [CrawledURL] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM crawled_urls WHERE session_id = ?
                ORDER BY crawl_depth ASC, discovered_at ASC
                LIMIT ? OFFSET ?
            """, arguments: [sessionID.uuidString, limit, offset])
            return rows.compactMap { crawledURLFromRow($0) }
        }
    }

    func fetchURL(sessionID: UUID, normalizedURL: String) throws -> CrawledURL? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM crawled_urls WHERE session_id = ? AND normalized_url = ?
            """, arguments: [sessionID.uuidString, normalizedURL]) else { return nil }
            return crawledURLFromRow(row)
        }
    }

    func countURLs(sessionID: UUID) throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM crawled_urls WHERE session_id = ?
            """, arguments: [sessionID.uuidString]) ?? 0
        }
    }

    private func crawledURLFromRow(_ row: Row) -> CrawledURL? {
        guard let id = UUID(uuidString: row["id"]),
              let sessionID = UUID(uuidString: row["session_id"]) else { return nil }

        var u = CrawledURL(
            id: id,
            sessionID: sessionID,
            url: row["url"],
            normalizedURL: row["normalized_url"],
            discoveredAt: Date(timeIntervalSince1970: row["discovered_at"]),
            crawlDepth: row["crawl_depth"],
            source: URLSource(rawValue: row["source"]) ?? .crawl,
            isInternal: (row["is_internal"] as Int) == 1
        )
        if let ts: Double = row["fetched_at"] { u.fetchedAt = Date(timeIntervalSince1970: ts) }
        u.statusCode = row["status_code"]
        u.contentType = row["content_type"]
        u.finalURL = row["final_url"]
        u.redirectChain = (try? decodeJSON(row["redirect_chain_json"])) ?? []
        u.responseTimeMs = row["response_time_ms"]
        u.contentSizeBytes = row["content_size_bytes"]
        u.title = row["title"]
        u.titleLength = row["title_length"]
        u.metaDescription = row["meta_description"]
        u.metaDescriptionLength = row["meta_description_length"]
        u.h1 = row["h1"]
        u.h1Count = row["h1_count"]
        u.h2Count = row["h2_count"]
        u.canonicalURL = row["canonical_url"]
        u.robotsDirectives = (try? decodeJSON(row["robots_directives_json"])) ?? RobotsDirectives()
        u.hreflangTags = (try? decodeJSON(row["hreflang_json"])) ?? []
        u.openGraphTitle = row["og_title"]
        u.openGraphDescription = row["og_description"]
        u.structuredDataTypes = (try? decodeJSON(row["structured_data_types"])) ?? []
        u.internalInlinkCount = row["internal_inlink_count"]
        u.internalOutlinkCount = row["internal_outlink_count"]
        u.externalOutlinkCount = row["external_outlink_count"]
        u.imageCount = row["image_count"]
        u.wordCount = row["word_count"]
        u.contentHash = row["content_hash"]
        u.isIndexable = (row["is_indexable"] as Int) == 1
        u.indexabilityReason = (row["indexability_reason"] as String?).flatMap { IndexabilityReason(rawValue: $0) }
        u.isBlockedByRobots = (row["is_blocked_by_robots"] as Int) == 1
        return u
    }
}

// MARK: — Issue Operations

extension DatabaseManager {

    func insertIssues(_ issues: [Issue]) throws {
        guard !issues.isEmpty else { return }
        try pool.write { db in
            for issue in issues {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO issues
                        (session_id, url, issue_key, severity, category, title, description, remediation, data_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    issue.sessionID.uuidString,
                    issue.url,
                    issue.issueKey,
                    issue.severity.rawValue,
                    issue.category.rawValue,
                    issue.title,
                    issue.description,
                    issue.remediation,
                    jsonString(issue.data),
                ])
            }
        }
    }

    func fetchIssues(sessionID: UUID, category: IssueCategory? = nil, severity: IssueSeverity? = nil) throws -> [Issue] {
        try pool.read { db in
            var sql = "SELECT * FROM issues WHERE session_id = ?"
            var arguments: [DatabaseValue] = [sessionID.uuidString.databaseValue]
            if let cat = category {
                sql += " AND category = ?"
                arguments.append(cat.rawValue.databaseValue)
            }
            if let sev = severity {
                sql += " AND severity = ?"
                arguments.append(sev.rawValue.databaseValue)
            }
            sql += " ORDER BY severity, category, url"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return rows.compactMap { issueFromRow($0) }
        }
    }

    func countIssuesByCategory(sessionID: UUID) throws -> [String: Int] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT category, COUNT(*) as cnt FROM issues WHERE session_id = ?
                GROUP BY category
            """, arguments: [sessionID.uuidString])
            var result: [String: Int] = [:]
            for row in rows {
                result[row["category"]] = row["cnt"]
            }
            return result
        }
    }

    private func issueFromRow(_ row: Row) -> Issue? {
        guard
            let sessionID = UUID(uuidString: row["session_id"]),
            let severity = IssueSeverity(rawValue: row["severity"]),
            let category = IssueCategory(rawValue: row["category"])
        else { return nil }
        let def = IssueDefinition(
            key: row["issue_key"],
            severity: severity,
            category: category,
            title: row["title"],
            description: row["description"],
            remediation: row["remediation"]
        )
        let data: [String: String] = (try? decodeJSON(row["data_json"])) ?? [:]
        let issue = Issue(
            id: UUID(),
            sessionID: sessionID,
            url: row["url"],
            definition: def,
            data: data
        )
        return issue
    }
}

// MARK: — Link Operations

extension DatabaseManager {

    func insertLinks(_ links: [Link]) throws {
        guard !links.isEmpty else { return }
        try pool.write { db in
            for link in links {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO links
                        (session_id, source_url, target_url, anchor_text, rel_json, tag_name, is_internal)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    link.sessionID.uuidString,
                    link.sourceURL,
                    link.targetURL,
                    link.anchorText,
                    jsonString(link.rel),
                    link.tagName.rawValue,
                    link.isInternal ? 1 : 0,
                ])
            }
        }
    }

    func fetchLinks(sessionID: UUID, sourceURL: String) throws -> [Link] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM links WHERE session_id = ? AND source_url = ?
            """, arguments: [sessionID.uuidString, sourceURL])
            return rows.compactMap { linkFromRow($0) }
        }
    }

    private func linkFromRow(_ row: Row) -> Link? {
        guard let sessionID = UUID(uuidString: row["session_id"]) else { return nil }
        let rel: LinkRel = (try? decodeJSON(row["rel_json"])) ?? LinkRel()
        return Link(
            sessionID: sessionID,
            sourceURL: row["source_url"],
            targetURL: row["target_url"],
            anchorText: row["anchor_text"],
            rel: rel,
            tagName: LinkTag(rawValue: row["tag_name"]) ?? .anchor,
            isInternal: (row["is_internal"] as Int) == 1
        )
    }
}

// MARK: — Robots Cache

extension DatabaseManager {

    func cacheRobots(sessionID: UUID, host: String, content: String?) throws {
        try pool.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO robots_cache (session_id, host, content, fetched_at)
                VALUES (?, ?, ?, ?)
            """, arguments: [sessionID.uuidString, host, content, Date().timeIntervalSince1970])
        }
    }

    func fetchCachedRobots(sessionID: UUID, host: String) throws -> String?? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT content FROM robots_cache WHERE session_id = ? AND host = ?
            """, arguments: [sessionID.uuidString, host]) else { return nil }
            let content: String? = row["content"]
            return .some(content)
        }
    }
}

// MARK: — Helpers

private func jsonString<T: Encodable>(_ value: T) -> String {
    let data = try? JSONEncoder().encode(value)
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

private func decodeJSON<T: Decodable>(_ string: String?) throws -> T {
    guard let s = string, let data = s.data(using: .utf8) else {
        throw DatabaseError(message: "Cannot decode nil JSON string as \(T.self)")
    }
    return try JSONDecoder().decode(T.self, from: data)
}
