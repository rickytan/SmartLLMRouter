import SwiftUI

// MARK: - PrimaryButton

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: DesignToken.Layout.buttonIconSize, height: DesignToken.Layout.buttonIconSize)
                } else if let icon {
                    Image(systemName: icon)
                        .font(DesignToken.Font.system(size: DesignToken.Layout.buttonIconSize, weight: .medium))
                }

                Text(title)
                    .font(DesignToken.Font.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: DesignToken.Layout.buttonMinHeight)
            .background(buttonBackground)
            .foregroundColor(isDisabled ? DesignToken.Colors.buttonLabel.opacity(0.5) : DesignToken.Colors.buttonLabel)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            .scaleEffect(isPressed ? DesignToken.Animation.pressScale : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
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
        if isDisabled {
            return DesignToken.Colors.accent.opacity(0.4)
        }
        return isHovered ? DesignToken.Colors.accentHover : DesignToken.Colors.accent
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        PrimaryButton("Start Service", icon: "play.fill") {}
        PrimaryButton("Loading...", isLoading: true) {}
        PrimaryButton("Disabled", isDisabled: true) {}
    }
    .padding()
    .frame(width: 200)
}
