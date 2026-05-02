import SwiftUI

@main
struct SmartLLMRouterApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra(L10n.App.title, systemImage: "brain.fill") {
            MenuView()
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
        }
    }
}
