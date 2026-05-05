import SwiftUI

// MARK: - SecondaryButton

struct SecondaryButton: View {
    let title: String
    let icon: String?
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    init(
        _ title: String,
        icon: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                }

                Text(title)
                    .font(DesignToken.Font.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: DesignToken.Layout.buttonMinHeight)
            .background(buttonBackground)
            .foregroundColor(buttonForeground)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                    .stroke(DesignToken.Colors.accent, lineWidth: 1)
            )
            .scaleEffect(isPressed ? DesignToken.Animation.pressScale : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .onHover { hovering in
            guard !isDisabled else { return }
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isDisabled else { return }
                    withAnimation(.easeInOut(duration: DesignToken.Animation.pressDuration)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    guard !isDisabled else { return }
                    withAnimation(.easeInOut(duration: DesignToken.Animation.pressDuration)) {
                        isPressed = false
                    }
                }
        )
    }

    private var buttonBackground: Color {
        isHovered ? DesignToken.Colors.accent.opacity(0.1) : Color.clear
    }

    private var buttonForeground: Color {
        isHovered ? DesignToken.Colors.accent : DesignToken.Colors.accent
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        SecondaryButton("Configure Later", icon: "gearshape") {}
        SecondaryButton("Skip") {}
        SecondaryButton("Disabled", isDisabled: true) {}
    }
    .padding()
    .frame(width: 200)
}
