import SwiftUI

/// Main URL results table with sortable columns and live search/filter.
struct URLTableView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var selectedURL: CrawledURL?

    @State private var sortOrder: [KeyPathComparator<CrawledURL>] = []
    @State private var searchText: String = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var indexabilityFilter: IndexabilityFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            table
        }
        .navigationTitle(navigationTitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter URLs")
    }

    // MARK: — Filter Bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Status", selection: $statusFilter) {
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Picker("Indexability", selection: $indexabilityFilter) {
                ForEach(IndexabilityFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 160)

            Spacer()

            Text("\(filteredURLs.count) URLs")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .disabled(env.activeSession == nil)
            .help("Export URLs to CSV")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: — Table

    private var table: some View {
        Table(of: CrawledURL.self, selection: selectedURLID, sortOrder: $sortOrder) {
            TableColumn("URL", value: \.normalizedURL) { url in
                URLTableCell(url: url)
            }
            .width(min: 200, ideal: 320)

            TableColumn("Status") { url in
                StatusCodeBadge(code: url.statusCode)
            }
            .width(60)

            TableColumn("Title", value: \.title.orEmpty) { url in
                Text(url.title ?? "—")
                    .foregroundStyle(url.title == nil ? .tertiary : .primary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("H1", value: \.h1.orEmpty) { url in
                Text(url.h1 ?? "—")
                    .foregroundStyle(url.h1 == nil ? .orange : .primary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 160)

            TableColumn("Depth") { url in
                Text("\(url.crawlDepth)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(50)

            TableColumn("Word Count") { url in
                Text(url.wordCount.map(String.init) ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(80)

            TableColumn("Inlinks") { url in
                Text("\(url.internalInlinkCount)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(60)

            TableColumn("Indexable") { url in
                Image(systemName: url.isIndexable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(url.isIndexable ? .green : .red)
            }
            .width(70)
        } rows: {
            ForEach(sortedFilteredURLs) { url in
                TableRow(url)
            }
        }
    }

    // MARK: — Filtering & Sorting

    private var filteredURLs: [CrawledURL] {
        env.recentURLs.filter { url in
            guard statusFilter.matches(url: url) else { return false }
            guard indexabilityFilter.matches(url: url) else { return false }
            if !searchText.isEmpty {
                return url.normalizedURL.localizedCaseInsensitiveContains(searchText)
                    || (url.title?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            return true
        }
    }

    private var sortedFilteredURLs: [CrawledURL] {
        if sortOrder.isEmpty {
            return filteredURLs.sorted { lhs, rhs in
                lhs.crawlDepth < rhs.crawlDepth
            }
        }

        return filteredURLs.sorted(using: sortOrder)
    }

    private var navigationTitle: String {
        env.selectedProject.map { "URLs — \($0.name)" } ?? "URLs"
    }

    // MARK: — CSV Export

    private func exportCSV() {
        guard let session = env.activeSession else { return }
        Task {
            do {
                let fileURL = try await CSVExporter.exportURLs(sessionID: session.id, db: env.db)
                await MainActor.run {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = fileURL.lastPathComponent
                    panel.begin { response in
                        guard response == .OK, let dest = panel.url else { return }
                        try? FileManager.default.copyItem(at: fileURL, to: dest)
                    }
                }
            } catch {
                await MainActor.run {
                    env.errorMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private var selectedURLID: Binding<CrawledURL.ID?> {
        Binding(
            get: { selectedURL?.id },
            set: { newValue in
                selectedURL = sortedFilteredURLs.first { $0.id == newValue }
            }
        )
    }
}

// MARK: — URL Table Cell

struct URLTableCell: View {
    let url: CrawledURL

    var body: some View {
        HStack(spacing: 6) {
            if url.isBlockedByRobots {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Text(url.normalizedURL)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(url.statusCode == nil ? .tertiary : .primary)
        }
    }
}

// MARK: — Status Code Badge

struct StatusCodeBadge: View {
    let code: Int?

    var body: some View {
        if let code = code {
            Text("\(code)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color(for: code).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(color(for: code))
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private func color(for code: Int) -> Color {
        switch code {
        case 200...299: return .green
        case 300...399: return .blue
        case 400...499: return .orange
        case 500...599: return .red
        default: return .secondary
        }
    }
}

// MARK: — Filters

enum StatusFilter: CaseIterable {
    case all, ok, redirects, clientErrors, serverErrors

    var label: String {
        switch self {
        case .all: return "All"
        case .ok: return "2xx"
        case .redirects: return "3xx"
        case .clientErrors: return "4xx"
        case .serverErrors: return "5xx"
        }
    }

    func matches(url: CrawledURL) -> Bool {
        switch self {
        case .all: return true
        case .ok: return url.statusCode.map { (200...299).contains($0) } ?? false
        case .redirects: return url.statusCode.map { (300...399).contains($0) } ?? false
        case .clientErrors: return url.statusCode.map { (400...499).contains($0) } ?? false
        case .serverErrors: return url.statusCode.map { (500...599).contains($0) } ?? false
        }
    }
}

enum IndexabilityFilter: CaseIterable {
    case all, indexable, nonIndexable

    var label: String {
        switch self {
        case .all: return "All"
        case .indexable: return "Indexable"
        case .nonIndexable: return "Non-Indexable"
        }
    }

    func matches(url: CrawledURL) -> Bool {
        switch self {
        case .all: return true
        case .indexable: return url.isIndexable
        case .nonIndexable: return !url.isIndexable
        }
    }
}

// MARK: — Helpers

extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
