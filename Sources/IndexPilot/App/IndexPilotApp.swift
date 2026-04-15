import SwiftUI

@main
struct IndexPilotApp: App {

    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(env)
                .frame(minWidth: 960, minHeight: 600)
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
