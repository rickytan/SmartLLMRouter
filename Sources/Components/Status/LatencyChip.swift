import SwiftUI

// MARK: - LatencyChip

/// A chip displaying latency with color-coded indicator.
/// Extracted from MenuView.swift.
struct LatencyChip: View {
    let latencyMs: Double

    var body: some View {
        HStack(spacing: DesignToken.Spacing.xs) {
            Circle()
                .fill(latencyColor)
                .frame(
                    width: DesignToken.Layout.statusDotPulseSize / 2 - 1,
                    height: DesignToken.Layout.statusDotPulseSize / 2 - 1
                )

            Text(String(format: "%.0fms", latencyMs))
                .font(DesignToken.Font.monoMicro())
        }
        .padding(.horizontal, DesignToken.Layout.badgePaddingH)
        .padding(.vertical, DesignToken.Layout.badgePaddingV)
        .background(latencyColor.opacity(0.12))
        .cornerRadius(DesignToken.Layout.badgeCornerRadius)
    }

    private var latencyColor: Color {
        if latencyMs < Double(DesignToken.Latency.fastThreshold) {
            return DesignToken.Colors.latencyFast
        } else if latencyMs < Double(DesignToken.Latency.normalThreshold) {
            return DesignToken.Colors.latencyNormal
        } else {
            return DesignToken.Colors.latencySlow
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 12) {
        LatencyChip(latencyMs: 142)
        LatencyChip(latencyMs: 456)
        LatencyChip(latencyMs: 1200)
    }
    .padding()
}
