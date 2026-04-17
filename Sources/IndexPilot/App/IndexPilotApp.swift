import SwiftUI

@main
struct IndexPilotApp: App {

    @State private var env = AppEnvironment()
    @State private var showNewProject = false

    var body: some Scene {
        WindowGroup {
            ContentView(showNewProject: $showNewProject)
                .environment(env)
                .frame(minWidth: 960, minHeight: 600)
                .sheet(isPresented: $showNewProject) {
                    NewProjectSheet()
                        .environment(env)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(env: env)
        }

        Settings {
            SettingsView()
                .environment(env)
        }
    }
}
