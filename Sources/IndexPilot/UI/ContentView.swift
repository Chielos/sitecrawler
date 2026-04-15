import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selectedSidebarItem: SidebarItem? = .urls
    @State private var showNewProjectSheet = false
    @State private var showCrawlConfig = false
    @State private var selectedURL: CrawledURL?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedItem: $selectedSidebarItem,
                showNewProject: $showNewProjectSheet
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            contentPanel
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        } detail: {
            detailPanel
        }
        .toolbar {
            CrawlToolbar(showCrawlConfig: $showCrawlConfig)
        }
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet()
        }
        .sheet(isPresented: $showCrawlConfig) {
            if let project = env.selectedProject {
                CrawlConfigurationSheet(project: project)
            }
        }
        .alert("Error", isPresented: .constant(env.errorMessage != nil)) {
            Button("OK") { env.errorMessage = nil }
        } message: {
            Text(env.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newProject)) { _ in
            showNewProjectSheet = true
        }
    }

    @ViewBuilder
    private var contentPanel: some View {
        switch selectedSidebarItem {
        case .urls, .none:
            URLTableView(selectedURL: $selectedURL)
        case .issues:
            IssueListView()
        case .exports:
            ExportsView()
        case .schedules:
            SchedulesView()
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let url = selectedURL {
            URLDetailView(crawledURL: url)
        } else {
            EmptyDetailView()
        }
    }
}

// MARK: — Sidebar Items

enum SidebarItem: String, CaseIterable, Hashable {
    case urls = "URLs"
    case issues = "Issues"
    case exports = "Exports"
    case schedules = "Schedules"

    var icon: String {
        switch self {
        case .urls: return "globe"
        case .issues: return "exclamationmark.triangle"
        case .exports: return "square.and.arrow.up"
        case .schedules: return "clock"
        }
    }
}

// MARK: — Empty Detail

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a URL to inspect")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}
