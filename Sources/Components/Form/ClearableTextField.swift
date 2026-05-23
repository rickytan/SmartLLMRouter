import SwiftUI

// MARK: - ClearableTextField

/// A unified text field with consistent height, corner radius, and an optional clear ("X") button.
struct ClearableTextField: View {
    let placeholder: String
    @Binding var text: String
    let showClearButton: Bool
    let accessibilityID: String?

    @State private var isHovered: Bool = false

    init(
        _ placeholder: String,
        text: Binding<String>,
        showClearButton: Bool = true,
        accessibilityID: String? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.showClearButton = showClearButton
        self.accessibilityID = accessibilityID
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.xs) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DesignToken.Font.caption())
                .frame(height: DesignToken.Layout.buttonMinHeight)

            if showClearButton && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DesignToken.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field.clearButton")
            }
        }
        .padding(.horizontal, DesignToken.Spacing.sm)
        .frame(height: DesignToken.Layout.buttonMinHeight)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.buttonCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                .stroke(
                    isHovered ? DesignToken.Colors.textTertiary : DesignToken.Colors.border,
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityIdentifier(accessibilityID ?? "")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ClearableTextField("Enter model name", text: .constant(""))
        ClearableTextField("Enter model name", text: .constant("gpt-4o"))
        ClearableTextField("No clear button", text: .constant("read-only"), showClearButton: false)
    }
    .padding()
    .frame(width: 300)
}
