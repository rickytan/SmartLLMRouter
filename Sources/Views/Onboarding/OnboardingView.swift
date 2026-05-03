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
                .padding(.top, 20)
                .padding(.bottom, 12)

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
                .padding(16)
        }
        .frame(width: 480, height: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .transition(.opacity)
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(stepProgressColor(for: step))
                    .frame(width: 8, height: 8)
                    .accessibilityIdentifier("onboarding.progress.\(step.rawValue)")
            }
        }
        .padding(.horizontal, 16)
    }

    private func stepProgressColor(for step: OnboardingStep) -> Color {
        let steps = OnboardingStep.allCases
        guard let currentIndex = steps.firstIndex(of: currentStep),
              let stepIndex = steps.firstIndex(of: step)
        else {
            return Color.gray.opacity(0.3)
        }

        if stepIndex < currentIndex {
            return Color(#colorLiteral(red: 0, green: 0.784, blue: 0.325, alpha: 1))
        } else if stepIndex == currentIndex {
            return Color(#colorLiteral(red: 0, green: 0.478, blue: 1, alpha: 1))
        } else {
            return Color.gray.opacity(0.3)
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 56))
                .foregroundColor(Color(#colorLiteral(red: 0, green: 0.478, blue: 1, alpha: 1)))
                .accessibilityIdentifier("onboarding.welcome.icon")

            Text(L10n.Onboarding.title)
                .font(.system(size: 20, weight: .bold))
                .accessibilityIdentifier("onboarding.welcome.title")

            Text(L10n.Onboarding.subtitle)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("onboarding.welcome.subtitle")

            VStack(spacing: 12) {
                featureRow(icon: "arrow.triangle.2.circlepath", text: L10n.Onboarding.featureFailover)
                    .accessibilityIdentifier("onboarding.welcome.feature.failover")
                featureRow(icon: "key.fill", text: L10n.Onboarding.featureMultiKey)
                    .accessibilityIdentifier("onboarding.welcome.feature.multikey")
                featureRow(icon: "shield.fill", text: L10n.Onboarding.featurePrivacy)
                    .accessibilityIdentifier("onboarding.welcome.feature.privacy")
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(#colorLiteral(red: 0, green: 0.784, blue: 0.325, alpha: 1)))
                .frame(width: 20)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Add Channel Step

    private var addChannelStep: some View {
        VStack(spacing: 16) {
            Text(L10n.Onboarding.addChannel)
                .font(.system(size: 15, weight: .semibold))
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
        .padding(.horizontal, 24)
    }

    private var providerGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return LazyVGrid(columns: columns, spacing: 8) {
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
        .frame(maxHeight: 120)
    }

    private var apiKeySection: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.Settings.channelsApiKey)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                if let template = channelManager.getProviderTemplate(id: selectedProviderId ?? "") {
                    Text(template.nameEn)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            SecureField("", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
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
        .padding(.top, 4)
    }

    private func connectionTestStatus(result: ConnectionTestResult) -> some View {
        HStack(spacing: 6) {
            Image(systemName: result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result == .success
                    ? Color(#colorLiteral(red: 0, green: 0.784, blue: 0.325, alpha: 1))
                    : Color(#colorLiteral(red: 1, green: 0.322, blue: 0.322, alpha: 1)))

            Text(result == .success ? L10n.Status.connected : L10n.Status.disconnected)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
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
        VStack(spacing: 20) {
            Text(L10n.Onboarding.shellConfig)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityIdentifier("onboarding.shellconfig.title")

            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundColor(Color(#colorLiteral(red: 0, green: 0.478, blue: 1, alpha: 1)))

            Text(L10n.Onboarding.shellConfigDescription)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
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
        .padding(.horizontal, 24)
    }

    private func shellConfigStatus(result: ShellConfigResult) -> some View {
        HStack(spacing: 6) {
            Image(systemName: result == .success ? "checkmark.circle.fill" : "info.circle")
                .foregroundColor(result == .success
                    ? Color(#colorLiteral(red: 0, green: 0.784, blue: 0.325, alpha: 1))
                    : Color(#colorLiteral(red: 1, green: 0.698, blue: 0, alpha: 1)))

            Text(result == .success
                 ? L10n.Onboarding.shellConfigSuccess
                 : L10n.Onboarding.shellConfigSkipped)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
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
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(Color(#colorLiteral(red: 0, green: 0.784, blue: 0.325, alpha: 1)))
                .accessibilityIdentifier("onboarding.done.icon")

            Text(L10n.Onboarding.done)
                .font(.system(size: 20, weight: .bold))
                .accessibilityIdentifier("onboarding.done.title")

            Text(L10n.Onboarding.doneDescription)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("onboarding.done.description")
        }
        .padding(.horizontal, 24)
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
                .foregroundColor(.secondary)
                .accessibilityIdentifier("onboarding.skip")
            } else if currentStep != .done {
                Button(L10n.Onboarding.back) {
                    goBack()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
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
            VStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected
                        ? Color(#colorLiteral(red: 0, green: 0.478, blue: 1, alpha: 1))
                        : .secondary)

                Text(template.nameEn)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                isSelected
                    ? Color(#colorLiteral(red: 0, green: 0.478, blue: 1, alpha: 1)).opacity(0.1)
                    : isHovered ? Color.gray.opacity(0.08) : Color.clear
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected
                            ? Color(#colorLiteral(red: 0, green: 0.478, blue: 1, alpha: 1))
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(onComplete: {})
}
