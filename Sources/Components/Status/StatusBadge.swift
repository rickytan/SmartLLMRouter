import SwiftUI

// MARK: - StatusBadge

/// A badge showing success (green), failure (red), or warning (yellow) status.
struct StatusBadge: View {
    enum BadgeStatus {
        case success
        case failure
        case warning
    }

    let status: BadgeStatus
    let text: String

    var body: some View {
        HStack(spacing: DesignToken.Spacing.xxs) {
            Image(systemName: statusIcon)
                .font(.system(size: 10))
                .foregroundColor(statusColor)

            Text(text)
                .font(DesignToken.Font.micro())
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, DesignToken.Layout.badgePaddingH)
        .padding(.vertical, DesignToken.Layout.badgePaddingV)
        .background(statusColor.opacity(0.12))
        .cornerRadius(DesignToken.Layout.badgeCornerRadius)
    }

    private var statusIcon: String {
        switch status {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .success:
            return DesignToken.Colors.statusOnline
        case .failure:
            return DesignToken.Colors.statusOffline
        case .warning:
            return DesignToken.Colors.statusWarning
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        StatusBadge(status: .success, text: "Connected")
        StatusBadge(status: .failure, text: "Failed")
        StatusBadge(status: .warning, text: "Cooldown")
    }
    .padding()
}
