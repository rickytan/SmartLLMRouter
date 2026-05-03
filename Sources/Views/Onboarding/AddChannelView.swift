import SwiftUI

// MARK: - AddChannelView

struct AddChannelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var channelStore = ChannelStore.shared
    @ObservedObject private var channelManager = ChannelManager.shared

    let editingChannel: Channel?

    // Form state
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var selectedProtocol: APIProtocol = .auto
    @State private var priority: Int = 1
    @State private var selectedProviderId: String?
    @State private var models: [ModelEntry] = []
    @State private var isFetchingModels: Bool = false
    @State private var newModelName: String = ""
    @State private var showingModelEditor: Bool = false
    @State private var editingModelIndex: Int?
    @State private var showProviderGrid: Bool = true

    // Validation
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false

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

            // Scrollable form content
            ScrollView {
                VStack(spacing: DesignToken.Spacing.lg) {
                    // Provider template selection (only when adding new)
                    if editingChannel == nil {
                        providerSection
                    }

                    // Basic info
                    basicInfoSection

                    // Models section
                    modelsSection

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(DesignToken.Font.caption())
                            .foregroundColor(DesignToken.Colors.statusOffline)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(DesignToken.Spacing.lg)
            }

            Divider()
                .padding(.horizontal, DesignToken.Spacing.lg)

            // Footer buttons
            footerButtons
                .padding(DesignToken.Spacing.lg)
        }
        .frame(width: DesignToken.Layout.addChannelWidth, height: DesignToken.Layout.addChannelHeight)
        .sheet(isPresented: $showingModelEditor) {
            if let index = editingModelIndex, index < models.count {
                ModelMetadataEditorView(
                    model: models[index],
                    onSave: { updatedModel in
                        models[index] = updatedModel
                        showingModelEditor = false
                    }
                )
            }
        }
        .onAppear {
            if let channel = editingChannel {
                name = channel.name
                baseURL = channel.baseURL
                selectedProtocol = channel.protocol
                priority = channel.priority
                models = channel.models
                selectedProviderId = channel.providerId
                apiKey = KeychainManager.shared.getAPIKey(for: channel.id) ?? ""
                showProviderGrid = false
            } else {
                priority = channelStore.channels.count + 1
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(editingChannel != nil ? L10n.Settings.channelsEdit : L10n.Settings.channelsAdd)
                .font(DesignToken.Font.h2())
                .accessibilityIdentifier("addchannel.title")

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: DesignToken.Layout.closeIconSize))
                    .foregroundColor(DesignToken.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addchannel.close")
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.sm) {
            Text(L10n.Onboarding.addChannel)
                .font(DesignToken.Font.h3())

            if showProviderGrid {
                providerGrid
            } else {
                Text(selectedProviderId.flatMap { channelManager.getProviderTemplate(id: $0)?.nameEn } ?? "")
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textSecondary)
                    .padding(.vertical, DesignToken.Spacing.xs)
            }
        }
        .accessibilityIdentifier("addchannel.providerSection")
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
                    let channel = channelManager.createChannelFromTemplate(
                        templateId: template.id,
                        apiKey: "" // Will be set from form
                    )
                    if let channel = channel {
                        name = channel.name
                        baseURL = channel.baseURL
                        models = channel.models
                    }
                }
                .accessibilityIdentifier("addchannel.provider.\(template.id)")
            }
        }
        .frame(maxHeight: DesignToken.Layout.addChannelGridMaxHeight)
        .accessibilityIdentifier("addchannel.providerGrid")
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.md) {
            // Name
            formRow(label: L10n.Settings.channelsName) {
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("addchannel.name")
            }

            // Base URL
            formRow(label: L10n.Settings.channelsBaseUrl) {
                TextField("", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignToken.Font.mono())
                    .accessibilityIdentifier("addchannel.baseURL")
            }

            // API Key
            formRow(label: L10n.Settings.channelsApiKey) {
                SecureField("", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignToken.Font.mono())
                    .accessibilityIdentifier("addchannel.apiKey")
            }

            // Protocol
            formRow(label: L10n.Settings.channelsProtocol) {
                Picker("", selection: $selectedProtocol) {
                    ForEach(APIProtocol.allCases, id: \.self) { protocolType in
                        Text(protocolType.rawValue)
                            .tag(protocolType)
                    }
                }
                .frame(width: DesignToken.Layout.protocolPickerWidth)
                .accessibilityIdentifier("addchannel.protocol")
            }

            // Priority
            formRow(label: L10n.Settings.channelsPriority) {
                TextField("", value: $priority, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: DesignToken.Layout.priorityFieldWidth)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("addchannel.priority")
            }
        }
        .accessibilityIdentifier("addchannel.basicInfo")
    }

    private func formRow(label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: DesignToken.Spacing.md) {
            Text(label)
                .font(DesignToken.Font.body())
                .frame(width: DesignToken.Layout.formLabelWidth, alignment: .trailing)

            content()
        }
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.sm) {
            HStack {
                Text(L10n.Settings.channelsModels)
                    .font(DesignToken.Font.h3())

                Spacer()

                // Fetch Models button
                HoverButton(
                    title: isFetchingModels ? L10n.Status.fetchingModels : L10n.Settings.channelsFetchModels,
                    icon: isFetchingModels ? "ellipsis.circle.fill" : "arrow.clockwise"
                ) {
                    Task { await fetchModels() }
                }
                .disabled(isFetchingModels || baseURL.isEmpty || apiKey.isEmpty)
                .accessibilityIdentifier("addchannel.fetchModels")
            }

            // Model list
            if models.isEmpty {
                Text(L10n.Menu.requestsNone)
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
                .frame(maxHeight: DesignToken.Layout.modelListMaxHeight)
            }

            // Add model manually
            HStack(spacing: DesignToken.Spacing.sm) {
                TextField("", text: $newModelName, prompt: Text(L10n.AddChannel.modelPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .font(DesignToken.Font.monoCaption())
                    .accessibilityIdentifier("addchannel.newModelName")

                HoverButton(title: "+", icon: "plus") {
                    addManualModel()
                }
                .disabled(newModelName.isEmpty)
                .accessibilityIdentifier("addchannel.addModel")
            }
        }
        .accessibilityIdentifier("addchannel.modelsSection")
    }

    private func modelRow(model: ModelEntry, index: Int) -> some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            Text(model.identifier)
                .font(DesignToken.Font.caption())
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Metadata indicator
            if model.contextLength != nil || model.inputPricePer1M != nil {
                HStack(spacing: 2) {
                    if let ctx = model.contextLength {
                        Text(formatContext(ctx))
                            .font(DesignToken.Font.monoMicro())
                            .foregroundColor(DesignToken.Colors.textSecondary)
                    }
                    if let price = model.inputPricePer1M {
                        Text("$" + String(format: "%.1f", price))
                            .font(DesignToken.Font.monoMicro())
                            .foregroundColor(DesignToken.Colors.textSecondary)
                    }
                }
            }

            // Edit metadata button
            Button {
                editingModelIndex = index
                showingModelEditor = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignToken.Colors.textSecondary)
            .accessibilityIdentifier("addchannel.model.edit.\(index)")

            // Remove button
            Button {
                models.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignToken.Colors.textSecondary)
            .accessibilityIdentifier("addchannel.model.remove.\(index)")
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

        // Temporarily store key for fetch
        try? KeychainManager.shared.setAPIKey(apiKey, for: tempChannel.id)

        let fetchedModels = await channelManager.fetchModels(channel: tempChannel)

        // Clean up temp key
        try? KeychainManager.shared.removeAPIKey(for: tempChannel.id)

        if fetchedModels.isEmpty {
            errorMessage = L10n.Error.network("No models returned")
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
            Button(L10n.Onboarding.back) {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignToken.Colors.textSecondary)
            .accessibilityIdentifier("addchannel.cancel")

            Spacer()

            HoverButton(
                title: isSaving ? L10n.Status.saving : (editingChannel != nil ? L10n.Settings.channelsEdit : L10n.Onboarding.setup),
                icon: isSaving ? "ellipsis.circle.fill" : "checkmark.circle.fill"
            ) {
                Task { await saveChannel() }
            }
            .disabled(!isValid)
            .accessibilityIdentifier("addchannel.save")
        }
    }

    private var isValid: Bool {
        !name.isEmpty && !baseURL.isEmpty && !apiKey.isEmpty
    }

    private func saveChannel() async {
        guard isValid else { return }

        isSaving = true
        errorMessage = nil

        do {
            if let existingChannel = editingChannel {
                // Update existing channel
                var updated = existingChannel
                updated.name = name
                updated.baseURL = baseURL
                updated.protocol = selectedProtocol
                updated.priority = priority
                updated.models = models

                try KeychainManager.shared.setAPIKey(apiKey, for: existingChannel.id)
                channelStore.updateChannel(updated)
            } else {
                // Create new channel
                if let templateId = selectedProviderId {
                    if let channel = channelManager.createChannelFromTemplate(
                        templateId: templateId,
                        apiKey: apiKey
                    ) {
                        var finalChannel = channel
                        finalChannel.name = name.isEmpty ? channel.name : name
                        finalChannel.protocol = selectedProtocol
                        finalChannel.priority = priority
                        finalChannel.models = models.isEmpty ? channel.models : models

                        channelStore.addChannel(finalChannel)
                    } else {
                        errorMessage = L10n.Error.unknown
                    }
                } else {
                    // Create from scratch
                    let newChannel = Channel(
                        id: UUID().uuidString,
                        name: name,
                        baseURL: baseURL,
                        priority: priority,
                        protocol: selectedProtocol,
                        models: models
                    )

                    try KeychainManager.shared.setAPIKey(apiKey, for: newChannel.id)
                    channelStore.addChannel(newChannel)
                }
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
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
        _contextLength = State(initialValue: model.contextLength.map { "\($0)" } ?? "")
        _inputPrice = State(initialValue: model.inputPricePer1M.map { String(format: "%.2f", $0) } ?? "")
        _outputPrice = State(initialValue: model.outputPricePer1M.map { String(format: "%.2f", $0) } ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(model.identifier)
                    .font(DesignToken.Font.h3())

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
            .padding(.horizontal, DesignToken.Spacing.lg)
            .padding(.top, DesignToken.Spacing.md)
            .padding(.bottom, DesignToken.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignToken.Spacing.lg)

            // Form fields
            VStack(spacing: DesignToken.Spacing.lg) {
                // Context Length
                formRow(label: L10n.ModelEditor.contextLength) {
                    TextField("e.g. 128000", text: $contextLength)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("modelEditor.contextLength")
                }

                // Input Price
                formRow(label: L10n.ModelEditor.inputPrice) {
                    TextField("e.g. 5.00", text: $inputPrice)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("modelEditor.inputPrice")
                }

                // Output Price
                formRow(label: L10n.ModelEditor.outputPrice) {
                    TextField("e.g. 15.00", text: $outputPrice)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("modelEditor.outputPrice")
                }
            }
            .padding(DesignToken.Spacing.lg)

            Divider()
                .padding(.horizontal, DesignToken.Spacing.lg)

            // Footer
            HStack {
                Button(L10n.ModelEditor.cancel) {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignToken.Colors.textSecondary)

                Spacer()

                HoverButton(title: L10n.Status.saved, icon: "checkmark.circle.fill") {
                    save()
                }
                .accessibilityIdentifier("modelEditor.save")
            }
            .padding(DesignToken.Spacing.lg)
        }
        .frame(width: DesignToken.Layout.modelEditorWidth, height: DesignToken.Layout.modelEditorHeight)
    }

    private func formRow(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.xs) {
            Text(label)
                .font(DesignToken.Font.micro())
                .foregroundColor(DesignToken.Colors.textSecondary)

            content()
        }
    }

    private func save() {
        var updated = model
        updated.contextLength = Int(contextLength)
        updated.inputPricePer1M = Double(inputPrice)
        updated.outputPricePer1M = Double(outputPrice)
        onSave(updated)
    }
}

// MARK: - Preview

#Preview {
    AddChannelView()
}
