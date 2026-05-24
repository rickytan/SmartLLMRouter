import SwiftUI

// MARK: - DesignToken

enum DesignToken {

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Colors

    enum Colors {
        // Fixed hex colors (status/accent) from Assets.xcassets
        static let statusOnline = Asset.statusOnline.swiftUIColor
        static let statusOffline = Asset.statusOffline.swiftUIColor
        static let statusWarning = Asset.statusWarning.swiftUIColor
        static let accent = Asset.accent.swiftUIColor
        static let accentHover = Asset.accentHover.swiftUIColor

        // Destructive action color (delete, remove)
        static let destructive = statusOffline

        // Reference colors (adapt to Light/Dark automatically)
        static let bgPrimary = Asset.bgPrimary.swiftUIColor
        static let bgSecondary = Asset.bgSecondary.swiftUIColor
        static let textPrimary = Asset.textPrimary.swiftUIColor
        static let textSecondary = Asset.textSecondary.swiftUIColor
        static let textTertiary = Asset.textTertiary.swiftUIColor

        // Hover fill (alpha adapts to appearance)
        static let hoverFill = Asset.hoverFill.swiftUIColor

        // Button label text (white for both light/dark modes)
        static let buttonLabel = Asset.buttonLabel.swiftUIColor

        // Border color (subtle, adapts to light/dark)
        static let border = Asset.border.swiftUIColor

        // Latency colors (aliases matching status colors)
        static let latencyFast = statusOnline
        static let latencyNormal = statusWarning
        static let latencySlow = statusOffline

        // Status indicator overlay
        static let statusPulseOverlay = statusOnline.opacity(0.3)
    }

    // MARK: - Font

    enum Font {
        static func h1() -> SwiftUI.Font { .system(size: 20, weight: .bold) }
        static func h2() -> SwiftUI.Font { .system(size: 15, weight: .semibold) }
        static func h3() -> SwiftUI.Font { .system(size: 13, weight: .semibold) }
        static func body() -> SwiftUI.Font { .system(size: 13) }
        static func caption() -> SwiftUI.Font { .system(size: 11) }
        static func micro() -> SwiftUI.Font { .system(size: 10, weight: .medium) }
        static func microSmall() -> SwiftUI.Font { .system(size: 9) }
        static func value() -> SwiftUI.Font { .system(size: 24, weight: .bold) }
        static func mono() -> SwiftUI.Font { .system(size: 12, design: .monospaced) }
        static func monoCaption() -> SwiftUI.Font { .system(size: 11, design: .monospaced) }
        static func monoMicro() -> SwiftUI.Font { .system(size: 10, design: .monospaced) }

        // Convenience: size + weight
        static func system(size: CGFloat, weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: design)
        }
    }

    // MARK: - Layout

    enum Layout {
        static let menuWidth: CGFloat = 300
        static let menuPadding: CGFloat = 12
        static let settingsWidth: CGFloat = 560
        static let settingsHeight: CGFloat = 420
        static let onboardingWidth: CGFloat = 520
        static let onboardingHeight: CGFloat = 500
        static let addChannelWidth: CGFloat = 520
        static let addChannelHeight: CGFloat = 500
        static let modelEditorWidth: CGFloat = 360
        static let modelEditorHeight: CGFloat = 280
        static let buttonMinHeight: CGFloat = 28
        static let buttonCornerRadius: CGFloat = 6
        static let cardCornerRadius: CGFloat = 10
        static let cardPadding: CGFloat = 16
        static let badgePaddingH: CGFloat = 6
        static let badgePaddingV: CGFloat = 2
        static let badgeCornerRadius: CGFloat = 4
        static let statusDotSize: CGFloat = 8
        static let statusDotPulseSize: CGFloat = 14
        static let buttonIconSize: CGFloat = 12
        static let heroIconSize: CGFloat = 56
        static let largeIconSize: CGFloat = 40
        static let gridMaxHeight: CGFloat = 120
        static let addChannelGridMaxHeight: CGFloat = 100
        static let modelListMaxHeight: CGFloat = 120
        static let formLabelWidth: CGFloat = 100
        static let protocolPickerWidth: CGFloat = 120
        static let priorityFieldWidth: CGFloat = 60
        static let iconFrameWidth: CGFloat = 20
        static let cardIconSize: CGFloat = 16
        static let closeIconSize: CGFloat = 16
        static let featureIconSize: CGFloat = 14
        static let rowCornerRadius: CGFloat = 4

        // Settings & Usage
        static let settingsFrameWidth: CGFloat = 560
        static let settingsFrameHeight: CGFloat = 420
        static let chartHeight: CGFloat = 140
        static let statusIndicatorSmall: CGFloat = 6
        static let chartBarCornerRadius: CGFloat = 3
        static let rowHoverBorderWidth: CGFloat = 1
        static let statCardIconSize: CGFloat = 20
        static let smallIconSize: CGFloat = 11
    }

    // MARK: - Animation

    enum Animation {
        static let hoverDuration = 0.15
        static let pressDuration = 0.1
        static let pressScale = 0.98
        static let pulseDuration = 1.5
        static let pulseDurationSlow = 2.0
    }

    // MARK: - Latency

    enum Latency {
        static let fastThreshold = 300
        static let normalThreshold = 800
    }
}
