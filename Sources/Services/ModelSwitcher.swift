import Foundation
import SwiftUI

/// Protocol compatibility for model switching
enum ModelProtocolCompatibility: String, Codable, CaseIterable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"

    /// Check if this protocol is compatible with a given channel protocol
    /// The proxy can convert between protocols, so we check converter support
    func isCompatibleWith(channelProtocol: APIProtocol) -> Bool {
        switch (self, channelProtocol) {
        case (_, .auto):
            // Auto channel can handle anything
            return true
        case (.openai, .openai), (.anthropic, .anthropic):
            // Direct match
            return true
        case (.openai, .anthropic), (.anthropic, .openai):
            // Proxy can convert between these protocols
            return true
        }
    }
}

/// Service managing the active model selection
@MainActor
final class ModelSwitcher: ObservableObject {
    private let selectedModelKey = "smartllm_selected_model"
    private let channelServices: ChannelServices
    private let modelOverrideState: ModelOverrideRuntimeState
    private let defaults: UserDefaults

    /// Currently selected model ID. Nil means "Default/Passthrough".
    @Published var selectedModelID: String? {
        didSet {
            saveSelection()
            modelOverrideState.update(selectedModelID: selectedModelID)
        }
    }

    /// Whether a non-default model is selected
    var hasOverride: Bool {
        selectedModelID != nil
    }

    /// Display name for the current selection
    var displayName: String {
        guard let id = selectedModelID else {
            return L10n.Model.defaultPassthrough
        }
        // Look up across all channels (model may live on any channel)
        if let model = Self.anyModelMatches(modelID: id, in: allAvailableModels) {
            return model.displayName
        }
        // Fallback: return the ID
        return id
    }

    /// List of models available on the active channel
    var availableModels: [ModelEntry] {
        guard let channel = channelServices.activeChannel else {
            return []
        }
        return channel.models.filter { $0.isEnabled }
    }

    /// List of all models across all channels (for global mode)
    var allAvailableModels: [ModelEntry] {
        let channels = channelServices.enabledChannels
        var seen = Set<String>()
        var result: [ModelEntry] = []

        for channel in channels.sorted(by: { $0.priority < $1.priority }) {
            for model in channel.models where model.isEnabled && !seen.contains(model.identifier) {
                seen.insert(model.identifier)
                result.append(model)
            }
        }
        return result
    }

    /// Models available for the model selector dropdown.
    /// Aggregates models from ALL channels (deduped by identifier, sorted by channel priority).
    /// SmartRouter handles routing to the right channel automatically.
    var compatibleModels: [ModelEntry] {
        allAvailableModels
    }

    init(
        channelServices: ChannelServices,
        modelOverrideState: ModelOverrideRuntimeState = ModelOverrideRuntimeState(),
        defaults: UserDefaults = .standard
    ) {
        self.channelServices = channelServices
        self.modelOverrideState = modelOverrideState
        self.defaults = defaults
        selectedModelID = defaults.string(forKey: selectedModelKey)
        if selectedModelID == "Default" || selectedModelID?.isEmpty == true {
            selectedModelID = nil
        }
        modelOverrideState.update(selectedModelID: selectedModelID)

        // Validate that the stored model still exists on any channel
        if let modelID = selectedModelID {
            let exists = channelServices.enabledChannels.contains { channel in
                channel.models.contains { $0.isEnabled && Self.modelMatches(requested: modelID, stored: $0.identifier) }
            }
            if !exists {
                selectedModelID = nil
            }
        }
    }

    /// Select a model by identifier
    func selectModel(_ modelID: String?) {
        selectedModelID = modelID
    }

    /// Reset to default passthrough
    func resetToDefault() {
        selectedModelID = nil
    }

    /// Clears the selection if it no longer exists on an enabled channel.
    func validateSelection() {
        guard let modelID = selectedModelID else {
            return
        }

        let exists = channelServices.enabledChannels.contains { channel in
            channel.models.contains { $0.isEnabled && Self.modelMatches(requested: modelID, stored: $0.identifier) }
        }
        if !exists {
            selectedModelID = nil
        }
    }

    // MARK: - Persistence

    private func saveSelection() {
        if let id = selectedModelID {
            defaults.set(id, forKey: selectedModelKey)
        } else {
            defaults.removeObject(forKey: selectedModelKey)
        }
    }

    // MARK: - Model Name Matching

    /// Flexible model name matching that handles aggregated provider prefixes.
    /// e.g. "z-ai/glm-5.1" matches "glm-5.1" and vice versa.
    nonisolated static func modelMatches(requested: String, stored: String) -> Bool {
        // Exact match
        if requested == stored { return true }

        // Strip prefix: "z-ai/glm-5.1" → "glm-5.1"
        let requestedBase = requested.split(separator: "/").last.map(String.init) ?? requested
        let storedBase = stored.split(separator: "/").last.map(String.init) ?? stored

        return requestedBase == storedBase
    }

    /// Check if a model identifier matches any model in the collection
    static func anyModelMatches(modelID: String, in models: [ModelEntry]) -> ModelEntry? {
        models.first { modelMatches(requested: modelID, stored: $0.identifier) }
    }

    // MARK: - Protocol Validation

    /// Validate if a model can be used with the current routing context
    /// Returns true if the model is compatible with the active channel
    func isModelCompatible(_ modelID: String, with channel: Channel) -> Bool {
        channel.models.contains { Self.modelMatches(requested: modelID, stored: $0.identifier) }
    }

    /// Get the protocol required for a given model on a channel
    func getProtocolForModel(_ modelID: String, on channel: Channel) -> APIProtocol? {
        guard channel.models.contains(where: { Self.modelMatches(requested: modelID, stored: $0.identifier) }) else {
            return nil
        }
        return channel.protocol
    }
}
