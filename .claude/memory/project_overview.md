---
name: IndexPilot Project Overview
description: macOS SEO crawler app — stack choice, implementation status, file structure
type: project
---

App named **IndexPilot**. macOS 14+ Apple Silicon native SEO crawler.

**Stack:** SwiftUI + AppKit | Swift actor crawl engine (Rust V2) | GRDB + SQLite | SwiftSoup HTML parser

**Location:** /Users/chielos/Documents/GitHub/sitecrawler/

**What's built (MVP complete as of 2026-04-15):**
- Full GRDB database with 4 migrations (projects, sessions, URLs, links, issues, robots cache, queue, schedules, content hashes)
- RFC 3986 URL normalizer + scope checker
- RFC 9309 robots.txt parser + actor cache
- URLFrontier actor (min-heap, dedup, DB spillover at 10k, checkpoint/resume)
- HostRateLimiter actor (per-host politeness)
- Fetcher (manual redirect tracking — captures full chain)
- HTMLParser (SwiftSoup) + ContentExtractor (title, meta, h1, canonical, hreflang, OG, LD+JSON, word count, SHA-256 hash)
- SitemapParser (XML standard + index)
- CrawlEngine actor (TaskGroup concurrency, AsyncStream<CrawlEvent> for UI)
- IssueEngine (19 per-URL checks + 3 aggregate checks)
- CSV/JSON/Sitemap exporters (background Task)
- Full SwiftUI shell: sidebar, toolbar, URL table (sortable, filterable, searchable), URL detail (4 tabs: overview, directives, links, issues), issue list, settings window, new project sheet, crawl config sheet
- Unit tests: URLNormalizer, RobotsParser, ContentExtractor, IssueEngine, DatabaseManager
- Python QA test server (TestServer/server.py, port 8765)
- Docs: ADR-001, ARCHITECTURE.md, ROADMAP.md, PACKAGING.md

**Stubbed/V1:** JS rendering, scheduling UI, orphan detection, near-duplicate SimHash, custom extraction rules, auth/Keychain, crawl comparison, visualisations, CLI mode, Rust engine

**Why:** IndexPilot is the project name. Screaming Frog-inspired but original. Not a clone.
