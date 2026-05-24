import SwiftUI

// MARK: - LabeledNumberField

/// Same style as LabeledTextField but with NumberFormatter.
/// Supports Int binding. Uses DesignToken for all colors/spacing.
struct LabeledNumberField: View {
    let label: String
    let placeholder: String
    @Binding var value: Int
    let accessibilityID: String?

    init(
        _ label: String,
        placeholder: String = "",
        value: Binding<Int>,
        accessibilityID: String? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._value = value
        self.accessibilityID = accessibilityID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(label)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)

            TextField(placeholder, value: $value, formatter: numberFormatter)
                .textFieldStyle(.roundedBorder)
        }
        .accessibilityIdentifier(accessibilityID ?? "")
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 65535
        return formatter
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        LabeledNumberField(
            "Port",
            placeholder: "1897",
            value: .constant(1897),
            accessibilityID: "form.port"
        )
        LabeledNumberField(
            "Priority",
            placeholder: "1",
            value: .constant(1),
            accessibilityID: "form.priority"
        )
    }
    .padding()
    .frame(width: 300)
}
