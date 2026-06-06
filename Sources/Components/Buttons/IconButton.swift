import SwiftUI

// MARK: - IconButton

struct IconButton: View {
    let icon: String
    let tooltip: String
    let isDisabled: Bool
    let color: Color?
    let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    init(
        icon: String,
        tooltip: String,
        isDisabled: Bool = false,
        color: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.tooltip = tooltip
        self.isDisabled = isDisabled
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignToken.Font.system(size: 12, weight: .medium))
                .frame(width: DesignToken.Layout.buttonMinHeight, height: DesignToken.Layout.buttonMinHeight)
                .background(isHovered ? DesignToken.Colors.hoverFill : Color.clear)
                .foregroundColor(resolvedColor)
                .cornerRadius(DesignToken.Layout.badgeCornerRadius)
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
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .accessibilityIdentifier("icon.button.\(icon)")
    }

    private var resolvedColor: Color {
        if isDisabled {
            return DesignToken.Colors.textTertiary
        }
        return color ?? DesignToken.Colors.textSecondary
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 12) {
        IconButton(icon: "bolt.fill", tooltip: "Speed Test") {}
        IconButton(icon: "pencil", tooltip: "Edit") {}
        IconButton(icon: "trash", tooltip: "Delete", color: .red) {}
        IconButton(icon: "gearshape", tooltip: "Settings", isDisabled: true) {}
    }
    .padding()
}
