import SwiftUI

// MARK: - ChannelRowView

/// A row displaying a channel with status, info, and action buttons.
/// Reads live channel data from ChannelStore by ID to ensure UI stays in sync.
struct ChannelRowView: View {
    let channelID: String
    let index: Int
    let circuitState: CircuitState
    let isSelected: Bool
    @ObservedObject private var channelStore: ChannelStore
    @ObservedObject private var channelManager: ChannelManager
    @State private var isHovered = false
    @State private var isTesting = false
    @State private var showingEditSheet = false

    @MainActor
    init(
        channelID: String,
        index: Int,
        circuitState: CircuitState = .closed,
        isSelected: Bool = false,
        services: AppServices? = nil
    ) {
        let services = services ?? .shared
        self.channelID = channelID
        self.index = index
        self.circuitState = circuitState
        self.isSelected = isSelected
        _channelStore = ObservedObject(wrappedValue: services.channelStore)
        _channelManager = ObservedObject(wrappedValue: services.channelManager)
    }

    /// Live channel data from store (always up-to-date)
    private var channel: Channel {
        channelStore.channels.first(where: { $0.id == channelID })
            ?? Channel(id: channelID, name: "", providerId: "", baseURL: "", protocol: .openai, models: [])
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            // Drag Handle
            Image(systemName: "line.3.horizontal")
                .font(DesignToken.Font.system(size: 12, weight: .medium))
                .foregroundColor(DesignToken.Colors.textTertiary)
                .onHover { isHovering in
                    if isHovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .accessibilityIdentifier("channel.dragHandle.\(index)")

            // Status Indicator
            channelStatusIndicator

            // Channel Info
            VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                HStack {
                    Text(channel.name)
                        .font(DesignToken.Font.h3())
                        .lineLimit(1)
                        .accessibilityIdentifier("channel.name.\(index)")

                    Spacer()

                    if channel.lastLatencyMs > 0 && channel.isEnabled {
                        LatencyChip(latencyMs: channel.lastLatencyMs)
                    }
                }

                Text(channel.displayEndpointSummary)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .lineLimit(1)

                if !channel.models.isEmpty {
                    Text(channel.models.map(\.identifier).prefix(3).joined(separator: ", "))
                        .font(DesignToken.Font.micro())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            // Actions
            HStack(spacing: DesignToken.Spacing.xs) {
                // Enable/Disable Toggle
                IconButton(
                    icon: channel.isEnabled ? "pause.circle" : "play.circle",
                    tooltip: channel.isEnabled ? L10n.Settings.channelsDisable : L10n.Settings.channelsEnable,
                    color: channel.isEnabled ? DesignToken.Colors.statusWarning : DesignToken.Colors.statusOnline
                ) {
                    channelStore.setChannelEnabled(id: channelID, isEnabled: !channel.isEnabled)
                }
                .accessibilityIdentifier("channel.toggle.\(index)")

                IconButton(
                    icon: isTesting ? "ellipsis.circle.fill" : "bolt.fill",
                    tooltip: L10n.Settings.channelsTestConnection
                ) {
                    Task {
                        isTesting = true
                        _ = await channelManager.speedTest(channel: channel)
                        isTesting = false
                    }
                }
                .disabled(!channel.isEnabled)
                .accessibilityIdentifier("channel.speedtest.\(index)")

                IconButton(
                    icon: "pencil",
                    tooltip: L10n.Settings.channelsEdit
                ) {
                    showingEditSheet = true
                }
                .accessibilityIdentifier("settings.channels.row.editButton")

                IconButton(
                    icon: "trash",
                    tooltip: L10n.Settings.channelsDelete,
                    color: DesignToken.Colors.destructive
                ) {
                    channelStore.removeChannel(id: channelID)
                }
                .accessibilityIdentifier("settings.channels.row.deleteButton")
            }
        }
        .padding(.vertical, DesignToken.Spacing.sm)
        .padding(.horizontal, DesignToken.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignToken.Layout.rowCornerRadius, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(DesignToken.Colors.accent)
                    .frame(width: 2)
                    .padding(.vertical, DesignToken.Spacing.sm)
            }
        }
        .opacity(channel.isEnabled ? 1.0 : 0.5)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddChannelView(editingChannel: channel)
        }
        .accessibilityIdentifier("channel.row.\(index)")
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return DesignToken.Colors.accent.opacity(0.1)
        }
        if isHovered {
            return DesignToken.Colors.hoverFill
        }
        return Color.clear
    }

    @ViewBuilder
    private var channelStatusIndicator: some View {
        switch circuitState {
        case .open:
            Image(systemName: "bolt.slash.fill")
                .font(DesignToken.Font.system(size: 10, weight: .semibold))
                .foregroundColor(DesignToken.Colors.statusOffline)
                .frame(width: 14, height: 14)
                .help(L10n.CircuitBreaker.stateOpen)
                .accessibilityLabel(L10n.CircuitBreaker.stateOpen)
                .accessibilityIdentifier("channel.status.\(index).circuitOpen")
        case .halfOpen:
            Image(systemName: "bolt.horizontal.circle")
                .font(DesignToken.Font.system(size: 11, weight: .semibold))
                .foregroundColor(DesignToken.Colors.statusWarning)
                .frame(width: 14, height: 14)
                .help(L10n.CircuitBreaker.stateHalfOpen)
                .accessibilityLabel(L10n.CircuitBreaker.stateHalfOpen)
                .accessibilityIdentifier("channel.status.\(index).circuitHalfOpen")
        case .closed:
            StatusIndicatorView(
                isRunning: channel.isEnabled && !channel.isCoolingDown,
                isCooldown: channel.isCoolingDown
            )
            .frame(width: 14, height: 14)
            .accessibilityIdentifier("channel.status.\(index)")
        }
    }
}

// MARK: - Preview

#Preview {
    struct Preview: View {
        var body: some View {
            let sampleChannel = Channel(
                id: "preview-1",
                name: "DeepSeek",
                providerId: "deepseek",
                baseURL: "https://api.deepseek.com",
                protocol: .openai,
                models: [
                    ModelEntry(id: "1", identifier: "deepseek-chat", displayName: "deepseek-chat", isEnabled: true),
                    ModelEntry(id: "2", identifier: "deepseek-coder", displayName: "deepseek-coder", isEnabled: true)
                ]
            )

            return VStack(spacing: 0) {
                ChannelRowView(channelID: sampleChannel.id, index: 0, isSelected: false)
            }
            .padding()
            .frame(width: 400)
        }
    }

    return Preview()
}
