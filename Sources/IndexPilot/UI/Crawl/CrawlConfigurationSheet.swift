import SwiftUI

struct CrawlConfigurationSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var project: Project
    @State private var config: CrawlConfiguration

    init(project: Project) {
        self.project = project
        self._config = State(initialValue: project.configuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Crawl Configuration").font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(20)
            Divider()

            TabView {
                scopeTab.tabItem { Label("Scope", systemImage: "scope") }
                politenessTab.tabItem { Label("Politeness", systemImage: "clock") }
                identityTab.tabItem { Label("Identity", systemImage: "person") }
                urlsTab.tabItem { Label("URLs", systemImage: "link") }
            }
            .padding()

            Divider()
            HStack {
                Button("Reset to Defaults") { config = CrawlConfiguration() }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Save") {
                    var updated = project
                    updated.configuration = config
                    try? env.db.updateProject(updated)
                    if let idx = env.projects.firstIndex(where: { $0.id == project.id }) {
                        env.projects[idx] = updated
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(20)
        }
        .frame(width: 560, height: 500)
    }

    private var scopeTab: some View {
        Form {
            Section("Boundaries") {
                Toggle("Constrain to seed domain", isOn: $config.constrainToSeedDomain)
                Toggle("Include subdomains", isOn: $config.includeSubdomains)
                    .disabled(!config.constrainToSeedDomain)
                LabeledContent("Max Depth") {
                    Stepper("\(config.maxDepth)", value: $config.maxDepth, in: 0...100)
                }
                LabeledContent("Max URLs (0=unlimited)") {
                    TextField("", value: $config.maxURLs, format: .number)
                }
            }
            Section("Filters") {
                Toggle("Skip non-HTML content types", isOn: .constant(true)).disabled(true)
                Toggle("Import sitemap at start", isOn: $config.importSitemapAtStart)
            }
        }
        .formStyle(.grouped)
    }

    private var politenessTab: some View {
        Form {
            Section("Rate Limiting") {
                LabeledContent("Req/sec per host") {
                    HStack {
                        Slider(value: $config.requestsPerSecondPerHost, in: 0.1...20, step: 0.1)
                        Text(String(format: "%.1f", config.requestsPerSecondPerHost))
                            .monospacedDigit().frame(width: 35)
                    }
                }
                LabeledContent("Max concurrent requests") {
                    Stepper("\(config.maxConcurrentRequests)", value: $config.maxConcurrentRequests, in: 1...100)
                }
                LabeledContent("Max concurrent per host") {
                    Stepper("\(config.maxConcurrentRequestsPerHost)", value: $config.maxConcurrentRequestsPerHost, in: 1...10)
                }
            }
            Section("Timeouts & Retries") {
                LabeledContent("Timeout (seconds)") {
                    Stepper(
                        "\(Int(config.timeoutSeconds))s",
                        value: $config.timeoutSeconds,
                        in: 3...60, step: 1
                    )
                }
                LabeledContent("Max retries") {
                    Stepper("\(config.maxRetries)", value: $config.maxRetries, in: 0...5)
                }
            }
            Section("Robots") {
                Toggle("Obey robots.txt", isOn: $config.obeyRobots)
            }
        }
        .formStyle(.grouped)
    }

    private var identityTab: some View {
        Form {
            Section("User-Agent") {
                TextField("User-Agent", text: $config.userAgent)
                    .font(.system(.body, design: .monospaced))
            }
            Section("Custom Headers") {
                Text("Custom header support — add key:value pairs")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                // TODO: key-value list editor in V1
            }
        }
        .formStyle(.grouped)
    }

    private var urlsTab: some View {
        Form {
            Section("URL Normalisation") {
                Toggle("Strip tracking parameters (utm_*, etc.)", isOn: $config.stripTrackingParameters)
                Toggle("Normalise trailing slashes", isOn: $config.normalizeTrailingSlash)
                Toggle("Sort query parameters", isOn: $config.sortQueryParameters)
                Toggle("Canonicalise HTTP vs HTTPS", isOn: $config.canonicalizeHTTPSvsHTTP)
            }
            Section("Response Limits") {
                LabeledContent("Max response size") {
                    Picker("", selection: $config.maxResponseBodyBytes) {
                        Text("1 MB").tag(1_000_000)
                        Text("5 MB").tag(5_000_000)
                        Text("10 MB").tag(10_000_000)
                        Text("25 MB").tag(25_000_000)
                    }
                    .labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
    }
}
