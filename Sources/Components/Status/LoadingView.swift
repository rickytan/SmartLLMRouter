import SwiftUI

// MARK: - LoadingView

/// A centered loading indicator with optional text.
struct LoadingView: View {
    let text: String?

    init(text: String? = nil) {
        self.text = text
    }

    var body: some View {
        VStack(spacing: DesignToken.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            if let text {
                Text(text)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignToken.Spacing.lg)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        LoadingView()
        LoadingView(text: "Fetching models...")
    }
    .frame(width: 200, height: 150)
    .background(DesignToken.Colors.bgPrimary)
}
