import SwiftUI

// MARK: - StatCard

/// A stat display card with icon, value, and label.
/// Extracted from SettingsView.swift.
struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: DesignToken.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: DesignToken.Layout.statCardIconSize))
                .foregroundColor(DesignToken.Colors.accent)

            Text(value)
                .font(DesignToken.Font.value())

            Text(title)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignToken.Layout.cardPadding)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.cardCornerRadius)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.cardCornerRadius)
                .stroke(
                    isHovered ? DesignToken.Colors.accent.opacity(0.3) : Color.clear,
                    lineWidth: DesignToken.Layout.rowHoverBorderWidth
                )
        )
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 12) {
        StatCard(title: "Today's Tokens", value: "12.4K", icon: "textformat")
        StatCard(title: "Total Requests", value: "847", icon: "arrow.up.right")
        StatCard(title: "Est. Cost", value: "$4.20", icon: "dollarsign.circle")
    }
    .padding()
    .frame(width: 500)
}
