import Foundation
import Swifter

@MainActor
final class ModelEndpointHandler {
    private let services: RouterServices
    private let modelAggregator: any ModelAggregating
    private let initialFetchTimeout: TimeInterval

    init(
        services: RouterServices,
        modelAggregator: (any ModelAggregating)? = nil,
        initialFetchTimeout: TimeInterval = 8
    ) {
        self.services = services
        self.modelAggregator = modelAggregator ?? services.modelAggregator
        self.initialFetchTimeout = initialFetchTimeout
    }

    func handleListModels() -> HttpResponse {
        // Fast path: If we have cached models, return them immediately.
        if modelAggregator.hasCachedModels() {
            let models = modelAggregator.allModels()
            return HttpResponse.ok(.json([
                "object": "list",
                "data": models.map { modelJSON(for: $0.identifier, ownedBy: "aggregated") }
            ]))
        }

        // First request path: Block and wait for the fetch to complete.
        // We use a semaphore to bridge the async fetch into this sync handler.
        // Timeout is set to 8s (5s request timeout + 3s processing buffer).
        let fetchResult = InitialModelFetchResult()
        Task.detached { [modelAggregator, fetchResult] in
            fetchResult.complete(await modelAggregator.fetchAllModelsIfNeeded())
        }

        // Wait for the fetch to finish, but don't wait forever.
        let fetchSucceeded = fetchResult.wait(timeout: initialFetchTimeout)

        if fetchSucceeded == true {
            let models = modelAggregator.allModels()
            return HttpResponse.ok(.json([
                "object": "list",
                "data": models.map { modelJSON(for: $0.identifier, ownedBy: "aggregated") }
            ]))
        }

        // Fallback path: Timeout or fetch failed.
        // Return whatever static models we have in ChannelStore to avoid empty response.
        Log.warn("[Proxy] /v1/models fetch timed out or failed, returning fallback models")
        var fallbackModels: [[String: Any]] = []
        for channel in services.runtimeState.enabledChannelsSnapshot() {
            for model in channel.models where model.isEnabled {
                fallbackModels.append(modelJSON(for: model.identifier, ownedBy: channel.name))
            }
        }

        return HttpResponse.ok(.json(["object": "list", "data": fallbackModels]))
    }

    func handleSingleModel(modelId: String?) -> HttpResponse {
        guard let modelId else {
            return errorResponse(400, "Missing model ID")
        }

        var foundModel: ModelEntry?
        var foundChannelName = "unknown"

        if modelAggregator.hasCachedModels() {
            let models = modelAggregator.allModels()
            foundModel = models.first { ModelSwitcher.modelMatches(requested: modelId, stored: $0.identifier) }
            if foundModel != nil {
                foundChannelName = ownerName(for: modelId) ?? foundChannelName
                if let foundModel {
                    return HttpResponse.ok(.json(modelJSON(for: foundModel.identifier, ownedBy: foundChannelName)))
                }
            }
        }

        for channel in services.runtimeState.enabledChannelsSnapshot() {
            if let model = channel.models.first(where: { $0.isEnabled && ModelSwitcher.modelMatches(requested: modelId, stored: $0.identifier) }) {
                foundModel = model
                foundChannelName = channel.name
                break
            }
        }

        guard let model = foundModel else {
            return errorResponse(404, "Model '\(modelId)' not found")
        }

        return HttpResponse.ok(.json(modelJSON(for: model.identifier, ownedBy: foundChannelName)))
    }

    private func ownerName(for modelId: String) -> String? {
        for channel in services.runtimeState.enabledChannelsSnapshot()
            where channel.models.contains(where: { $0.isEnabled && ModelSwitcher.modelMatches(requested: modelId, stored: $0.identifier) }) {
            return channel.name
        }
        return nil
    }

    private func modelJSON(for modelId: String, ownedBy: String) -> [String: Any] {
        [
            "id": modelId,
            "object": "model",
            "created": Int(Date().timeIntervalSince1970),
            "owned_by": ownedBy
        ]
    }

    private func errorResponse(_ statusCode: Int, _ message: String) -> HttpResponse {
        ProxyEndpointSupport.errorResponse(statusCode, message)
    }
}

private final class InitialModelFetchResult: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var succeeded = false

    func complete(_ succeeded: Bool) {
        lock.lock()
        self.succeeded = succeeded
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> Bool? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }
        return succeeded
    }
}
