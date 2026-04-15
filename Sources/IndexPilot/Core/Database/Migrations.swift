import GRDB
import Foundation

/// All database migrations in order.
/// RULE: migrations are additive only. Never drop or rename columns in released versions.
enum Migrations {

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial_schema", migrate: v1InitialSchema)
        migrator.registerMigration("v1_url_queue_spillover", migrate: v1URLQueueSpillover)
        migrator.registerMigration("v1_schedules", migrate: v1Schedules)
        migrator.registerMigration("v1_content_hashes", migrate: v1ContentHashes)
    }

    // MARK: — v1 Initial Schema

    private static func v1InitialSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE projects (
                id          TEXT PRIMARY KEY NOT NULL,
                name        TEXT NOT NULL,
                seed_urls   TEXT NOT NULL DEFAULT '[]',
                config_json TEXT NOT NULL DEFAULT '{}',
                created_at  REAL NOT NULL,
                updated_at  REAL NOT NULL
            );
        """)

        try db.execute(sql: """
            CREATE TABLE crawl_sessions (
                id                          TEXT PRIMARY KEY NOT NULL,
                project_id                  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                status                      TEXT NOT NULL DEFAULT 'queued',
                seed_urls                   TEXT NOT NULL DEFAULT '[]',
                config_json                 TEXT NOT NULL DEFAULT '{}',
                started_at                  REAL NOT NULL,
                completed_at                REAL,
                stats_json                  TEXT NOT NULL DEFAULT '{}',
                frontier_checkpoint_json    TEXT
            );
        """)
        try db.execute(sql: "CREATE INDEX idx_sessions_project ON crawl_sessions(project_id);")

        // Core URL table. Written once per URL, updated with fetch results.
        try db.execute(sql: """
            CREATE TABLE crawled_urls (
                id                          TEXT PRIMARY KEY NOT NULL,
                session_id                  TEXT NOT NULL REFERENCES crawl_sessions(id) ON DELETE CASCADE,
                url                         TEXT NOT NULL,
                normalized_url              TEXT NOT NULL,
                discovered_at               REAL NOT NULL,
                fetched_at                  REAL,
                crawl_depth                 INTEGER NOT NULL DEFAULT 0,
                source                      TEXT NOT NULL DEFAULT 'crawl',
                is_internal                 INTEGER NOT NULL DEFAULT 1,

                -- HTTP
                status_code                 INTEGER,
                content_type                TEXT,
                final_url                   TEXT,
                redirect_chain_json         TEXT NOT NULL DEFAULT '[]',
                response_time_ms            INTEGER,
                content_size_bytes          INTEGER,
                fetch_error                 TEXT,

                -- Extracted metadata
                title                       TEXT,
                title_length                INTEGER,
                meta_description            TEXT,
                meta_description_length     INTEGER,
                h1                          TEXT,
                h1_count                    INTEGER NOT NULL DEFAULT 0,
                h2_count                    INTEGER NOT NULL DEFAULT 0,
                canonical_url               TEXT,
                robots_directives_json      TEXT NOT NULL DEFAULT '{}',
                hreflang_json               TEXT NOT NULL DEFAULT '[]',
                og_title                    TEXT,
                og_description              TEXT,
                structured_data_types       TEXT NOT NULL DEFAULT '[]',

                -- Link counts (denormalized)
                internal_inlink_count       INTEGER NOT NULL DEFAULT 0,
                internal_outlink_count      INTEGER NOT NULL DEFAULT 0,
                external_outlink_count      INTEGER NOT NULL DEFAULT 0,
                image_count                 INTEGER NOT NULL DEFAULT 0,

                -- Content analysis
                word_count                  INTEGER,
                content_hash                TEXT,

                -- Indexability
                is_indexable                INTEGER NOT NULL DEFAULT 1,
                indexability_reason         TEXT,
                is_blocked_by_robots        INTEGER NOT NULL DEFAULT 0,

                UNIQUE(session_id, normalized_url)
            );
        """)
        try db.execute(sql: "CREATE INDEX idx_urls_session ON crawled_urls(session_id);")
        try db.execute(sql: "CREATE INDEX idx_urls_status ON crawled_urls(session_id, status_code);")
        try db.execute(sql: "CREATE INDEX idx_urls_normalized ON crawled_urls(normalized_url);")
        try db.execute(sql: "CREATE INDEX idx_urls_indexable ON crawled_urls(session_id, is_indexable);")
        try db.execute(sql: "CREATE INDEX idx_urls_depth ON crawled_urls(session_id, crawl_depth);")

        // Edge table: internal link graph
        try db.execute(sql: """
            CREATE TABLE links (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id      TEXT NOT NULL REFERENCES crawl_sessions(id) ON DELETE CASCADE,
                source_url      TEXT NOT NULL,
                target_url      TEXT NOT NULL,
                anchor_text     TEXT,
                rel_json        TEXT NOT NULL DEFAULT '{}',
                tag_name        TEXT NOT NULL DEFAULT 'a',
                is_internal     INTEGER NOT NULL DEFAULT 1,
                UNIQUE(session_id, source_url, target_url, tag_name)
            );
        """)
        try db.execute(sql: "CREATE INDEX idx_links_session_source ON links(session_id, source_url);")
        try db.execute(sql: "CREATE INDEX idx_links_session_target ON links(session_id, target_url);")

        // Issue table
        try db.execute(sql: """
            CREATE TABLE issues (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id      TEXT NOT NULL REFERENCES crawl_sessions(id) ON DELETE CASCADE,
                url             TEXT NOT NULL,
                issue_key       TEXT NOT NULL,
                severity        TEXT NOT NULL,
                category        TEXT NOT NULL,
                title           TEXT NOT NULL,
                description     TEXT NOT NULL,
                remediation     TEXT NOT NULL DEFAULT '',
                data_json       TEXT NOT NULL DEFAULT '{}',
                UNIQUE(session_id, url, issue_key)
            );
        """)
        try db.execute(sql: "CREATE INDEX idx_issues_session ON issues(session_id);")
        try db.execute(sql: "CREATE INDEX idx_issues_key ON issues(session_id, issue_key);")
        try db.execute(sql: "CREATE INDEX idx_issues_severity ON issues(session_id, severity);")
        try db.execute(sql: "CREATE INDEX idx_issues_category ON issues(session_id, category);")

        // Robots.txt cache — one entry per host per session
        try db.execute(sql: """
            CREATE TABLE robots_cache (
                session_id  TEXT NOT NULL,
                host        TEXT NOT NULL,
                content     TEXT,
                fetched_at  REAL NOT NULL,
                PRIMARY KEY(session_id, host)
            );
        """)
    }

    // MARK: — URL queue spillover for large crawls

    private static func v1URLQueueSpillover(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE url_queue (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id  TEXT NOT NULL REFERENCES crawl_sessions(id) ON DELETE CASCADE,
                url         TEXT NOT NULL,
                depth       INTEGER NOT NULL DEFAULT 0,
                priority    REAL NOT NULL DEFAULT 0.0,
                enqueued_at REAL NOT NULL,
                UNIQUE(session_id, url)
            );
        """)
        try db.execute(sql: "CREATE INDEX idx_queue_session_priority ON url_queue(session_id, priority DESC);")
    }

    // MARK: — Schedules

    private static func v1Schedules(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE schedules (
                id                  TEXT PRIMARY KEY NOT NULL,
                project_id          TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                name                TEXT NOT NULL,
                frequency_json      TEXT NOT NULL,
                is_enabled          INTEGER NOT NULL DEFAULT 1,
                next_run_at         REAL,
                last_run_at         REAL,
                last_run_status     TEXT,
                export_destination  TEXT,
                created_at          REAL NOT NULL,
                run_history_json    TEXT NOT NULL DEFAULT '[]'
            );
        """)
        try db.execute(sql: "CREATE INDEX idx_schedules_project ON schedules(project_id);")
        try db.execute(sql: "CREATE INDEX idx_schedules_next_run ON schedules(next_run_at) WHERE is_enabled = 1;")
    }

    // MARK: — Content hashes for duplicate detection

    private static func v1ContentHashes(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE content_hashes (
                session_id      TEXT NOT NULL,
                url             TEXT NOT NULL,
                content_hash    TEXT NOT NULL,
                PRIMARY KEY(session_id, url)
            );
        """)
        try db.execute(sql: "CREATE INDEX idx_hashes_hash ON content_hashes(session_id, content_hash);")
    }
}
