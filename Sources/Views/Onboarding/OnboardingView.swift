import SwiftUI

// MARK: - PendingChannel

/// Temporary channel held during onboarding before batch-persisting
struct PendingChannel: Identifiable {
    let id = UUID()
    let channel: Channel
    let apiKey: String
    let testStatus: TestStatus

    enum TestStatus: Equatable {
        case success
        case failure(String)
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .welcome
    @State private var shellConfigResult: ShellConfigResult?

    // Batch channel-add state
    @State private var pendingChannels: [PendingChannel] = []
    @State private var isAddingChannel: Bool = false

    // Form-level state (reset after each Test & Add)
    @State private var selectedProviderId: String?
    @State private var isCustomProvider: Bool = false
    @State private var selectedProtocol: APIProtocol = .openai
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var customProviderName: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: ChannelManager.ConnectionTestResult?
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

    // MARK: - Add Channel Step (Batch Mode)

    private var addChannelStep: some View {
        VStack(spacing: DesignToken.Spacing.md) {
            // Header row: title + Add button
            HStack {
                Text(L10n.Onboarding.addedChannelsCount(pendingChannels.count))
                    .font(DesignToken.Font.h3())
                    .foregroundColor(DesignToken.Colors.textPrimary)

                Spacer()

                BadgeButton(
                    title: isAddingChannel ? L10n.AddChannel.cancel : L10n.Onboarding.addChannelAdd,
                    icon: isAddingChannel ? "minus" : "plus"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAddingChannel.toggle()
                        if isAddingChannel {
                            resetForm()
                        }
                    }
                }
                .accessibilityIdentifier("onboarding.addchannel.toggle")
            }
            .padding(.horizontal, DesignToken.Spacing.lg)
            .padding(.top, DesignToken.Spacing.xs)

            Divider()
                .padding(.horizontal, DesignToken.Spacing.lg)

            // Scrollable content area
            ScrollView {
                VStack(spacing: DesignToken.Spacing.md) {
                    // Pending channel list
                    if !pendingChannels.isEmpty {
                        pendingChannelList
                    } else if !isAddingChannel {
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
                    }

                    // Expandable form
                    if isAddingChannel {
                        channelForm
                    }
                }
                .padding(.horizontal, DesignToken.Spacing.lg)
            }
        }
    }

    // MARK: - Pending Channel List

    private var pendingChannelList: some View {
        VStack(spacing: DesignToken.Spacing.xs) {
            ForEach(Array(pendingChannels.enumerated()), id: \.element.id) { index, pending in
                pendingChannelRow(pending: pending, index: index)
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

    private func pendingChannelRow(pending: PendingChannel, index: Int) -> some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            // Icon
            if let providerId = pending.channel.providerId, providerId != "custom" {
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
                Text(pending.channel.name)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textPrimary)
                    .lineLimit(1)
                Text(pending.channel.protocol.rawValue)
                    .font(DesignToken.Font.system(size: 10))
                    .foregroundColor(DesignToken.Colors.textTertiary)
            }

            Spacer()

            // Status
            switch pending.testStatus {
            case .success:
                HStack(spacing: DesignToken.Spacing.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignToken.Colors.statusOnline)
                    Text(L10n.Onboarding.connected)
                        .font(DesignToken.Font.system(size: 11))
                        .foregroundColor(DesignToken.Colors.statusOnline)
                }
            case .failure(let message):
                HStack(spacing: DesignToken.Spacing.xxs) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignToken.Colors.statusOffline)
                    Text(L10n.Onboarding.connectionFailed)
                        .font(DesignToken.Font.system(size: 11))
                        .foregroundColor(DesignToken.Colors.statusOffline)
                    if !message.isEmpty {
                        Text(message)
                            .font(DesignToken.Font.system(size: 10))
                            .foregroundColor(DesignToken.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            // Delete button
            IconButton(icon: "xmark.circle.fill", tooltip: L10n.AddChannel.delete) {
                pendingChannels.remove(at: index)
            }
            .accessibilityIdentifier("onboarding.addchannel.delete.\(index)")
        }
        .padding(.horizontal, DesignToken.Spacing.xs)
        .padding(.vertical, DesignToken.Spacing.xs)
    }

    // MARK: - Channel Form (Expandable)

    private var channelForm: some View {
        VStack(spacing: DesignToken.Spacing.md) {
            // Inner split-pane form
            HStack(spacing: 0) {
                // Left pane: Provider list
                VStack(spacing: 0) {
                    // Search bar
                    SearchBar(
                        text: $searchQuery,
                        placeholder: L10n.AddChannel.search
                    )

                    Divider()

                    // Provider list
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            // Custom provider
                            ProviderListItem(
                                id: "custom",
                                name: L10n.AddChannel.customProvider,
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
                                ProviderListItem(
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
                            LabeledTextField(
                                label: L10n.Onboarding.providerName,
                                text: $customProviderName,
                                placeholder: L10n.AddChannel.providerNamePlaceholder
                            )
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
                        LabeledTextField(
                            label: L10n.Onboarding.baseUrl,
                            text: $baseURL,
                            placeholder: L10n.AddChannel.baseUrlPlaceholder
                        )

                        // API Key
                        LabeledSecureField(
                            label: L10n.Settings.channelsApiKey,
                            text: $apiKey,
                            placeholder: L10n.AddChannel.apiKeyPlaceholder
                        )

                        // Test & Add button row
                        HStack(spacing: DesignToken.Spacing.sm) {
                            HoverButton(
                                title: isTestingConnection ? L10n.Status.testing : L10n.Onboarding.testAndAdd,
                                icon: isTestingConnection ? "ellipsis.circle.fill" : "checkmark.circle"
                            ) {
                                Task { await testAndAdd() }
                            }
                            .disabled(!isFormValid || isTestingConnection)
                            .accessibilityIdentifier("onboarding.addchannel.testAndAdd")

                            SecondaryButton(L10n.Onboarding.cancel) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isAddingChannel = false
                                }
                            }
                        }

                        // Test result
                        if let result = connectionTestResult {
                            connectionTestStatus(result: result)
                        }
                    }
                    .padding(DesignToken.Spacing.lg)
                }
            }
            .frame(height: 380)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DesignToken.Colors.accent.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(8)
        }
    }

    private var isFormValid: Bool {
        !apiKey.isEmpty && !baseURL.isEmpty
    }

    // MARK: - Form helpers

    private var filteredProviders: [ProviderTemplate] {
        if searchQuery.isEmpty {
            return channelManager.providerTemplates
        }
        let q = searchQuery.lowercased()
        return channelManager.providerTemplates.filter {
            $0.nameEn.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
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
            Text(L10n.Onboarding.apiProtocol)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)

            ProtocolSelector(
                selection: $selectedProtocol,
                onProtocolChange: { proto in
                    // Update base URL if using a template
                    if !isCustomProvider, let template = selectedProviderId.flatMap({ channelManager.getProviderTemplate(id: $0) }) {
                        if let url = template.baseURL(for: proto.rawValue.lowercased()) {
                            baseURL = url
                        }
                    }
                    connectionTestResult = nil
                }
            )
        }
    }

    private func connectionTestStatus(result: ChannelManager.ConnectionTestResult) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
            HStack(spacing: DesignToken.Spacing.xxs) {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.success
                        ? DesignToken.Colors.statusOnline
                        : DesignToken.Colors.statusOffline)

                Text(result.success ? L10n.Status.connected : L10n.Status.disconnected)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }

            if !result.success, let msg = errorMessage {
                Text(msg)
                    .font(DesignToken.Font.system(size: 11))
                    .foregroundColor(DesignToken.Colors.statusOffline)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if result.success && !result.models.isEmpty {
                Text(L10n.Onboarding.modelsFetched(result.models.count))
                    .font(DesignToken.Font.system(size: 11))
                    .foregroundColor(DesignToken.Colors.statusOnline)
            }
        }
        .accessibilityIdentifier("onboarding.addchannel.connectionStatus")
    }

    @State private var errorMessage: String?

    // MARK: - Test & Add

    private func testAndAdd() async {
        isTestingConnection = true
        connectionTestResult = nil
        errorMessage = nil

        let resolvedProtocol = selectedProtocol

        let tempChannel = Channel(
            id: UUID().uuidString,
            name: isCustomProvider ? (customProviderName.isEmpty ? "Custom" : customProviderName) : (selectedProviderId.flatMap { channelManager.getProviderTemplate(id: $0)?.nameEn } ?? "Test"),
            providerId: isCustomProvider ? "custom" : selectedProviderId,
            baseURL: baseURL,
            protocol: resolvedProtocol,
            models: []
        )

        // Temporarily store key for test
        do {
            try KeychainManager.shared.setAPIKey(apiKey, for: tempChannel.id)
        } catch {
            Log.error("Failed to set temporary API key for test: \(error.localizedDescription)")
        }
        defer {
            do {
                try KeychainManager.shared.removeAPIKey(for: tempChannel.id)
            } catch {
                Log.error("Failed to remove temporary API key: \(error.localizedDescription)")
            }
        }

        let result = await channelManager.testConnection(channel: tempChannel)

        if result.success {
            connectionTestResult = result
            // Enrich models with template metadata
            let template = selectedProviderId.flatMap { channelManager.getProviderTemplate(id: $0) }
            let enrichedModels = channelManager.mergeModelsWithTemplateMetadata(
                fetchedModels: result.models,
                template: template
            )

            // Create channel with enriched models
            let enrichedChannel = Channel(
                id: tempChannel.id,
                name: tempChannel.name,
                providerId: tempChannel.providerId,
                baseURL: tempChannel.baseURL,
                protocol: tempChannel.protocol,
                models: enrichedModels
            )

            // Add to pending list
            let pending = PendingChannel(
                channel: enrichedChannel,
                apiKey: apiKey,
                testStatus: .success
            )
            pendingChannels.append(pending)
            // Reset form but keep it open for adding more
            resetForm()
        } else {
            connectionTestResult = result
            errorMessage = result.errorMessage ?? "Connection failed"
            // Keep form filled so user can retry
        }
        isTestingConnection = false
    }

    private func resetForm() {
        selectedProviderId = nil
        isCustomProvider = false
        selectedProtocol = .openai
        apiKey = ""
        baseURL = ""
        customProviderName = ""
        connectionTestResult = nil
        errorMessage = nil
        searchQuery = ""
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
                .accessibilityIdentifier("onboarding.launch")
            } else {
                HoverButton(
                    title: nextButtonTitle,
                    icon: "arrow.right"
                ) {
                    goToNextStep()
                }
                .disabled(!canProceed)
                .accessibilityIdentifier("onboarding.next")
            }
        }
    }

    private var successCount: Int {
        pendingChannels.filter { $0.testStatus == .success }.count
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
            // At least 1 successfully tested channel
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
            // Batch-save all success channels
            for pending in pendingChannels where pending.testStatus == .success {
                do {
                    try KeychainManager.shared.setAPIKey(pending.apiKey, for: pending.channel.id)
                } catch {
                    Log.error("Failed to save API key for channel \(pending.channel.name): \(error.localizedDescription)")
                }
                ChannelStore.shared.addChannel(pending.channel)
            }
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
