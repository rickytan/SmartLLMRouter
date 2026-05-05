import SwiftUI

// MARK: - EmptyChannelView

/// Empty state view for the channels tab.
/// Extracted from SettingsView.swift.
struct EmptyChannelView: View {
    var body: some View {
        VStack(spacing: DesignToken.Spacing.md) {
            Image(systemName: "server.rack")
                .font(.system(size: DesignToken.Layout.heroIconSize))
                .foregroundColor(DesignToken.Colors.textSecondary)

            Text(L10n.Settings.channelsEmptyTitle)
                .font(DesignToken.Font.system(size: 13, weight: .medium))

            Text(L10n.Settings.channelsEmptySubtitle)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignToken.Spacing.xl)
        .accessibilityIdentifier("settings.channels.emptyState")
    }
}

// MARK: - Preview

#Preview {
    EmptyChannelView()
        .frame(width: 300, height: 200)
}
