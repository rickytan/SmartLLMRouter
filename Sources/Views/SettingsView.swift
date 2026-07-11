import SwiftUI
import AppKit
import Charts
import Sparkle

// MARK: - SettingsView

private enum SettingsTab: Int, Hashable {
    case general
    case channels
    case advanced
    case usage
    case about

    var size: CGSize {
        switch self {
        case .general:
            CGSize(width: 640, height: 540)
        case .channels:
            CGSize(width: 800, height: 600)
        case .advanced:
            CGSize(width: 640, height: 600)
        case .usage:
            CGSize(width: 800, height: 600)
        case .about:
            CGSize(width: 480, height: 360)
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label(L10n.Settings.general, systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
                .accessibilityIdentifier("settings.tabGeneral")

            ChannelsTab()
                .tabItem {
                    Label(L10n.Settings.channels, systemImage: "server.rack")
                }
                .tag(SettingsTab.channels)
                .accessibilityIdentifier("settings.tabChannels")

            AdvancedTab()
                .tabItem {
                    Label(L10n.Settings.advanced, systemImage: "slider.horizontal.3")
                }
                .tag(SettingsTab.advanced)
                .accessibilityIdentifier("settings.tabAdvanced")

            UsageTab()
                .tabItem {
                    Label(L10n.Settings.usage, systemImage: "chart.bar.fill")
                }
                .tag(SettingsTab.usage)
                .accessibilityIdentifier("settings.tabUsage")

            AboutTab()
                .tabItem {
                    Label(L10n.Settings.about, systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
                .accessibilityIdentifier("settings.tabAbout")
        }
        .frame(width: selectedTab.size.width, height: selectedTab.size.height)
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var proxy: ProxyServer
    @ObservedObject private var shellConfig: ShellConfigManager
    @ObservedObject private var claudeCode: ClaudeCodeConfigManager

    @MainActor
    init(services: AppServices? = nil) {
        let services = services ?? .shared
        _appState = ObservedObject(wrappedValue: services.appState)
        _proxy = ObservedObject(wrappedValue: services.proxyServer)
        _shellConfig = ObservedObject(wrappedValue: services.shellConfigManager)
        _claudeCode = ObservedObject(wrappedValue: services.claudeCodeConfigManager)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
                pageHeader

                sectionTitle(L10n.Settings.generalSectionProxy)
                    .accessibilityIdentifier("settings.general.serviceHeader")
                GeneralFormCard {
                    portRow
                    rowDivider
                    launchRow
                }

                sectionTitle(L10n.Settings.generalIntegrations)
                GeneralFormCard {
                    shellRow
                    rowDivider
                    claudeRow
                }

                footerHint
            }
            .padding(DesignToken.Layout.cardPadding)
        }
        .onAppear {
            claudeCode.refresh()
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                Text(L10n.Settings.general)
                    .font(DesignToken.Font.h1())
                    .foregroundColor(DesignToken.Colors.textPrimary)
                Text(L10n.Settings.generalSubtitle)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignToken.Spacing.md) {
                ServiceStatusBadge(isRunning: proxy.isRunning)
                PrimaryActionButton(
                    title: proxy.isRunning ? L10n.Settings.generalStopService : L10n.Settings.generalStartService,
                    icon: proxy.isRunning ? "stop.fill" : "play.fill"
                ) {
                    if proxy.isRunning {
                        proxy.stop()
                    } else {
                        proxy.start()
                    }
                }
                .accessibilityIdentifier(proxy.isRunning ? "settings.general.stop" : "settings.general.start")
            }
        }
    }

    // MARK: - Section Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignToken.Font.h2())
            .foregroundColor(DesignToken.Colors.textPrimary)
    }

    private var rowDivider: some View {
        Divider()
    }

    private func iconBox(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(DesignToken.Font.system(size: 15, weight: .medium))
            .foregroundColor(DesignToken.Colors.textSecondary)
            .frame(width: 28, height: 28)
            .background(DesignToken.Colors.bgSecondary)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
    }

    // MARK: - Service Rows

    private var portRow: some View {
        GeneralFormRow {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                Text(L10n.Settings.generalPort)
                    .font(DesignToken.Font.body())
                    .foregroundColor(DesignToken.Colors.textPrimary)
                Text(L10n.Settings.generalPortHint)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }
        } trailing: {
            PortField(value: $appState.port, placeholder: L10n.Settings.generalPortPlaceholder)
        }
        .accessibilityIdentifier("settings.general.port")
    }

    private var launchRow: some View {
        GeneralFormRow {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                Text(L10n.Settings.generalAutoStart)
                    .font(DesignToken.Font.body())
                    .foregroundColor(DesignToken.Colors.textPrimary)
                Text(L10n.Settings.generalAutoStartHint)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }
        } trailing: {
            Toggle("", isOn: $appState.launchAtLogin)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .accessibilityIdentifier("settings.general.launchAtLogin")
    }

    // MARK: - Integration Rows

    private var shellRow: some View {
        GeneralFormRow {
            HStack(spacing: DesignToken.Spacing.md) {
                iconBox("terminal")
                VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                    Text(L10n.Settings.generalShellEnv)
                        .font(DesignToken.Font.body())
                        .foregroundColor(DesignToken.Colors.textPrimary)
                    Text(shellStatusText)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                        .accessibilityIdentifier("settings.general.shellStatus")
                }
            }
        } trailing: {
            SecondaryActionButton(
                title: shellConfig.isConfigured ? L10n.Settings.generalUpdateShellConfig : L10n.Settings.generalSetupShellEnv,
                icon: shellConfig.isConfigured ? "checkmark.circle" : "gearshape"
            ) {
                Task {
                    _ = await shellConfig.configure(port: appState.port)
                }
            }
        }
        .accessibilityIdentifier("settings.general.shellConfigure")
    }

    @ViewBuilder
    private var claudeRow: some View {
        GeneralFormRow {
            HStack(spacing: DesignToken.Spacing.md) {
                iconBox("arrow.triangle.swap")
                VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                    Text(L10n.ClaudeCode.takeoverToggle)
                        .font(DesignToken.Font.body())
                        .foregroundColor(DesignToken.Colors.textPrimary)
                    Text(L10n.ClaudeCode.takeoverDescription)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    claudeURLStatus
                    if let error = claudeCode.lastError {
                        HStack(spacing: DesignToken.Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(DesignToken.Font.system(size: DesignToken.Layout.smallIconSize, weight: .medium))
                            Text(error)
                                .font(DesignToken.Font.caption())
                                .foregroundColor(DesignToken.Colors.statusWarning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityIdentifier("settings.general.claudeCodeError")
                    }
                }
            }
        } trailing: {
            Toggle("", isOn: Binding(
                get: { claudeCode.isActive },
                set: { claudeCode.toggleTakeover(enable: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .accessibilityIdentifier("settings.general.claudeCodeToggle")
    }

    private var claudeURLStatus: some View {
        HStack(spacing: DesignToken.Spacing.xs) {
            Circle()
                .fill(claudeCode.isActive ? DesignToken.Colors.statusOnline : DesignToken.Colors.textTertiary)
                .frame(width: 7, height: 7)
            Text(urlStatusText)
                .font(DesignToken.Font.monoMicro())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityIdentifier("settings.general.claudeCodeStatus")
    }

    private var urlStatusText: String {
        if !claudeCode.configExists {
            return L10n.ClaudeCode.configNotFound
        }
        if claudeCode.currentURL.isEmpty {
            return L10n.ClaudeCode.currentUrlNotSet
        }
        return L10n.ClaudeCode.currentUrl(claudeCode.currentURL)
    }

    private var shellStatusText: String {
        let status = shellConfig.isConfigured
            ? L10n.Settings.generalShellConfiguredLabel
            : L10n.Settings.generalNotConfigured
        return "\(status) · \(L10n.Settings.generalShellSupportHint)"
    }

    // MARK: - Footer

    private var footerHint: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.sm) {
            Image(systemName: "checkmark.shield")
                .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                .foregroundColor(DesignToken.Colors.textSecondary)
            Text(L10n.Settings.generalPrivacyHint)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignToken.Spacing.xs)
    }
}

// MARK: - General Form Components

private struct GeneralFormCard<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(DesignToken.Colors.bgPrimary)
        .cornerRadius(DesignToken.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.cardCornerRadius)
                .stroke(DesignToken.Colors.border, lineWidth: 1)
        )
    }
}

private struct GeneralFormRow<Leading: View, Trailing: View>: View {
    @ViewBuilder private let leading: Leading
    @ViewBuilder private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.md) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, DesignToken.Spacing.md)
        .padding(.vertical, DesignToken.Spacing.sm)
    }
}

private struct ServiceStatusBadge: View {
    let isRunning: Bool

    var body: some View {
        let color = isRunning ? DesignToken.Colors.statusOnline : DesignToken.Colors.statusOffline
        HStack(spacing: DesignToken.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: DesignToken.Layout.statusDotSize, height: DesignToken.Layout.statusDotSize)
            Text(isRunning ? L10n.Settings.generalServiceRunning : L10n.Settings.generalServiceStopped)
                .font(DesignToken.Font.caption())
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(.vertical, DesignToken.Layout.badgePaddingV)
        .padding(.horizontal, DesignToken.Layout.badgePaddingH)
        .background(color.opacity(0.12))
        .cornerRadius(DesignToken.Layout.badgeCornerRadius)
    }
}

private struct PrimaryActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                Text(title)
                    .font(DesignToken.Font.system(size: 12, weight: .semibold))
            }
            .foregroundColor(DesignToken.Colors.buttonLabel)
            .padding(.horizontal, DesignToken.Spacing.md)
            .frame(minHeight: DesignToken.Layout.buttonMinHeight)
            .background(isHovered ? DesignToken.Colors.accentHover : DesignToken.Colors.accent)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
    }
}

private struct SecondaryActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                Text(title)
                    .font(DesignToken.Font.system(size: 12, weight: .medium))
            }
            .foregroundColor(DesignToken.Colors.accent)
            .padding(.horizontal, DesignToken.Spacing.md)
            .frame(minHeight: DesignToken.Layout.buttonMinHeight)
            .background(isHovered ? DesignToken.Colors.accent.opacity(0.08) : DesignToken.Colors.bgPrimary)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                    .stroke(DesignToken.Colors.accent, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
    }
}

private struct PortField: View {
    @Binding var value: Int
    let placeholder: String

    var body: some View {
        TextField(placeholder, value: $value, formatter: Self.formatter)
            .font(DesignToken.Font.mono())
            .foregroundColor(DesignToken.Colors.textPrimary)
            .textFieldStyle(.plain)
            .frame(width: 160, height: DesignToken.Layout.buttonMinHeight)
            .padding(.horizontal, DesignToken.Spacing.sm)
            .background(DesignToken.Colors.bgPrimary)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                    .stroke(DesignToken.Colors.border, lineWidth: 1)
            )
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 65535
        return formatter
    }()
}

private struct GeneralFormFullRow<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignToken.Spacing.md)
            .padding(.vertical, DesignToken.Spacing.sm)
    }
}

private struct InlineDoubleField: View {
    @Binding var value: Double
    let placeholder: String

    var body: some View {
        TextField(placeholder, value: $value, formatter: Self.formatter)
            .font(DesignToken.Font.mono())
            .foregroundColor(DesignToken.Colors.textPrimary)
            .textFieldStyle(.plain)
            .frame(width: 120, height: DesignToken.Layout.buttonMinHeight)
            .padding(.horizontal, DesignToken.Spacing.sm)
            .background(DesignToken.Colors.bgPrimary)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                    .stroke(DesignToken.Colors.border, lineWidth: 1)
            )
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximum = 1000
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
}

// MARK: - Channels Tab

private enum ChannelListFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            L10n.Settings.channelsFilterAll
        case .enabled:
            L10n.Settings.channelsFilterEnabled
        case .disabled:
            L10n.Settings.channelsFilterDisabled
        }
    }
}

struct ChannelsTab: View {
    @ObservedObject private var channelStore: ChannelStore
    @ObservedObject private var channelManager: ChannelManager
    private let channelExportService: ChannelExportService
    @State private var showingAddChannel = false
    @State private var showingConfigImporter = false
    @State private var isTestingAll = false
    @State private var channelSearchText = ""
    @State private var channelFilter: ChannelListFilter = .all
    @State private var showingSortBySpeedConfirmation = false

    @MainActor
    init(services: AppServices? = nil) {
        let services = services ?? .shared
        _channelStore = ObservedObject(wrappedValue: services.channelStore)
        _channelManager = ObservedObject(wrappedValue: services.channelManager)
        channelExportService = services.channelExportService
    }

    var body: some View {
        VStack(spacing: DesignToken.Spacing.md) {
            channelsHeaderActions
            channelListToolbar

            channelList

            channelsFooter
        }
        .padding(DesignToken.Layout.cardPadding)
        .alert(L10n.Settings.channelsSortBySpeedConfirmTitle, isPresented: $showingSortBySpeedConfirmation) {
            Button(L10n.AddChannel.cancel, role: .cancel) {}
            Button(L10n.Settings.channelsSortBySpeedConfirm) {
                channelStore.sortChannelsByLatency()
            }
        } message: {
            Text(L10n.Settings.channelsSortBySpeedConfirmMessage)
        }
        .sheet(isPresented: $showingAddChannel) {
            AddChannelView()
        }
        .sheet(isPresented: $showingConfigImporter) {
            ConfigImporterView()
        }
    }

    private var channelsHeaderActions: some View {
        HStack(alignment: .center, spacing: DesignToken.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                Text(L10n.Settings.channels)
                    .font(DesignToken.Font.h2())
                    .foregroundColor(DesignToken.Colors.textPrimary)

                Text(L10n.Settings.channelsSubtitle)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignToken.Spacing.md)

            speedTestSplitButton

            IconButton(
                icon: "square.and.arrow.down.on.square",
                tooltip: L10n.ConfigImporter.title
            ) {
                showingConfigImporter = true
            }
            .accessibilityIdentifier("settings.channels.importConfig")

            primaryToolbarButton(
                title: L10n.Settings.channelsAdd,
                icon: "plus"
            ) {
                showingAddChannel = true
            }
            .frame(width: 112)
            .accessibilityIdentifier("settings.channels.add")
        }
    }

    private var speedTestSplitButton: some View {
        HStack(spacing: 0) {
            Button {
                runSpeedTests()
            } label: {
                HStack(spacing: DesignToken.Spacing.xs) {
                    Image(systemName: isTestingAll ? "ellipsis.circle.fill" : "bolt.fill")
                        .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                    Text(isTestingAll ? L10n.Settings.channelsTesting : L10n.Settings.channelsTestAll)
                        .font(DesignToken.Font.system(size: 12, weight: .medium))
                }
                .frame(width: 98, height: DesignToken.Layout.buttonMinHeight)
            }
            .buttonStyle(.plain)
            .disabled(isTestingAll || channelStore.enabledChannels.isEmpty)
            .accessibilityIdentifier("settings.channels.testAll")

            Divider()
                .frame(height: DesignToken.Layout.buttonMinHeight - 8)

            Button {
                showingSortBySpeedConfirmation = true
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                    .frame(width: DesignToken.Layout.buttonMinHeight, height: DesignToken.Layout.buttonMinHeight)
            }
            .buttonStyle(.plain)
            .disabled(channelStore.channels.filter { $0.lastLatencyMs > 0 }.count < 2)
            .help(L10n.Settings.channelsSortBySpeed)
            .accessibilityLabel(L10n.Settings.channelsSortBySpeed)
            .accessibilityIdentifier("settings.channels.sortBySpeed")
        }
        .background(DesignToken.Colors.bgSecondary)
        .foregroundColor(DesignToken.Colors.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                .stroke(DesignToken.Colors.border, lineWidth: 1)
        )
    }

    private var channelListToolbar: some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            HStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(DesignToken.Font.system(size: 12, weight: .medium))
                    .foregroundColor(DesignToken.Colors.textTertiary)
                TextField(L10n.Settings.channelsSearchPlaceholder, text: $channelSearchText)
                    .textFieldStyle(.plain)
                    .font(DesignToken.Font.caption())
            }
            .padding(.horizontal, DesignToken.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DesignToken.Layout.buttonMinHeight)
            .background(DesignToken.Colors.bgSecondary)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                    .stroke(DesignToken.Colors.border, lineWidth: 1)
            )
            .accessibilityIdentifier("settings.channels.searchField")

            Text(channelCountText)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .lineLimit(1)
                .frame(minWidth: 58, alignment: .trailing)
                .accessibilityIdentifier("settings.channels.count")

            Picker("", selection: $channelFilter) {
                ForEach(ChannelListFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 156)
            .accessibilityIdentifier("settings.channels.filter")
        }
    }

    @ViewBuilder
    private var channelList: some View {
        if channelStore.channels.isEmpty {
            EmptyChannelView()
        } else if filteredChannels.isEmpty {
            noMatchingChannelsView
        } else {
            List {
                if isFilteringChannels {
                    ForEach(filteredChannels) { channel in
                        ChannelRowView(channelID: channel.id, index: channelStore.channels.firstIndex(of: channel) ?? 0)
                    }
                } else {
                    ForEach(channelStore.channels) { channel in
                        ChannelRowView(channelID: channel.id, index: channelStore.channels.firstIndex(of: channel) ?? 0)
                    }
                    .onMove(perform: channelStore.moveChannel)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .accessibilityIdentifier("settings.channels.list")
        }
    }

    private var noMatchingChannelsView: some View {
        VStack(spacing: DesignToken.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DesignToken.Font.system(size: 28, weight: .regular))
                .foregroundColor(DesignToken.Colors.textTertiary)
            Text(L10n.Settings.channelsNoMatchesTitle)
                .font(DesignToken.Font.h3())
                .foregroundColor(DesignToken.Colors.textPrimary)
            Text(L10n.Settings.channelsNoMatchesSubtitle)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("settings.channels.noMatches")
    }

    private var channelsFooter: some View {
        HStack(spacing: DesignToken.Spacing.xs) {
            IconButton(
                icon: "square.and.arrow.up",
                tooltip: L10n.ChannelExport.exportChannels,
                isDisabled: channelStore.channels.isEmpty
            ) {
                channelExportService.showExportOptions(channels: channelStore.channels)
            }
            .help(L10n.ChannelExport.exportChannels)
            .accessibilityIdentifier("settings.channels.exportChannels")

            IconButton(
                icon: "square.and.arrow.down",
                tooltip: L10n.ChannelExport.importChannels
            ) {
                channelExportService.importChannelsWithPanel()
            }
            .help(L10n.ChannelExport.importChannels)
            .accessibilityIdentifier("settings.channels.importChannels")

            Spacer()

            Text(isFilteringChannels ? L10n.Settings.channelsReorderFilteredHint : L10n.Settings.channelsReorderHint)
                .font(DesignToken.Font.micro())
                .foregroundColor(DesignToken.Colors.textTertiary)
        }
        .padding(.bottom, DesignToken.Spacing.xs)
    }

    private func runSpeedTests() {
        Task {
            isTestingAll = true
            await channelManager.speedTestAllChannels()
            isTestingAll = false
        }
    }

    private func primaryToolbarButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                Text(title)
                    .font(DesignToken.Font.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: DesignToken.Layout.buttonMinHeight)
            .foregroundColor(DesignToken.Colors.buttonLabel)
            .background(DesignToken.Colors.accent)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
        }
        .buttonStyle(.plain)
    }

    private var filteredChannels: [Channel] {
        channelStore.channels.filter { channel in
            let matchesFilter: Bool
            switch channelFilter {
            case .all:
                matchesFilter = true
            case .enabled:
                matchesFilter = channel.isEnabled
            case .disabled:
                matchesFilter = !channel.isEnabled
            }

            guard matchesFilter else { return false }

            let query = channelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }

            let searchableText = ([channel.name, channel.displayEndpointSummary] + channel.models.map(\.identifier))
                .joined(separator: " ")
                .lowercased()
            return searchableText.contains(query)
        }
    }

    private var isFilteringChannels: Bool {
        !channelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || channelFilter != .all
    }

    private var channelCountText: String {
        if isFilteringChannels {
            return L10n.Settings.channelsFilteredCount(filteredChannels.count, channelStore.channels.count)
        }
        return L10n.Settings.channelsCount(channelStore.channels.count)
    }

}

// MARK: - Advanced Tab

struct AdvancedTab: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var channelStore: ChannelStore
    @ObservedObject private var smartRouter: SmartRouter
    private let circuitBreaker: CircuitBreaker
    @State private var circuitStates: [String: CircuitState] = [:]
    @State private var refreshTimer: Timer?

    @MainActor
    init(services: AppServices? = nil) {
        let services = services ?? .shared
        _appState = ObservedObject(wrappedValue: services.appState)
        _channelStore = ObservedObject(wrappedValue: services.channelStore)
        _smartRouter = ObservedObject(wrappedValue: services.smartRouter)
        circuitBreaker = services.circuitBreaker
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
                pageHeader

                sectionTitle(L10n.Settings.advancedFailover)
                GeneralFormCard {
                    GeneralFormRow {
                        Text(L10n.Settings.advancedFailover)
                            .font(DesignToken.Font.body())
                            .foregroundColor(DesignToken.Colors.textPrimary)
                    } trailing: {
                        Toggle("", isOn: $appState.autoFailover)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .accessibilityIdentifier("settings.advanced.autoFailoverToggle")
                }

                sectionTitle(L10n.Settings.advancedSmartFallback)
                GeneralFormCard {
                    GeneralFormRow {
                        Text(L10n.Settings.advancedSmartFallback)
                            .font(DesignToken.Font.body())
                            .foregroundColor(DesignToken.Colors.textPrimary)
                    } trailing: {
                        Toggle("", isOn: Binding(
                            get: { smartRouter.smartFallbackEnabled },
                            set: { smartRouter.smartFallbackEnabled = $0; smartRouter.saveSettings() }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .accessibilityIdentifier("settings.advanced.smartFallback")

                    Divider()

                    GeneralFormFullRow {
                        Text(L10n.Settings.advancedSmartFallbackWarning)
                            .font(DesignToken.Font.caption())
                            .foregroundColor(DesignToken.Colors.statusWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    GeneralFormRow {
                        VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                            Text(L10n.Settings.advancedMaxFallbackCost)
                                .font(DesignToken.Font.body())
                                .foregroundColor(DesignToken.Colors.textPrimary)
                            Text(L10n.Settings.advancedMaxFallbackCostHint)
                                .font(DesignToken.Font.caption())
                                .foregroundColor(DesignToken.Colors.textSecondary)
                        }
                    } trailing: {
                        InlineDoubleField(
                            value: Binding(
                                get: { smartRouter.maxFallbackCost },
                                set: { smartRouter.maxFallbackCost = $0; smartRouter.saveSettings() }
                            ),
                            placeholder: "$2.00"
                        )
                    }
                    .accessibilityIdentifier("settings.advanced.maxFallbackCost")
                }

                circuitBreakerHeader
                GeneralFormCard {
                    circuitBreakerCardContent
                }

                sectionTitle(L10n.Settings.advancedCooldown)
                GeneralFormCard {
                    cooldownRow(title: L10n.Settings.advancedCooldown429, value: "30m")
                        .accessibilityIdentifier("settings.advanced.cooldown.429")
                    Divider()
                    cooldownRow(title: L10n.Settings.advancedCooldown5xx, value: "10m")
                        .accessibilityIdentifier("settings.advanced.cooldown.5xx")
                    Divider()
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

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
            Text(L10n.Settings.advanced)
                .font(DesignToken.Font.h1())
                .foregroundColor(DesignToken.Colors.textPrimary)
            Text(L10n.Settings.advancedSubtitle)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignToken.Font.h2())
            .foregroundColor(DesignToken.Colors.textPrimary)
    }

    // MARK: - Circuit Breaker

    private var circuitBreakerHeader: some View {
        HStack {
            Text(L10n.CircuitBreaker.title)
                .font(DesignToken.Font.h2())
                .foregroundColor(DesignToken.Colors.textPrimary)
            Spacer()
            Button {
                resetAllCircuits()
            } label: {
                Text(L10n.CircuitBreaker.resetAll)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.advanced.resetCircuits")
        }
    }

    @ViewBuilder
    private var circuitBreakerCardContent: some View {
        GeneralFormFullRow {
            Text(L10n.CircuitBreaker.description)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if circuitStates.isEmpty {
            Divider()
            GeneralFormFullRow {
                HStack(spacing: DesignToken.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                        .foregroundColor(DesignToken.Colors.statusOnline)
                    Text(L10n.CircuitBreaker.stateClosed)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                }
            }
        } else {
            ForEach(Array(circuitStates.sorted(by: { $0.key < $1.key }).enumerated()), id: \.element.key) { _, entry in
                Divider()
                circuitStateRow(channelID: entry.key, state: entry.value)
            }
        }
    }

    private func circuitStateRow(channelID: String, state: CircuitState) -> some View {
        GeneralFormRow {
            HStack(spacing: DesignToken.Spacing.sm) {
                Circle()
                    .fill(stateColor(for: state))
                    .frame(width: DesignToken.Layout.statusDotSize, height: DesignToken.Layout.statusDotSize)
                Text(channelStore.channels.first(where: { $0.id == channelID })?.name ?? channelID)
                    .font(DesignToken.Font.body())
                    .foregroundColor(DesignToken.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } trailing: {
            HStack(spacing: DesignToken.Spacing.xs) {
                Text(stateLabel(for: state))
                    .font(DesignToken.Font.system(size: 11, weight: .medium))
                    .foregroundColor(stateColor(for: state))
                    .padding(.horizontal, DesignToken.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(stateColor(for: state).opacity(0.1))
                    .cornerRadius(4)
                if case .open(let until) = state {
                    let remaining = max(0, until.timeIntervalSince(Date()))
                    if remaining > 0 {
                        Text(formatRemainingTime(remaining))
                            .font(DesignToken.Font.monoMicro())
                            .foregroundColor(DesignToken.Colors.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Cooldown

    private func cooldownRow(title: String, value: String) -> some View {
        GeneralFormRow {
            Text(title)
                .font(DesignToken.Font.body())
                .foregroundColor(DesignToken.Colors.textPrimary)
        } trailing: {
            Text(value)
                .font(DesignToken.Font.mono())
                .foregroundColor(DesignToken.Colors.textSecondary)
        }
    }

    // MARK: - Helpers

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
        circuitStates = circuitBreaker.allStates()
    }

    private func resetAllCircuits() {
        for channel in channelStore.channels {
            circuitBreaker.reset(channelID: channel.id)
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
    @ObservedObject private var usage: UsageTracker
    @ObservedObject private var channelStore: ChannelStore

    @MainActor
    init(services: AppServices? = nil) {
        let services = services ?? .shared
        _usage = ObservedObject(wrappedValue: services.usageTracker)
        _channelStore = ObservedObject(wrappedValue: services.channelStore)
    }

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
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            Text(L10n.About.appName)
                .font(DesignToken.Font.h1())

            Text(L10n.Settings.aboutVersion(appVersion))
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
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
