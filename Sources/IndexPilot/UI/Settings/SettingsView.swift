import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultConcurrency") private var defaultConcurrency: Int = 5
    @AppStorage("defaultReqPerSec") private var defaultReqPerSec: Double = 1.0
    @AppStorage("defaultObeyRobots") private var defaultObeyRobots: Bool = true
    @AppStorage("defaultUserAgent") private var defaultUserAgent: String = "IndexPilot/1.0 (+https://indexpilot.app/bot)"
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            defaultsTab
                .tabItem { Label("Crawl Defaults", systemImage: "network") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                Picker("Color Scheme", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            Section("Storage") {
                LabeledContent("Database location") {
                    Text((try? DatabaseManager.defaultPath()) ?? "Unknown")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Reveal in Finder") {
                    if let path = try? DatabaseManager.defaultPath() {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var defaultsTab: some View {
        Form {
            Section("Politeness") {
                LabeledContent("Default concurrency") {
                    Stepper("\(defaultConcurrency)", value: $defaultConcurrency, in: 1...50)
                }
                LabeledContent("Default req/sec per host") {
                    HStack {
                        Slider(value: $defaultReqPerSec, in: 0.1...10, step: 0.1)
                        Text(String(format: "%.1f", defaultReqPerSec))
                            .monospacedDigit().frame(width: 35)
                    }
                }
                Toggle("Obey robots.txt by default", isOn: $defaultObeyRobots)
            }
            Section("Identity") {
                TextField("User-Agent", text: $defaultUserAgent)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            VStack(spacing: 4) {
                Text("IndexPilot").font(.title.weight(.bold))
                Text("Version 0.1.0 (MVP)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("A professional-grade SEO crawler for macOS Apple Silicon.\nBuilt for technical SEO audits at scale.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
