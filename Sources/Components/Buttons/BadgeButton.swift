import SwiftUI

// MARK: - BadgeButton

/// A small badge-style button with icon and text, used for inline actions like add/cancel toggles.
struct BadgeButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    init(title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(DesignToken.Font.caption())
            }
            .padding(.horizontal, DesignToken.Spacing.sm)
            .padding(.vertical, DesignToken.Spacing.xxs)
            .background(buttonBackground)
            .foregroundColor(DesignToken.Colors.accent)
            .cornerRadius(DesignToken.Layout.badgeCornerRadius)
            .scaleEffect(isPressed ? DesignToken.Animation.pressScale : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: DesignToken.Animation.pressDuration)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: DesignToken.Animation.pressDuration)) {
                        isPressed = false
                    }
                }
        )
    }

    private var buttonBackground: Color {
        isHovered
            ? DesignToken.Colors.accent.opacity(0.18)
            : DesignToken.Colors.accent.opacity(0.15)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        BadgeButton(title: "Add Channel", icon: "plus") {}
        BadgeButton(title: "Cancel", icon: "minus") {}
    }
    .padding()
}
