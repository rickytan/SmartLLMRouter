import SwiftUI

// MARK: - FormRow

/// A horizontal form row with a right-aligned fixed-width label and content.
struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: DesignToken.Spacing.md) {
            Text(label)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .frame(width: DesignToken.Layout.formLabelWidth, alignment: .trailing)

            content()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        FormRow(label: "Name") {
            TextField("Enter name", text: .constant(""))
                .textFieldStyle(.roundedBorder)
        }
        FormRow(label: "Port") {
            TextField("1897", text: .constant("1897"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }
    .padding()
}
