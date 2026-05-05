import SwiftUI

// MARK: - LabeledPicker

/// A label displayed above a Picker.
struct LabeledPicker<Content: View>: View {
    let label: String
    @Binding var selection: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(label)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)

            Picker(selection: $selection) {
                content()
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        LabeledPicker(label: "Language", selection: .constant("en")) {
            Text("English").tag("en")
            Text("中文").tag("zh")
        }
        LabeledPicker(label: "Protocol", selection: .constant("openai")) {
            Text("OpenAI").tag("openai")
            Text("Anthropic").tag("anthropic")
        }
    }
    .padding()
    .frame(width: 250)
}
