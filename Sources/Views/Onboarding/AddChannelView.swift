import SwiftUI

// MARK: - AddChannelView (Modal Form Layout)

struct AddChannelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var channelManager = ChannelManager.shared

    let editingChannel: Channel?

    // Form state
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var selectedProtocol: APIProtocol = .openai
    @State private var priority: Int = 1
    @State private var selectedProviderId: String?
    @State private var models: [ModelEntry] = []
    @State private var isFetchingModels: Bool = false
    @State private var newModelName: String = ""
    @State private var showingModelEditor: Bool = false
    @State private var editingModelIndex: Int?

    // Custom provider state
    @State private var isCustomProvider: Bool = false
    @State private var customProviderName: String = ""

    // Validation
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: ChannelManager.ConnectionTestResult?

    // Search (for provider picker)
    @State private var searchQuery: String = ""

    init(editingChannel: Channel? = nil) {
        self.editingChannel = editingChannel
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

                    // Test connection
                    testConnectionSection

                    Divider()

                    // Models section
                    modelsSection
                }
                .padding(DesignToken.Spacing.lg)
            }
            .frame(maxHeight: .infinity) // Ensure ScrollView takes all available vertical space

            Divider()
                .padding(.horizontal, DesignToken.Spacing.lg)

            // Footer buttons
            footerButtons
                .padding(DesignToken.Spacing.lg)
        }
        .frame(width: DesignToken.Layout.addChannelWidth, height: DesignToken.Layout.addChannelHeight)
        .onAppear {
            if let channel = editingChannel {
                name = channel.name
                baseURL = channel.baseURL
                selectedProtocol = channel.protocol
                priority = channel.priority
                models = channel.models
                selectedProviderId = channel.providerId
                apiKey = KeychainManager.shared.getAPIKey(for: channel.id) ?? ""
                isCustomProvider = (channel.providerId == nil || channel.providerId == "custom")
            } else {
                priority = channelStore.channels.count + 1
                selectedProviderId = channelManager.providerTemplates.first?.id
                applyTemplateSelection()
            }
        }
        .sheet(isPresented: $showingModelEditor) {
            if let index = editingModelIndex, index < models.count {
                ModelMetadataEditorView(model: models[index]) { updated in
                    models[index] = updated
                    showingModelEditor = false
                }
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
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(L10n.AddChannel.providerName)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)

            if isCustomProvider {
                LabeledTextField(
                    label: "",
                    text: $customProviderName,
                    placeholder: L10n.AddChannel.providerNamePlaceholder,
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
                        apiKey = ""
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
                testResult = nil
            }
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
            LabeledTextField(
                label: L10n.Settings.channelsBaseUrl,
                text: $baseURL,
                placeholder: L10n.AddChannel.baseUrlPlaceholder,
                accessibilityID: "addChannel.baseUrlField"
            )

            LabeledSecureField(
                label: L10n.Settings.channelsApiKey,
                text: $apiKey,
                placeholder: L10n.AddChannel.apiKeyPlaceholder,
                accessibilityID: "addChannel.apiKeyField"
            )

            LabeledNumberField(
                L10n.Settings.channelsPriority,
                placeholder: "1",
                value: $priority,
                accessibilityID: "addChannel.priorityField"
            )
        }
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
            .disabled(apiKey.isEmpty || baseURL.isEmpty || isTesting)
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
            try KeychainManager.shared.setAPIKey(apiKey, for: tempChannel.id)
        } catch {
            Log.error("Failed to set test API key: \(error.localizedDescription)")
        }
        defer {
            do {
                try KeychainManager.shared.removeAPIKey(for: tempChannel.id)
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
            models = enrichedModels
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
                .disabled(isFetchingModels || !isTestSuccessful)
                .accessibilityIdentifier("addChannel.fetchModelsButton")
            }

            if models.isEmpty {
                Text(L10n.AddChannel.noModels)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignToken.Spacing.md)
            } else {
                VStack(spacing: DesignToken.Spacing.xs) {
                    ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                        modelRow(model: model, index: index)
                    }
                }
                .frame(maxHeight: 180)
            }

            // Add model manually
            HStack(spacing: DesignToken.Spacing.sm) {
                LabeledTextField(
                    label: "",
                    text: $newModelName,
                    placeholder: L10n.AddChannel.modelNamePlaceholder
                )

                Button {
                    addManualModel()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: DesignToken.Layout.buttonMinHeight, height: DesignToken.Layout.buttonMinHeight)
                        .background(DesignToken.Colors.accent.opacity(0.1))
                        .foregroundColor(DesignToken.Colors.accent)
                        .cornerRadius(DesignToken.Layout.buttonCornerRadius)
                }
                .buttonStyle(.plain)
                .disabled(newModelName.isEmpty)
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

            // Vision / Multimodal Icon
            if model.supportsVision {
                Image(systemName: "photo.fill")
                    .font(.system(size: 10))
                    .foregroundColor(DesignToken.Colors.accent)
            }

            // Edit Button (Standard Button for reliable interaction)
            Button {
                Log.info("[AddChannelView] Edit button tapped for model at index \(index), model: \(model.identifier)")
                editingModelIndex = index
                showingModelEditor = true
                Log.info("[AddChannelView] showingModelEditor set to true, editingModelIndex: \(index)")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignToken.Colors.textSecondary)
            .accessibilityIdentifier("addChannel.modelRow.editButton")

            // Delete Button (Standard Button for reliable interaction)
            Button {
                models.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignToken.Colors.textSecondary)
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

    private func fetchModels() async {
        guard !baseURL.isEmpty, !apiKey.isEmpty else { return }

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

        try? KeychainManager.shared.setAPIKey(apiKey, for: tempChannel.id)
        let fetchedModels = await channelManager.fetchModels(channel: tempChannel)
        try? KeychainManager.shared.removeAPIKey(for: tempChannel.id)

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
        !name.isEmpty && !baseURL.isEmpty && !apiKey.isEmpty
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

                try KeychainManager.shared.setAPIKey(apiKey, for: existingChannel.id)
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

                try KeychainManager.shared.setAPIKey(apiKey, for: newChannel.id)
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
            isEnabled: true
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
}

// MARK: - ModelMetadataEditorView

struct ModelMetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let model: ModelEntry
    let onSave: (ModelEntry) -> Void

    @State private var contextLength: String
    @State private var inputPrice: String
    @State private var outputPrice: String

    init(model: ModelEntry, onSave: @escaping (ModelEntry) -> Void) {
        self.model = model
        self.onSave = onSave
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
                    dismiss()
                }
            }

            Divider()

            LabeledTextField(
                label: L10n.ModelEditor.contextLengthLabel,
                text: $contextLength,
                placeholder: L10n.ModelEditor.contextLengthPlaceholder
            )
            LabeledTextField(
                label: L10n.ModelEditor.inputPriceLabel,
                text: $inputPrice,
                placeholder: L10n.ModelEditor.inputPricePlaceholder
            )
            LabeledTextField(
                label: L10n.ModelEditor.outputPriceLabel,
                text: $outputPrice,
                placeholder: L10n.ModelEditor.outputPricePlaceholder
            )

            Divider()

            HStack {
                SecondaryButton(L10n.ModelEditor.cancel) {
                    dismiss()
                }
                Spacer()
                PrimaryButton(L10n.ModelEditor.save) {
                    var updated = model
                    updated.contextLength = Int(contextLength)
                    updated.inputPricePer1M = Double(inputPrice)
                    updated.outputPricePer1M = Double(outputPrice)
                    onSave(updated)
                }
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
