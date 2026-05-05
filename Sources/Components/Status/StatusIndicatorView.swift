import SwiftUI

// MARK: - StatusIndicatorView

/// A circular status indicator with optional pulse animation.
/// Extracted from MenuView.swift.
struct StatusIndicatorView: View {
    let isRunning: Bool
    let isCooldown: Bool

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: DesignToken.Layout.statusDotSize, height: DesignToken.Layout.statusDotSize)
            .overlay(
                Circle()
                    .fill(statusPulseColor)
                    .frame(width: DesignToken.Layout.statusDotPulseSize, height: DesignToken.Layout.statusDotPulseSize)
                    .opacity(showPulse ? 0.6 : 0)
                    .animation(
                        Animation.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true),
                        value: showPulse
                    )
            )
    }

    private var statusColor: Color {
        if isCooldown {
            return DesignToken.Colors.statusWarning
        } else if isRunning {
            return DesignToken.Colors.statusOnline
        } else {
            return DesignToken.Colors.statusOffline
        }
    }

    private var statusPulseColor: Color {
        if isCooldown {
            return DesignToken.Colors.statusWarning.opacity(0.3)
        } else if isRunning {
            return DesignToken.Colors.statusOnline.opacity(0.3)
        } else {
            return DesignToken.Colors.statusOffline.opacity(0.3)
        }
    }

    private var showPulse: Bool {
        isRunning || isCooldown
    }

    private var pulseDuration: TimeInterval {
        isCooldown ? DesignToken.Animation.pulseDurationSlow : DesignToken.Animation.pulseDuration
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        HStack {
            Text("Running:")
            StatusIndicatorView(isRunning: true, isCooldown: false)
        }
        HStack {
            Text("Stopped:")
            StatusIndicatorView(isRunning: false, isCooldown: false)
        }
        HStack {
            Text("Cooldown:")
            StatusIndicatorView(isRunning: true, isCooldown: true)
        }
    }
    .padding()
}
