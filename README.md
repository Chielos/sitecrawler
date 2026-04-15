# IndexPilot

A professional-grade macOS SEO crawler for Apple Silicon. Crawl websites at scale, analyze technical SEO issues, and export actionable reports — all locally on your Mac.

## Quick Start

### Prerequisites
- macOS 14.0+
- Swift 5.9+ (Xcode 15+)
- Apple Silicon (M1/M2/M3)

### Build & Run

```bash
# Clone
git clone <repo-url>
cd sitecrawler

# Resolve dependencies and build
swift build --arch arm64

# Run tests
swift test --arch arm64

# Open in Xcode
xed .
```

### Local QA Test Server

The test server provides a mini-website with intentional SEO issues for integration testing:

```bash
# Terminal 1: Start the local test server
python3 TestServer/server.py

# Then open IndexPilot, create a new project, and crawl:
# http://localhost:8765/
```

The test site includes:
- Normal pages with correct SEO structure
- Pages with missing titles, thin content, noindex
- A 3-hop redirect chain
- 404 and 500 pages
- robots.txt and sitemap.xml

## Project Structure

```
Sources/IndexPilot/
├── App/                    # App entry point, environment, commands
├── Core/
│   ├── Models/             # Data model structs (no dependencies)
│   ├── Database/           # GRDB database manager, migrations
│   ├── Crawler/            # Crawl engine, URL frontier, fetcher, parser, extractor
│   ├── Issues/             # Issue engine, 19 check implementations
│   └── Export/             # CSV, JSON, sitemap exporters
└── UI/
    ├── Sidebar/            # Sidebar + project picker
    ├── Toolbar/            # Crawl control toolbar + stats chip
    ├── Crawl/              # URL table, new project sheet, config sheet
    ├── URLDetail/          # URL detail pane (4 tabs)
    ├── Issues/             # Issue list with filters
    └── Settings/           # Settings window

Tests/
├── IndexPilotTests/        # Unit tests
└── Fixtures/               # robots.txt, HTML, sitemap fixtures

TestServer/
└── server.py               # Python QA server (no dependencies)

docs/
├── ADR-001-stack-decision.md
├── ARCHITECTURE.md
├── ROADMAP.md
└── PACKAGING.md
```

## Architecture

**Stack:** SwiftUI + AppKit bridge | Swift actor-based crawl engine | GRDB + SQLite | SwiftSoup HTML parser

The crawl engine runs as a Swift `actor` using a `TaskGroup` of N concurrent workers. Progress is published via `AsyncStream<CrawlEvent>` consumed by `@Observable` view models on the main actor. The UI never blocks.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design.

## Key Design Decisions

- **Stack choice:** See [docs/ADR-001-stack-decision.md](docs/ADR-001-stack-decision.md)
- **Data model:** SQLite via GRDB with additive-only migrations
- **Deduplication:** SHA-256 of normalized URL — computed once at discovery
- **Resumability:** Frontier checkpointed to DB every 500 URLs
- **Memory:** CrawledURL structs are written to SQLite after processing and evicted; frontier spills to DB at 10k URLs in-memory
- **Issue system:** Data-driven — add a new check by implementing `PerURLCheck` protocol + 1-line registration

## What's Implemented (MVP)

| Component | Status |
|-----------|--------|
| URL Normalization (RFC 3986) | Complete |
| Robots.txt parsing (RFC 9309) | Complete |
| URL Frontier (priority queue + dedup + spillover) | Complete |
| HTTP fetcher with redirect tracking | Complete |
| HTML parsing (SwiftSoup) | Complete |
| Content extraction (title, meta, h1, canonical, hreflang, OG, LD+JSON, word count, hash) | Complete |
| XML sitemap parser | Complete |
| Issue engine: 19 checks | Complete |
| CSV/JSON/Sitemap exports | Complete |
| SwiftUI shell (full, dark mode) | Complete |
| Unit tests | Complete |
| Local QA test server | Complete |
| JS rendering | Stubbed (V1) |
| Scheduling | Stubbed (V1) |

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full roadmap.

## Packaging

Distribution as a signed, notarized `.app` — see [docs/PACKAGING.md](docs/PACKAGING.md).
