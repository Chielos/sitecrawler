# IndexPilot — Architecture

## Overview

IndexPilot is a native macOS desktop SEO crawler for Apple Silicon. It crawls websites, analyzes technical SEO issues, persists results in a local SQLite database, and presents findings through a SwiftUI interface.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SwiftUI Shell                                │
│  Sidebar │ Toolbar │ URL Table │ Detail Pane │ Issue List │ Exports  │
└────────────────────────┬────────────────────────────────────────────┘
                         │ @Observable ViewModels / AsyncStream
┌────────────────────────▼────────────────────────────────────────────┐
│                      AppEnvironment                                 │
│          (single source of truth: projects, active session)         │
└────────────┬──────────────────────────────────┬─────────────────────┘
             │                                  │
┌────────────▼──────────┐           ┌───────────▼──────────────────────┐
│     CrawlEngine       │           │       DatabaseManager            │
│  (actor, concurrent)  │◄──────────│  (GRDB, WAL mode, migrations)    │
│                       │   writes  │                                  │
│  URLFrontier (actor)  │           │  Tables:                         │
│  Fetcher pool         │           │    projects                      │
│  HTMLParser           │           │    crawl_sessions                │
│  ContentExtractor     │           │    crawled_urls                  │
│  RobotsParser cache   │           │    links                         │
│  IssueRunner          │           │    issues                        │
│                       │           │    content_hashes                │
└────────────┬──────────┘           │    robots_cache                  │
             │                      │    schedules                     │
             │ URLSession           └──────────────────────────────────┘
             ▼
      Internet / LAN
```

## Module Boundaries

### Core/Models
Plain Swift structs and enums. No dependencies. Represent the domain entities: `Project`, `CrawlSession`, `CrawledURL`, `Link`, `Issue`, `IssueDefinition`, `Schedule`, `CrawlConfiguration`.

### Core/Database
`DatabaseManager` owns the GRDB `DatabasePool`. Provides typed read/write methods. All SQL runs here. No business logic.

### Core/Crawler
The crawl pipeline:

```
CrawlEngine (actor)
    ├── URLFrontier (actor)        — priority queue + seen set
    ├── RobotsCache (actor)        — per-host robots.txt fetch + parse
    ├── Fetcher                    — URLSession, redirect tracking, HEAD/GET
    ├── HTMLParser                 — SwiftSoup, link/asset extraction
    ├── ContentExtractor           — title, meta, h1/h2, canonicals, directives
    └── IssueRunner                — per-URL issue checks, writes to DB
```

The engine publishes progress via `AsyncStream<CrawlEvent>`, consumed by `CrawlViewModel`.

### Core/Issues
`IssueDefinition` is a value type describing a check:

```swift
struct IssueDefinition {
    let key: String
    let severity: IssueSeverity
    let category: IssueCategory
    let title: String
    let description: String
    let remediation: String
    let check: (CrawledURL, CrawlContext) -> Bool
}
```

`IssueEngine` holds all registered definitions and evaluates them. Adding a new check is one struct definition + registration. Post-crawl aggregate checks (duplicates, orphans) run as a separate pass over the database.

### Core/Export
`ExportManager` schedules export jobs using a `TaskGroup`. Each exporter (`CSVExporter`, `JSONExporter`, `SitemapExporter`) operates on a snapshot query, never the live crawl state, to avoid blocking.

### UI
Standard SwiftUI with `@Observable` view models. All view models are `@MainActor`. Background work is done via `Task { }` and results are published to observable state.

## Data Flow: Live Crawl

```
CrawlEngine.start()
  └─ spawns TaskGroup of N concurrent fetch tasks
       └─ each task:
            1. URLFrontier.next() — dequeue next URL
            2. RobotsCache.isAllowed(url) — check robots
            3. Fetcher.fetch(url) — HTTP, capture redirect chain
            4. HTMLParser.parse(responseBody) — SwiftSoup
            5. ContentExtractor.extract(document, response) → CrawledURL
            6. IssueRunner.evaluate(crawledURL) → [Issue]
            7. DatabaseManager.write(crawledURL, issues, links)
            8. URLFrontier.enqueue(discoveredURLs)
            9. emit CrawlEvent.urlProcessed(crawledURL) → AsyncStream
                 └─ CrawlViewModel consumes → @Published state → UI refresh
```

## Concurrency Model

- `CrawlEngine` is an `actor` — all coordination is actor-isolated.
- `URLFrontier` is a separate `actor` — the engine calls it concurrently from its `TaskGroup` children.
- `RobotsCache` is an `actor` — multiple fetch workers share it safely.
- `DatabaseManager` uses GRDB's `DatabasePool` which supports concurrent reads and serialized writes. Writes are batched per 50 URLs using `GRDB.Database.execute()` within a transaction.
- UI updates run on `@MainActor`. The `AsyncStream<CrawlEvent>` is consumed in a `Task { for await event in stream { } }` on the main actor.
- All `URLSession` calls use `async/await` — no callbacks.

## Resumable Crawls

The `URLFrontier` state is checkpointed to the database every 500 URLs. On resume:
1. Load the last checkpoint from `crawl_sessions.frontier_checkpoint_json`.
2. Re-populate the frontier from the checkpoint.
3. Mark all `crawled_urls` rows with `fetched_at IS NOT NULL` as already seen (re-inject into the dedup set, not the queue).
4. Continue from where the crawl stopped.

## Robots.txt Strategy

1. Before fetching any URL on a given host, `RobotsCache.fetch(host)` is called.
2. The robots.txt is fetched once per crawl session per host and cached in `robots_cache`.
3. Parsing implements RFC 9309 (Robots Exclusion Protocol): `User-agent`, `Disallow`, `Allow`, `Crawl-delay`, `Sitemap`.
4. Both the configured crawl user-agent and `*` are checked; the most specific matching rule wins.
5. If robots.txt returns a non-200 (except 401/403), crawling is allowed for the content of the missing file (treat as empty).
6. If robots.txt returns 401/403, all URLs on that host are blocked.
7. The `obeyRobots` flag in `CrawlConfiguration` can disable this entirely.

## URL Normalization

Applied at discovery time and again before deduplication. Rules applied in order:

1. Lowercase scheme and host
2. Strip default ports (80 for http:, 443 for https:)
3. Strip fragment (`#…`)
4. Decode unnecessarily percent-encoded characters (unreserved chars per RFC 3986)
5. Normalize percent-encoding to uppercase hex
6. Sort query parameters (configurable — default OFF to preserve parameter semantics)
7. Strip known tracking parameters (utm_*, fbclid, gclid — configurable)
8. One trailing slash normalization pass: remove trailing slash unless path is empty (configurable)
9. IDN: Punycode encode non-ASCII hostnames

## JS Rendering Architecture (V1)

Two rendering workers are available:

**WKWebView Worker (lightweight):** A pool of off-screen `WKWebView` instances. Suitable for light frameworks (React SSR, WordPress with some JS). Each view is reused across requests. Runs in-process.

**Playwright Worker (heavy):** A separate Swift XPC service (`IndexPilotRenderer.appex`) that manages a Playwright Node.js process. Communicates via XPC. Falls back to WKWebView if unavailable. Supports full SPA rendering, network interception, and cookie injection.

Both workers expose `func render(url: URL, config: RenderConfig) async throws -> RenderResult`.

## Security

- macOS Keychain stores per-project credentials (cookies, basic-auth passwords, API keys).
- `KeychainManager` wraps `SecItemAdd`/`SecItemCopyMatching` with `kSecAttrService = "com.indexPilot.credentials"`.
- No secrets in SQLite or exported files.
- Crawl politeness defaults: 1 req/sec per host, 10 concurrent connections total.
- `obeyRobots = true` by default.
- User-agent defaults to `IndexPilot/1.0 (+https://indexPilot.app/bot)`.
- Exports sanitize any credentials from headers before writing.

## Performance Targets

| Scale | URLs | RAM target | Crawl duration |
|-------|------|-----------|----------------|
| Small | ≤5k | <200 MB | <5 min |
| Medium | 50k | <500 MB | <45 min |
| Large | 250k | <1.5 GB | configurable |

Key techniques:
- GRDB WAL mode: concurrent reads don't block writes.
- `CrawledURL` structs are written to DB and evicted from memory after processing.
- Issue summaries are pre-aggregated by category in DB — UI never does full-table scans.
- `Table` view in SwiftUI uses lazy loading — only visible rows are in memory.
- `URLFrontier` spills to the `urls_queue` DB table when in-memory queue exceeds 10k items.
