import SwiftUI

// MARK: - SettingsView

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
                    Label(L10n.Settings.general, systemImage: "gearshape")
                }
                .tag(0)
                .accessibilityIdentifier("settings.tab.general")

            ChannelsTab()
                .tabItem {
                    Label(L10n.Settings.channels, systemImage: "server.rack")
                }
                .tag(1)
                .accessibilityIdentifier("settings.tab.channels")

            AdvancedTab()
                .tabItem {
                    Label(L10n.Settings.advanced, systemImage: "slider.horizontal.3")
                }
                .tag(2)
                .accessibilityIdentifier("settings.tab.advanced")

            UsageTab()
                .tabItem {
                    Label(L10n.Settings.usage, systemImage: "chart.bar.fill")
                }
                .tag(3)
                .accessibilityIdentifier("settings.tab.usage")

            AboutTab()
                .tabItem {
                    Label(L10n.Settings.about, systemImage: "info.circle")
                }
                .tag(4)
                .accessibilityIdentifier("settings.tab.about")
        }
        .frame(width: 560, height: 420)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var shellConfig = ShellConfigManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Service Control Section
                serviceSection

                Divider()
                    .padding(.horizontal, 16)

                // Shell Environment Section
                shellSection
            }
            .padding(16)
        }
    }

    // MARK: - Service Section

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service")
                .font(.system(size: 15, weight: .semibold))

            // Start/Stop Button
            HoverButton(
                title: proxy.isRunning ? "⏹️ Stop Service" : "▶️ Start Service",
                icon: proxy.isRunning ? "stop.fill" : "play.fill"
            ) {
                Task {
                    if proxy.isRunning {
                        await proxy.stop()
                    } else {
                        await proxy.start()
                    }
                }
            }
            .accessibilityIdentifier(proxy.isRunning ? "settings.general.stop" : "settings.general.start")

            // Status Line
            HStack(spacing: 6) {
                StatusIndicatorView(isRunning: proxy.isRunning, isCooldown: false)
                    .frame(width: 6, height: 6)

                Text(proxy.isRunning ? "Running on port \(proxy.port)" : "Service stopped")
                    .font(.system(size: 11))
                    .foregroundColor(proxy.isRunning ? .green : .secondary)
            }

            // Port Input
            HStack {
                Text(L10n.Settings.generalPort)
                    .font(.system(size: 13))

                Spacer()

                TextField("", value: $appState.port, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("settings.general.port")
            }

            // Launch at Login Toggle
            Toggle(isOn: $appState.launchAtLogin) {
                Text(L10n.Settings.generalAutoStart)
                    .font(.system(size: 13))
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("settings.general.launchAtLogin")
        }
    }

    // MARK: - Shell Section

    private var shellSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shell Environment")
                .font(.system(size: 15, weight: .semibold))

            HoverButton(
                title: shellConfig.isConfigured ? "✅ Update Shell Config" : "⚙️ Setup Shell Environment",
                icon: shellConfig.isConfigured ? "checkmark.circle.fill" : "gearshape"
            ) {
                Task {
                    _ = await shellConfig.configure(port: appState.port)
                }
            }

            // Status
            HStack(spacing: 6) {
                if shellConfig.isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Variables already added to ~/.zshrc")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("Not configured")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Channels Tab

struct ChannelsTab: View {
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var channelManager = ChannelManager.shared
    @State private var showingAddChannel = false
    @State private var isTestingAll = false

    var body: some View {
        VStack(spacing: 12) {
            // Toolbar
            HStack {
                HoverButton(
                    title: isTestingAll ? "Testing..." : "⚡ Test All",
                    icon: isTestingAll ? "ellipsis.circle.fill" : "bolt.fill"
                ) {
                    Task {
                        isTestingAll = true
                        await channelManager.speedTestAllChannels()
                        isTestingAll = false
                    }
                }
                .disabled(isTestingAll)
                .accessibilityIdentifier("settings.channels.testAll")

                Spacer()

                HoverButton(
                    title: L10n.Settings.channelsAdd,
                    icon: "plus"
                ) {
                    showingAddChannel = true
                }
                .accessibilityIdentifier("settings.channels.add")
            }
            .padding(.horizontal, 16)

            Divider()

            // Channel List
            if channelStore.channels.isEmpty {
                EmptyChannelView()
            } else {
                List {
                    ForEach(Array(channelStore.channels.enumerated()), id: \.element.id) { index, channel in
                        ChannelRowView(channel: channel, index: index)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                .accessibilityIdentifier("settings.channels.list")
            }

            // Hint
            Text("Reorder: drag using ⠿ handle on left")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
        }
        .padding(16)
        .sheet(isPresented: $showingAddChannel) {
            AddChannelView()
        }
    }
}

// MARK: - Channel Row View

struct ChannelRowView: View {
    let channel: Channel
    let index: Int
    @ObservedObject private var channelManager = ChannelManager.shared
    @State private var isHovered = false
    @State private var isTesting = false

    var body: some View {
        HStack(spacing: 8) {
            // Status Indicator
            StatusIndicatorView(
                isRunning: !channel.isCoolingDown,
                isCooldown: channel.isCoolingDown
            )
            .frame(width: 8, height: 8)
            .accessibilityIdentifier("channel.status.\(index)")

            // Channel Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(channel.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    if channel.lastLatencyMs > 0 {
                        LatencyChip(latencyMs: channel.lastLatencyMs)
                    }
                }

                Text(channel.baseURL)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if !channel.models.isEmpty {
                    Text(channel.models.map(\.identifier).prefix(3).joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Actions
            HStack(spacing: 4) {
                Button {
                    Task {
                        isTesting = true
                        _ = await channelManager.speedTest(channel: channel)
                        isTesting = false
                    }
                } label: {
                    Image(systemName: isTesting ? "ellipsis.circle.fill" : "bolt.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("channel.speedtest.\(index)")

                Button {
                    // Edit channel
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("channel.edit.\(index)")

                Button {
                    ChannelStore.shared.removeChannel(id: channel.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("channel.delete.\(index)")
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovered ? Color.gray.opacity(0.08) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityIdentifier("channel.row.\(index)")
    }
}

// MARK: - Empty Channel View

struct EmptyChannelView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No channels configured")
                .font(.system(size: 13, weight: .medium))

            Text("Add one to get started")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - Advanced Tab

struct AdvancedTab: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Failover Section
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Settings.advancedFailover)
                        .font(.system(size: 15, weight: .semibold))

                    Toggle(L10n.Settings.advancedFailover, isOn: $appState.autoFailover)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("settings.advanced.failover")
                }

                Divider()
                    .padding(.horizontal, 16)

                // Cooldown Section
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Settings.advancedCooldown)
                        .font(.system(size: 15, weight: .semibold))

                    cooldownRow(title: L10n.Settings.advancedCooldown429, value: "30m")
                        .accessibilityIdentifier("settings.advanced.cooldown.429")
                    cooldownRow(title: L10n.Settings.advancedCooldown5xx, value: "10m")
                        .accessibilityIdentifier("settings.advanced.cooldown.5xx")
                    cooldownRow(title: L10n.Settings.advancedCooldown401, value: "24h")
                        .accessibilityIdentifier("settings.advanced.cooldown.401")
                }
            }
            .padding(16)
        }
    }

    private func cooldownRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Usage Tab

struct UsageTab: View {
    @ObservedObject private var usage = UsageTracker.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stat Cards
                HStack(spacing: 16) {
                    StatCard(
                        title: L10n.Settings.usageTotalRequests,
                        value: "\(usage.todayStats.totalRequests)",
                        icon: "arrow.up.right"
                    )
                    .accessibilityIdentifier("usage.totalRequests")

                    StatCard(
                        title: L10n.Settings.usageTotalTokens,
                        value: formatTokens(usage.todayStats.totalTokens),
                        icon: "text.word.spacing"
                    )
                    .accessibilityIdentifier("usage.totalTokens")

                    StatCard(
                        title: L10n.Settings.usageTotalCost,
                        value: String(format: "$%.2f", usage.todayStats.totalCost),
                        icon: "dollarsign.circle"
                    )
                    .accessibilityIdentifier("usage.totalCost")
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.vertical, 16)
        }
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

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)

            Text(value)
                .font(.system(size: 24, weight: .bold))

            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("SmartLLM Router")
                .font(.system(size: 20, weight: .bold))

            Text(L10n.Settings.aboutVersion("1.0.0"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .accessibilityIdentifier("about.version")

            VStack(spacing: 12) {
                HoverButton(
                    title: L10n.Settings.aboutGithub,
                    icon: "link"
                ) {
                    if let url = URL(string: "https://github.com/rickytan/SmartLLMRouter") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .accessibilityIdentifier("about.github")

                HoverButton(
                    title: L10n.Settings.aboutLicense,
                    icon: "doc.text"
                ) {
                    // Show license
                }
            }

            Spacer()
        }
        .padding(32)
    }
}

// MARK: - Add Channel View (Placeholder)

struct AddChannelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Channel")
                .font(.system(size: 15, weight: .semibold))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Base URL", text: $baseURL)
                .textFieldStyle(.roundedBorder)

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Add") {
                    // Add channel logic
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
