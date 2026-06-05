import SwiftUI

// MARK: - MenuView

struct MenuView: View {
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var usage = UsageTracker.shared
    @ObservedObject private var channelManager = ChannelManager.shared
    @ObservedObject private var modelSwitcher = ModelSwitcher.shared
    // Timer to refresh relative timestamps ("X minutes ago")
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: .zero) {
            // Status Header
            statusHeader
                .padding(.horizontal, DesignToken.Layout.menuPadding)
                .padding(.top, DesignToken.Layout.menuPadding)
                .padding(.bottom, DesignToken.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignToken.Layout.menuPadding)

            // Quick Stats
            quickStats
                .padding(.horizontal, DesignToken.Layout.menuPadding)
                .padding(.vertical, DesignToken.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignToken.Layout.menuPadding)

            // Auto-Failover Toggle
            failoverToggle
                .padding(.horizontal, DesignToken.Layout.menuPadding)
                .padding(.vertical, DesignToken.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignToken.Layout.menuPadding)

            // Model Selector
            modelSelector
                .padding(.horizontal, DesignToken.Layout.menuPadding)
                .padding(.vertical, DesignToken.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignToken.Layout.menuPadding)

            // Active Channel
            activeChannelInfo
                .padding(.horizontal, DesignToken.Layout.menuPadding)
                .padding(.vertical, DesignToken.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignToken.Layout.menuPadding)

            // Recent Requests
            recentRequests
                .padding(.horizontal, DesignToken.Layout.menuPadding)
                .padding(.vertical, DesignToken.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignToken.Layout.menuPadding)

            // Actions
            actionButtons
                .padding(.horizontal, DesignToken.Layout.menuPadding)
                .padding(.top, DesignToken.Spacing.sm)
                .padding(.bottom, DesignToken.Spacing.xs)

            Divider()
                .padding(.horizontal, DesignToken.Layout.menuPadding)

            // Settings & Quit
            footerButtons
                .padding(.horizontal, DesignToken.Layout.menuPadding)
                .padding(.vertical, DesignToken.Spacing.sm)
        }
        .frame(width: DesignToken.Layout.menuWidth)
        .onReceive(timer) { _ in
            now = Date()
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack {
            StatusIndicatorView(isRunning: proxy.isRunning, isCooldown: false)
                .accessibilityIdentifier("menu.status.running")

            Text(proxy.isRunning ? L10n.App.statusRunning : L10n.App.statusStopped)
                .font(DesignToken.Font.h3())

            Spacer()

            Text(":\(proxy.port)")
                .font(DesignToken.Font.monoMicro())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .accessibilityIdentifier("menu.port.label")
        }
    }

    // MARK: - Quick Stats

    private var quickStats: some View {
        Text(L10n.Menu.statsSummary(Int64(usage.todayStats.totalRequests), Int64(usage.todayStats.totalTokens)))
            .font(DesignToken.Font.caption())
            .foregroundColor(DesignToken.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier("menu.statsLabel")
    }

    // MARK: - Failover Toggle

    private var failoverToggle: some View {
        ToggleRow(
            appState.autoFailover ? L10n.Menu.failoverAuto : L10n.Menu.failoverManual,
            isOn: Binding(
                get: { appState.autoFailover },
                set: { _ in appState.toggleAutoFailover() }
            )
        )
        .accessibilityIdentifier("menu.failover.toggle")
    }

    // MARK: - Model Selector

    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            HStack {
                Text(L10n.Model.selectorLabel)
                    .font(DesignToken.Font.system(size: 11, weight: .medium))
                    .foregroundColor(DesignToken.Colors.textSecondary)

                Spacer()

                Image(systemName: modelSwitcher.hasOverride ? "checkmark.circle.fill" : "circle")
                    .font(DesignToken.Font.system(size: 10))
                    .foregroundColor(modelSwitcher.hasOverride ? DesignToken.Colors.accent : DesignToken.Colors.textTertiary)
            }

            if modelSwitcher.compatibleModels.isEmpty {
                Text(L10n.Model.noModelsAvailable)
                    .font(DesignToken.Font.micro())
                    .foregroundColor(DesignToken.Colors.textTertiary)
            } else {
                Menu {
                    Button {
                        modelSwitcher.resetToDefault()
                    } label: {
                        Label(
                            L10n.Model.defaultPassthrough,
                            systemImage: !modelSwitcher.hasOverride ? "checkmark" : "circle"
                        )
                    }

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
                } label: {
                    HStack(spacing: DesignToken.Spacing.xs) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                            .foregroundColor(DesignToken.Colors.textSecondary)

                        Text(modelSwitcher.displayName)
                            .font(DesignToken.Font.system(size: 12, weight: .medium))
                            .foregroundColor(modelSwitcher.hasOverride ? DesignToken.Colors.accent : DesignToken.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(DesignToken.Font.system(size: 10, weight: .semibold))
                            .foregroundColor(DesignToken.Colors.textTertiary)
                    }
                    .padding(.horizontal, DesignToken.Spacing.sm)
                    .frame(maxWidth: .infinity, minHeight: DesignToken.Layout.buttonMinHeight)
                    .background(DesignToken.Colors.hoverFill)
                    .cornerRadius(DesignToken.Layout.buttonCornerRadius)
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("menu.model.submenu")
            }
        }
        .accessibilityIdentifier("menu.model.selector")
    }

    // MARK: - Active Channel Info

    private var activeChannelInfo: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            if let channel = channelStore.activeChannel {
                HStack(spacing: DesignToken.Spacing.xs) {
                    Text(L10n.Menu.channelActive(channel.name))
                        .font(DesignToken.Font.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    if channel.lastLatencyMs > 0 {
                        LatencyChip(latencyMs: channel.lastLatencyMs)
                    }
                }

                Text(channel.baseURL)
                    .font(DesignToken.Font.micro())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(L10n.Menu.channelActive(L10n.Settings.channelsAdd))
                    .font(DesignToken.Font.system(size: 12, weight: .medium))
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }
        }
        .accessibilityIdentifier("menu.active.channel")
    }

    // MARK: - Recent Requests

    private var recentRequests: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(L10n.Menu.requestsRecent)
                .font(DesignToken.Font.system(size: 11, weight: .medium))
                .foregroundColor(DesignToken.Colors.textSecondary)

            let recent = Array(usage.records.suffix(5).reversed())
            if recent.isEmpty {
                Text(L10n.Menu.requestsNone)
                    .font(DesignToken.Font.micro())
                    .foregroundColor(DesignToken.Colors.textTertiary)
            } else {
                ForEach(recent, id: \.timestamp) { record in
                    HStack(spacing: DesignToken.Spacing.xs) {
                        Text(record.model)
                            .font(DesignToken.Font.micro())
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("·")
                            .font(DesignToken.Font.micro())
                            .foregroundColor(DesignToken.Colors.textTertiary)

                        Text(timeAgo(from: record.timestamp))
                            .font(DesignToken.Font.micro())
                            .foregroundColor(DesignToken.Colors.textSecondary)

                        Text("·")
                            .font(DesignToken.Font.micro())
                            .foregroundColor(DesignToken.Colors.textTertiary)

                        Image(systemName: record.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(DesignToken.Font.system(size: 10))
                            .foregroundColor(record.isError ? DesignToken.Colors.statusOffline : DesignToken.Colors.statusOnline)
                    }
                }
            }
        }
            .accessibilityIdentifier("menu.recentRequestsList")
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return L10n.Menu.timeSeconds(seconds)
        } else if seconds < 3600 {
            return L10n.Menu.timeMinutes(seconds / 60)
        } else {
            return L10n.Menu.timeHours(seconds / 3600)
        }
    }

    // MARK: - Action Buttons

    @State private var isTestingKey: Bool = false

    private var actionButtons: some View {
        VStack(spacing: DesignToken.Spacing.xs) {
            HoverButton(title: L10n.Menu.copyEnv, icon: "square.and.arrow.up") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "export ANTHROPIC_BASE_URL=http://localhost:\(proxy.port)/v1\nexport OPENAI_BASE_URL=http://localhost:\(proxy.port)/v1",
                    forType: .string
                )
            }
            .accessibilityIdentifier("menu.copyEnvButton")

            HoverButton(
                title: isTestingKey ? L10n.Status.testing : L10n.Menu.testKey,
                icon: isTestingKey ? "ellipsis.circle.fill" : "checkmark.circle"
            ) {
                Task {
                    isTestingKey = true
                    if let channel = channelStore.activeChannel {
                        _ = await channelManager.testConnection(channel: channel)
                    }
                    isTestingKey = false
                }
            }
            .disabled(channelStore.activeChannel == nil || isTestingKey)
            .accessibilityIdentifier("menu.testKeyButton")
        }
        .font(DesignToken.Font.system(size: 12))
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        HStack(spacing: DesignToken.Spacing.lg) {
            settingsButton

            Spacer()

            HoverButton(title: L10n.Menu.quit, icon: "power") {
                NSApp.terminate(nil)
            }
            .accessibilityIdentifier("menu.quitButton")
        }
        .font(DesignToken.Font.system(size: 12))
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                HStack(spacing: DesignToken.Spacing.xs) {
                    Image(systemName: "gearshape")
                        .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))

                    Text(L10n.Menu.settings)
                        .font(DesignToken.Font.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: DesignToken.Layout.buttonMinHeight)
                .foregroundColor(DesignToken.Colors.textPrimary)
                .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.settingsButton")
            .onTapGesture {
                // Activate app to bring settings window to front
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            HoverButton(title: L10n.Menu.settings, icon: "gearshape") {
                // Activate app first, then show settings
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .accessibilityIdentifier("menu.settingsButton")
        }
    }
}

// MARK: - Preview

#Preview {
    MenuView()
}
