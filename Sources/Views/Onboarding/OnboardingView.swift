import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedProviderId: String?
    @State private var apiKey: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var shellConfigResult: ShellConfigResult?

    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelManager = ChannelManager.shared
    @ObservedObject private var shellConfig = ShellConfigManager.shared

    enum OnboardingStep: String, CaseIterable {
        case welcome
        case addChannel
        case shellConfig
        case done
    }

    enum ConnectionTestResult {
        case success
        case failure
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
        .frame(width: DesignToken.Layout.onboardingWidth, height: DesignToken.Layout.onboardingHeight)
        .background(DesignToken.Colors.bgPrimary)
        .transition(.opacity)
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

    // MARK: - Add Channel Step

    private var addChannelStep: some View {
        VStack(spacing: DesignToken.Spacing.lg) {
            Text(L10n.Onboarding.addChannel)
                .font(DesignToken.Font.h2())
                .accessibilityIdentifier("onboarding.addchannel.title")

            // Provider grid
            providerGrid
                .accessibilityIdentifier("onboarding.addchannel.providerGrid")

            // API Key input (shown when provider selected)
            if selectedProviderId != nil {
                apiKeySection
            }

            // Connection test result
            if let result = connectionTestResult {
                connectionTestStatus(result: result)
            }
        }
        .padding(.horizontal, DesignToken.Spacing.xl)
    }

    private var providerGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: DesignToken.Spacing.sm),
            GridItem(.flexible(), spacing: DesignToken.Spacing.sm),
            GridItem(.flexible(), spacing: DesignToken.Spacing.sm),
            GridItem(.flexible(), spacing: DesignToken.Spacing.sm)
        ]

        return LazyVGrid(columns: columns, spacing: DesignToken.Spacing.sm) {
            ForEach(channelManager.providerTemplates) { template in
                ProviderCard(
                    template: template,
                    isSelected: selectedProviderId == template.id
                ) {
                    selectedProviderId = template.id
                    connectionTestResult = nil
                }
                .accessibilityIdentifier("onboarding.provider.\(template.id)")
            }
        }
        .frame(maxHeight: DesignToken.Layout.gridMaxHeight)
    }

    private var apiKeySection: some View {
        VStack(spacing: DesignToken.Spacing.sm) {
            HStack {
                Text(L10n.Settings.channelsApiKey)
                    .font(DesignToken.Font.system(size: 13, weight: .medium))

                Spacer()

                if let template = channelManager.getProviderTemplate(id: selectedProviderId ?? "") {
                    Text(template.nameEn)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                }
            }

            SecureField("", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .font(DesignToken.Font.mono())
                .accessibilityIdentifier("onboarding.addchannel.apiKey")

            // Test connection button
            HStack {
                HoverButton(
                    title: isTestingConnection ? L10n.Status.testing : L10n.Onboarding.testConnection,
                    icon: isTestingConnection ? "ellipsis.circle.fill" : "checkmark.circle"
                ) {
                    Task {
                        await testConnection()
                    }
                }
                .disabled(apiKey.isEmpty || isTestingConnection)
                .accessibilityIdentifier("onboarding.addchannel.testConnection")

                Spacer()
            }
        }
        .padding(.top, DesignToken.Spacing.xs)
    }

    private func connectionTestStatus(result: ConnectionTestResult) -> some View {
        HStack(spacing: DesignToken.Spacing.xs + 2) {
            Image(systemName: result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result == .success
                    ? DesignToken.Colors.statusOnline
                    : DesignToken.Colors.statusOffline)

            Text(result == .success ? L10n.Status.connected : L10n.Status.disconnected)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
        }
        .accessibilityIdentifier("onboarding.addchannel.connectionStatus")
    }

    private func testConnection() async {
        guard let providerId = selectedProviderId else { return }

        isTestingConnection = true
        connectionTestResult = nil

        let tempChannel = Channel(
            id: UUID().uuidString,
            name: channelManager.getProviderTemplate(id: providerId)?.nameEn ?? "",
            providerId: providerId,
            baseURL: channelManager.getProviderTemplate(id: providerId)?.baseURL ?? "",
            protocol: .auto,
            models: []
        )

        // Temporarily store key for test
        try? KeychainManager.shared.setAPIKey(apiKey, for: tempChannel.id)

        let success = await channelManager.testConnection(channel: tempChannel)

        // Clean up temp key
        try? KeychainManager.shared.removeAPIKey(for: tempChannel.id)

        connectionTestResult = success ? .success : .failure
        isTestingConnection = false
    }

    // MARK: - Shell Config Step

    private var shellConfigStep: some View {
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

            // Config button
            HoverButton(
                title: shellConfig.isConfigured ? L10n.Onboarding.shellConfigured : L10n.Onboarding.shellConfigure,
                icon: shellConfig.isConfigured ? "checkmark.circle.fill" : "gearshape"
            ) {
                Task {
                    await configureShell()
                }
            }
            .accessibilityIdentifier("onboarding.shellconfig.configureButton")

            // Status
            if let result = shellConfigResult {
                shellConfigStatus(result: result)
            }
        }
        .padding(.horizontal, DesignToken.Spacing.xl)
    }

    private func shellConfigStatus(result: ShellConfigResult) -> some View {
        HStack(spacing: DesignToken.Spacing.xs + 2) {
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

    // MARK: - Navigation Buttons

    @ViewBuilder
    private var navigationButtons: some View {
        HStack {
            // Skip / Back button
            if currentStep == .welcome {
                Button(L10n.Onboarding.skip) {
                    completeOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignToken.Colors.textSecondary)
                .accessibilityIdentifier("onboarding.skip")
            } else if currentStep != .done {
                Button(L10n.Onboarding.back) {
                    goBack()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignToken.Colors.textSecondary)
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
                .accessibilityIdentifier("onboarding.launch")
            } else {
                HoverButton(
                    title: currentStep == .shellConfig ? L10n.Onboarding.finish : L10n.Onboarding.next,
                    icon: "arrow.right"
                ) {
                    goToNextStep()
                }
                .disabled(!canProceed)
                .accessibilityIdentifier("onboarding.next")
            }
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case .welcome:
            true
        case .addChannel:
            selectedProviderId != nil && !apiKey.isEmpty
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
            // Save the channel
            if let providerId = selectedProviderId {
                if let channel = channelManager.createChannelFromTemplate(
                    templateId: providerId,
                    apiKey: apiKey
                ) {
                    ChannelStore.shared.addChannel(channel)
                }
            }
            currentStep = .shellConfig
        case .shellConfig:
            currentStep = .done
        case .done:
            break
        }
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

// MARK: - Provider Card

struct ProviderCard: View {
    let template: ProviderTemplate
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: "globe")
                    .font(.system(size: DesignToken.Layout.cardIconSize, weight: .medium))
                    .foregroundColor(isSelected
                        ? DesignToken.Colors.accent
                        : DesignToken.Colors.textSecondary)

                Text(template.nameEn)
                    .font(DesignToken.Font.micro())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isSelected ? DesignToken.Colors.textPrimary : DesignToken.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignToken.Spacing.sm)
            .padding(.horizontal, DesignToken.Spacing.xs)
            .background(
                isSelected
                    ? DesignToken.Colors.accent.opacity(0.1)
                    : isHovered ? DesignToken.Colors.hoverFill : Color.clear
            )
            .cornerRadius(DesignToken.Layout.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Layout.buttonCornerRadius)
                    .stroke(
                        isSelected
                            ? DesignToken.Colors.accent
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignToken.Animation.hoverDuration)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(onComplete: {})
}
