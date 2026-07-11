import SwiftUI

// MARK: - MenuView

struct MenuView: View {
    @ObservedObject private var proxy: ProxyServer
    @ObservedObject private var appState: AppState
    @ObservedObject private var channelStore: ChannelStore
    @ObservedObject private var usage: UsageTracker
    @ObservedObject private var channelManager: ChannelManager
    @ObservedObject private var modelSwitcher: ModelSwitcher

    @State private var now = Date()
    @State private var isTestingKey = false

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    @MainActor
    init(services: AppServices? = nil) {
        let services = services ?? .shared
        _proxy = ObservedObject(wrappedValue: services.proxyServer)
        _appState = ObservedObject(wrappedValue: services.appState)
        _channelStore = ObservedObject(wrappedValue: services.channelStore)
        _usage = ObservedObject(wrappedValue: services.usageTracker)
        _channelManager = ObservedObject(wrappedValue: services.channelManager)
        _modelSwitcher = ObservedObject(wrappedValue: services.modelSwitcher)
    }

    var body: some View {
        VStack(spacing: DesignToken.Spacing.md) {
            proxyStatusPanel
            routingPanel
            recentRequestsPanel
            quickActions
            footerButtons
        }
        .padding(DesignToken.Spacing.md)
        .frame(width: DesignToken.Layout.menuWidth)
        .background(DesignToken.Colors.bgPrimary)
        .onReceive(timer) { _ in
            now = Date()
        }
    }

    // MARK: - Status

    private var proxyStatusPanel: some View {
        VStack(spacing: DesignToken.Spacing.sm) {
            HStack(spacing: DesignToken.Spacing.sm) {
                StatusIndicatorView(isRunning: proxy.isRunning, isCooldown: false)
                    .accessibilityIdentifier(proxy.isRunning ? "menu.status.running" : "menu.status.stopped")

                VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                    Text(proxy.isRunning ? L10n.App.statusRunning : L10n.App.statusStopped)
                        .font(DesignToken.Font.system(size: 18, weight: .bold))
                        .foregroundColor(DesignToken.Colors.textPrimary)

                    Text(proxyStatusSubtitle)
                        .font(DesignToken.Font.microSmall())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: DesignToken.Spacing.xs)

                Text(verbatim: ":\(displayPort)")
                    .font(DesignToken.Font.monoMicro())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .padding(.horizontal, DesignToken.Spacing.sm)
                    .frame(height: 26)
                    .background(DesignToken.Colors.bgSecondary)
                    .cornerRadius(DesignToken.Layout.buttonCornerRadius)
                    .accessibilityIdentifier("menu.port.label")

                Button {
                    toggleProxy()
                } label: {
                    HStack(spacing: DesignToken.Spacing.xs) {
                        Image(systemName: proxy.isRunning ? "pause.fill" : "play.fill")
                            .font(DesignToken.Font.system(size: 10, weight: .semibold))

                        Text(proxy.isRunning ? L10n.Menu.proxyPause : L10n.Menu.proxyStart)
                            .font(DesignToken.Font.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(DesignToken.Colors.textPrimary)
                    .padding(.horizontal, DesignToken.Spacing.sm)
                    .frame(height: 28)
                    .background(DesignToken.Colors.bgSecondary)
                    .cornerRadius(DesignToken.Layout.buttonCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                            .stroke(DesignToken.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu.proxy.toggle")
            }

            HStack(spacing: DesignToken.Spacing.sm) {
                statTile(
                    value: compactCount(usage.todayStats.totalRequests),
                    label: L10n.Menu.statsRequestsLabel,
                    accessibilityID: "menu.stats.requests"
                )

                statTile(
                    value: compactCount(usage.todayStats.totalTokens),
                    label: L10n.Menu.statsTokensLabel,
                    accessibilityID: "menu.stats.tokens"
                )
            }
            .accessibilityIdentifier("menu.statsLabel")
        }
    }

    private var proxyStatusSubtitle: String {
        if !proxy.isRunning, let lastError = proxy.lastError, !lastError.isEmpty {
            return lastError
        }

        return proxy.isRunning ? L10n.Menu.proxyRunningSubtitle : L10n.Menu.proxyStoppedSubtitle
    }

    private var displayPort: Int {
        proxy.isRunning ? proxy.port : appState.port
    }

    private func statTile(value: String, label: String, accessibilityID: String) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
            Text(value)
                .font(DesignToken.Font.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(DesignToken.Colors.textPrimary)
                .lineLimit(1)

            Text(label)
                .font(DesignToken.Font.microSmall())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignToken.Spacing.sm)
        .frame(height: 48)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.cardCornerRadius)
                .stroke(DesignToken.Colors.border, lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityID)
    }

    // MARK: - Routing

    private var routingPanel: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.sm) {
            sectionHeader(title: L10n.Menu.routingTitle, trailing: L10n.Menu.routingProtocols)
            modelSelector

            Divider()

            HStack(spacing: DesignToken.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                    Text(appState.autoFailover ? L10n.Menu.failoverAuto : L10n.Menu.failoverManual)
                        .font(DesignToken.Font.h3())
                        .foregroundColor(DesignToken.Colors.textPrimary)

                    Text(L10n.Menu.failoverSubtitle)
                        .font(DesignToken.Font.microSmall())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { appState.autoFailover },
                    set: { _ in appState.toggleAutoFailover() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("menu.failover.toggle")
            }
        }
        .padding(DesignToken.Spacing.md)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.cardCornerRadius)
                .stroke(DesignToken.Colors.border, lineWidth: 1)
        )
    }

    private var modelSelector: some View {
        VStack(spacing: .zero) {
            Menu {
                Button {
                    modelSwitcher.resetToDefault()
                } label: {
                    Label(
                        L10n.Model.defaultPassthrough,
                        systemImage: !modelSwitcher.hasOverride ? "checkmark" : "circle"
                    )
                }

                if !modelSwitcher.compatibleModels.isEmpty {
                    Divider()

                    ForEach(modelSwitcher.compatibleModels, id: \.identifier) { model in
                        Button {
                            modelSwitcher.selectModel(model.identifier)
                        } label: {
                            Label(
                                model.displayName,
                                systemImage: modelSwitcher.selectedModelID == model.identifier ? "checkmark" : "circle"
                            )
                        }
                    }
                }
            } label: {
                HStack(spacing: DesignToken.Spacing.sm) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(DesignToken.Font.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignToken.Colors.accent)
                        .frame(width: 26, height: 26)
                        .background(DesignToken.Colors.accent.opacity(0.12))
                        .cornerRadius(DesignToken.Layout.buttonCornerRadius)

                    VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                        Text(modelSwitcher.displayName)
                            .font(DesignToken.Font.h3())
                            .foregroundColor(modelSwitcher.hasOverride ? DesignToken.Colors.accent : DesignToken.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(modelSwitcher.hasOverride ? L10n.Menu.routingOverrideSubtitle : L10n.Menu.routingDefaultSubtitle)
                            .font(DesignToken.Font.microSmall())
                            .foregroundColor(DesignToken.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(DesignToken.Font.system(size: 10, weight: .semibold))
                        .foregroundColor(DesignToken.Colors.textTertiary)
                }
                .padding(.horizontal, DesignToken.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(DesignToken.Colors.hoverFill)
                .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            }
            .menuStyle(.borderlessButton)
            .accessibilityIdentifier("menu.model.submenu")
        }
        .accessibilityIdentifier("menu.model.selector")
    }

    // MARK: - Requests

    private var recentRequestsPanel: some View {
        let recent: [UsageRecord] = {
            let latestPerModel = Dictionary(grouping: usage.records, by: \.model)
                .compactMap { (_, recs) -> UsageRecord? in
                    recs.max(by: { $0.timestamp < $1.timestamp })
                }
            return latestPerModel.sorted { $0.timestamp > $1.timestamp }.prefix(5).map { $0 }
        }()

        return VStack(alignment: .leading, spacing: DesignToken.Spacing.sm) {
            sectionHeader(title: L10n.Menu.requestsRecent, trailing: L10n.Menu.requestsCount(recent.count))

            if recent.isEmpty {
                Text(L10n.Menu.requestsNone)
                    .font(DesignToken.Font.micro())
                    .foregroundColor(DesignToken.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignToken.Spacing.xs)
            } else {
                VStack(spacing: DesignToken.Spacing.xs) {
                    ForEach(recent, id: \.model) { record in
                        recentRequestRow(record)
                    }
                }
            }
        }
        .padding(DesignToken.Spacing.md)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.cardCornerRadius)
                .stroke(DesignToken.Colors.border, lineWidth: 1)
        )
        .accessibilityIdentifier("menu.recentRequestsList")
    }

    private func recentRequestRow(_ record: UsageRecord) -> some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            Circle()
                .fill(record.isError ? DesignToken.Colors.statusOffline : DesignToken.Colors.statusOnline)
                .frame(width: 9, height: 9)

            Text(record.model)
                .font(DesignToken.Font.system(size: 12, weight: .semibold))
                .foregroundColor(DesignToken.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: DesignToken.Spacing.sm)

            Text(timeAgo(from: record.timestamp))
                .font(DesignToken.Font.micro())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(minHeight: 24)
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return L10n.Menu.timeSeconds(seconds)
        } else if seconds < 3600 {
            return L10n.Menu.timeMinutes(seconds / 60)
        } else if seconds < 86400 {
            return L10n.Menu.timeHours(seconds / 3600)
        } else {
            let days = seconds / 86400
            let hours = (seconds % 86400) / 3600
            return L10n.Menu.timeDaysHours(days, hours)
        }
    }

    // MARK: - Actions

    private var quickActions: some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            menuActionButton(
                title: L10n.Menu.copyConfig,
                icon: "square.and.arrow.up",
                isPrimary: true
            ) {
                copyEnvironmentConfig()
            }
            .accessibilityIdentifier("menu.copyEnvButton")

            menuActionButton(
                title: isTestingKey ? L10n.Status.testing : L10n.Menu.testChannels,
                icon: isTestingKey ? "ellipsis.circle.fill" : "checkmark.circle",
                isDisabled: channelStore.enabledChannels.isEmpty || isTestingKey
            ) {
                testAllChannels()
            }
            .accessibilityIdentifier("menu.testKeyButton")
        }
    }

    private var footerButtons: some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            settingsButton

            menuActionButton(title: L10n.Menu.quit, icon: "power", isDestructive: true) {
                NSApp.terminate(nil)
            }
            .accessibilityIdentifier("menu.quitButton")
        }
        .padding(.top, DesignToken.Spacing.xs)
        .overlay(alignment: .top) {
            Divider()
                .offset(y: -DesignToken.Spacing.xs)
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                actionLabel(title: L10n.Menu.settings, icon: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.settingsButton")
            .simultaneousGesture(TapGesture().onEnded {
                prepareSettingsWindowPresentation()
            })
        } else {
            menuActionButton(title: L10n.Menu.settings, icon: "gearshape") {
                NotificationCenter.default.post(name: .closeMenuBarPopover, object: nil)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                bringSettingsWindowToFrontSoon()
            }
            .accessibilityIdentifier("menu.settingsButton")
        }
    }

    private func menuActionButton(
        title: String,
        icon: String,
        isPrimary: Bool = false,
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(title: title, icon: icon, isPrimary: isPrimary, isDestructive: isDestructive)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }

    private func actionLabel(
        title: String,
        icon: String,
        isPrimary: Bool = false,
        isDestructive: Bool = false
    ) -> some View {
        HStack(spacing: DesignToken.Spacing.xs) {
            Image(systemName: icon)
                .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))

            Text(title)
                .font(DesignToken.Font.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .foregroundColor(actionForeground(isPrimary: isPrimary, isDestructive: isDestructive))
        .background(isPrimary ? DesignToken.Colors.accent : DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.buttonCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                .stroke(isPrimary ? DesignToken.Colors.accent : DesignToken.Colors.border, lineWidth: 1)
        )
    }

    private func actionForeground(isPrimary: Bool, isDestructive: Bool) -> Color {
        if isPrimary {
            return DesignToken.Colors.buttonLabel
        }
        if isDestructive {
            return DesignToken.Colors.destructive
        }
        return DesignToken.Colors.textPrimary
    }

    private func sectionHeader(title: String, trailing: String) -> some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            Text(title)
                .font(DesignToken.Font.system(size: 11, weight: .bold))
                .foregroundColor(DesignToken.Colors.textSecondary)
                .textCase(.uppercase)

            Spacer()

            Text(trailing)
                .font(DesignToken.Font.microSmall())
                .foregroundColor(DesignToken.Colors.textTertiary)
                .lineLimit(1)
        }
    }

    private func toggleProxy() {
        if proxy.isRunning {
            proxy.stop()
        } else {
            proxy.start(port: appState.port)
        }

        NotificationCenter.default.post(name: .proxyRunningStateChanged, object: nil)
    }

    private func copyEnvironmentConfig() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "export ANTHROPIC_BASE_URL=http://localhost:\(displayPort)/v1\nexport OPENAI_BASE_URL=http://localhost:\(displayPort)/v1",
            forType: .string
        )
    }

    private func testAllChannels() {
        Task {
            isTestingKey = true
            for channel in channelStore.enabledChannels {
                _ = await channelManager.testConnection(channel: channel)
            }
            isTestingKey = false
        }
    }

    private func compactCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func prepareSettingsWindowPresentation() {
        NotificationCenter.default.post(name: .closeMenuBarPopover, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        bringSettingsWindowToFrontSoon()
    }

    private func bringSettingsWindowToFrontSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            bringSettingsWindowToFront()
        }
    }

    private func bringSettingsWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)

        let titledWindows = NSApp.windows.filter { window in
            window.styleMask.contains(.titled) && !window.isMiniaturized
        }
        let settingsWindow = titledWindows.first { window in
            window.title.localizedCaseInsensitiveContains(L10n.Menu.settings)
                || window.title.localizedCaseInsensitiveContains(L10n.Settings.title)
        } ?? titledWindows.first

        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }
}

// MARK: - Preview

#Preview {
    MenuView()
}
