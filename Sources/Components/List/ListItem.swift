import SwiftUI

// MARK: - ListItem

/// A generic list row with hover background, padding, and optional divider.
struct ListItem<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let action: (() -> Void)?

    @State private var isHovered: Bool = false

    init(action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.action = action
    }

    var body: some View {
        let itemView = content()
            .padding(.vertical, DesignToken.Spacing.sm)
            .padding(.horizontal, DesignToken.Spacing.md)
            .background(isHovered ? DesignToken.Colors.hoverFill : Color.clear)
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                    isHovered = hovering
                }
            }

        if let action {
            Button(action: action) {
                itemView
            }
            .buttonStyle(.plain)
        } else {
            itemView
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        ListItem {
            HStack {
                Text("Item 1")
                    .font(DesignToken.Font.body())
                Spacer()
                Text("Detail")
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }
        }

        Divider()
            .padding(.horizontal, DesignToken.Spacing.md)

        ListItem {
            Text("Item 2 (no action)")
                .font(DesignToken.Font.body())
        }
    }
    .padding()
    .frame(width: 250)
}
