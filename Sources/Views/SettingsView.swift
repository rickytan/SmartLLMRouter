import SwiftUI
import Charts
import Sparkle

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
                .accessibilityIdentifier("settings.tabGeneral")

            ChannelsTab()
                .tabItem {
                    Label(L10n.Settings.channels, systemImage: "server.rack")
                }
                .tag(1)
                .accessibilityIdentifier("settings.tabChannels")

            AdvancedTab()
                .tabItem {
                    Label(L10n.Settings.advanced, systemImage: "slider.horizontal.3")
                }
                .tag(2)
                .accessibilityIdentifier("settings.tabAdvanced")

            UsageTab()
                .tabItem {
                    Label(L10n.Settings.usage, systemImage: "chart.bar.fill")
                }
                .tag(3)
                .accessibilityIdentifier("settings.tabUsage")

            AboutTab()
                .tabItem {
                    Label(L10n.Settings.about, systemImage: "info.circle")
                }
                .tag(4)
                .accessibilityIdentifier("settings.tabAbout")
        }
        .frame(width: DesignToken.Layout.settingsFrameWidth, height: DesignToken.Layout.settingsFrameHeight)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var shellConfig = ShellConfigManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.xl) {
                // Service Control Section
                serviceSection

                Divider()
                    .padding(.horizontal, DesignToken.Layout.cardPadding)

                // Shell Environment Section
                shellSection
            }
            .padding(DesignToken.Layout.cardPadding)
        }
    }

    // MARK: - Service Section

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
            Text(L10n.Settings.generalService)
                .font(DesignToken.Font.h2())
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
            .accessibilityIdentifier("settings.general.startStopButton")

            // Status Line
            HStack(spacing: DesignToken.Spacing.xs) {
                StatusIndicatorView(isRunning: proxy.isRunning, isCooldown: false)
                    .frame(width: DesignToken.Layout.statusIndicatorSmall, height: DesignToken.Layout.statusIndicatorSmall)
                    .accessibilityIdentifier(proxy.isRunning ? "menu.status.running" : "menu.status.stopped")

                Text(proxy.isRunning
                     ? L10n.Settings.generalRunningOnPort(proxy.port)
                     : L10n.Settings.generalServiceStopped)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(proxy.isRunning
                        ? DesignToken.Colors.statusOnline
                        : DesignToken.Colors.textSecondary)
            }

            // Port Input
            LabeledNumberField(
                L10n.Settings.generalPort,
                placeholder: L10n.Settings.generalPortPlaceholder,
                value: $appState.port,
                accessibilityID: "settings.general.portField"
            )

            // Launch at Login Toggle
            ToggleRow(
                L10n.Settings.generalAutoStart,
                isOn: $appState.launchAtLogin
            )
            .accessibilityIdentifier("settings.general.autoStartToggle")
        }
    }

    // MARK: - Shell Section

    private var shellSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
            Text(L10n.Settings.generalShellEnv)
                .font(DesignToken.Font.h2())
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
            HStack(spacing: DesignToken.Spacing.xs) {
                if shellConfig.isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignToken.Colors.statusOnline)
                    Text(L10n.Settings.generalShellConfigured)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                } else {
                    Text(L10n.Settings.generalNotConfigured)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
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
    @State private var showingConfigImporter = false
    @State private var isTestingAll = false

    var body: some View {
        VStack(spacing: DesignToken.Spacing.md) {
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

                // Import Config button
                HoverButton(
                    title: L10n.ConfigImporter.title,
                    icon: "square.and.arrow.down.on.square"
                ) {
                    showingConfigImporter = true
                }
                .accessibilityIdentifier("settings.channels.importConfig")

                HoverButton(
                    title: L10n.Settings.channelsAdd,
                    icon: "plus"
                ) {
                    showingAddChannel = true
                }
                .accessibilityIdentifier("settings.channels.addButton")
            }
            .padding(.horizontal, DesignToken.Layout.cardPadding)

            Divider()

            // Channel List
            if channelStore.channels.isEmpty {
                EmptyChannelView()
            } else {
                List {
                    ForEach(channelStore.channels) { channel in
                        ChannelRowView(channel: channel, index: channelStore.channels.firstIndex(of: channel) ?? 0)
                    }
                    .onMove(perform: channelStore.moveChannel)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                .accessibilityIdentifier("settings.channels.list")
            }

            // Hint
            Text(L10n.Settings.channelsReorderHint)
                .font(DesignToken.Font.micro())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .padding(.bottom, DesignToken.Spacing.xs)
        }
        .padding(DesignToken.Layout.cardPadding)
        .sheet(isPresented: $showingAddChannel) {
            AddChannelView()
        }
        .sheet(isPresented: $showingConfigImporter) {
            ConfigImporterView()
        }
    }
}

// MARK: - Advanced Tab

struct AdvancedTab: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared
    @State private var circuitStates: [String: CircuitState] = [:]
    @State private var refreshTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.xl) {
                // Failover Section
                VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
                    Text(L10n.Settings.advancedFailover)
                        .font(DesignToken.Font.h2())

                    ToggleRow(
                        L10n.Settings.advancedFailover,
                        isOn: $appState.autoFailover
                    )
                    .accessibilityIdentifier("settings.advanced.autoFailoverToggle")
                }

                Divider()
                    .padding(.horizontal, DesignToken.Layout.cardPadding)

                // Smart Model Fallback Section
                smartFallbackSection

                Divider()
                    .padding(.horizontal, DesignToken.Layout.cardPadding)

                // Circuit Breaker Section
                circuitBreakerSection

                Divider()
                    .padding(.horizontal, DesignToken.Layout.cardPadding)

                // Cooldown Section
                VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
                    Text(L10n.Settings.advancedCooldown)
                        .font(DesignToken.Font.h2())

                    cooldownRow(title: L10n.Settings.advancedCooldown429, value: "30m")
                        .accessibilityIdentifier("settings.advanced.cooldown.429")
                    cooldownRow(title: L10n.Settings.advancedCooldown5xx, value: "10m")
                        .accessibilityIdentifier("settings.advanced.cooldown.5xx")
                    cooldownRow(title: L10n.Settings.advancedCooldown401, value: "24h")
                        .accessibilityIdentifier("settings.advanced.cooldown.401")
                }
            }
            .padding(DesignToken.Layout.cardPadding)
        }
        .onAppear {
            refreshCircuitStates()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in
                    refreshCircuitStates()
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
    }

    private var smartFallbackSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
            Text(L10n.Settings.advancedSmartFallback)
                .font(DesignToken.Font.h2())

            ToggleRow(
                L10n.Settings.advancedSmartFallback,
                isOn: Binding(
                    get: { SmartRouter.shared.smartFallbackEnabled },
                    set: { SmartRouter.shared.smartFallbackEnabled = $0; SmartRouter.shared.saveSettings() }
                )
            )
            .accessibilityIdentifier("settings.advanced.smartFallback")

            Text(L10n.Settings.advancedSmartFallbackWarning)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledDoubleField(
                L10n.Settings.advancedMaxFallbackCost,
                placeholder: "$2.00",
                hint: L10n.Settings.advancedMaxFallbackCostHint,
                value: Binding(
                    get: { SmartRouter.shared.maxFallbackCost },
                    set: { SmartRouter.shared.maxFallbackCost = $0; SmartRouter.shared.saveSettings() }
                ),
                accessibilityID: "settings.advanced.maxFallbackCost"
            )
        }
    }

    private func cooldownRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(DesignToken.Font.body())

            Spacer()

            Text(value)
                .font(DesignToken.Font.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(DesignToken.Colors.textSecondary)
        }
    }

    // MARK: - Circuit Breaker Section

    private var circuitBreakerSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
            HStack {
                Text(L10n.CircuitBreaker.title)
                    .font(DesignToken.Font.h2())

                Spacer()

                Button {
                    resetAllCircuits()
                } label: {
                    Text(L10n.CircuitBreaker.resetAll)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.accent)
                }
            }

            Text(L10n.CircuitBreaker.description)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if circuitStates.isEmpty {
                HStack(spacing: DesignToken.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignToken.Colors.statusOnline)
                    Text(L10n.CircuitBreaker.stateClosed)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                }
            } else {
                ForEach(circuitStates.sorted(by: { $0.key < $1.key }), id: \.key) { channelID, state in
                    circuitStateRow(channelID: channelID, state: state)
                }
            }
        }
    }

    private func circuitStateRow(channelID: String, state: CircuitState) -> some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            // Status indicator
            Circle()
                .fill(stateColor(for: state))
                .frame(width: DesignToken.Layout.statusDotSize, height: DesignToken.Layout.statusDotSize)

            // Channel name
            let channelName = channelStore.channels.first(where: { $0.id == channelID })?.name ?? channelID
            Text(channelName)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textPrimary)

            Spacer()

            // State label
            Text(stateLabel(for: state))
                .font(DesignToken.Font.system(size: 11, weight: .medium))
                .foregroundColor(stateColor(for: state))
                .padding(.horizontal, DesignToken.Spacing.xs)
                .padding(.vertical, 2)
                .background(stateColor(for: state).opacity(0.1))
                .cornerRadius(4)

            // Remaining time (if open)
            if case .open(let until) = state {
                let remaining = max(0, until.timeIntervalSince(Date()))
                if remaining > 0 {
                    Text(formatRemainingTime(remaining))
                        .font(DesignToken.Font.system(size: 10, design: .monospaced))
                        .foregroundColor(DesignToken.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, DesignToken.Spacing.sm)
        .padding(.vertical, DesignToken.Spacing.xs)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(8)
    }

    private func stateColor(for state: CircuitState) -> Color {
        switch state {
        case .closed:
            DesignToken.Colors.statusOnline
        case .open:
            DesignToken.Colors.statusOffline
        case .halfOpen:
            DesignToken.Colors.statusWarning
        }
    }

    private func stateLabel(for state: CircuitState) -> String {
        switch state {
        case .closed:
            L10n.CircuitBreaker.stateClosed
        case .open:
            L10n.CircuitBreaker.stateOpen
        case .halfOpen:
            L10n.CircuitBreaker.stateHalfOpen
        }
    }

    private func formatRemainingTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            return "\(Int(seconds / 60))m"
        }
    }

    private func refreshCircuitStates() {
        circuitStates = CircuitBreaker.shared.allStates()
    }

    private func resetAllCircuits() {
        for channel in channelStore.channels {
            CircuitBreaker.shared.reset(channelID: channel.id)
        }
        refreshCircuitStates()
    }
}

// MARK: - Daily Channel Usage Data for Stacked Bar Chart

struct DailyChannelUsage: Identifiable {
    let id = UUID()
    let date: Date
    let channelName: String
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

// Channel colors for chart legend
extension Color {
    static let channelColors: [Color] = [
        .blue, .green, .orange, .purple, .red,
        .yellow, .pink, .cyan, .mint, .indigo,
        .teal, .brown, .gray
    ]

    static func channelColor(for name: String) -> Color {
        let hash = name.hashValue
        let index = abs(hash) % channelColors.count
        return channelColors[index]
    }
}

// MARK: - Usage Tab

struct UsageTab: View {
    @ObservedObject private var usage = UsageTracker.shared
    @ObservedObject private var channelStore = ChannelStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.lg + DesignToken.Spacing.sm) {
                // Stat Cards
                HStack(spacing: DesignToken.Spacing.md) {
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
                .padding(.horizontal, DesignToken.Layout.cardPadding)

                // 30-day stacked bar chart by channel
                if dailyChannelUsageData.isEmpty {
                    VStack(spacing: DesignToken.Spacing.sm) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: DesignToken.Layout.largeIconSize))
                            .foregroundColor(DesignToken.Colors.textSecondary)
                        Text(L10n.Settings.usageNoData)
                            .font(DesignToken.Font.body())
                            .foregroundColor(DesignToken.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignToken.Spacing.xl)
                    .accessibilityIdentifier("usage.chart.empty")
                } else {
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.sm) {
                        Text(L10n.Settings.usageChartTitle)
                            .font(DesignToken.Font.h3())
                            .padding(.horizontal, DesignToken.Layout.cardPadding)

                        Chart {
                            ForEach(dailyChannelUsageData) { item in
                                BarMark(
                                    x: .value("Date", item.date, unit: .day),
                                    y: .value("Tokens", item.tokens)
                                )
                                .foregroundStyle(Color.channelColor(for: item.channelName))
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
                        .frame(height: DesignToken.Layout.chartHeight)
                        .padding(.horizontal, DesignToken.Spacing.sm)
                        .accessibilityIdentifier("usage.chart.bar")

                        // Channel legend
                        if !channelNamesInChart.isEmpty {
                            HStack(spacing: DesignToken.Spacing.sm) {
                                ForEach(channelNamesInChart, id: \.self) { name in
                                    HStack(spacing: DesignToken.Spacing.xs) {
                                        Circle()
                                            .fill(Color.channelColor(for: name))
                                            .frame(width: DesignToken.Layout.statusDotSize, height: DesignToken.Layout.statusDotSize)
                                        Text(name)
                                            .font(DesignToken.Font.micro())
                                            .foregroundColor(DesignToken.Colors.textSecondary)
                                    }
                                }
                            }
                            .padding(.top, DesignToken.Spacing.xs)
                            .padding(.horizontal, DesignToken.Layout.cardPadding)
                        }
                    }
                    .padding(.vertical, DesignToken.Spacing.xs)
                }

                // Channel Statistics
                if channelStats.isEmpty {
                    EmptyChannelStats()
                } else {
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.sm) {
                        Text(L10n.Settings.usageChannelStats)
                            .font(DesignToken.Font.h3())
                            .padding(.horizontal, DesignToken.Layout.cardPadding)

                        VStack(spacing: DesignToken.Spacing.xs) {
                            ForEach(channelStats) { stat in
                                ChannelStatRow(stat: stat)
                            }
                        }
                        .accessibilityIdentifier("usage.channelStats")
                    }
                    .padding(.vertical, DesignToken.Spacing.xs)
                }

                Spacer()
            }
            .padding(.vertical, DesignToken.Layout.cardPadding)
        }
    }

    // Compute daily channel usage for the last 30 days (stacked by channel)
    private var dailyChannelUsageData: [DailyChannelUsage] {
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!

    // Key: date+channel -> usage data
        struct DayChannelKey: Hashable {
            let date: Date
            let channelName: String
        }
        var dailyChannelMap: [DayChannelKey: (tokens: Int, requests: Int, cost: Double)] = [:]

        // Aggregate records
        for record in usage.records where record.timestamp >= startDate {
            let dayStart = calendar.startOfDay(for: record.timestamp)
            let key = DayChannelKey(date: dayStart, channelName: record.channelName)
            if let existing = dailyChannelMap[key] {
                dailyChannelMap[key] = (
                    existing.tokens + record.totalTokens,
                    existing.requests + 1,
                    existing.cost + record.estimatedCost
                )
            } else {
                dailyChannelMap[key] = (record.totalTokens, 1, record.estimatedCost)
            }
        }

        return dailyChannelMap
            .map { DailyChannelUsage(date: $0.key.date, channelName: $0.key.channelName, tokens: $0.value.tokens, requests: $0.value.requests, cost: $0.value.cost) }
            .sorted { $0.date < $1.date || ($0.date == $1.date && $0.channelName < $1.channelName) }
    }

    // Get sorted unique channel names in the chart data
    private var channelNamesInChart: [String] {
        Set(dailyChannelUsageData.map(\.channelName)).sorted()
    }

    // Compute per-channel stats from today's records
    private var channelStats: [ChannelStat] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        var statsMap: [String: (requests: Int, tokens: Int, cost: Double)] = [:]

        for record in usage.records where record.timestamp >= todayStart {
            if let existing = statsMap[record.channelName] {
                statsMap[record.channelName] = (
                    existing.requests + 1,
                    existing.tokens + record.totalTokens,
                    existing.cost + record.estimatedCost
                )
            } else {
                statsMap[record.channelName] = (1, record.totalTokens, record.estimatedCost)
            }
        }

        return statsMap
            .map { channelName, value in
                ChannelStat(
                    channelName: channelName,
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
        HStack(spacing: DesignToken.Spacing.md) {
            Text(stat.channelName)
                .font(DesignToken.Font.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer()

            HStack(spacing: DesignToken.Spacing.lg) {
                statItem(label: L10n.Settings.usageRequests, value: "\(stat.requests)")
                statItem(label: L10n.Settings.usageTokens, value: formatTokens(stat.tokens))
                statItem(label: L10n.Settings.usageCost, value: String(format: "$%.2f", stat.cost))
            }
        }
        .padding(.horizontal, DesignToken.Spacing.md)
        .padding(.vertical, DesignToken.Spacing.sm)
        .background(isHovered ? DesignToken.Colors.hoverFill : DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.buttonCornerRadius)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: DesignToken.Spacing.xs) {
            Text(value)
                .font(DesignToken.Font.system(size: 12, weight: .semibold))
            Text(label)
                .font(DesignToken.Font.microSmall())
                .foregroundColor(DesignToken.Colors.textSecondary)
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
        VStack(spacing: DesignToken.Spacing.sm) {
            Text(L10n.Settings.usageNoData)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignToken.Spacing.md)
        .accessibilityIdentifier("usage.channelStats.empty")
    }
}

// MARK: - About Tab

struct AboutTab: View {
    @StateObject private var updaterDelegate = SparkleUpdaterDelegate.shared

    var body: some View {
        VStack(spacing: DesignToken.Spacing.lg + DesignToken.Spacing.sm) {
            Image(systemName: "network")
                .font(.system(size: DesignToken.Layout.heroIconSize))
                .foregroundColor(DesignToken.Colors.accent)

            Text(L10n.About.appName)
                .font(DesignToken.Font.h1())

            Text(L10n.Settings.aboutVersion("1.0.0"))
                .font(DesignToken.Font.body())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .accessibilityIdentifier("about.version")

            VStack(spacing: DesignToken.Spacing.md) {
                // Check for Updates button (Sparkle)
                HoverButton(
                    title: L10n.Settings.aboutCheckUpdate,
                    icon: "arrow.down.circle"
                ) {
                    updaterDelegate.checkForUpdates()
                }
                .accessibilityIdentifier("settings.about.checkUpdateButton")

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
        .padding(DesignToken.Spacing.xl)
    }
}

// MARK: - Sparkle Updater Delegate

@MainActor
final class SparkleUpdaterDelegate: ObservableObject {
    static let shared = SparkleUpdaterDelegate()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        // SPUStandardUpdaterController starts looking for updates automatically
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
