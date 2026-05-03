import SwiftUI

struct SettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var usage = UsageTracker.shared
    @State private var selectedTab = 0
    @State private var showingAddChannel = false

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label(L10n.Settings.general, systemImage: "gear")
                }
                .tag(0)

            ChannelsTab()
                .tabItem {
                    Label(L10n.Settings.channels, systemImage: "server.rack")
                }
                .tag(1)

            AdvancedTab()
                .tabItem {
                    Label(L10n.Settings.advanced, systemImage: "slider.horizontal.3")
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
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var proxy = ProxyServer.shared

    var body: some View {
        Form {
            Section(header: Text(L10n.Settings.general)) {
                HStack {
                    Text(L10n.Settings.generalPort)
                    Spacer()
                    TextField(L10n.Settings.generalPortPlaceholder, value: $appState.port, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding()
    }
}

// MARK: - Channels Tab

struct ChannelsTab: View {
    @ObservedObject private var channelStore = ChannelStore.shared
    @State private var showingAddChannel = false

    var body: some View {
        VStack {
            List {
                ForEach(channelStore.channels) { channel in
                    ChannelRow(channel: channel)
                }
            }

            Divider()

            HStack {
                Button(action: { showingAddChannel = true }) {
                    Label(L10n.Settings.channelsAdd, systemImage: "plus")
                }

                Spacer()
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(channel.name)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if channel.isCoolingDown {
                    Text("⚠️")
                        .font(.system(size: 12))
                }
            }
            Text(channel.baseURL)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if !channel.models.isEmpty {
                Text(channel.models.map(\.identifier).joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Advanced Tab

struct AdvancedTab: View {
    var body: some View {
        Form {
            Section(header: Text(L10n.Settings.advancedFailover)) {
                Toggle(L10n.Settings.advancedFailover, isOn: .constant(true))
            }

            Section(header: Text(L10n.Settings.advancedCooldown)) {
                HStack {
                    Text(L10n.Settings.advancedCooldown429)
                    Spacer()
                    Text("30m")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(L10n.Settings.advancedCooldown5xx)
                    Spacer()
                    Text("10m")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(L10n.Settings.advancedCooldown401)
                    Spacer()
                    Text("24h")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Usage Tab

struct UsageTab: View {
    @ObservedObject private var usage = UsageTracker.shared

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                UsageCard(
                    title: L10n.Settings.usageTotalRequests,
                    value: "\(usage.todayStats.totalRequests)"
                )
                UsageCard(
                    title: L10n.Settings.usageTotalTokens,
                    value: formatTokens(usage.todayStats.totalTokens)
                )
                UsageCard(
                    title: L10n.Settings.usageTotalCost,
                    value: String(format: "$%.4f", usage.todayStats.totalCost)
                )
            }

            Spacer()
        }
        .padding()
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}

struct UsageCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("SmartLLM Router")
                .font(.system(size: 20, weight: .bold))

            Text(L10n.Settings.aboutVersion("1.0.0"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Button(L10n.Settings.aboutGithub) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/rickytan/SmartLLMRouter")!)
                }

                Button(L10n.Settings.aboutLicense) {
                    // Show license
                }
            }
            .buttonStyle(.borderless)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
