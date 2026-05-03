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

/// Singleton service managing the active model selection
@MainActor
final class ModelSwitcher: ObservableObject {
    static let shared = ModelSwitcher()

    private let selectedModelKey = "smartllm_selected_model"

    /// Currently selected model ID. Nil means "Default/Passthrough".
    @Published var selectedModelID: String? {
        didSet {
            saveSelection()
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
        // Look up the display name from active channel models
        if let channel = ChannelStore.shared.activeChannel,
           let model = channel.models.first(where: { $0.identifier == id })
        {
            return model.displayName
        }
        // Fallback: return the ID
        return id
    }

    /// List of models available on the active channel
    var availableModels: [ModelEntry] {
        guard let channel = ChannelStore.shared.activeChannel else {
            return []
        }
        return channel.models.filter { $0.isEnabled }
    }

    /// List of all models across all channels (for global mode)
    var allAvailableModels: [ModelEntry] {
        let channels = ChannelStore.shared.channels
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

    /// Models compatible with the current client protocol context.
    /// For Phase 5, since the proxy handles protocol conversion between
    /// Anthropic and OpenAI, all models on the active channel are compatible.
    var compatibleModels: [ModelEntry] {
        guard let channel = ChannelStore.shared.activeChannel else {
            return []
        }

        // If channel protocol is auto, all models are available
        if channel.protocol == .auto {
            return availableModels
        }

        // Otherwise, filter to models compatible with the channel's protocol
        // Since proxy handles conversion, all channel models are compatible
        return availableModels
    }

    private init() {
        selectedModelID = UserDefaults.standard.string(forKey: selectedModelKey)
        if selectedModelID == "Default" || selectedModelID == "" {
            selectedModelID = nil
        }

        // Validate that the stored model still exists on the active channel
        if let modelID = selectedModelID {
            let exists = ChannelStore.shared.activeChannel?.models.contains { $0.identifier == modelID } ?? false
            if !exists {
                // Model no longer available, reset to default
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

    // MARK: - Persistence

    private func saveSelection() {
        if let id = selectedModelID {
            UserDefaults.standard.set(id, forKey: selectedModelKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedModelKey)
        }
    }

    // MARK: - Protocol Validation

    /// Validate if a model can be used with the current routing context
    /// Returns true if the model is compatible with the active channel
    func isModelCompatible(_ modelID: String, with channel: Channel) -> Bool {
        // Check if model exists on the channel
        guard channel.models.contains(where: { $0.identifier == modelID }) else {
            return false
        }
        return true
    }

    /// Get the protocol required for a given model on a channel
    func getProtocolForModel(_ modelID: String, on channel: Channel) -> APIProtocol? {
        guard channel.models.contains(where: { $0.identifier == modelID }) else {
            return nil
        }
        return channel.protocol
    }
}
