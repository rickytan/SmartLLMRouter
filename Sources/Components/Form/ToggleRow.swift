import SwiftUI

// MARK: - ToggleRow

/// A horizontal row with title (+ optional subtitle) on left, Toggle on right.
/// Hover background change. Uses DesignToken for all colors/spacing.
struct ToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    @State private var isHovered: Bool = false

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                Text(title)
                    .font(DesignToken.Font.body())
                    .foregroundColor(DesignToken.Colors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, DesignToken.Spacing.sm)
        .padding(.vertical, DesignToken.Spacing.xs)
        .background(isHovered ? DesignToken.Colors.hoverFill : Color.clear)
        .cornerRadius(DesignToken.Layout.rowCornerRadius)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DesignToken.Spacing.sm) {
        ToggleRow("Auto-Failover", isOn: .constant(true))
        ToggleRow("Launch at Login", subtitle: "Start automatically when you log in", isOn: .constant(false))
        ToggleRow("Dark Mode", isOn: .constant(true))
    }
    .padding()
    .frame(width: 300)
}
