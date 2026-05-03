import SwiftUI

// MARK: - MenuView

struct MenuView: View {
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var usage = UsageTracker.shared
    @ObservedObject private var channelManager = ChannelManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Status Header
            statusHeader
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 12)

            // Quick Stats
            quickStats
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 12)

            // Auto-Failover Toggle
            failoverToggle
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 12)

            // Active Channel
            activeChannelInfo
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 12)

            // Recent Requests
            recentRequests
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 12)

            // Actions
            actionButtons
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()
                .padding(.horizontal, 12)

            // Settings & Quit
            footerButtons
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 300)
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack {
            StatusIndicatorView(isRunning: proxy.isRunning, isCooldown: false)
                .accessibilityIdentifier("menu.status.running")

            Text(proxy.isRunning ? L10n.App.statusRunning : L10n.App.statusStopped)
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Text(":\(proxy.port)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .accessibilityIdentifier("menu.port.label")
        }
    }

    // MARK: - Quick Stats

    private var quickStats: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Menu.statsRequests(Int64(usage.todayStats.totalRequests)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Menu.statsTokens(Int64(usage.todayStats.totalTokens)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
        .font(.system(size: 12))
        .toggleStyle(.switch)
        .accessibilityIdentifier("menu.failover.toggle")
    }

    // MARK: - Active Channel Info

    private var activeChannelInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let channel = channelStore.activeChannel {
                HStack(spacing: 6) {
                    Text(L10n.Menu.channelActive(channel.name))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    if channel.lastLatencyMs > 0 {
                        LatencyChip(latencyMs: channel.lastLatencyMs)
                    }
                }

                Text(channel.baseURL)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(L10n.Menu.channelActive(L10n.Settings.channelsAdd))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityIdentifier("menu.active.channel")
    }

    // MARK: - Recent Requests

    private var recentRequests: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.Menu.requestsRecent)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if usage.todayStats.totalRequests == 0 {
                Text(L10n.Menu.requestsNone)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text("\(usage.todayStats.totalRequests) today")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityIdentifier("menu.recent.requests")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 6) {
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
        .font(.system(size: 12))
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        HStack(spacing: 12) {
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
        .font(.system(size: 12))
    }
}

// MARK: - Status Indicator View

struct StatusIndicatorView: View {
    let isRunning: Bool
    let isCooldown: Bool

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .fill(statusColor.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .opacity(showPulse ? 0.6 : 0)
                    .animation(
                        Animation.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true),
                        value: showPulse
                    )
            )
    }

    private var statusColor: Color {
        if isCooldown {
            return Color(#colorLiteral(red: 1, green: 0.698, blue: 0, alpha: 1)) // #FFB300
        } else if isRunning {
            return Color(#colorLiteral(red: 0, green: 0.784, blue: 0.325, alpha: 1)) // #00C853
        } else {
            return Color(#colorLiteral(red: 1, green: 0.322, blue: 0.322, alpha: 1)) // #FF5252
        }
    }

    private var showPulse: Bool {
        isRunning || isCooldown
    }

    private var pulseDuration: TimeInterval {
        isCooldown ? 2.0 : 1.5
    }
}

// MARK: - Latency Chip

struct LatencyChip: View {
    let latencyMs: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(latencyColor)
                .frame(width: 6, height: 6)

            Text(String(format: "%.0fms", latencyMs))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(latencyColor.opacity(0.12))
        .cornerRadius(4)
    }

    private var latencyColor: Color {
        if latencyMs < 300 {
            return Color(#colorLiteral(red: 0, green: 0.784, blue: 0.325, alpha: 1))
        } else if latencyMs < 800 {
            return Color(#colorLiteral(red: 1, green: 0.698, blue: 0, alpha: 1))
        } else {
            return Color(#colorLiteral(red: 1, green: 0.322, blue: 0.322, alpha: 1))
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .foregroundColor(isHovered ? .accentColor : .primary)
            .cornerRadius(6)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
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
