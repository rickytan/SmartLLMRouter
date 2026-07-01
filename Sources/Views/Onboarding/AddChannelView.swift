import SwiftUI

// MARK: - AddChannelView (Modal Form Layout)

struct AddChannelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var channelStore: ChannelStore
    @ObservedObject private var channelManager: ChannelManager
    @ObservedObject private var freeLLMKeySyncService: FreeLLMKeySyncService
    private let channelServices: ChannelServices

    let editingChannel: Channel?

    // Form state
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKeys: [String] = [""]
    @State private var selectedProtocol: APIProtocol = .openai
    @State private var priority: Int = 1
    @State private var selectedProviderId: String?
    @State private var models: [ModelEntry] = []
    @State private var isFetchingModels: Bool = false
    @State private var newModelName: String = ""

    // Custom provider state
    @State private var isCustomProvider: Bool = false
    @State private var customProviderName: String = ""

    // Validation
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: ChannelManager.ConnectionTestResult?
    @State private var freeKeysErrorMessage: String?
    @State private var originalAPIKeys: [String] = []

    // Search (for provider picker)
    @State private var searchQuery: String = ""

    @MainActor
    init(editingChannel: Channel? = nil, services: AppServices? = nil) {
        let services = services ?? .shared
        self.editingChannel = editingChannel
        _channelStore = ObservedObject(wrappedValue: services.channelStore)
        _channelManager = ObservedObject(wrappedValue: services.channelManager)
        _freeLLMKeySyncService = ObservedObject(wrappedValue: services.freeLLMKeySyncService)
        channelServices = services.channelServices
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, DesignToken.Spacing.lg)
                .padding(.top, DesignToken.Spacing.md)
                .padding(.bottom, DesignToken.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignToken.Spacing.lg)

            // Scrollable form
            ScrollView {
                VStack(spacing: DesignToken.Spacing.lg) {
                    // Provider selection
                    providerSection

                    // Protocol selector (Segmented)
                    protocolSegmentedView

                    Divider()

                    // Connection details
                    connectionSection

                    // Free key source
                    freeKeysSection

                    // Test connection
                    testConnectionSection

                    Divider()

                    // Models section
                    modelsSection
                }
                .padding(DesignToken.Spacing.lg)
            }
            .frame(maxHeight: .infinity)

            Divider()
                .padding(.horizontal, DesignToken.Spacing.lg)

            // Footer buttons
            footerButtons
                .padding(DesignToken.Spacing.lg)
        }
        .frame(width: DesignToken.Layout.addChannelWidth, height: DesignToken.Layout.addChannelHeight)
        .onChange(of: baseURL) { _ in
            resetConnectionValidation()
        }
        .onChange(of: apiKeys) { _ in
            resetConnectionValidation()
        }
        .onChange(of: selectedProtocol) { _ in
            resetConnectionValidation()
        }
        .onAppear {
            if let channel = editingChannel {
                name = channel.name
                baseURL = channel.baseURL
                selectedProtocol = channel.protocol
                priority = channel.priority
                models = channel.models
                let knownProvider = channel.providerId.flatMap { id in
                    channelManager.providerTemplates.contains(where: { $0.id == id }) ? id : nil
                }
                selectedProviderId = knownProvider
                let storedAPIKeys = channelServices.apiKeys(for: channel.id)
                apiKeys = storedAPIKeys.isEmpty ? [""] : storedAPIKeys
                originalAPIKeys = sanitizeAPIKeys(storedAPIKeys)
                isCustomProvider = (knownProvider == nil)
                if isCustomProvider {
                    customProviderName = channel.name
                }
                testResult = .success(models: channel.models)
            } else {
                priority = channelStore.channels.count + 1
                selectedProviderId = channelManager.providerTemplates.first?.id
                applyTemplateSelection()
            }
        }

    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(editingChannel != nil ? L10n.Settings.channelsEdit : L10n.Settings.channelsAdd)
                .font(DesignToken.Font.h2())

            Spacer()

            IconButton(icon: "xmark.circle.fill", tooltip: L10n.AddChannel.cancel) {
                dismiss()
            }
            .accessibilityIdentifier("addChannel.headerCloseButton")
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(L10n.AddChannel.providerName)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)

            if isCustomProvider {
                ClearableTextField(
                    L10n.AddChannel.providerNamePlaceholder,
                    text: $customProviderName,
                    showClearButton: false,
                    accessibilityID: "addChannel.customNameField"
                )
                .onChange(of: customProviderName) { newName in
                    name = newName
                }
            } else {
                Picker(selection: $selectedProviderId) {
                    Text(L10n.AddChannel.customProvider).tag("custom" as String?)
                    ForEach(channelManager.providerTemplates) { template in
                        Text(template.nameEn).tag(template.id as String?)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("addChannel.providerPicker")
                .onChange(of: selectedProviderId) { _ in
                    if selectedProviderId == "custom" {
                        isCustomProvider = true
                        name = ""
                        baseURL = ""
                        apiKeys = [""]
                        selectedProtocol = .openai
                        models = []
                    } else {
                        isCustomProvider = false
                        applyTemplateSelection()
                    }
                    testResult = nil
                }
            }
        }
    }

    // MARK: - Protocol Segmented View

    private var protocolSegmentedView: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(L10n.AddChannel.protocol)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)

            Picker(selection: $selectedProtocol) {
                Text(L10n.Settings.generalProtocolOpenai).tag(APIProtocol.openai)
                Text(L10n.Settings.generalProtocolAnthropic).tag(APIProtocol.anthropic)
                if isCustomProvider {
                    Text(L10n.Settings.generalProtocolAuto).tag(APIProtocol.auto)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("addChannel.protocolPicker")
            .onChange(of: selectedProtocol) { _ in
                if !isCustomProvider, let template = selectedProviderId.flatMap({ channelManager.getProviderTemplate(id: $0) }) {
                    if let url = template.baseURL(for: selectedProtocol.rawValue.lowercased()) {
                        baseURL = url
                    }
                }
                resetConnectionValidation()
            }
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
            ClearableTextField(
                L10n.AddChannel.baseUrlPlaceholder,
                text: $baseURL,
                label: L10n.Settings.channelsBaseUrl,
                showClearButton: false,
                accessibilityID: "addChannel.baseUrlField"
            )

            apiKeysEditor

            LabeledNumberField(
                L10n.Settings.channelsPriority,
                placeholder: "1",
                value: $priority,
                accessibilityID: "addChannel.priorityField"
            )
        }
    }

    private var apiKeysEditor: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            HStack {
                Text(L10n.AddChannel.apiKeys)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)

                Spacer()

                IconButton(
                    icon: "plus.circle",
                    tooltip: L10n.AddChannel.addApiKey
                ) {
                    apiKeys.append("")
                }
                .accessibilityIdentifier("addChannel.addApiKeyButton")
            }

            VStack(spacing: DesignToken.Spacing.xs) {
                ForEach(apiKeys.indices, id: \.self) { index in
                    HStack(spacing: DesignToken.Spacing.xs) {
                        SecureField(L10n.AddChannel.apiKeyPlaceholder, text: apiKeyBinding(at: index))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("addChannel.apiKeyField.\(index)")

                        IconButton(
                            icon: "chevron.up",
                            tooltip: L10n.AddChannel.moveApiKeyUp,
                            isDisabled: index == 0
                        ) {
                            moveAPIKey(from: index, to: index - 1)
                        }
                        .accessibilityIdentifier("addChannel.moveApiKeyUpButton.\(index)")

                        IconButton(
                            icon: "chevron.down",
                            tooltip: L10n.AddChannel.moveApiKeyDown,
                            isDisabled: index >= apiKeys.count - 1
                        ) {
                            moveAPIKey(from: index, to: index + 1)
                        }
                        .accessibilityIdentifier("addChannel.moveApiKeyDownButton.\(index)")

                        IconButton(
                            icon: "minus.circle",
                            tooltip: L10n.AddChannel.removeApiKey,
                            isDisabled: apiKeys.count <= 1,
                            color: DesignToken.Colors.destructive
                        ) {
                            apiKeys.remove(at: index)
                            if apiKeys.isEmpty {
                                apiKeys = [""]
                            }
                        }
                        .accessibilityIdentifier("addChannel.removeApiKeyButton.\(index)")
                    }
                }
            }
        }
    }

    private var freeKeysSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.sm) {
            HStack(spacing: DesignToken.Spacing.sm) {
                Image(systemName: "key.fill")
                    .font(DesignToken.Font.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignToken.Colors.accent)

                VStack(alignment: .leading, spacing: DesignToken.Spacing.xxs) {
                    Text(L10n.AddChannel.freeKeysTitle)
                        .font(DesignToken.Font.h3())
                    Text(L10n.AddChannel.freeKeysSubtitle)
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.textSecondary)
                }

                Spacer()

                Link(destination: FreeLLMKeySyncService.repositoryURL) {
                    Image(systemName: "info.circle")
                        .font(DesignToken.Font.system(size: 14, weight: .medium))
                        .frame(width: DesignToken.Layout.buttonMinHeight, height: DesignToken.Layout.buttonMinHeight)
                        .foregroundColor(DesignToken.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help(L10n.AddChannel.freeKeysSourceHelp)
                .accessibilityLabel(L10n.AddChannel.freeKeysSourceHelp)
                .accessibilityIdentifier("addChannel.freeKeys.sourceInfoButton")
            }

            ToggleRow(
                L10n.AddChannel.freeKeysAutoSync,
                subtitle: L10n.AddChannel.freeKeysAutoSyncSubtitle,
                isOn: $freeLLMKeySyncService.autoSyncEnabled
            )
            .accessibilityIdentifier("addChannel.freeKeys.autoSyncToggle")

            HoverButton(
                title: freeLLMKeySyncService.isSyncing ? L10n.AddChannel.freeKeysFetching : L10n.AddChannel.freeKeysFetchAndAdd,
                icon: freeLLMKeySyncService.isSyncing ? "ellipsis.circle.fill" : "arrow.clockwise"
            ) {
                Task { await fetchAndAddFreeKeys() }
            }
            .disabled(freeLLMKeySyncService.isSyncing)
            .accessibilityIdentifier("addChannel.freeKeys.fetchButton")

            if let freeKeysErrorMessage {
                Text(freeKeysErrorMessage)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.statusOffline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignToken.Spacing.sm)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(DesignToken.Layout.rowCornerRadius)
    }

    // MARK: - Test Connection

    private var testConnectionSection: some View {
        HStack {
            HoverButton(
                title: isTesting ? L10n.Status.testing : L10n.Settings.channelsTestConnection,
                icon: isTesting ? "ellipsis.circle.fill" : "checkmark.circle"
            ) {
                Task { await testConnection() }
            }
            .disabled(!hasAPIKey || baseURL.isEmpty || isTesting)
            .accessibilityIdentifier("addChannel.testConnectionButton")

            Spacer()

            if let result = testResult {
                if result.success {
                    Label(L10n.Status.connected, systemImage: "checkmark.circle.fill")
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.statusOnline)
                } else {
                    Label(result.errorMessage ?? "Unknown error", systemImage: "xmark.circle.fill")
                        .font(DesignToken.Font.caption())
                        .foregroundColor(DesignToken.Colors.statusOffline)
                }
            }
        }
    }

    private var isTestSuccessful: Bool {
        testResult?.success == true
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        let tempChannel = Channel(
            id: UUID().uuidString,
            name: name.isEmpty ? "test" : name,
            providerId: selectedProviderId,
            baseURL: baseURL,
            protocol: selectedProtocol,
            models: []
        )

        do {
            try channelServices.setAPIKeys(sanitizedAPIKeys, for: tempChannel.id)
        } catch {
            Log.error("Failed to set test API key: \(error.localizedDescription)")
        }
        defer {
            do {
                try channelServices.removeAPIKey(for: tempChannel.id)
            } catch {
                Log.error("Failed to remove test API key: \(error.localizedDescription)")
            }
        }

        let result = await channelManager.testConnection(channel: tempChannel)

        if result.success {
            testResult = result
            let template = selectedProviderId.flatMap { channelManager.getProviderTemplate(id: $0) }
            let enrichedModels = channelManager.mergeModelsWithTemplateMetadata(
                fetchedModels: result.models,
                template: template
            )
            if !enrichedModels.isEmpty {
                models = enrichedModels
            }
        } else {
            testResult = result
        }
        isTesting = false
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.sm) {
            HStack {
                Text(L10n.AddChannel.models)
                    .font(DesignToken.Font.h3())

                Spacer()

                HoverButton(
                    title: isFetchingModels ? L10n.Status.fetchingModels : L10n.AddChannel.fetchModels,
                    icon: isFetchingModels ? "ellipsis.circle.fill" : "arrow.clockwise"
                ) {
                    Task { await fetchModels() }
                }
                .disabled(isFetchingModels || !isConnectionUsable)
                .accessibilityIdentifier("addChannel.fetchModelsButton")
            }

            if models.isEmpty {
                Text(L10n.AddChannel.noModels)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignToken.Spacing.md)
            } else {
                ScrollView {
                    VStack(spacing: DesignToken.Spacing.xs) {
                        ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                            modelRow(model: model, index: index)
                        }
                    }
                    .padding(.vertical, DesignToken.Spacing.xxs)
                }
                .frame(maxHeight: 180)
                .background(DesignToken.Colors.bgSecondary)
                .cornerRadius(DesignToken.Layout.rowCornerRadius)
            }

            // Add model manually
            HStack(spacing: DesignToken.Spacing.sm) {
                ClearableTextField(
                    L10n.AddChannel.modelNamePlaceholder,
                    text: $newModelName,
                    accessibilityID: "addChannel.manualModelField"
                )

                IconButton(
                    icon: "plus",
                    tooltip: L10n.AddChannel.addModel,
                    isDisabled: newModelName.isEmpty
                ) {
                    addManualModel()
                }
            }
        }
    }

    private func modelRow(model: ModelEntry, index: Int) -> some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            // Model Name
            Text(model.identifier)
                .font(DesignToken.Font.caption())
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Context Length
            if let ctx = model.contextLength {
                Text(formatContext(ctx))
                    .font(DesignToken.Font.monoMicro())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }

            // Input Types Badges
            HStack(spacing: 2) {
                ForEach(model.inputTypes, id: \.self) { type in
                    Text(type.uppercased())
                        .font(DesignToken.Font.system(size: 8, weight: .medium))
                        .foregroundColor(inputTypeColor(type))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(inputTypeColor(type).opacity(0.15))
                        .cornerRadius(3)
                }
            }

            // Edit Button
            IconButton(
                icon: "gearshape",
                tooltip: L10n.ModelEditor.editModel(model.identifier)
            ) {
                Log.info("[AddChannelView] Edit button tapped for model at index \(index), model: \(model.identifier)")
                let capturedIndex = index
                ModalPresenter.presentSheet(
                    content: ModelMetadataEditorView(model: model,
                        onSave: { updated in
                            models[capturedIndex] = updated
                            ModalPresenter.dismissSheet()
                        },
                        onCancel: {
                            ModalPresenter.dismissSheet()
                        }
                    ),
                    size: CGSize(width: 360, height: 320)
                )
            }
            .accessibilityIdentifier("addChannel.modelRow.editButton")

            // Delete Button
            IconButton(
                icon: "xmark.circle.fill",
                tooltip: L10n.AddChannel.removeModel
            ) {
                models.remove(at: index)
            }
            .accessibilityIdentifier("addChannel.modelRow.deleteButton")
        }
        .padding(.horizontal, DesignToken.Spacing.sm)
        .padding(.vertical, DesignToken.Spacing.xs)
        .background(DesignToken.Colors.hoverFill.opacity(0.625))
        .cornerRadius(DesignToken.Layout.rowCornerRadius)
    }

    private func formatContext(_ length: Int) -> String {
        if length >= 1_000_000 {
            return String(format: "%.0fM", Double(length) / 1_000_000)
        } else if length >= 1000 {
            return String(format: "%.0fK", Double(length) / 1000)
        }
        return "\(length)"
    }

    private func inputTypeColor(_ type: String) -> Color {
        switch type {
        case "text":
            return DesignToken.Colors.textSecondary
        case "image":
            return DesignToken.Colors.accent
        case "video":
            return Color.purple
        case "audio":
            return Color.orange
        default:
            return DesignToken.Colors.textTertiary
        }
    }

    private func fetchModels() async {
        guard !baseURL.isEmpty, hasAPIKey else { return }

        isFetchingModels = true
        errorMessage = nil

        let tempChannel = Channel(
            id: UUID().uuidString,
            name: name.isEmpty ? "temp" : name,
            providerId: selectedProviderId,
            baseURL: baseURL,
            protocol: selectedProtocol,
            models: models
        )

        try? channelServices.setAPIKeys(sanitizedAPIKeys, for: tempChannel.id)
        let fetchedModels = await channelManager.fetchModels(channel: tempChannel)
        try? channelServices.removeAPIKey(for: tempChannel.id)

        if fetchedModels.isEmpty {
            errorMessage = "No models returned"
        } else {
            models = fetchedModels
        }
        isFetchingModels = false
    }

    private func addManualModel() {
        guard !newModelName.isEmpty else { return }

        let newModel = ModelEntry(
            id: UUID().uuidString,
            identifier: newModelName,
            displayName: newModelName,
            isEnabled: true
        )

        models.append(newModel)
        newModelName = ""
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            SecondaryButton(L10n.AddChannel.cancel) {
                dismiss()
            }
            .frame(width: 100)
            .accessibilityIdentifier("addChannel.cancelButton")

            Spacer()

            PrimaryButton(
                isSaving ? L10n.Status.saving : (editingChannel != nil ? L10n.AddChannel.update : L10n.AddChannel.addChannel),
                icon: isSaving ? "ellipsis.circle.fill" : "checkmark.circle.fill",
                isLoading: isSaving,
                isDisabled: !isValid
            ) {
                Task { await saveChannel() }
            }
            .frame(maxWidth: 200)
            .accessibilityIdentifier("addChannel.saveButton")
        }
    }

    private var isValid: Bool {
        !name.isEmpty && !baseURL.isEmpty && hasAPIKey && isConnectionUsable && !models.isEmpty
    }

    // MARK: - Save

    private func saveChannel() async {
        guard isValid else { return }

        isSaving = true
        errorMessage = nil

        do {
            if let existingChannel = editingChannel {
                var updated = existingChannel
                updated.name = name
                updated.baseURL = baseURL
                updated.protocol = selectedProtocol
                updated.priority = priority
                updated.models = models
                updated.providerId = isCustomProvider ? "custom" : selectedProviderId

                try channelServices.setAPIKeys(sanitizedAPIKeys, for: existingChannel.id)
                channelStore.updateChannel(updated)
            } else {
                let providerId = isCustomProvider ? "custom" : selectedProviderId
                let newChannel = Channel(
                    id: UUID().uuidString,
                    name: name,
                    providerId: providerId,
                    baseURL: baseURL,
                    priority: priority,
                    protocol: selectedProtocol,
                    models: models.isEmpty ? defaultModelsForProvider() : models
                )

                try channelServices.setAPIKeys(sanitizedAPIKeys, for: newChannel.id)
                channelStore.addChannel(newChannel)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func defaultModelsForProvider() -> [ModelEntry] {
        if !isCustomProvider, let template = selectedProviderId.flatMap({ channelManager.getProviderTemplate(id: $0) }) {
            return template.defaultModels.map { providerModelToModelEntry($0) }
        }
        return []
    }

    // MARK: - Helpers

    private func providerModelToModelEntry(_ pm: ProviderModel) -> ModelEntry {
        ModelEntry(
            id: UUID().uuidString,
            identifier: pm.model,
            displayName: pm.model,
            contextLength: pm.contextLength,
            inputPricePer1M: pm.inputPrice,
            outputPricePer1M: pm.outputPrice,
            isEnabled: true,
            inputTypes: pm.inputTypes ?? ["text"]
        )
    }

    private func applyTemplateSelection() {
        guard let templateId = selectedProviderId,
              let template = channelManager.getProviderTemplate(id: templateId) else { return }

        name = template.nameEn
        if let firstProtocol = template.supportsProtocols.first {
            selectedProtocol = APIProtocol(rawValue: firstProtocol.capitalized) ?? .openai
            baseURL = template.baseURL(for: firstProtocol) ?? ""
        } else if let fallback = template.baseURL {
            baseURL = fallback
        }
        models = template.defaultModels.map { providerModelToModelEntry($0) }
        isCustomProvider = false
    }

    private func resetConnectionValidation() {
        if testResult != nil {
            testResult = nil
        }
    }

    private func fetchAndAddFreeKeys() async {
        freeKeysErrorMessage = nil
        do {
            _ = try await freeLLMKeySyncService.syncNow()
            dismiss()
        } catch {
            freeKeysErrorMessage = error.localizedDescription
        }
    }

    private var sanitizedAPIKeys: [String] {
        sanitizeAPIKeys(apiKeys)
    }

    private var isConnectionUsable: Bool {
        isTestSuccessful || isEditingConnectionUnchanged
    }

    private var isEditingConnectionUnchanged: Bool {
        guard let editingChannel else { return false }
        return baseURL == editingChannel.baseURL
            && selectedProtocol == editingChannel.protocol
            && sanitizedAPIKeys == originalAPIKeys
    }

    private func sanitizeAPIKeys(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.compactMap { key in
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                return nil
            }
            seen.insert(trimmed)
            return trimmed
        }
    }

    private var hasAPIKey: Bool {
        !sanitizedAPIKeys.isEmpty
    }

    private func apiKeyBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard apiKeys.indices.contains(index) else { return "" }
                return apiKeys[index]
            },
            set: { newValue in
                guard apiKeys.indices.contains(index) else { return }
                apiKeys[index] = newValue
            }
        )
    }

    private func moveAPIKey(from source: Int, to destination: Int) {
        guard apiKeys.indices.contains(source),
              apiKeys.indices.contains(destination),
              source != destination else {
            return
        }
        apiKeys.swapAt(source, destination)
    }
}

// MARK: - ModelMetadataEditorView

struct ModelMetadataEditorView: View {
    let model: ModelEntry
    let onSave: (ModelEntry) -> Void
    let onCancel: () -> Void

    @State private var contextLength: String
    @State private var inputPrice: String
    @State private var outputPrice: String

    init(model: ModelEntry, onSave: @escaping (ModelEntry) -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        self.onSave = onSave
        self.onCancel = onCancel
        _contextLength = State(initialValue: model.contextLength.map(String.init) ?? "")
        _inputPrice = State(initialValue: model.inputPricePer1M.map { String(format: "%.2f", $0) } ?? "")
        _outputPrice = State(initialValue: model.outputPricePer1M.map { String(format: "%.2f", $0) } ?? "")
    }

    var body: some View {
        VStack(spacing: DesignToken.Spacing.md) {
            HStack {
                Text(L10n.ModelEditor.editModel(model.identifier))
                    .font(DesignToken.Font.h3())
                Spacer()
                IconButton(icon: "xmark.circle.fill", tooltip: L10n.ModelEditor.close) {
                    onCancel()
                }
                .accessibilityIdentifier("modelEditor.closeButton")
            }

            Divider()

            ClearableTextField(
                L10n.ModelEditor.contextLengthPlaceholder,
                text: $contextLength,
                label: L10n.ModelEditor.contextLengthLabel,
                showClearButton: false,
                accessibilityID: "modelEditor.contextLengthField"
            )
            ClearableTextField(
                L10n.ModelEditor.inputPricePlaceholder,
                text: $inputPrice,
                label: L10n.ModelEditor.inputPriceLabel,
                showClearButton: false,
                accessibilityID: "modelEditor.inputPriceField"
            )
            ClearableTextField(
                L10n.ModelEditor.outputPricePlaceholder,
                text: $outputPrice,
                label: L10n.ModelEditor.outputPriceLabel,
                showClearButton: false,
                accessibilityID: "modelEditor.outputPriceField"
            )

            Divider()

            HStack {
                SecondaryButton(L10n.ModelEditor.cancel) {
                    onCancel()
                }
                .accessibilityIdentifier("modelEditor.cancelButton")
                Spacer()
                PrimaryButton(L10n.ModelEditor.save) {
                    var updated = model
                    updated.contextLength = Int(contextLength)
                    updated.inputPricePer1M = Double(inputPrice)
                    updated.outputPricePer1M = Double(outputPrice)
                    onSave(updated)
                }
                .accessibilityIdentifier("modelEditor.saveButton")
            }
        }
        .padding(DesignToken.Spacing.lg)
        .frame(width: 360, height: 320)
    }
}

// MARK: - Preview

#Preview {
    AddChannelView()
}
