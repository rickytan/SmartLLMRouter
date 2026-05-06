import SwiftUI

// MARK: - ProviderListItem

/// A selectable provider list row with icon, name, and optional checkmark.
struct ProviderListItem: View {
    let id: String
    let name: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? DesignToken.Colors.accent : DesignToken.Colors.textSecondary)
                    .frame(width: 24)

                Text(name)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(isSelected ? DesignToken.Colors.textPrimary : DesignToken.Colors.textSecondary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignToken.Colors.accent)
                }
            }
            .padding(.horizontal, DesignToken.Spacing.sm)
            .padding(.vertical, DesignToken.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return DesignToken.Colors.accent.opacity(0.12)
        }
        return isHovered ? DesignToken.Colors.hoverFill : Color.clear
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        ProviderListItem(id: "custom", name: "Custom", icon: "globe", isSelected: true) {}
        Divider().padding(.horizontal, DesignToken.Spacing.sm)
        ProviderListItem(id: "openai", name: "OpenAI", icon: "bubble.left.and.bubble.right", isSelected: false) {}
        ProviderListItem(id: "anthropic", name: "Anthropic", icon: "message", isSelected: false) {}
    }
    .padding()
    .frame(width: 200)
}
