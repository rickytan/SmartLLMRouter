import SwiftUI

// MARK: - InfoCard

/// An informational card with icon, title, description, and optional close button.
struct InfoCard: View {
    let icon: String
    let title: String
    let description: String
    let onClose: (() -> Void)?

    @State private var isHovered: Bool = false

    init(
        icon: String,
        title: String,
        description: String,
        onClose: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: DesignToken.Layout.cardIconSize, weight: .medium))
                .foregroundColor(DesignToken.Colors.accent)
                .frame(width: DesignToken.Layout.iconFrameWidth)

            VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                Text(title)
                    .font(DesignToken.Font.h3())
                    .foregroundColor(DesignToken.Colors.textPrimary)

                Text(description)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            if let onClose {
                IconButton(icon: "xmark", tooltip: L10n.AddChannel.cancel) {
                    onClose()
                }
            }
        }
        .padding(DesignToken.Spacing.md)
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
    VStack(spacing: 12) {
        InfoCard(
            icon: "info.circle.fill",
            title: "Setup Complete",
            description: "Shell environment configured successfully."
        )
        InfoCard(
            icon: "checkmark.circle.fill",
            title: "Connection Verified",
            description: "All channels are reachable.",
            onClose: {}
        )
    }
    .padding()
    .frame(width: 350)
}
