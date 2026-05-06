import SwiftUI

// MARK: - ProviderRow

/// A selectable provider row for the AddChannel provider list.
/// Uses DesignToken for all colors/spacing. Replaces native Button in provider list.
struct ProviderRow: View {
    let id: String
    let name: String
    let icon: String
    let isSelected: Bool
    let isCustom: Bool
    let action: () -> Void

    @State private var isHovered = false

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
            .background(
                isSelected
                    ? DesignToken.Colors.accent.opacity(0.12)
                    : (isHovered ? DesignToken.Colors.hoverFill : Color.clear)
            )
            .cornerRadius(DesignToken.Layout.rowCornerRadius)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        ProviderRow(
            id: "custom",
            name: "Custom / Local",
            icon: "globe",
            isSelected: true,
            isCustom: true
        ) {}
        Divider().padding(.horizontal, DesignToken.Spacing.sm)
        ProviderRow(
            id: "openai",
            name: "OpenAI",
            icon: "sparkle",
            isSelected: false,
            isCustom: false
        ) {}
        ProviderRow(
            id: "anthropic",
            name: "Anthropic",
            icon: "brain",
            isSelected: false,
            isCustom: false
        ) {}
    }
    .frame(width: 220)
    .padding()
}
