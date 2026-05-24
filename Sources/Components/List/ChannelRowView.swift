import SwiftUI

// MARK: - ChannelRowView

/// A row displaying a channel with status, info, and action buttons.
/// Reads live channel data from ChannelStore by ID to ensure UI stays in sync.
struct ChannelRowView: View {
    let channelID: String
    let index: Int
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var channelManager = ChannelManager.shared
    @State private var isHovered = false
    @State private var isTesting = false
    @State private var showingEditSheet = false

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
            StatusIndicatorView(
                isRunning: !channel.isCoolingDown,
                isCooldown: channel.isCoolingDown
            )
            .frame(width: DesignToken.Layout.statusDotSize, height: DesignToken.Layout.statusDotSize)
            .accessibilityIdentifier("channel.status.\(index)")

            // Channel Info
            VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                HStack {
                    Text(channel.name)
                        .font(DesignToken.Font.h3())
                        .lineLimit(1)
                        .accessibilityIdentifier("channel.name.\(index)")

                    Spacer()

                    if channel.lastLatencyMs > 0 {
                        LatencyChip(latencyMs: channel.lastLatencyMs)
                    }
                }

                Text(channel.baseURL)
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
                    ChannelStore.shared.removeChannel(id: channelID)
                }
                .accessibilityIdentifier("settings.channels.row.deleteButton")
            }
        }
        .padding(.vertical, DesignToken.Spacing.sm)
        .padding(.horizontal, DesignToken.Spacing.md)
        .background(isHovered ? DesignToken.Colors.hoverFill : Color.clear)
        .cornerRadius(DesignToken.Layout.buttonCornerRadius)
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
                ChannelRowView(channelID: sampleChannel.id, index: 0)
            }
            .padding()
            .frame(width: 400)
        }
    }

    return Preview()
}
