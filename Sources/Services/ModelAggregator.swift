import Foundation

protocol ModelAggregating: AnyObject, Sendable {
    func fetchAllModelsIfNeeded() async -> Bool
    func allModels() -> [ModelEntry]
    func hasCachedModels() -> Bool
}

/// Service that manages an in-memory cache of aggregated models
/// from all configured upstream channels. Fetches lazily on first request
/// and merges results with deduplication by model identifier.
/// NOTE: This class is NOT @MainActor. Network requests run in the background.
/// Only updates to ChannelStore happen on MainActor.
final class ModelAggregator: ModelAggregating, @unchecked Sendable {
    private let channelServices: ChannelServices

    /// In-memory cache of aggregated model entries, keyed by channel ID.
    private var cachedModels: [String: [ModelEntry]] = [:]

    /// Tracks whether the initial lazy fetch has been triggered.
    private var hasInitialized: Bool = false
    
    /// Lock to protect `hasInitialized` and `cachedModels` access.
    private let lock = NSLock()

    @MainActor
    init(channelServices: ChannelServices) {
        self.channelServices = channelServices
    }

    // MARK: - Public API

    /// Fetches models from all channels, merges, deduplicates, and updates
    /// the ChannelStore. Triggers lazy loading on first call.
    /// This is an async function and should be called from a background context or Task.
    func fetchAllModelsIfNeeded() async -> Bool {
        let shouldFetch = markInitializedIfNeeded()

        guard shouldFetch else { return hasCachedModels() }

        return await fetchAndMergeAllChannels()
    }

    /// Force-refresh models from all channels regardless of cache state.
    func refreshAllModels() async {
        _ = await fetchAndMergeAllChannels()
    }

    /// Clears cached aggregation so the next request reflects current channel state.
    func invalidateCache() {
        lock.lock()
        cachedModels = [:]
        hasInitialized = false
        lock.unlock()
    }

    /// Returns the aggregated, deduplicated list of all known model entries
    /// across all channels. Reads from the in-memory cache.
    /// Thread-safe.
    func allModels() -> [ModelEntry] {
        lock.lock()
        let cacheSnapshot = cachedModels
        lock.unlock()

        var seen = Set<String>()
        var result: [ModelEntry] = []

        // Gather from cache first
        for models in cacheSnapshot.values {
            for model in models where model.isEnabled {
                if !seen.contains(model.identifier) {
                    seen.insert(model.identifier)
                    result.append(model)
                }
            }
        }

        return result
    }
    
    /// Checks if we have any cached models.
    func hasCachedModels() -> Bool {
        lock.lock()
        let isEmpty = cachedModels.isEmpty
        lock.unlock()
        return !isEmpty
    }

    // MARK: - Internal

    /// Fetches models from every channel concurrently, merges results,
    /// and updates each channel's model list in ChannelStore.
    private func fetchAndMergeAllChannels() async -> Bool {
        let channels = await MainActor.run {
            return self.channelServices.enabledChannels
        }
        
        guard !channels.isEmpty else {
            Log.info("[ModelAggregator] No channels configured, skipping fetch")
            return false
        }

        Log.info("[ModelAggregator] Fetching models from \(channels.count) channels")

        // Fetch from all channels concurrently with 5s timeout each
        let results = await withTaskGroup(of: (Channel, [ModelEntry]).self) { group in
            for channel in channels {
                group.addTask {
                    let models = await self.fetchModelsForChannel(channel)
                    return (channel, models)
                }
            }

            var channelResults: [(Channel, [ModelEntry])] = []
            for await result in group {
                channelResults.append(result)
            }
            return channelResults
        }

        // Merge results and prepare updates
        var allUniqueModels: [String: ModelEntry] = [:]
        var updates: [(id: String, models: [ModelEntry])] = []

        for (channel, models) in results {
            if !models.isEmpty {
                updates.append((id: channel.id, models: models))

                // Add to global dedup map
                for model in models {
                    if allUniqueModels[model.identifier] == nil {
                        allUniqueModels[model.identifier] = model
                    }
                }

                cache(models, for: channel.id)
                
                Log.info("[ModelAggregator] Channel '\(channel.name)': \(models.count) models fetched")
            } else {
                Log.warn("[ModelAggregator] Channel '\(channel.name)': no models returned")
            }
        }

        // Write updated models back to ChannelStore on MainActor
        // Create a local copy to avoid capturing mutable 'updates' across actor boundary
        let finalUpdates = updates
        await MainActor.run {
            for update in finalUpdates {
                self.channelServices.updateModels(update.models, for: update.id)
            }
            self.channelServices.saveChannels()
        }

        let totalUnique = allUniqueModels.count
        Log.info("[ModelAggregator] Aggregation complete: \(totalUnique) unique models from \(updates.count) channels")
        return !updates.isEmpty
    }

    private func markInitializedIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !hasInitialized else { return false }
        hasInitialized = true
        return true
    }

    private func cache(_ models: [ModelEntry], for channelID: String) {
        lock.lock()
        defer { lock.unlock() }

        cachedModels[channelID] = models
    }

    /// Fetches models from a single channel with appropriate auth headers
    /// and a 5-second timeout.
    private func fetchModelsForChannel(_ channel: Channel) async -> [ModelEntry] {
        let apiKeys = await MainActor.run {
            self.channelServices.apiKeys(for: channel.id)
        }
        
        guard !apiKeys.isEmpty else {
            Log.warn("[ModelAggregator] No API key for channel '\(channel.name)', skipping")
            return []
        }

        // Build the models URL
        let baseURL = channel.baseURL
        let modelsURL = URLBuilder.buildModelsURL(baseURL: baseURL)

        guard let url = modelsURL else {
            Log.warn("[ModelAggregator] Invalid URL for channel '\(channel.name)': \(baseURL)")
            return []
        }

        for (index, apiKey) in apiKeys.enumerated() {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5 // 5s timeout per channel

            // Set auth headers based on channel protocol
            switch channel.protocol {
            case .anthropic:
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            case .openai, .auto:
                // Both OpenAI and Auto channels use Bearer auth for /v1/models
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200
                else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "nil"
                    Log.warn("[ModelAggregator] HTTP \(statusCode) from '\(channel.name)': \(bodyPreview)")
                    if ProxyEndpointSupport.shouldRetryWithNextAPIKey(statusCode: statusCode, body: data),
                       index < apiKeys.count - 1 {
                        Log.warn("[ModelAggregator] API key #\(index + 1) failed for '\(channel.name)', trying next key")
                        continue
                    }
                    return []
                }

                return parseModelsResponse(data: data)
            } catch {
                Log.warn("[ModelAggregator] Fetch failed for '\(channel.name)': \(error.localizedDescription)")
                return []
            }
        }

        return []
    }

    /// Parses an OpenAI-style /v1/models JSON response into ModelEntry objects.
    /// Fallback parsing for non-standard responses.
    private func parseModelsResponse(data: Data) -> [ModelEntry] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }
            
            var modelList: [[String: Any]] = []
            
            // Standard OpenAI format
            if let list = json["data"] as? [[String: Any]] {
                modelList = list
            } 
            // Google/Other format (sometimes uses "models" array)
            else if let list = json["models"] as? [[String: Any]] {
                // Transform to match OpenAI structure
                modelList = list.map { model in
                    var transformed = model
                    if let name = model["name"] as? String {
                        transformed["id"] = name.replacingOccurrences(of: "models/", with: "")
                    }
                    return transformed
                }
            }
            
            guard !modelList.isEmpty else {
                return []
            }

            return modelList.compactMap { modelDict -> ModelEntry? in
                // Try "id" first, then "name" (some proxies return name)
                let modelId = (modelDict["id"] as? String) ?? (modelDict["name"] as? String)
                guard let id = modelId else { return nil }

                // Extract context_length
                let contextLength = modelDict["context_length"] as? Int

                // Extract pricing
                let pricing = modelDict["pricing"] as? [String: Any]
                let inputPrice = Self.parsePricingValue(pricing?["prompt"])
                let outputPrice = Self.parsePricingValue(pricing?["completion"])

                // Extract input_modalities → inputTypes
                // Check both top-level and architecture.input_modalities (OpenRouter format)
                let inputTypes: [String]
                if let topLevelModalities = modelDict["input_modalities"] {
                    inputTypes = Self.parseInputTypes(from: topLevelModalities)
                } else if let architecture = modelDict["architecture"] as? [String: Any],
                          let archModalities = architecture["input_modalities"] {
                    inputTypes = Self.parseInputTypes(from: archModalities)
                } else {
                    inputTypes = ["text"]
                }

                return ModelEntry(
                    id: UUID().uuidString,
                    identifier: id,
                    displayName: modelDict["name"] as? String ?? id,
                    contextLength: contextLength,
                    inputPricePer1M: inputPrice,
                    outputPricePer1M: outputPrice,
                    isEnabled: true,
                    inputTypes: inputTypes
                )
            }
        } catch {
            Log.warn("[ModelAggregator] Failed to parse models response: \(error.localizedDescription)")
            return []
        }
    }

    /// Parse input_modalities array from API response into inputTypes
    private static func parseInputTypes(from value: Any?) -> [String] {
        guard let modalities = value as? [String] else {
            return ["text"]
        }

        let validTypes = modalities.compactMap { modality -> String? in
            switch modality {
            case "text", "image", "video", "audio":
                return modality
            default:
                return nil
            }
        }

        return validTypes.isEmpty ? ["text"] : validTypes
    }

    /// Parse pricing value (string or number) to Double
    private static func parsePricingValue(_ value: Any?) -> Double? {
        if let str = value as? String {
            return Double(str)
        }
        if let num = value as? Double {
            return num
        }
        if let num = value as? Int {
            return Double(num)
        }
        return nil
    }
}
