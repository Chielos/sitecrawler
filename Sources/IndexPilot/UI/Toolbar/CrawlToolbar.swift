import SwiftUI

struct CrawlToolbar: ToolbarContent {
    @Environment(AppEnvironment.self) private var env
    @Binding var showCrawlConfig: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            // Start / Stop
            Button {
                if env.isCrawling {
                    env.cancelCrawl()
                } else if let project = env.selectedProject {
                    env.startCrawl(for: project)
                }
            } label: {
                Label(
                    env.isCrawling ? "Stop" : "Start Crawl",
                    systemImage: env.isCrawling ? "stop.circle.fill" : "play.circle.fill"
                )
                .symbolRenderingMode(.multicolor)
            }
            .disabled(env.selectedProject == nil)
            .help(env.isCrawling ? "Stop Crawl" : "Start Crawl")

            // Pause
            if env.isCrawling {
                Button {
                    env.pauseCrawl()
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
                .help("Pause Crawl")
            }

            // Config
            Button {
                showCrawlConfig = true
            } label: {
                Label("Configure", systemImage: "slider.horizontal.3")
            }
            .disabled(env.selectedProject == nil || env.isCrawling)
            .help("Crawl Configuration")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // Stats summary
            if env.isCrawling || env.activeSession != nil {
                CrawlStatsChip(stats: env.crawlStats)
            }

            // Export
            Menu {
                Button("Export URLs as CSV…") {
                    exportCSV()
                }
                Button("Export Issues as CSV…") {
                    exportIssuesCSV()
                }
                Button("Export as JSON…") {
                    exportJSON()
                }
                Divider()
                Button("Generate Sitemap…") {
                    exportSitemap()
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(env.activeSession == nil)
        }
    }

    private func exportCSV() {
        guard let session = env.activeSession else { return }
        Task { @MainActor in
            do {
                let url = try await CSVExporter.exportURLs(sessionID: session.id, db: env.db)
                savePanel(url: url)
            } catch {
                env.errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportIssuesCSV() {
        guard let session = env.activeSession else { return }
        Task { @MainActor in
            do {
                let url = try await CSVExporter.exportIssues(sessionID: session.id, db: env.db)
                savePanel(url: url)
            } catch {
                env.errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportJSON() {
        guard let session = env.activeSession else { return }
        Task { @MainActor in
            do {
                let url = try await JSONExporter.export(session: session, db: env.db)
                savePanel(url: url)
            } catch {
                env.errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportSitemap() {
        guard let session = env.activeSession,
              let seedURL = env.selectedProject?.seedURLs.first.flatMap(URL.init) else { return }
        Task { @MainActor in
            do {
                let url = try await SitemapExporter.export(sessionID: session.id, baseURL: seedURL, db: env.db)
                savePanel(url: url)
            } catch {
                env.errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func savePanel(url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            try? FileManager.default.copyItem(at: url, to: dest)
        }
    }
}

// MARK: — Stats Chip

struct CrawlStatsChip: View {
    let stats: CrawlStats

    var body: some View {
        HStack(spacing: 10) {
            statItem(value: stats.totalURLsCrawled, label: "crawled", color: .blue)
            Divider().frame(height: 16)
            statItem(value: stats.total4xx, label: "4xx", color: .orange)
            statItem(value: stats.total5xx, label: "5xx", color: .red)
            if stats.totalIssues > 0 {
                Divider().frame(height: 16)
                statItem(value: stats.totalIssues, label: "issues", color: .yellow)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func statItem(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(value)").foregroundStyle(value > 0 ? color : .secondary)
            Text(label).foregroundStyle(.tertiary)
        }
    }
}
