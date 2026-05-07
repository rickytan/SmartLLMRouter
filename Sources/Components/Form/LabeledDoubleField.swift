import SwiftUI

// MARK: - LabeledDoubleField

/// Same style as LabeledNumberField but with Double binding.
/// Used for cost/price inputs. Uses DesignToken for all colors/spacing.
struct LabeledDoubleField: View {
    let label: String
    let placeholder: String
    let hint: String?
    @Binding var value: Double
    let accessibilityID: String?

    init(
        _ label: String,
        placeholder: String = "",
        hint: String? = nil,
        value: Binding<Double>,
        accessibilityID: String? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self.hint = hint
        self._value = value
        self.accessibilityID = accessibilityID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            HStack(spacing: DesignToken.Spacing.xs) {
                Text(label)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)

                if let hint {
                    Text(hint)
                        .font(DesignToken.Font.micro())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                }
            }

            TextField(placeholder, value: $value, formatter: doubleFormatter)
                .textFieldStyle(.roundedBorder)
        }
        .accessibilityIdentifier(accessibilityID ?? "")
    }

    private var doubleFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximum = 1000
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        LabeledDoubleField(
            "Max Fallback Cost",
            placeholder: "$2.00",
            hint: "per request",
            value: .constant(2.0),
            accessibilityID: "form.maxFallbackCost"
        )
    }
    .padding()
    .frame(width: 300)
}
