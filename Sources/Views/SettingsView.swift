import SwiftUI
import Charts

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
            Text(L10n.Settings.generalService)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityIdentifier("settings.general.serviceHeader")

            // Start/Stop Button
            HoverButton(
                title: proxy.isRunning ? L10n.Settings.generalStopService : L10n.Settings.generalStartService,
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
                    .accessibilityIdentifier(proxy.isRunning ? "menu.status.running" : "menu.status.stopped")

                Text(proxy.isRunning
                     ? L10n.Settings.generalRunningOnPort(proxy.port)
                     : L10n.Settings.generalServiceStopped)
                    .font(.system(size: 11))
                    .foregroundColor(proxy.isRunning
                        ? Color(#colorLiteral(red: 0, green: 0.784, blue: 0.325, alpha: 1))
                        : .secondary)
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
            Text(L10n.Settings.generalShellEnv)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityIdentifier("settings.general.shellHeader")

            HoverButton(
                title: shellConfig.isConfigured ? L10n.Settings.generalUpdateShellConfig : L10n.Settings.generalSetupShellEnv,
                icon: shellConfig.isConfigured ? "checkmark.circle.fill" : "gearshape"
            ) {
                Task {
                    _ = await shellConfig.configure(port: appState.port)
                }
            }
            .accessibilityIdentifier("settings.general.shellConfigure")

            // Status
            HStack(spacing: 6) {
                if shellConfig.isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(#colorLiteral(red: 0, green: 0.784, blue: 0.325, alpha: 1)))
                    Text(L10n.Settings.generalShellConfigured)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text(L10n.Settings.generalNotConfigured)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .accessibilityIdentifier("settings.general.shellStatus")
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
                    title: isTestingAll ? L10n.Settings.channelsTesting : L10n.Settings.channelsTestAll,
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
            Text(L10n.Settings.channelsReorderHint)
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
                        .accessibilityIdentifier("channel.name.\(index)")

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
                .foregroundColor(.secondary)
                .accessibilityIdentifier("channel.speedtest.\(index)")

                Button {
                    // Edit channel
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("channel.edit.\(index)")

                Button {
                    ChannelStore.shared.removeChannel(id: channel.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("channel.delete.\(index)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovered ? Color.gray.opacity(0.08) : Color.clear)
        .cornerRadius(6)
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
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(L10n.Settings.channelsEmptyTitle)
                .font(.system(size: 13, weight: .medium))

            Text(L10n.Settings.channelsEmptySubtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .accessibilityIdentifier("settings.channels.emptyState")
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

// MARK: - Daily Usage Data for Charts

struct DailyUsage: Identifiable {
    let id = UUID()
    let date: Date
    let tokens: Int
    let requests: Int
    let cost: Double
}

struct ChannelStat: Identifiable {
    let id = UUID()
    let channelName: String
    let requests: Int
    let tokens: Int
    let cost: Double
}

// MARK: - Usage Tab

struct UsageTab: View {
    @ObservedObject private var usage = UsageTracker.shared
    @ObservedObject private var channelStore = ChannelStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stat Cards
                HStack(spacing: 12) {
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

                // 30-day bar chart
                if dailyUsageData.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text(L10n.Settings.usageNoData)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .accessibilityIdentifier("usage.chart.empty")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Settings.usageChartTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)

                        Chart {
                            ForEach(dailyUsageData) { day in
                                BarMark(
                                    x: .value("Date", day.date, unit: .day),
                                    y: .value("Tokens", day.tokens)
                                )
                                .foregroundStyle(Color.accentColor.opacity(0.75))
                                .cornerRadius(3)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 5)) { value in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let tokens = value.as(Int.self) {
                                        Text(formatTokens(tokens))
                                    }
                                }
                            }
                        }
                        .frame(height: 140)
                        .padding(.horizontal, 8)
                        .accessibilityIdentifier("usage.chart.bar")
                    }
                    .padding(.vertical, 4)
                }

                // Channel Statistics
                if channelStats.isEmpty {
                    EmptyChannelStats()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Settings.usageChannelStats)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)

                        VStack(spacing: 4) {
                            ForEach(channelStats) { stat in
                                ChannelStatRow(stat: stat)
                            }
                        }
                        .accessibilityIdentifier("usage.channelStats")
                    }
                    .padding(.vertical, 4)
                }

                Spacer()
            }
            .padding(.vertical, 16)
        }
    }

    // Compute daily usage for the last 30 days
    private var dailyUsageData: [DailyUsage] {
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!

        var dailyMap: [Date: (tokens: Int, requests: Int, cost: Double)] = [:]

        // Initialize all 30 days with zero
        for dayOffset in 0 ..< 30 {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                dailyMap[calendar.startOfDay(for: date)] = (0, 0, 0)
            }
        }

        // Aggregate records
        for record in usage.records where record.timestamp >= startDate {
            let dayStart = calendar.startOfDay(for: record.timestamp)
            if let existing = dailyMap[dayStart] {
                dailyMap[dayStart] = (
                    existing.tokens + record.totalTokens,
                    existing.requests + 1,
                    existing.cost + record.estimatedCost
                )
            }
        }

        return dailyMap
            .map { DailyUsage(date: $0.key, tokens: $0.value.tokens, requests: $0.value.requests, cost: $0.value.cost) }
            .sorted { $0.date < $1.date }
    }

    // Compute per-channel stats from today's records
    private var channelStats: [ChannelStat] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        var statsMap: [String: (requests: Int, tokens: Int, cost: Double)] = [:]

        for record in usage.records where record.timestamp >= todayStart {
            if let existing = statsMap[record.channelID] {
                statsMap[record.channelID] = (
                    existing.requests + 1,
                    existing.tokens + record.totalTokens,
                    existing.cost + record.estimatedCost
                )
            } else {
                statsMap[record.channelID] = (1, record.totalTokens, record.estimatedCost)
            }
        }

        return statsMap
            .map { channelID, value in
                ChannelStat(
                    channelName: value.requests > 0 ?
                        (usage.records.first { $0.channelID == channelID }?.channelName ?? channelID) : channelID,
                    requests: value.requests,
                    tokens: value.tokens,
                    cost: value.cost)
            }
            .sorted { $0.tokens > $1.tokens }
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

// MARK: - Channel Stat Row

struct ChannelStatRow: View {
    let stat: ChannelStat
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Text(stat.channelName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer()

            HStack(spacing: 16) {
                statItem(label: L10n.Settings.usageRequests, value: "\(stat.requests)")
                statItem(label: L10n.Settings.usageTokens, value: formatTokens(stat.tokens))
                statItem(label: L10n.Settings.usageCost, value: String(format: "$%.2f", stat.cost))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.gray.opacity(0.08) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .semibold))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
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

// MARK: - Empty Channel Stats

struct EmptyChannelStats: View {
    var body: some View {
        VStack(spacing: 8) {
            Text(L10n.Settings.usageNoData)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityIdentifier("usage.channelStats.empty")
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    @State private var isHovered = false

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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text(L10n.About.appName)
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

// MARK: - Preview

#Preview {
    SettingsView()
}
