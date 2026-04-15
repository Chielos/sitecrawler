import SwiftUI

struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var selectedItem: SidebarItem?
    @Binding var showNewProject: Bool

    var body: some View {
        List(selection: $selectedItem) {
            // Project picker
            Section("Project") {
                if env.projects.isEmpty {
                    Button {
                        showNewProject = true
                    } label: {
                        Label("New Project…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                } else {
                    Picker("", selection: Binding(
                        get: { env.selectedProject },
                        set: { env.selectedProject = $0 }
                    )) {
                        ForEach(env.projects) { project in
                            Text(project.name).tag(Optional(project))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            // Crawl status
            if env.isCrawling || env.activeSession != nil {
                Section("Current Crawl") {
                    CrawlStatusRow()
                }
            }

            // Navigation items
            Section("Analysis") {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    HStack {
                        Label(item.rawValue, systemImage: item.icon)
                        Spacer(minLength: 8)
                        if let count = badgeCount(for: item) {
                            Text("\(count)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.16), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("IndexPilot")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewProject = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Project")
            }
        }
    }

    private func badgeCount(for item: SidebarItem) -> Int? {
        switch item {
        case .issues:
            let count = env.crawlStats.totalIssues
            return count > 0 ? count : nil
        default:
            return nil
        }
    }
}

// MARK: — Crawl Status Row

struct CrawlStatusRow: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if env.isCrawling {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
                Text(env.isCrawling ? "Crawling…" : "Finished")
                    .font(.callout.weight(.medium))
            }

            HStack(spacing: 16) {
                statLabel(value: env.crawlStats.totalURLsCrawled, label: "crawled")
                statLabel(value: env.crawlStats.totalURLsQueued, label: "queued")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if env.isCrawling && env.crawlStats.crawlRateURLsPerSecond > 0 {
                Text(String(format: "%.1f URLs/s", env.crawlStats.crawlRateURLsPerSecond))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statLabel(value: Int, label: String) -> some View {
        HStack(spacing: 2) {
            Text("\(value)").fontWeight(.semibold)
            Text(label)
        }
    }
}
