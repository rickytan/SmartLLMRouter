import SwiftUI

// MARK: - MenuView

struct MenuView: View {
    private struct RecentModelSummary: Identifiable {
        let latest: UsageRecord
        let inputTokens: Int
        let outputTokens: Int

        var id: String { latest.model }
    }

    @ObservedObject private var proxy: ProxyServer
    @ObservedObject private var appState: AppState
    @ObservedObject private var usage: UsageTracker
    @ObservedObject private var modelSwitcher: ModelSwitcher

    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    @MainActor
    init(services: AppServices? = nil) {
        let services = services ?? .shared
        _proxy = ObservedObject(wrappedValue: services.proxyServer)
        _appState = ObservedObject(wrappedValue: services.appState)
        _usage = ObservedObject(wrappedValue: services.usageTracker)
        _modelSwitcher = ObservedObject(wrappedValue: services.modelSwitcher)
    }

    var body: some View {
        VStack(spacing: DesignToken.Spacing.sm) {
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
        VStack(spacing: DesignToken.Spacing.xs) {
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

            HStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: "chart.bar.fill")
                    .font(DesignToken.Font.system(size: 10, weight: .medium))
                    .foregroundColor(DesignToken.Colors.textTertiary)

                Text(L10n.Menu.requestsCount(usage.todayStats.totalRequests))
                    .font(DesignToken.Font.micro())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .lineLimit(1)

                tokenMetric(icon: "arrow.down", value: usage.todayStats.totalInputTokens)
                tokenMetric(icon: "arrow.up", value: usage.todayStats.totalOutputTokens)

                Spacer()

                if usage.todayStats.totalRequests > 0 {
                    Text(L10n.Menu.statsErrorRate(Int(usage.todayStats.errorRate * 100)))
                        .font(DesignToken.Font.monoMicro())
                        .foregroundColor(usage.todayStats.errorRate > 0
                            ? DesignToken.Colors.statusOffline
                            : DesignToken.Colors.statusOnline)
                }
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

    // MARK: - Routing

    private var routingPanel: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            sectionHeader(title: L10n.Menu.routingTitle, trailing: L10n.Menu.routingProtocols)
            modelSelector
        }
        .padding(DesignToken.Spacing.sm)
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
                .frame(maxWidth: .infinity, minHeight: 36)
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
        let recent = recentModelSummaries

        return VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            sectionHeader(title: L10n.Menu.requestsRecent, trailing: L10n.Menu.requestsCount(recent.count))

            if recent.isEmpty {
                Text(L10n.Menu.requestsNone)
                    .font(DesignToken.Font.micro())
                    .foregroundColor(DesignToken.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignToken.Spacing.xs)
            } else {
                VStack(spacing: DesignToken.Spacing.xs) {
                    ForEach(recent) { summary in
                        recentRequestRow(summary)
                    }
                }
            }
        }
        .padding(DesignToken.Spacing.sm)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.cardCornerRadius)
                .stroke(DesignToken.Colors.border, lineWidth: 1)
        )
        .accessibilityIdentifier("menu.recentRequestsList")
    }

    private var recentModelSummaries: [RecentModelSummary] {
        Dictionary(grouping: usage.displayRecords, by: \.model)
            .compactMap { _, records -> RecentModelSummary? in
                guard let latest = records.max(by: { $0.timestamp < $1.timestamp }) else {
                    return nil
                }
                return RecentModelSummary(
                    latest: latest,
                    inputTokens: records.reduce(0) { $0 + $1.inputTokens },
                    outputTokens: records.reduce(0) { $0 + $1.outputTokens }
                )
            }
            .sorted { $0.latest.timestamp > $1.latest.timestamp }
            .prefix(5)
            .map { $0 }
    }

    private func recentRequestRow(_ summary: RecentModelSummary) -> some View {
        let record = summary.latest

        return HStack(alignment: .top, spacing: DesignToken.Spacing.sm) {
            Circle()
                .fill(record.isError ? DesignToken.Colors.statusOffline : DesignToken.Colors.statusOnline)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                HStack(spacing: DesignToken.Spacing.xs) {
                    Text(record.model)
                        .font(DesignToken.Font.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignToken.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    statusCodeBadge(record.statusCode)

                    Spacer(minLength: DesignToken.Spacing.xs)

                    Text(timeAgo(from: record.timestamp))
                        .font(DesignToken.Font.microSmall())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                        .lineLimit(1)
                }

                Text(requestMetadata(record, summary: summary))
                    .font(DesignToken.Font.monoMicro())
                    .foregroundColor(record.isError
                        ? DesignToken.Colors.statusOffline
                        : DesignToken.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minHeight: 30)
    }

    private func requestMetadata(_ record: UsageRecord, summary: RecentModelSummary) -> String {
        "\(record.channelName)  ↓\(compactCount(summary.inputTokens))  ↑\(compactCount(summary.outputTokens))  \(Int(record.latency))ms"
    }

    private func tokenMetric(icon: String, value: Int) -> some View {
        HStack(spacing: DesignToken.Spacing.xxs) {
            Image(systemName: icon)
                .font(DesignToken.Font.system(size: 8, weight: .semibold))
            Text(compactCount(value))
                .font(DesignToken.Font.monoMicro())
        }
        .foregroundColor(DesignToken.Colors.textSecondary)
        .lineLimit(1)
    }

    private func statusCodeBadge(_ statusCode: Int) -> some View {
        let color: Color = if (200..<300).contains(statusCode) {
            DesignToken.Colors.statusOnline
        } else if statusCode >= 400 {
            DesignToken.Colors.statusOffline
        } else {
            DesignToken.Colors.statusWarning
        }

        return Text(verbatim: "\(statusCode)")
            .font(DesignToken.Font.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, DesignToken.Spacing.xs)
            .padding(.vertical, DesignToken.Spacing.xxs)
            .background(color.opacity(0.12))
            .cornerRadius(DesignToken.Layout.badgeCornerRadius)
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
        menuActionButton(
            title: L10n.Menu.copyConfig,
            icon: "square.and.arrow.up",
            isPrimary: true
        ) {
            copyEnvironmentConfig()
        }
        .accessibilityIdentifier("menu.copyEnvButton")
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
        .frame(maxWidth: .infinity, minHeight: 32)
        .foregroundColor(actionForeground(isPrimary: isPrimary, isDestructive: isDestructive))
        .background(isPrimary ? DesignToken.Colors.accent : Color.clear)
        .cornerRadius(DesignToken.Layout.buttonCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                .stroke(isPrimary ? DesignToken.Colors.accent : Color.clear, lineWidth: 1)
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
