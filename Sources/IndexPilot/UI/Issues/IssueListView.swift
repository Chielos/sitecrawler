import SwiftUI

struct IssueListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var issues: [Issue] = []
    @State private var selectedCategory: IssueCategory? = nil
    @State private var selectedSeverity: IssueSeverity? = nil
    @State private var searchText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            filterHeader
            Divider()

            if isLoading {
                ProgressView("Loading issues…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredIssues.isEmpty {
                emptyState
            } else {
                issueTable
            }
        }
        .navigationTitle("Issues")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search issues")
        .task(id: env.activeSession?.id) {
            await loadIssues()
        }
    }

    // MARK: — Filter Header

    private var filterHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Severity filters
                ForEach(IssueSeverity.allCases, id: \.self) { sev in
                    FilterChip(
                        label: sev.displayLabel,
                        count: countBySeverity[sev] ?? 0,
                        isSelected: selectedSeverity == sev,
                        color: severityColor(sev)
                    ) {
                        selectedSeverity = selectedSeverity == sev ? nil : sev
                    }
                }

                Divider().frame(height: 20)

                // Category filters
                ForEach(IssueCategory.allCases, id: \.self) { cat in
                    let count = countByCategory[cat.rawValue] ?? 0
                    if count > 0 {
                        FilterChip(
                            label: cat.rawValue,
                            count: count,
                            isSelected: selectedCategory == cat,
                            color: .blue
                        ) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: — Issue Table

    private var issueTable: some View {
        Table(of: Issue.self) {
            TableColumn("Severity") { issue in
                SeverityBadge(severity: issue.severity)
            }
            .width(80)

            TableColumn("Issue") { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title).font(.callout.weight(.medium))
                    Text(issue.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TableColumn("Category") { issue in
                Text(issue.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(120)
        } rows: {
            ForEach(filteredIssues) { issue in
                TableRow(issue)
            }
        }
    }

    // MARK: — Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(env.activeSession == nil ? "No crawl data yet" : "No issues found")
                .font(.headline)
            Text(env.activeSession == nil
                 ? "Start a crawl to see SEO issues."
                 : "All checks passed for the current crawl.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Computed

    private var filteredIssues: [Issue] {
        issues.filter { issue in
            if let sev = selectedSeverity, issue.severity != sev { return false }
            if let cat = selectedCategory, issue.category != cat { return false }
            if !searchText.isEmpty {
                return issue.title.localizedCaseInsensitiveContains(searchText)
                    || issue.url.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    private var countBySeverity: [IssueSeverity: Int] {
        Dictionary(grouping: issues, by: \.severity).mapValues(\.count)
    }

    private var countByCategory: [String: Int] {
        Dictionary(grouping: issues, by: { $0.category.rawValue }).mapValues(\.count)
    }

    // MARK: — Load

    private func loadIssues() async {
        guard let session = env.activeSession else { issues = []; return }
        isLoading = true
        defer { isLoading = false }
        issues = (try? env.db.fetchIssues(sessionID: session.id)) ?? []
    }

    private func severityColor(_ s: IssueSeverity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .opportunity: return .blue
        case .info: return .secondary
        }
    }
}

// MARK: — Supporting Views

struct SeverityBadge: View {
    let severity: IssueSeverity

    var body: some View {
        Text(severity.displayLabel)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .opportunity: return .blue
        case .info: return .secondary
        }
    }
}

struct FilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    private let badgeBackground = Color.secondary.opacity(0.18)
    private let borderColor = Color.secondary.opacity(0.24)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? color : badgeBackground, in: Capsule())
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? color : borderColor, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }
}
