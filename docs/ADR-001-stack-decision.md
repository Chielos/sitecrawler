# ADR-001: Stack Decision — IndexPilot macOS SEO Crawler

**Status:** Accepted  
**Date:** 2025-01-15  
**Deciders:** Architecture team

---

## Context

We need to build a native macOS desktop SEO crawler targeting Apple Silicon (M-series). The application must crawl 50k–250k URLs per session with real-time UI feedback, persist results in a local database, support optional JS rendering, and feel like a first-class macOS citizen.

The four candidates evaluated:

| Option | Engine | UI | Renderer |
|--------|--------|----|----------|
| A | Swift concurrency + URLSession | SwiftUI | WKWebView |
| B | Tauri + Rust | WebView (HTML/CSS) | Playwright subprocess |
| C | Electron + Node.js | HTML/CSS | Playwright built-in |
| D | Rust engine + SwiftUI shell | SwiftUI | WKWebView + Playwright option |

---

## Decision

**Option D: Rust crawl engine + SwiftUI native shell**, structured as a Swift Package with the Rust engine compiled to a static library and bridged via a thin C ABI.

For the **MVP**, the Rust engine is replaced by a pure-Swift actor-based engine so the team can ship and iterate without the FFI complexity. The Swift engine is hidden behind a protocol (`CrawlEngineProtocol`) that is designed to be swapped for the Rust-backed implementation in V2 without touching UI code.

This is an intentional two-phase decision:
- **Phase 1–3 (MVP/V1):** Pure Swift engine using `async/await`, `Actor`, `URLSession`, `SwiftSoup`, and `GRDB`.
- **Phase 2+ (post-V1):** Rust crawl engine linked as a static library via `cbindgen`-generated headers, drop-in replacement behind the protocol.

---

## Rationale

### Why not Electron (Option C)?
- Electron ships a 200 MB Chromium runtime unconditionally.
- Memory ceiling is far lower — Chromium's process model and V8's heap compete directly with the crawl's working set.
- No native macOS APIs: no Keychain, no NSSharingService, no AppKit sheet animations, no proper `NSMenu`.
- JS rendering is already handled by Playwright; adding Electron on top doubles the rendering surface.
- App signing and notarization with Electron requires additional hardened runtime exemptions that increase attack surface.

### Why not Tauri (Option B)?
- Tauri uses macOS's built-in WKWebView for its UI, meaning UI quality depends on whatever CSS tricks you implement — it never feels as native as SwiftUI.
- Rust backend is excellent, but Tauri's IPC overhead for high-frequency crawl events (thousands of URL completions/second) leads to frame drops and batching hacks.
- Multi-window management, sheet presentations, and toolbar semantics in Tauri require significant workaround code.

### Why not pure Swift (Option A)?
- Swift is excellent for I/O-bound networking, but Rust offers measurably lower per-URL overhead for the HTML parsing, URL normalization, deduplication, and issue-detection hot path.
- Per-URL work in Swift has ~30% more allocator pressure than idiomatic Rust with arena allocators.
- Defer to V2 rather than block MVP.

### Why SwiftUI?
- `NavigationSplitView`, `Table`, `Chart`, and `SwiftData`/GRDB integrate cleanly.
- `@Observable` macro (macOS 14+) eliminates most boilerplate.
- SwiftUI on Apple Silicon has hardware-accelerated compositing via Metal — animations are free.
- Code signing, sandboxing, and entitlement management is well-understood for SwiftUI apps.
- App Review rules do not apply; this is a direct-distribution desktop app.

### Why GRDB over SwiftData?
- SwiftData wraps Core Data. Core Data's SQLite WAL checkpointing and large-insert performance are poor at 100k+ row ingestion rates.
- GRDB gives direct SQL control: `INSERT OR REPLACE`, batch inserts with `ValueObservation`, and custom indexes.
- GRDB supports migrations, typed query builders, and raw SQL fallback — all needed here.

### Why SwiftSoup over libxml2 / XMLDocument?
- SwiftSoup is a pure-Swift port of Jsoup — the industry's best-tested HTML5 parser.
- Zero C interop, no CFString bridging, fast enough for the parsing hot path at our scale.
- Handles malformed HTML correctness that URLSession-fetched pages require.

---

## Consequences

- The crawl engine protocol boundary (`CrawlEngineProtocol`) must be stabilized before V1 ships.
- GRDB migrations must be additive — no destructive migrations after first public release.
- The Rust engine replacement in V2 will require a `cbindgen` build step added to the Package.swift plugin phase. Budget ~2 sprints.
- WKWebView pooling for JS rendering adds macOS entitlement `com.apple.security.network.client` and increases sandbox complexity — defer to V1.
- Playwright/Chromium rendering worker runs as an XPC helper process to satisfy sandbox requirements.

---

## Alternatives Rejected

- **DuckDB instead of SQLite:** DuckDB is a columnar analytics engine — excellent for offline aggregation queries but it adds a 40 MB binary and lacks row-level streaming inserts without buffering. Revisit for the comparison/analytics features in V2.
- **Core Data:** See GRDB justification above.
- **FoundationNetworking on Linux:** Ruled out — this is macOS-only and URLSession on Darwin is the reference implementation.
