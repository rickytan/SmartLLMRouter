import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .welcome
    @State private var shellConfigResult: ShellConfigResult?

    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelManager = ChannelManager.shared
    @ObservedObject private var shellConfig = ShellConfigManager.shared
    @ObservedObject private var channelStore = ChannelStore.shared

    enum OnboardingStep: String, CaseIterable {
        case welcome
        case addChannel
        case shellConfig
        case done
    }

    enum ShellConfigResult {
        case success
        case skipped
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
                .padding(.top, DesignToken.Spacing.lg + DesignToken.Spacing.xs)
                .padding(.bottom, DesignToken.Spacing.md)

            // Step content
            switch currentStep {
            case .welcome:
                welcomeStep
            case .addChannel:
                addChannelStep
            case .shellConfig:
                shellConfigStep
            case .done:
                doneStep
            }

            Spacer()

            // Navigation buttons
            navigationButtons
                .padding(DesignToken.Spacing.lg)
        }
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 8) }
        .frame(width: DesignToken.Layout.onboardingWidth, height: DesignToken.Layout.onboardingHeight)
        .background(DesignToken.Colors.bgPrimary)
        .transition(.opacity)
        .sheet(isPresented: $showingConfigImporter) {
            ConfigImporterView()
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(stepProgressColor(for: step))
                    .frame(width: DesignToken.Layout.statusDotSize, height: DesignToken.Layout.statusDotSize)
                    .accessibilityIdentifier("onboarding.progress.\(step.rawValue)")
            }
        }
        .padding(.horizontal, DesignToken.Spacing.lg)
    }

    private func stepProgressColor(for step: OnboardingStep) -> Color {
        let steps = OnboardingStep.allCases
        guard let currentIndex = steps.firstIndex(of: currentStep),
              let stepIndex = steps.firstIndex(of: step)
        else {
            return DesignToken.Colors.textTertiary
        }

        if stepIndex < currentIndex {
            return DesignToken.Colors.statusOnline
        } else if stepIndex == currentIndex {
            return DesignToken.Colors.accent
        } else {
            return DesignToken.Colors.textTertiary
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.lg + DesignToken.Spacing.xs) {
                Image(systemName: "network")
                    .font(.system(size: DesignToken.Layout.heroIconSize))
                    .foregroundColor(DesignToken.Colors.accent)
                    .accessibilityIdentifier("onboarding.welcome.icon")

                Text(L10n.Onboarding.title)
                    .font(DesignToken.Font.h1())
                    .accessibilityIdentifier("onboarding.welcome.title")

                Text(L10n.Onboarding.subtitle)
                    .font(DesignToken.Font.body())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignToken.Layout.cardPadding * 2)
                    .accessibilityIdentifier("onboarding.welcome.subtitle")

                VStack(spacing: DesignToken.Spacing.md) {
                    featureRow(icon: "arrow.triangle.2.circlepath", text: L10n.Onboarding.featureFailover)
                        .accessibilityIdentifier("onboarding.welcome.feature.failover")
                    featureRow(icon: "key.fill", text: L10n.Onboarding.featureMultiKey)
                        .accessibilityIdentifier("onboarding.welcome.feature.multikey")
                    featureRow(icon: "shield.fill", text: L10n.Onboarding.featurePrivacy)
                        .accessibilityIdentifier("onboarding.welcome.feature.privacy")
                }
                .padding(.top, DesignToken.Spacing.sm)
            }
            .padding(.horizontal, DesignToken.Spacing.xl)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: DesignToken.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: DesignToken.Layout.featureIconSize, weight: .medium))
                .foregroundColor(DesignToken.Colors.statusOnline)
                .frame(width: DesignToken.Layout.iconFrameWidth)

            Text(text)
                .font(DesignToken.Font.body())
                .foregroundColor(DesignToken.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Add Channel Step (Batch Mode)

    @State private var showingConfigImporter = false
    @State private var showingAddChannelSheet = false

    private var addChannelStep: some View {
        VStack(spacing: DesignToken.Spacing.md) {
            // Header row: title + buttons
            HStack {
                Text(L10n.Onboarding.addedChannelsCount(channelStore.channels.count))
                    .font(DesignToken.Font.h3())
                    .foregroundColor(DesignToken.Colors.textPrimary)

                Spacer()

                // Import Config button
                BadgeButton(
                    title: L10n.ConfigImporter.title,
                    icon: "square.and.arrow.down.on.square"
                ) {
                    showingConfigImporter = true
                }
                .accessibilityIdentifier("onboarding.addChannels.importButton")

                BadgeButton(
                    title: L10n.Onboarding.addChannelAdd,
                    icon: "plus"
                ) {
                    showingAddChannelSheet = true
                }
                .accessibilityIdentifier("onboarding.addChannels.addButton")
            }
            .padding(.horizontal, DesignToken.Spacing.lg)
            .padding(.top, DesignToken.Spacing.xs)

            Divider()
                .padding(.horizontal, DesignToken.Spacing.lg)

            // Scrollable content area
            ScrollView {
                VStack(spacing: DesignToken.Spacing.md) {
                    if channelStore.channels.isEmpty {
                        // Empty state
                        VStack(spacing: DesignToken.Spacing.sm) {
                            Image(systemName: "arrow.down.app")
                                .font(.system(size: DesignToken.Layout.largeIconSize))
                                .foregroundColor(DesignToken.Colors.textTertiary)
                            Text(L10n.Onboarding.addChannelSubtitle)
                                .font(DesignToken.Font.caption())
                                .foregroundColor(DesignToken.Colors.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, DesignToken.Spacing.lg)
                    } else {
                        channelList
                    }
                }
                .padding(.horizontal, DesignToken.Spacing.lg)
            }
        }
        .sheet(isPresented: $showingAddChannelSheet) {
            AddChannelView()
        }
    }

    // MARK: - Channel List

    private var channelList: some View {
        VStack(spacing: DesignToken.Spacing.xs) {
            ForEach(channelStore.channels) { channel in
                channelRow(channel: channel)
            }
        }
        .padding(DesignToken.Spacing.sm)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DesignToken.Colors.hoverFill, lineWidth: 0.5)
        )
    }

    private func channelRow(channel: Channel) -> some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            // Icon
            if let providerId = channel.providerId, providerId != "custom" {
                Image(systemName: ProviderIconMapper.symbol(for: providerId))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignToken.Colors.accent)
                    .frame(width: 20)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .frame(width: 20)
            }

            // Name + protocol
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textPrimary)
                    .lineLimit(1)
                Text(channel.protocol.rawValue)
                    .font(DesignToken.Font.system(size: 10))
                    .foregroundColor(DesignToken.Colors.textTertiary)
            }

            Spacer()

            // Status (Always connected since it's saved)
            HStack(spacing: DesignToken.Spacing.xxs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DesignToken.Colors.statusOnline)
                Text(L10n.Onboarding.connected)
                    .font(DesignToken.Font.system(size: 11))
                    .foregroundColor(DesignToken.Colors.statusOnline)
            }

            // Delete button
            IconButton(icon: "xmark.circle.fill", tooltip: L10n.AddChannel.delete) {
                removeChannel(channel)
            }
            .accessibilityIdentifier("onboarding.addChannels.channelRow.deleteButton")
        }
        .padding(.horizontal, DesignToken.Spacing.xs)
        .padding(.vertical, DesignToken.Spacing.xs)
    }

    @MainActor
    private func removeChannel(_ channel: Channel) {
        ChannelStore.shared.removeChannel(id: channel.id)
    }

    // MARK: - Shell Config Step

    private var shellConfigStep: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.lg + DesignToken.Spacing.xs) {
                Text(L10n.Onboarding.shellConfig)
                    .font(DesignToken.Font.h2())
                    .accessibilityIdentifier("onboarding.shellconfig.title")

                Image(systemName: "terminal")
                    .font(.system(size: DesignToken.Layout.largeIconSize))
                    .foregroundColor(DesignToken.Colors.accent)

                Text(L10n.Onboarding.shellConfigDescription)
                    .font(DesignToken.Font.body())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignToken.Spacing.xl)
                    .accessibilityIdentifier("onboarding.shellconfig.description")

                // Show the target file path
                VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                    Text(L10n.Onboarding.shellConfigTargetFile)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                    Text("~/.zshenv")
                        .font(DesignToken.Font.mono())
                        .foregroundColor(DesignToken.Colors.accent)
                        .padding(.horizontal, DesignToken.Spacing.xs)
                        .padding(.vertical, DesignToken.Spacing.xxs)
                        .background(DesignToken.Colors.hoverFill)
                        .cornerRadius(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignToken.Spacing.xl)

                // Preview of export commands
                VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                    Text(L10n.Onboarding.shellConfigWillAdd)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                    Text(shellConfig.getExportCommands(port: appState.port))
                        .font(DesignToken.Font.mono())
                        .foregroundColor(DesignToken.Colors.textPrimary)
                        .padding(DesignToken.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignToken.Colors.bgSecondary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignToken.Colors.hoverFill, lineWidth: 1)
                        )
                }
                .padding(.horizontal, DesignToken.Spacing.xl)

                // Config button
                HoverButton(
                    title: shellConfig.isConfigured ? L10n.Onboarding.shellConfigured : L10n.Onboarding.shellConfigure,
                    icon: shellConfig.isConfigured ? "checkmark.circle.fill" : "gearshape"
                ) {
                    Task {
                        await configureShell()
                    }
                }
                .accessibilityIdentifier("onboarding.shellConfig.applyButton")

                // Status
                if let result = shellConfigResult {
                    shellConfigStatus(result: result)
                }
            }
            .padding(.horizontal, DesignToken.Spacing.xl)
        }
    }

    private func shellConfigStatus(result: ShellConfigResult) -> some View {
        HStack(spacing: DesignToken.Spacing.xxs) {
            Image(systemName: result == .success ? "checkmark.circle.fill" : "info.circle")
                .foregroundColor(result == .success
                    ? DesignToken.Colors.statusOnline
                    : DesignToken.Colors.statusWarning)

            Text(result == .success
                 ? L10n.Onboarding.shellConfigSuccess
                 : L10n.Onboarding.shellConfigSkipped)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
        }
        .accessibilityIdentifier("onboarding.shellconfig.status")
    }

    private func configureShell() async {
        let result = await shellConfig.configure(port: appState.port)
        switch result {
        case .success:
            shellConfigResult = .success
        case .failure:
            shellConfigResult = .skipped
        }
    }

    // MARK: - Done Step

    private var doneStep: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.lg + DesignToken.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DesignToken.Layout.heroIconSize))
                    .foregroundColor(DesignToken.Colors.statusOnline)
                    .accessibilityIdentifier("onboarding.done.icon")

                Text(L10n.Onboarding.done)
                    .font(DesignToken.Font.h1())
                    .accessibilityIdentifier("onboarding.done.title")

                Text(L10n.Onboarding.doneDescription)
                    .font(DesignToken.Font.body())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignToken.Layout.cardPadding * 2)
                    .accessibilityIdentifier("onboarding.done.description")
            }
            .padding(.horizontal, DesignToken.Spacing.xl)
        }
    }

    // MARK: - Navigation Buttons

    @ViewBuilder
    private var navigationButtons: some View {
        HStack {
            // Skip / Back button
            if currentStep == .welcome {
                SecondaryButton(L10n.Onboarding.skip) {
                    completeOnboarding()
                }
                .frame(width: 100)
                .accessibilityIdentifier("onboarding.skip")
            } else if currentStep == .addChannel {
                // Skip is always available on addChannel step
                SecondaryButton(L10n.Onboarding.skip) {
                    skipToShellConfig()
                }
                .frame(width: 100)
                .accessibilityIdentifier("onboarding.skip")

                SecondaryButton(L10n.Onboarding.back) {
                    goBack()
                }
                .frame(width: 100)
                .accessibilityIdentifier("onboarding.back")
            } else if currentStep != .done {
                SecondaryButton(L10n.Onboarding.back) {
                    goBack()
                }
                .frame(width: 100)
                .accessibilityIdentifier("onboarding.back")
            }

            Spacer()

            // Next / Done button
            if currentStep == .done {
                HoverButton(
                    title: L10n.Onboarding.launch,
                    icon: "arrow.right"
                ) {
                    completeOnboarding()
                }
                .accessibilityIdentifier("onboarding.done.launchButton")
            } else {
                HoverButton(
                    title: nextButtonTitle,
                    icon: "arrow.right"
                ) {
                    goToNextStep()
                }
                .disabled(!canProceed)
                .accessibilityIdentifier("onboarding.welcome.nextButton")
            }
        }
    }

    private var successCount: Int {
        ChannelStore.shared.channels.count
    }

    private var nextButtonTitle: String {
        switch currentStep {
        case .addChannel:
            if successCount > 0 {
                return L10n.Onboarding.nextWithCount(successCount)
            }
            return L10n.Onboarding.next
        case .shellConfig:
            return L10n.Onboarding.finish
        default:
            return L10n.Onboarding.next
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case .welcome:
            true
        case .addChannel:
            // At least 1 channel added
            successCount > 0
        case .shellConfig:
            true
        case .done:
            true
        }
    }

    private func goToNextStep() {
        switch currentStep {
        case .welcome:
            currentStep = .addChannel
        case .addChannel:
            // Channels are already saved by AddChannelView
            currentStep = .shellConfig
        case .shellConfig:
            currentStep = .done
        case .done:
            break
        }
    }

    private func skipToShellConfig() {
        // Skip without saving any pending channels
        currentStep = .shellConfig
    }

    private func goBack() {
        switch currentStep {
        case .addChannel:
            currentStep = .welcome
        case .shellConfig:
            currentStep = .addChannel
        default:
            break
        }
    }

    private func completeOnboarding() {
        onComplete()
    }

}

// MARK: - Preview

#Preview {
    OnboardingView(onComplete: {})
}
