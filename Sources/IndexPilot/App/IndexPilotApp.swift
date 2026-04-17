import SwiftUI

public struct IndexPilotScene: Scene {

    @State private var env = AppEnvironment()
    @State private var showNewProject = false

    public init() {}

    public var body: some Scene {
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
