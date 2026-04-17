import SwiftUI

struct NewProjectSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var seedURLText: String = ""
    @State private var config = CrawlConfiguration()
    @State private var showAdvanced = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, seedURL }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !seedURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Project").font(.title2.weight(.semibold))
                    Text("Configure a new SEO crawl project").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()

            // Form
            Form {
                Section {
                    LabeledContent("Project Name") {
                        TextField("My Website", text: $name)
                            .focused($focusedField, equals: .name)
                    }
                    LabeledContent("Seed URL(s)") {
                        TextEditor(text: $seedURLText)
                            .focused($focusedField, equals: .seedURL)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 80)
                    }
                } header: {
                    Text("Basic")
                } footer: {
                    Text("Enter one URL per line. The crawler will start from these URLs.")
                        .foregroundStyle(.secondary)
                }

                Section("Scope") {
                    Toggle("Stay within seed domain", isOn: $config.constrainToSeedDomain)
                    Toggle("Include subdomains", isOn: $config.includeSubdomains)
                        .disabled(!config.constrainToSeedDomain)

                    LabeledContent("Max Depth") {
                        Stepper("\(config.maxDepth)", value: $config.maxDepth, in: 0...50)
                    }
                    LabeledContent("Max URLs") {
                        TextField("0 = unlimited", value: $config.maxURLs, format: .number)
                    }
                }

                Section("Politeness") {
                    LabeledContent("Req/sec per host") {
                        Slider(value: $config.requestsPerSecondPerHost, in: 0.1...10, step: 0.1)
                        Text(String(format: "%.1f", config.requestsPerSecondPerHost))
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                    LabeledContent("Concurrency") {
                        Stepper("\(config.maxConcurrentRequests)", value: $config.maxConcurrentRequests, in: 1...50)
                    }
                    Toggle("Obey robots.txt", isOn: $config.obeyRobots)
                }

                Section("Options") {
                    Toggle("Import sitemap at start", isOn: $config.importSitemapAtStart)
                    Toggle("Strip tracking parameters", isOn: $config.stripTrackingParameters)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Create Project") {
                    let urls = seedURLText
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    env.createProject(name: name, seedURLs: urls, config: config)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 520, height: 620)
        .onAppear {
            focusedField = .name
        }
    }
}
