import SwiftUI

// MARK: - MenuView

struct MenuView: View {
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var usage = UsageTracker.shared
    @ObservedObject private var channelManager = ChannelManager.shared

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
        HStack(spacing: DesignToken.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                Text(L10n.Menu.statsRequests(Int64(usage.todayStats.totalRequests)))
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                Text(L10n.Menu.statsTokens(Int64(usage.todayStats.totalTokens)))
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }

            Spacer()
        }
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

            if usage.todayStats.totalRequests == 0 {
                Text(L10n.Menu.requestsNone)
                    .font(DesignToken.Font.micro())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            } else {
                Text(L10n.Menu.statsRequests(Int64(usage.todayStats.totalRequests)))
                    .font(DesignToken.Font.micro())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }
        }
        .accessibilityIdentifier("menu.recent.requests")
    }

    // MARK: - Action Buttons

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

            HoverButton(title: L10n.Menu.testKey, icon: "checkmark.circle") {
                // Test active key - trigger connection test
            }
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

// MARK: - Status Indicator View

struct StatusIndicatorView: View {
    let isRunning: Bool
    let isCooldown: Bool

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: DesignToken.Layout.statusDotSize, height: DesignToken.Layout.statusDotSize)
            .overlay(
                Circle()
                    .fill(statusPulseColor)
                    .frame(width: DesignToken.Layout.statusDotPulseSize, height: DesignToken.Layout.statusDotPulseSize)
                    .opacity(showPulse ? 0.6 : 0)
                    .animation(
                        Animation.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true),
                        value: showPulse
                    )
            )
    }

    private var statusColor: Color {
        if isCooldown {
            return DesignToken.Colors.statusWarning
        } else if isRunning {
            return DesignToken.Colors.statusOnline
        } else {
            return DesignToken.Colors.statusOffline
        }
    }

    private var statusPulseColor: Color {
        if isCooldown {
            return DesignToken.Colors.statusWarning.opacity(0.3)
        } else if isRunning {
            return DesignToken.Colors.statusOnline.opacity(0.3)
        } else {
            return DesignToken.Colors.statusOffline.opacity(0.3)
        }
    }

    private var showPulse: Bool {
        isRunning || isCooldown
    }

    private var pulseDuration: TimeInterval {
        isCooldown ? DesignToken.Animation.pulseDurationSlow : DesignToken.Animation.pulseDuration
    }
}

// MARK: - Latency Chip

struct LatencyChip: View {
    let latencyMs: Double

    var body: some View {
        HStack(spacing: DesignToken.Spacing.xs) {
            Circle()
                .fill(latencyColor)
                .frame(width: DesignToken.Layout.statusDotPulseSize / 2 - 1, height: DesignToken.Layout.statusDotPulseSize / 2 - 1)

            Text(String(format: "%.0fms", latencyMs))
                .font(DesignToken.Font.monoMicro())
        }
        .padding(.horizontal, DesignToken.Layout.badgePaddingH)
        .padding(.vertical, DesignToken.Layout.badgePaddingV)
        .background(latencyColor.opacity(0.12))
        .cornerRadius(DesignToken.Layout.badgeCornerRadius)
    }

    private var latencyColor: Color {
        if latencyMs < Double(DesignToken.Latency.fastThreshold) {
            return DesignToken.Colors.latencyFast
        } else if latencyMs < Double(DesignToken.Latency.normalThreshold) {
            return DesignToken.Colors.latencyNormal
        } else {
            return DesignToken.Colors.latencySlow
        }
    }
}

// MARK: - Hover Button

struct HoverButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                Text(title)
                    .font(DesignToken.Font.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: DesignToken.Layout.buttonMinHeight)
            .background(isHovered ? DesignToken.Colors.accent.opacity(0.1) : Color.clear)
            .foregroundColor(isHovered ? DesignToken.Colors.accent : DesignToken.Colors.textPrimary)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            .scaleEffect(isPressed ? DesignToken.Animation.pressScale : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: DesignToken.Animation.pressDuration)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: DesignToken.Animation.pressDuration)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Preview

#Preview {
    MenuView()
}
