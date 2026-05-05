import SwiftUI

// MARK: - MenuView

struct MenuView: View {
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var usage = UsageTracker.shared
    @ObservedObject private var channelManager = ChannelManager.shared
    @ObservedObject private var modelSwitcher = ModelSwitcher.shared

    @State private var showingModelPicker = false

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
    }

    // MARK: - Failover Toggle

    private var failoverToggle: some View {
        Toggle(
            appState.autoFailover ? L10n.Menu.failoverAuto : L10n.Menu.failoverManual,
            isOn: Binding(
                get: { appState.autoFailover },
                set: { _ in appState.toggleAutoFailover() }
            )
        )
        .font(DesignToken.Font.system(size: 12))
        .toggleStyle(.switch)
        .accessibilityIdentifier("menu.failover.toggle")
    }

    // MARK: - Model Selector

    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            // Header row with label and current selection
            HStack {
                Text(L10n.Model.selectorLabel)
                    .font(DesignToken.Font.system(size: 11, weight: .medium))
                    .foregroundColor(DesignToken.Colors.textSecondary)

                Spacer()

                // Current model display
                Text(modelSwitcher.displayName)
                    .font(DesignToken.Font.system(size: 11, weight: .semibold))
                    .foregroundColor(modelSwitcher.hasOverride ? DesignToken.Colors.accent : DesignToken.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: modelSwitcher.hasOverride ? "checkmark.circle.fill" : "circle")
                    .font(DesignToken.Font.system(size: 10))
                    .foregroundColor(modelSwitcher.hasOverride ? DesignToken.Colors.accent : DesignToken.Colors.textTertiary)
            }

            // Model list (inline, no popover needed for menu bar)
            if modelSwitcher.compatibleModels.isEmpty {
                Text(L10n.Model.noModelsAvailable)
                    .font(DesignToken.Font.micro())
                    .foregroundColor(DesignToken.Colors.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignToken.Spacing.xs) {
                        // Default option
                        modelOptionButton(
                            modelID: nil,
                            displayName: L10n.Model.defaultPassthrough,
                            isSelected: !modelSwitcher.hasOverride
                        )

                        ForEach(modelSwitcher.compatibleModels, id: \.identifier) { model in
                            modelOptionButton(
                                modelID: model.identifier,
                                displayName: model.displayName,
                                isSelected: modelSwitcher.selectedModelID == model.identifier
                            )
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("menu.model.selector")
    }

    /// Individual model selection button
    private func modelOptionButton(modelID: String?, displayName: String, isSelected: Bool) -> some View {
        Button(action: {
            modelSwitcher.selectModel(modelID)
        }) {
            HStack(spacing: DesignToken.Spacing.xxs) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(DesignToken.Font.system(size: 8, weight: .bold))
                }
                Text(displayName)
                    .font(DesignToken.Font.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, DesignToken.Spacing.xs)
            .padding(.vertical, DesignToken.Spacing.xxs)
            .background(
                isSelected
                    ? DesignToken.Colors.accent.opacity(0.15)
                    : DesignToken.Colors.hoverFill
            )
            .foregroundColor(isSelected ? DesignToken.Colors.accent : DesignToken.Colors.textPrimary)
            .cornerRadius(DesignToken.Layout.badgeCornerRadius)
        }
        .buttonStyle(.plain)
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
        .accessibilityIdentifier("menu.recent.requests")
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
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
            .accessibilityIdentifier("menu.copy环境变量")

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
            .accessibilityIdentifier("menu测试密钥")
        }
        .font(DesignToken.Font.system(size: 12))
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        HStack(spacing: DesignToken.Spacing.lg) {
            HoverButton(title: L10n.Menu.settings, icon: "gearshape") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .accessibilityIdentifier("menu.settings")

            Spacer()

            HoverButton(title: L10n.Menu.quit, icon: "power") {
                NSApp.terminate(nil)
            }
            .accessibilityIdentifier("menu.quit")
        }
        .font(DesignToken.Font.system(size: 12))
    }
}

// MARK: - Preview

#Preview {
    MenuView()
}
