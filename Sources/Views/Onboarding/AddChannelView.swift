import SwiftUI

// MARK: - AddChannelView (Redesigned: Split-pane layout)

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
    @State private var customProviderIcon: String = "globe"

    // Validation
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: ConnectionTestResult?

    enum ConnectionTestResult {
        case success
        case failure(String)
    }

    // Search
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

            // Split-pane content
            if editingChannel == nil {
                HStack(spacing: 0) {
                    // Left pane: Provider list
                    providerListPane
                        .frame(width: 220)
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(DesignToken.Colors.hoverFill, lineWidth: 0.5)
                        )

                    Divider()

                    // Right pane: Config form
                    configFormPane
                }
            } else {
                // Editing mode: just the form
                configFormPane
            }

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
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(editingChannel != nil ? L10n.Settings.channelsEdit : L10n.Settings.channelsAdd)
                .font(DesignToken.Font.h2())

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: DesignToken.Layout.closeIconSize))
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Left Pane: Provider List

    private var providerListPane: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: DesignToken.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignToken.Colors.textTertiary)
                    .font(.system(size: 12))
                TextField("Search providers...", text: $searchQuery)
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

            // Scrollable provider list
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Custom provider option (always first)
                    providerListItem(
                        id: "custom",
                        name: "Custom / Local",
                        icon: "globe",
                        isSelected: isCustomProvider,
                        isCustom: true
                    )

                    Divider()
                        .padding(.horizontal, DesignToken.Spacing.sm)

                    // Built-in providers
                    ForEach(filteredProviders) { template in
                        providerListItem(
                            id: template.id,
                            name: template.nameEn,
                            icon: ProviderIconMapper.symbol(for: template.id),
                            isSelected: selectedProviderId == template.id && !isCustomProvider,
                            isCustom: false
                        )
                    }
                }
                .padding(.vertical, DesignToken.Spacing.xs)
            }
        }
    }

    private var filteredProviders: [ProviderTemplate] {
        if searchQuery.isEmpty {
            return channelManager.providerTemplates
        }
        let q = searchQuery.lowercased()
        return channelManager.providerTemplates.filter {
            $0.nameEn.lowercased().contains(q) ||
            $0.id.lowercased().contains(q)
        }
    }

    private func providerListItem(id: String, name: String, icon: String, isSelected: Bool, isCustom: Bool) -> some View {
        Button {
            selectProvider(id: id, isCustom: isCustom)
        } label: {
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
            .background(
                isSelected ? DesignToken.Colors.accent.opacity(0.12) : Color.clear
            )
        }
        .buttonStyle(.plain)
    }

    private func selectProvider(id: String, isCustom: Bool) {
        self.isCustomProvider = isCustom
        selectedProviderId = isCustom ? nil : id

        if isCustom {
            // Reset to defaults for custom
            name = ""
            baseURL = ""
            apiKey = ""
            selectedProtocol = .openai
            models = []
        } else {
            applyTemplateSelection()
        }
        testResult = nil
    }

    private func applyTemplateSelection() {
        guard let templateId = selectedProviderId,
              let template = channelManager.getProviderTemplate(id: templateId) else { return }

        name = template.nameEn
        // Use first protocol's URL as default
        if let firstProtocol = template.supportsProtocols.first {
            selectedProtocol = APIProtocol(rawValue: firstProtocol.capitalized) ?? .openai
            baseURL = template.baseURL(for: firstProtocol) ?? ""
        } else if let fallback = template.baseURL {
            baseURL = fallback
        }
        models = template.defaultModels.map { providerModelToModelEntry($0) }
        isCustomProvider = false
    }

    // MARK: - Right Pane: Config Form

    private var configFormPane: some View {
        ScrollView {
            VStack(spacing: DesignToken.Spacing.lg) {
                // Provider name / Custom name
                VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
                    if isCustomProvider {
                        Text("Provider Name")
                            .font(DesignToken.Font.caption())
                            .foregroundColor(DesignToken.Colors.textSecondary)
                        TextField("e.g. Local Ollama", text: $customProviderName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customProviderName) { newName in
                                name = newName
                            }
                    } else if let template = selectedProviderId.flatMap({ channelManager.getProviderTemplate(id: $0) }) {
                        HStack {
                            Image(systemName: ProviderIconMapper.symbol(for: template.id))
                                .foregroundColor(DesignToken.Colors.accent)
                            Text(template.nameEn)
                                .font(DesignToken.Font.h3())
                        }
                    }
                }

                // Protocol selector (for custom or multi-protocol providers)
                protocolSelectorView

                Divider()

                // Connection details
                VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
                    formRow(label: "Base URL") {
                        TextField("https://api.example.com/v1", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(DesignToken.Font.mono())
                    }

                    formRow(label: "API Key") {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(DesignToken.Font.mono())
                    }

                    formRow(label: "Priority") {
                        TextField("", value: $priority, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // Test connection
                testConnectionSection

                Divider()

                // Models section
                modelsSection
            }
            .padding(DesignToken.Spacing.lg)
        }
    }

    private var protocolSelectorView: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text("Protocol")
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
            testResult = nil
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

    private var testConnectionSection: some View {
        VStack(spacing: DesignToken.Spacing.sm) {
            HStack {
                HoverButton(
                    title: isTesting ? "Testing..." : "Test Connection",
                    icon: isTesting ? "ellipsis.circle.fill" : "checkmark.circle"
                ) {
                    Task { await testConnection() }
                }
                .disabled(apiKey.isEmpty || baseURL.isEmpty || isTesting)

                Spacer()

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(DesignToken.Font.caption())
                            .foregroundColor(DesignToken.Colors.statusOnline)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .font(DesignToken.Font.caption())
                            .foregroundColor(DesignToken.Colors.statusOffline)
                    }
                }
            }
        }
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
            testResult = .success
        } else {
            testResult = .failure(result.errorMessage ?? "Unknown error")
        }
        isTesting = false
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.sm) {
            HStack {
                Text("Models")
                    .font(DesignToken.Font.h3())

                Spacer()

                HoverButton(
                    title: isFetchingModels ? "Fetching..." : "Fetch Models",
                    icon: isFetchingModels ? "ellipsis.circle.fill" : "arrow.clockwise"
                ) {
                    Task { await fetchModels() }
                }
                .disabled(isFetchingModels || baseURL.isEmpty || apiKey.isEmpty)
            }

            if models.isEmpty {
                Text("No models added")
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
                TextField("e.g. gpt-4, llama3", text: $newModelName)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignToken.Font.monoCaption())

                HoverButton(title: "+", icon: "plus") {
                    addManualModel()
                }
                .disabled(newModelName.isEmpty)
            }
        }
    }

    private func modelRow(model: ModelEntry, index: Int) -> some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            Text(model.identifier)
                .font(DesignToken.Font.caption())
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if let ctx = model.contextLength {
                Text(formatContext(ctx))
                    .font(DesignToken.Font.monoMicro())
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }

            Button {
                editingModelIndex = index
                showingModelEditor = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: DesignToken.Layout.smallIconSize))
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignToken.Colors.textSecondary)

            Button {
                models.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: DesignToken.Layout.smallIconSize))
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignToken.Colors.textSecondary)
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

    // MARK: - Helpers

    private func formRow(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(label)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
            content()
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            Button(L10n.Onboarding.back) {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignToken.Colors.textSecondary)

            Spacer()

            HoverButton(
                title: isSaving ? "Saving..." : (editingChannel != nil ? "Update" : "Add Channel"),
                icon: isSaving ? "ellipsis.circle.fill" : "checkmark.circle.fill"
            ) {
                Task { await saveChannel() }
            }
            .disabled(!isValid)
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
                Text("Edit Model: \(model.identifier)")
                    .font(DesignToken.Font.h3())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignToken.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            formField(label: "Context Length (tokens)", text: $contextLength, placeholder: "128000")
            formField(label: "Input Price ($/1M tokens)", text: $inputPrice, placeholder: "5.00")
            formField(label: "Output Price ($/1M tokens)", text: $outputPrice, placeholder: "15.00")

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Spacer()
                Button("Save") {
                    var updated = model
                    updated.contextLength = Int(contextLength)
                    updated.inputPricePer1M = Double(inputPrice)
                    updated.outputPricePer1M = Double(outputPrice)
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignToken.Spacing.lg)
        .frame(width: 360, height: 320)
    }

    private func formField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(label)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(DesignToken.Font.mono())
        }
    }
}
