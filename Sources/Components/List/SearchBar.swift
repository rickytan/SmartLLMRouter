import SwiftUI

// MARK: - SearchBar

/// A search bar with magnifying glass icon, text field, and clear button.
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    let onClear: (() -> Void)?

    init(
        text: Binding<String>,
        placeholder: String = "Search...",
        onClear: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onClear = onClear
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignToken.Colors.textTertiary)
                .font(.system(size: 12))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DesignToken.Font.caption())

            if !text.isEmpty {
                Button {
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignToken.Colors.textTertiary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignToken.Spacing.sm)
        .padding(.vertical, DesignToken.Spacing.xs)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.badgeCornerRadius)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        SearchBar(text: .constant(""), placeholder: "Search providers...")
        SearchBar(text: .constant("DeepSeek"), placeholder: "Search providers...")
    }
    .padding()
    .frame(width: 250)
}
