import SwiftUI

/// Full detail pane for a single crawled URL.
/// Shows all extracted metadata, directives, link counts, issues, and redirect chain.
struct URLDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let crawledURL: CrawledURL

    @State private var selectedTab: DetailTab = .overview
    @State private var urlIssues: [Issue] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView(selection: $selectedTab) {
                OverviewTab(url: crawledURL)
                    .tabItem { Label("Overview", systemImage: "doc.text") }
                    .tag(DetailTab.overview)

                DirectivesTab(url: crawledURL)
                    .tabItem { Label("Directives", systemImage: "tag") }
                    .tag(DetailTab.directives)

                LinksTab(url: crawledURL)
                    .tabItem { Label("Links", systemImage: "link") }
                    .tag(DetailTab.links)

                IssueDetailTab(issues: urlIssues)
                    .tabItem { Label("Issues (\(urlIssues.count))", systemImage: "exclamationmark.triangle") }
                    .tag(DetailTab.issues)
            }
        }
        .background(.windowBackground)
        .task(id: crawledURL.id) {
            loadIssues()
        }
    }

    // MARK: — Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(crawledURL.title ?? crawledURL.normalizedURL)
                        .font(.headline)
                        .lineLimit(2)

                    Text(crawledURL.normalizedURL)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                StatusCodeBadge(code: crawledURL.statusCode)
                    .font(.body)
            }

            HStack(spacing: 12) {
                if let depth = crawledURL.crawlDepth as Int? {
                    chip(label: "Depth \(depth)", color: .blue)
                }
                if !crawledURL.isIndexable {
                    chip(label: "Non-Indexable", color: .red)
                }
                if crawledURL.isBlockedByRobots {
                    chip(label: "Robots Blocked", color: .orange)
                }
                if crawledURL.robotsDirectives.noindex {
                    chip(label: "Noindex", color: .orange)
                }
                if !crawledURL.redirectChain.isEmpty {
                    chip(label: "\(crawledURL.redirectChain.count) Redirect\(crawledURL.redirectChain.count > 1 ? "s" : "")", color: .purple)
                }
                Spacer()
                if let ms = crawledURL.responseTimeMs {
                    Text("\(ms)ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private func chip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func loadIssues() {
        guard let session = env.activeSession else { return }
        let url = crawledURL.normalizedURL
        urlIssues = (try? env.db.fetchIssues(sessionID: session.id)
            .filter { $0.url == url }) ?? []
    }

    enum DetailTab { case overview, directives, links, issues }
}

// MARK: — Overview Tab

struct OverviewTab: View {
    let url: CrawledURL

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Group {
                    DetailSection(title: "Titles & Descriptions") {
                        DetailRow("Title", value: url.title, badge: url.titleLength.map { "\($0) chars" })
                        DetailRow("Meta Description", value: url.metaDescription, badge: url.metaDescriptionLength.map { "\($0) chars" })
                        DetailRow("OG Title", value: url.openGraphTitle)
                        DetailRow("OG Description", value: url.openGraphDescription)
                    }

                    DetailSection(title: "Headings") {
                        DetailRow("H1", value: url.h1)
                        DetailRow("H1 Count", value: "\(url.h1Count)")
                        DetailRow("H2 Count", value: "\(url.h2Count)")
                    }

                    DetailSection(title: "Content") {
                        DetailRow("Word Count", value: url.wordCount.map(String.init))
                        DetailRow("Image Count", value: "\(url.imageCount)")
                        DetailRow("Content Size", value: url.contentSizeBytes.map { formatBytes($0) })
                        DetailRow("Content Type", value: url.contentType)
                    }

                    DetailSection(title: "Response") {
                        DetailRow("Status Code", value: url.statusCode.map(String.init))
                        DetailRow("Final URL", value: url.finalURL)
                        DetailRow("Response Time", value: url.responseTimeMs.map { "\($0)ms" })
                        if let err = url.fetchError {
                            DetailRow("Fetch Error", value: err.displayString, valueColor: .red)
                        }
                    }

                    if !url.redirectChain.isEmpty {
                        DetailSection(title: "Redirect Chain") {
                            ForEach(Array(url.redirectChain.enumerated()), id: \.offset) { _, hop in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("[\(hop.statusCode)]")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading) {
                                        Text(hop.fromURL).font(.caption2).textSelection(.enabled)
                                        Text("→ \(hop.toURL)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: — Directives Tab

struct DirectivesTab: View {
    let url: CrawledURL

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DetailSection(title: "Robots Directives") {
                    DetailRow("Source", value: url.robotsDirectives.source ?? "none")
                    DirectiveRow("Noindex", value: url.robotsDirectives.noindex)
                    DirectiveRow("Nofollow", value: url.robotsDirectives.nofollow)
                    DirectiveRow("Noarchive", value: url.robotsDirectives.noarchive)
                    DirectiveRow("Nosnippet", value: url.robotsDirectives.nosnippet)
                    DirectiveRow("Noimageindex", value: url.robotsDirectives.noimageindex)
                    if let date = url.robotsDirectives.unavailableAfter {
                        DetailRow("Unavailable After", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                DetailSection(title: "Canonical") {
                    DetailRow("Declared Canonical", value: url.canonicalURL)
                    let isSelf = url.canonicalURL == nil || url.canonicalURL == url.normalizedURL
                    DetailRow("Self-Referential", value: isSelf ? "Yes" : "No")
                }

                if !url.hreflangTags.isEmpty {
                    DetailSection(title: "Hreflang") {
                        ForEach(url.hreflangTags, id: \.lang) { tag in
                            HStack {
                                Text(tag.lang + (tag.region.map { "-\($0)" } ?? ""))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 60, alignment: .leading)
                                Text(tag.url)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, 3)
                            Divider()
                        }
                    }
                }

                if !url.structuredDataTypes.isEmpty {
                    DetailSection(title: "Structured Data") {
                        ForEach(url.structuredDataTypes, id: \.self) { type_ in
                            DetailRow("@type", value: type_)
                        }
                    }
                }

                DetailSection(title: "Indexability") {
                    DirectiveRow("Indexable", value: url.isIndexable)
                    if let reason = url.indexabilityReason {
                        DetailRow("Reason", value: reason.rawValue, valueColor: .orange)
                    }
                    DirectiveRow("Blocked by Robots", value: url.isBlockedByRobots)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }
}

// MARK: — Links Tab

struct LinksTab: View {
    @Environment(AppEnvironment.self) private var env
    let url: CrawledURL
    @State private var links: [Link] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                statBox(value: url.internalInlinkCount, label: "Internal Inlinks")
                statBox(value: url.internalOutlinkCount, label: "Internal Outlinks")
                statBox(value: url.externalOutlinkCount, label: "External Outlinks")
            }
            .padding(12)
            Divider()

            if links.isEmpty {
                Text("No link data available")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(links) { link in
                            HStack {
                                Image(systemName: link.isInternal ? "arrow.up.right.circle" : "globe")
                                    .foregroundStyle(link.isInternal ? .blue : .secondary)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(link.targetURL)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if let anchor = link.anchorText {
                                        Text(anchor)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if link.rel.nofollow {
                                    Text("nofollow")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.orange.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            Divider()
                        }
                    }
                }
            }
        }
        .task(id: url.id) {
            guard let session = env.activeSession else { return }
            links = (try? env.db.fetchLinks(sessionID: session.id, sourceURL: url.normalizedURL)) ?? []
        }
    }

    private func statBox(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title2.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: — Issues Tab

struct IssueDetailTab: View {
    let issues: [Issue]

    var body: some View {
        if issues.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title)
                Text("No issues found for this URL").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(issues.sorted { $0.severity < $1.severity }) { issue in
                        IssueCard(issue: issue)
                    }
                }
                .padding(12)
            }
        }
    }
}

struct IssueCard: View {
    let issue: Issue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SeverityDot(severity: issue.severity)
                Text(issue.title).font(.callout.weight(.semibold))
                Spacer()
                Text(issue.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(issue.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !issue.remediation.isEmpty {
                Text("Fix: \(issue.remediation)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SeverityDot: View {
    let severity: IssueSeverity

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
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

// MARK: — Shared Detail Components

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .padding(.bottom, 4)
            Divider()
            content
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String?
    var badge: String? = nil
    var valueColor: Color = .primary

    init(_ label: String, value: String?, badge: String? = nil, valueColor: Color = .primary) {
        self.label = label
        self.value = value
        self.badge = badge
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            if let value = value {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(valueColor)
                    .textSelection(.enabled)
                    .lineLimit(3)
            } else {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            }
            if let badge = badge {
                Spacer()
                Text(badge)
                    .font(.system(size: 10))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        Divider()
    }
}

struct DirectiveRow: View {
    let label: String
    let value: Bool

    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Image(systemName: value ? "checkmark" : "minus")
                .font(.caption)
                .foregroundStyle(value ? .orange : .tertiary)
            if value { Text("Yes").font(.caption).foregroundStyle(.orange) }
        }
        .padding(.vertical, 5)
        Divider()
    }
}
