import SwiftUI

// MARK: - FormSection

/// A section with a title, content, and bottom divider.
struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
            Text(title)
                .font(DesignToken.Font.h3())
                .foregroundColor(DesignToken.Colors.textPrimary)

            content()
        }

        Divider()
            .padding(.top, DesignToken.Spacing.md)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        FormSection(title: "Service") {
            Text("Content goes here")
                .font(DesignToken.Font.body())
        }
        FormSection(title: "Shell Environment") {
            Text("More content")
                .font(DesignToken.Font.body())
        }
    }
    .padding()
}
