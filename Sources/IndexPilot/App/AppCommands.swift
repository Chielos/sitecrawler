import SwiftUI

struct AppCommands: Commands {
    let env: AppEnvironment

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
                // Handled by ContentView sheet
                NotificationCenter.default.post(name: .newProject, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Crawl") {
            Button(env.isCrawling ? "Stop Crawl" : "Start Crawl") {
                if env.isCrawling {
                    env.cancelCrawl()
                } else if let project = env.selectedProject {
                    env.startCrawl(for: project)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(env.selectedProject == nil)

            Button("Pause Crawl") {
                env.pauseCrawl()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!env.isCrawling)

            Divider()

            Button("Export URLs as CSV…") {
                guard let session = env.activeSession else { return }
                Task {
                    let url = try? await CSVExporter.exportURLs(sessionID: session.id, db: env.db)
                    if let url = url {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(env.activeSession == nil)
        }
    }
}

extension Notification.Name {
    static let newProject = Notification.Name("IndexPilot.newProject")
}
