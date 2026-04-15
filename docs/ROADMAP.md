# IndexPilot Roadmap

## MVP (this implementation)

### Working
- [x] Full project/session data model in SQLite via GRDB
- [x] Additive database migrations
- [x] RFC 3986 URL normalization (dot segments, percent-encoding, port stripping, fragment removal)
- [x] Tracking parameter stripping (utm_*, gclid, fbclid, etc.)
- [x] RFC 9309 robots.txt parsing with wildcard support (`*` and `$`)
- [x] Per-session robots.txt caching (actor-isolated)
- [x] URL Frontier with min-heap priority queue, deduplication, and DB spillover
- [x] Resumable crawls via frontier checkpointing
- [x] Manual redirect tracking (full chain captured per URL)
- [x] Per-host rate limiting (actor-isolated)
- [x] SwiftSoup-based HTML parsing
- [x] Content extraction: title, meta description, H1/H2, canonical, robots directives, hreflang, OG tags, structured data types, word count, image count, SHA-256 content hash
- [x] XML sitemap parser (standard + index)
- [x] Scope checking (domain constraint, subdomain option, path prefix)
- [x] Issue engine: data-driven per-URL checks + aggregate post-crawl checks
- [x] 19 issue checks: 4xx, 5xx, redirect chain, redirect loop, missing title, title too short/long, missing meta description, meta too long, missing H1, multiple H1, canonical issues, noindex in sitemap, robots-blocked-but-linked, thin content, excessive depth, insecure canonical, duplicate titles, duplicate meta descriptions, duplicate content hash
- [x] CSV export (URLs, Issues)
- [x] JSON export
- [x] XML sitemap export
- [x] SwiftUI shell: NavigationSplitView, sidebar, toolbar, URL table with filters/search, URL detail view (4 tabs), issue list with category/severity filters
- [x] New project sheet, crawl configuration sheet, settings window
- [x] Dark mode support
- [x] Keyboard shortcuts
- [x] Unit tests: URL normalization, robots parsing, content extraction, issue engine, database manager

### Stubbed / Architecture-only
- [ ] Scheduling UI (SchedulesView shows placeholder)
- [ ] Export history panel  
- [ ] Sitemap discrepancy check (in sitemap but not crawled, vice versa)
- [ ] Orphan detection (not linked from any other page)
- [ ] JavaScript rendering (architecture defined in ARCHITECTURE.md)

---

## V1

### Features
- [ ] **JS Rendering Mode**: WKWebView worker pool for light JS, Playwright XPC helper for heavy SPA
- [ ] **Hreflang Auditing**: return-tag validation, language code verification, x-default check
- [ ] **Per-image alt text audit**: requires per-image data table (`url_images`)
- [ ] **Crawl comparison**: diff two sessions, show new/fixed/regressed issues
- [ ] **Scheduling**: full UI with day/week/month scheduling, run history, export destination
- [ ] **Custom extraction rules**: CSS selector / regex based extraction into custom columns
- [ ] **Auth support**: cookie import, custom header auth, basic auth via Keychain
- [ ] **Internal link graph visualisation**: SwiftUI Canvas force-directed graph
- [ ] **Internal link tree visualisation**: collapsible directory tree
- [ ] **Crawl depth chart**: SwiftUI Charts histogram
- [ ] **Status code distribution chart**: pie/bar chart
- [ ] **Indexability breakdown chart**
- [ ] **Orphan detection**: pages not linked from any crawled internal URL
- [ ] **Near-duplicate detection**: SimHash or MinHash similarity scoring
- [ ] **Mixed content detection**: HTTPS pages linking to HTTP resources
- [ ] **Structured data validation**: use Schema.org spec for type/property validation
- [ ] **Accessibility checks**: basic WCAG 2.1 AA hooks (alt text, ARIA landmarks)
- [ ] **Sitemap discrepancy tab**: URLs in sitemap but not crawled, and vice versa
- [ ] **CLI mode**: `indexpilot crawl <url>` for automation/CI

### Technical
- [ ] Rust crawl engine MVP (replace Swift engine behind `CrawlEngineProtocol`)
- [ ] `cbindgen` build plugin for Rust FFI
- [ ] URLSession streaming response bodies (avoid large-response memory spikes)
- [ ] DuckDB evaluation for aggregate analytics queries
- [ ] Background crawl daemon (launchd agent for scheduled runs when app is closed)
- [ ] macOS Keychain integration for credential storage (`KeychainManager`)
- [ ] Structured logging (OSLog + crash diagnostic hooks)
- [ ] Feature flags for unfinished features

---

## V2

- [ ] Google Search Console integration (OAuth2, impression/click data overlay)
- [ ] Google Analytics integration (engagement metrics overlay)
- [ ] PageSpeed Insights API integration (CWV metrics per URL)
- [ ] Team collaboration (shared project export/import format)
- [ ] Cloud backup option for crawl databases
- [ ] macOS Menu Bar quick-start widget
