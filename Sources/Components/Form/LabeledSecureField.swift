import SwiftUI

// MARK: - LabeledSecureField

/// A label displayed above a SecureField with rounded border.
struct LabeledSecureField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let accessibilityID: String?

    init(
        label: String,
        text: Binding<String>,
        placeholder: String = "",
        accessibilityID: String? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.accessibilityID = accessibilityID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(label)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)

            SecureField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .accessibilityIdentifier(accessibilityID ?? "")
    }
}

// MARK: - Preview

#Preview {
    LabeledSecureField(
        label: "API Key",
        text: .constant(""),
        placeholder: "sk-...",
        accessibilityID: "form.apiKey"
    )
    .padding()
    .frame(width: 300)
}
