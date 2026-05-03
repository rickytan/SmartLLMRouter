import SwiftUI

struct MenuView: View {
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var usage = UsageTracker.shared

    var body: some View {
        VStack {
            // Status Header
            statusHeader

            Divider()

            // Quick Stats
            quickStats

            Divider()

            // Auto-Failover Toggle
            failoverToggle

            Divider()

            // Active Channel
            activeChannelInfo

            Divider()

            // Recent Requests
            recentRequests

            Divider()

            // Actions
            actionButtons

            Divider()

            // Settings & Quit
            footerButtons
        }
        .padding(8)
        .frame(width: 280)
    }

    // MARK: - Subviews

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(proxy.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(proxy.isRunning ? L10n.App.statusRunning : L10n.App.statusStopped)
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Text(":\(proxy.port)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

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
    }

    private var activeChannelInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.Menu.channelActive(
                channelStore.activeChannel?.name ?? L10n.Settings.channelsAdd
            ))
            .font(.system(size: 12, weight: .medium))

            if let channel = channelStore.activeChannel {
                Text(channel.baseURL)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

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
    }

    private var actionButtons: some View {
        VStack(spacing: 6) {
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "export ANTHROPIC_BASE_URL=http://localhost:\(proxy.port)/v1\nexport OPENAI_BASE_URL=http://localhost:\(proxy.port)/v1",
                    forType: .string
                )
            }) {
                Text(L10n.Menu.copyEnv)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)

            Button(action: {
                // Test active key
            }) {
                Text(L10n.Menu.testKey)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 12))
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                Text(L10n.Menu.settings)
            }

            Spacer()

            Button(action: {
                NSApp.terminate(nil)
            }) {
                Text(L10n.Menu.quit)
            }
        }
        .font(.system(size: 12))
    }
}

#Preview {
    MenuView()
}
