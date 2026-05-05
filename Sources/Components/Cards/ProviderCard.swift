import SwiftUI

// MARK: - ProviderCard

/// A provider selection card with icon, name, and selected highlight.
struct ProviderCard: View {
    let providerName: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: DesignToken.Layout.cardIconSize, weight: .medium))
                    .foregroundColor(isSelected ? DesignToken.Colors.accent : DesignToken.Colors.textSecondary)

                Text(providerName)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(isSelected ? DesignToken.Colors.textPrimary : DesignToken.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DesignToken.Colors.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DesignToken.Spacing.sm)
            .background(cardBackground)
            .cornerRadius(DesignToken.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Layout.cardCornerRadius)
                    .stroke(
                        isSelected ? DesignToken.Colors.accent.opacity(0.5) : (isHovered ? DesignToken.Colors.hoverFill : Color.clear),
                        lineWidth: DesignToken.Layout.rowHoverBorderWidth
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
    }

    private var cardBackground: Color {
        if isSelected {
            return DesignToken.Colors.accent.opacity(0.08)
        }
        return isHovered ? DesignToken.Colors.hoverFill : DesignToken.Colors.bgSecondary
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 12) {
        ProviderCard(providerName: "DeepSeek", icon: "globe", isSelected: true) {}
        ProviderCard(providerName: "OpenAI", icon: "bubble.left.and.bubble.right", isSelected: false) {}
        ProviderCard(providerName: "Anthropic", icon: "message", isSelected: false) {}
    }
    .padding()
    .frame(width: 350)
}
