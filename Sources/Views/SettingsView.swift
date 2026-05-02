import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem {
                    Label(L10n.Settings.general, systemImage: "gear")
                }
                .tag(0)
            
            ChannelsTab()
                .tabItem {
                    Label(L10n.Settings.channels, systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(1)
            
            AdvancedTab()
                .tabItem {
                    Label(L10n.Settings.advanced, systemImage: "wrench.and.screwdriver")
                }
                .tag(2)
            
            UsageTab()
                .tabItem {
                    Label(L10n.Settings.usage, systemImage: "chart.bar")
                }
                .tag(3)
            
            AboutTab()
                .tabItem {
                    Label(L10n.Settings.about, systemImage: "info.circle")
                }
                .tag(4)
        }
        .frame(width: 600, height: 450)
    }
}

// General Tab
struct GeneralTab: View {
    @StateObject private var proxy = ProxyServer.shared
    
    var body: some View {
        Form {
            Section(L10n.Settings.serviceControl) {
                HStack {
                    Text("Proxy Status")
                    Spacer()
                    Button(proxy.isRunning ? L10n.Common.stop : L10n.Common.start) {
                        proxy.isRunning ? proxy.stop() : proxy.start()
                    }
                }
                
                HStack {
                    Text(L10n.Settings.localPort)
                    TextField("", text: .constant("1897"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                Toggle(L10n.Settings.launchAtLogin, isOn: .constant(true))
            }
            
            Section(L10n.Settings.environment) {
                Button(L10n.Settings.setupShell) {
                    // TODO: Setup Shell
                }
            }
        }
        .padding()
    }
}

// Channels Tab (Placeholder)
struct ChannelsTab: View {
    var body: some View {
        VStack {
            Text(L10n.Settings.channels)
                .font(.title2)
            Spacer()
        }
        .padding()
    }
}

// Advanced Tab (Placeholder)
struct AdvancedTab: View {
    var body: some View {
        VStack {
            Text(L10n.Settings.advanced)
                .font(.title2)
            Spacer()
        }
        .padding()
    }
}

// Usage Tab (Placeholder)
struct UsageTab: View {
    var body: some View {
        VStack {
            Text(L10n.Settings.usage)
                .font(.title2)
            Spacer()
        }
        .padding()
    }
}

// About Tab (Placeholder)
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundColor(.blue)
            
            Text(L10n.App.title)
                .font(.title2)
            
            Text("Version 1.0.0")
            
            Button(L10n.About.checkUpdates) {
                // TODO: Check updates
            }
            
            Spacer()
        }
        .padding()
    }
}
