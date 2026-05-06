import SwiftUI

// MARK: - ProtocolSelector

/// A chip-based protocol selector for OpenAI/Anthropic.
struct ProtocolSelector: View {
    @Binding var selection: APIProtocol
    let onProtocolChange: ((APIProtocol) -> Void)?

    init(selection: Binding<APIProtocol>, onProtocolChange: ((APIProtocol) -> Void)? = nil) {
        self._selection = selection
        self.onProtocolChange = onProtocolChange
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            protocolChip(.openai, label: L10n.Settings.generalProtocolOpenai)
            protocolChip(.anthropic, label: L10n.Settings.generalProtocolAnthropic)
        }
    }

    private func protocolChip(_ proto: APIProtocol, label: String) -> some View {
        Button {
            selection = proto
            onProtocolChange?(proto)
        } label: {
            HStack(spacing: DesignToken.Spacing.xxs) {
                Image(systemName: selection == proto ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))

                Text(label)
                    .font(DesignToken.Font.system(
                        size: 11,
                        weight: selection == proto ? .semibold : .regular
                    ))
            }
            .padding(.horizontal, DesignToken.Spacing.sm)
            .padding(.vertical, DesignToken.Spacing.xxs)
            .background(
                selection == proto
                    ? DesignToken.Colors.accent.opacity(0.15)
                    : DesignToken.Colors.bgSecondary
            )
            .foregroundColor(
                selection == proto
                    ? DesignToken.Colors.accent
                    : DesignToken.Colors.textPrimary
            )
            .cornerRadius(DesignToken.Layout.badgeCornerRadius)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ProtocolSelector(selection: .constant(.openai))
        ProtocolSelector(selection: .constant(.anthropic))
    }
    .padding()
}
