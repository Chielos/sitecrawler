import SwiftUI

struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var selectedItem: SidebarItem?
    @Binding var showNewProject: Bool

    @State private var editingProject: Project?
    @State private var deletingProject: Project?

    var body: some View {
        List(selection: $selectedItem) {
            // Project list
            Section("Projects") {
                if env.projects.isEmpty {
                    Button {
                        showNewProject = true
                    } label: {
                        Label("New Project…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(env.projects) { project in
                        ProjectRow(
                            project: project,
                            isSelected: env.selectedProject?.id == project.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { env.selectedProject = project }
                        .contextMenu {
                            Button("Edit Project…") { editingProject = project }
                            Divider()
                            Button("Delete Project…", role: .destructive) { deletingProject = project }
                        }
                        .listRowBackground(
                            env.selectedProject?.id == project.id
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                    }
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
                    SidebarItemRow(item: item, badge: badgeCount(for: item))
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
        .sheet(item: $editingProject) { project in
            NewProjectSheet(editingProject: project)
                .environment(env)
        }
        .alert("Delete Project", isPresented: .constant(deletingProject != nil), presenting: deletingProject) { project in
            Button("Delete", role: .destructive) {
                env.deleteProject(project)
                deletingProject = nil
            }
            Button("Cancel", role: .cancel) { deletingProject = nil }
        } message: { project in
            Text("Are you sure you want to delete \"\(project.name)\"? This cannot be undone.")
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

// MARK: — Sidebar Item Row

struct SidebarItemRow: View {
    let item: SidebarItem
    let badge: Int?

    var body: some View {
        HStack {
            Label(item.rawValue, systemImage: item.icon)
            Spacer(minLength: 8)
            if let count = badge {
                let countText = Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                countText
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.16), in: Capsule())
            }
        }
    }
}

// MARK: — Project Row

struct ProjectRow: View {
    let project: Project
    let isSelected: Bool

    private var domain: String? {
        project.seedURLs.first.flatMap { URL(string: $0)?.host }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
            if let domain = domain {
                Text(domain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
