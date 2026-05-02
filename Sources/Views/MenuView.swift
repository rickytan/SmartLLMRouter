import SwiftUI

struct MenuView: View {
    @StateObject private var appState = AppState.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            Text("🟢 \(L10n.App.statusRunning) | Port: 1897")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Auto Failover Toggle
            Toggle(L10n.Menu.autoSwitch, isOn: $appState.isAutoFailover)
            
            Divider()
            
            // Channel List
            ForEach(appState.channels) { channel in
                Button(action: {
                    // TODO: Select channel
                }) {
                    HStack {
                        Text(channel.name)
                        Spacer()
                        if channel.isCoolingDown {
                            Text("⏸").font(.caption)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Recent Requests
            Text(L10n.Menu.recentRequests)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Actions
            Button(L10n.Menu.copyEnvConfig) {
                // TODO: Copy to clipboard
            }
            
            Button(L10n.Menu.testActiveKey) {
                // TODO: Test active key
            }
            
            Divider()
            
            // Settings & Quit
            Button(L10n.Menu.settings) {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
            }
            
            Button(L10n.Menu.quit) {
                NSApp.terminate(nil)
            }
            .foregroundColor(.red)
        }
        .padding(8)
        .frame(width: 260)
    }
}
