import SwiftUI

// MARK: - LabeledTextField

/// A label displayed above a TextField with rounded border.
struct LabeledTextField: View {
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

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .accessibilityIdentifier(accessibilityID ?? "")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        LabeledTextField(
            label: "Base URL",
            text: .constant("https://api.example.com/v1"),
            placeholder: "https://api.example.com/v1",
            accessibilityID: "form.baseURL"
        )
        LabeledTextField(
            label: "Name",
            text: .constant(""),
            placeholder: "Enter name",
            accessibilityID: "form.name"
        )
    }
    .padding()
    .frame(width: 300)
}
