import SwiftUI

// MARK: - HoverButton

/// A text + icon button with hover highlight. Extracted from MenuView.swift.
struct HoverButton: View {
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
            HStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                Text(title)
                    .font(DesignToken.Font.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: DesignToken.Layout.buttonMinHeight)
            .background(isHovered ? DesignToken.Colors.accent.opacity(0.1) : Color.clear)
            .foregroundColor(isHovered ? DesignToken.Colors.accent : DesignToken.Colors.textPrimary)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
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
}

// MARK: - Preview

#Preview {
    HoverButton(title: L10n.Menu.settings, icon: "gearshape") {}
        .frame(width: 200)
        .padding()
}
