import SwiftUI

// MARK: - EmptyStateView

/// A centered empty state with icon, title, and description.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: DesignToken.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: DesignToken.Layout.heroIconSize))
                .foregroundColor(DesignToken.Colors.textSecondary)

            Text(title)
                .font(DesignToken.Font.system(size: 13, weight: .medium))
                .foregroundColor(DesignToken.Colors.textPrimary)

            Text(description)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignToken.Spacing.xl)
    }
}

// MARK: - Preview

#Preview {
    EmptyStateView(
        icon: "server.rack",
        title: "No channels configured",
        description: "Add one to get started"
    )
    .frame(width: 300, height: 200)
    .background(DesignToken.Colors.bgPrimary)
}
