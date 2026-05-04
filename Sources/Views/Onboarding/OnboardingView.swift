import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedProviderId: String?
    @State private var isCustomProvider: Bool = false
    @State private var selectedProtocol: APIProtocol = .openai
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var customProviderName: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var shellConfigResult: ShellConfigResult?
    @State private var searchQuery: String = ""

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
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 8) }
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

    // MARK: - Add Channel Step (Redesigned)

    private var addChannelStep: some View {
        HStack(spacing: 0) {
            // Left pane: Provider list
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: DesignToken.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignToken.Colors.textTertiary)
                        .font(.system(size: 12))
                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(DesignToken.Font.caption())
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DesignToken.Colors.textTertiary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignToken.Spacing.sm)
                .padding(.vertical, DesignToken.Spacing.xs)
                .background(DesignToken.Colors.bgSecondary)

                Divider()

                // Provider list
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Custom provider
                        providerListItem(
                            id: "custom",
                            name: "Custom / Local",
                            icon: "globe",
                            isSelected: isCustomProvider
                        ) {
                            isCustomProvider = true
                            selectedProviderId = nil
                            selectedProtocol = .openai
                            baseURL = "http://localhost:11434/v1"
                            connectionTestResult = nil
                        }

                        Divider().padding(.horizontal, DesignToken.Spacing.sm)

                        // Built-in providers
                        ForEach(filteredProviders) { template in
                            providerListItem(
                                id: template.id,
                                name: template.nameEn,
                                icon: ProviderIconMapper.symbol(for: template.id),
                                isSelected: selectedProviderId == template.id && !isCustomProvider
                            ) {
                                isCustomProvider = false
                                selectProviderTemplate(template)
                            }
                        }
                    }
                    .padding(.vertical, DesignToken.Spacing.xs)
                }
            }
            .frame(width: 200)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(DesignToken.Colors.hoverFill, lineWidth: 0.5)
            )

            Divider()

            // Right pane: Config form
            ScrollView {
                VStack(spacing: DesignToken.Spacing.lg) {
                    // Provider header
                    if isCustomProvider {
                        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                            Text("Provider Name")
                                .font(DesignToken.Font.caption())
                                .foregroundColor(DesignToken.Colors.textSecondary)
                            TextField("e.g. Local Ollama", text: $customProviderName)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else if let template = selectedProviderId.flatMap({ channelManager.getProviderTemplate(id: $0) }) {
                        HStack {
                            Image(systemName: ProviderIconMapper.symbol(for: template.id))
                                .foregroundColor(DesignToken.Colors.accent)
                            Text(template.nameEn)
                                .font(DesignToken.Font.h3())
                        }
                    }

                    // Protocol selector
                    protocolSelector

                    Divider()

                    // Base URL
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                        Text("Base URL")
                            .font(DesignToken.Font.caption())
                            .foregroundColor(DesignToken.Colors.textSecondary)
                        TextField("https://api.example.com/v1", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(DesignToken.Font.mono())
                    }

                    // API Key
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                        Text(L10n.Settings.channelsApiKey)
                            .font(DesignToken.Font.caption())
                            .foregroundColor(DesignToken.Colors.textSecondary)
                        SecureField(L10n.Onboarding.apiKeyPlaceholder, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(DesignToken.Font.mono())
                    }

                    // Test connection
                    testConnectionButton

                    // Result
                    if let result = connectionTestResult {
                        connectionTestStatus(result: result)
                    }
                }
                .padding(DesignToken.Spacing.lg)
            }
        }
    }

    private var filteredProviders: [ProviderTemplate] {
        if searchQuery.isEmpty {
            return channelManager.providerTemplates
        }
        let q = searchQuery.lowercased()
        return channelManager.providerTemplates.filter {
            $0.nameEn.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    private func providerListItem(id: String, name: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? DesignToken.Colors.accent : DesignToken.Colors.textSecondary)
                    .frame(width: 24)

                Text(name)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(isSelected ? DesignToken.Colors.textPrimary : DesignToken.Colors.textSecondary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignToken.Colors.accent)
                }
            }
            .padding(.horizontal, DesignToken.Spacing.sm)
            .padding(.vertical, DesignToken.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DesignToken.Colors.accent.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func selectProviderTemplate(_ template: ProviderTemplate) {
        selectedProviderId = template.id
        if let firstProtocol = template.supportsProtocols.first {
            selectedProtocol = APIProtocol(rawValue: firstProtocol.capitalized) ?? .openai
            baseURL = template.baseURL(for: firstProtocol) ?? ""
        } else if let fallback = template.baseURL {
            baseURL = fallback
            selectedProtocol = .openai
        }
        connectionTestResult = nil
    }

    private var protocolSelector: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text("API Protocol")
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)

            HStack(spacing: DesignToken.Spacing.sm) {
                protocolChip(.openai, label: "OpenAI")
                protocolChip(.anthropic, label: "Anthropic")
            }
        }
    }

    private func protocolChip(_ proto: APIProtocol, label: String) -> some View {
        Button {
            selectedProtocol = proto
            // Update base URL if using a template
            if !isCustomProvider, let template = selectedProviderId.flatMap({ channelManager.getProviderTemplate(id: $0) }) {
                if let url = template.baseURL(for: proto.rawValue.lowercased()) {
                    baseURL = url
                }
            }
            connectionTestResult = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedProtocol == proto ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                Text(label)
                    .font(DesignToken.Font.system(size: 11, weight: selectedProtocol == proto ? .semibold : .regular))
            }
            .padding(.horizontal, DesignToken.Spacing.sm)
            .padding(.vertical, DesignToken.Spacing.xxs)
            .background(
                selectedProtocol == proto
                    ? DesignToken.Colors.accent.opacity(0.15)
                    : DesignToken.Colors.bgSecondary
            )
            .foregroundColor(selectedProtocol == proto ? DesignToken.Colors.accent : DesignToken.Colors.textPrimary)
            .cornerRadius(DesignToken.Layout.badgeCornerRadius)
        }
        .buttonStyle(.plain)
    }

    private var testConnectionButton: some View {
        HoverButton(
            title: isTestingConnection ? L10n.Status.testing : L10n.Onboarding.testConnection,
            icon: isTestingConnection ? "ellipsis.circle.fill" : "checkmark.circle"
        ) {
            Task { await testConnection() }
        }
        .disabled(apiKey.isEmpty || baseURL.isEmpty || isTestingConnection)
        .accessibilityIdentifier("onboarding.addchannel.testConnection")
    }

    private func testConnection() async {
        isTestingConnection = true
        connectionTestResult = nil

        let resolvedProtocol = selectedProtocol

        let tempChannel = Channel(
            id: UUID().uuidString,
            name: isCustomProvider ? (customProviderName.isEmpty ? "Custom" : customProviderName) : (selectedProviderId.flatMap { channelManager.getProviderTemplate(id: $0)?.nameEn } ?? "Test"),
            providerId: isCustomProvider ? "custom" : selectedProviderId,
            baseURL: baseURL,
            protocol: resolvedProtocol,
            models: []
        )

        try? KeychainManager.shared.setAPIKey(apiKey, for: tempChannel.id)
        defer {
            try? KeychainManager.shared.removeAPIKey(for: tempChannel.id)
        }

        let result = await channelManager.testConnection(channel: tempChannel)

        if result.success {
            connectionTestResult = .success
        } else {
            connectionTestResult = .failure
            errorMessage = result.errorMessage ?? "Connection failed"
        }
        isTestingConnection = false
    }

    @State private var errorMessage: String?

    private func connectionTestStatus(result: ConnectionTestResult) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
            HStack(spacing: DesignToken.Spacing.xxs) {
                Image(systemName: result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result == .success
                        ? DesignToken.Colors.statusOnline
                        : DesignToken.Colors.statusOffline)

                Text(result == .success ? L10n.Status.connected : L10n.Status.disconnected)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }

            if result == .failure, let msg = errorMessage {
                Text(msg)
                    .font(DesignToken.Font.system(size: 11))
                    .foregroundColor(DesignToken.Colors.statusOffline)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("onboarding.addchannel.connectionStatus")
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
                .accessibilityIdentifier("onboarding.shellconfig.configureButton")

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
            !baseURL.isEmpty && !apiKey.isEmpty
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
            let providerId = isCustomProvider ? "custom" : selectedProviderId
            let channelName = isCustomProvider
                ? (customProviderName.isEmpty ? "Custom" : customProviderName)
                : (selectedProviderId.flatMap { channelManager.getProviderTemplate(id: $0)?.nameEn } ?? "Channel")

            let newChannel = Channel(
                id: UUID().uuidString,
                name: channelName,
                providerId: providerId,
                baseURL: baseURL,
                protocol: selectedProtocol,
                models: []
            )

            // Store API key
            try? KeychainManager.shared.setAPIKey(apiKey, for: newChannel.id)
            ChannelStore.shared.addChannel(newChannel)

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

// MARK: - Preview

#Preview {
    OnboardingView(onComplete: {})
}
