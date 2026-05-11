import Foundation

/// Singleton service that manages an in-memory cache of aggregated models
/// from all configured upstream channels. Fetches lazily on first request
/// and merges results with deduplication by model identifier.
@MainActor
final class ModelAggregator {
    static let shared = ModelAggregator()

    /// In-memory cache of aggregated model entries, keyed by channel ID.
    private var cachedModels: [String: [ModelEntry]] = [:]

    /// Timestamp of the last successful fetch. Used for cache freshness checks.
    private var lastFetchDate: Date?

    /// Tracks whether the initial lazy fetch has been triggered.
    private var hasInitialized: Bool = false

    private init() {}

    // MARK: - Public API

    /// Fetches models from all channels, merges, deduplicates, and updates
    /// the ChannelStore. Triggers lazy loading on first call.
    /// Safe to call from any thread (bridges to MainActor internally).
    func fetchAllModelsIfNeeded() async {
        guard !hasInitialized else { return }
        hasInitialized = true

        await fetchAndMergeAllChannels()
    }

    /// Force-refresh models from all channels regardless of cache state.
    func refreshAllModels() async {
        await fetchAndMergeAllChannels()
    }

    /// Returns the aggregated, deduplicated list of all known model entries
    /// across all channels. Reads from the in-memory cache.
    func allModels() -> [ModelEntry] {
        var seen = Set<String>()
        var result: [ModelEntry] = []

        // Gather from cache first
        for models in cachedModels.values {
            for model in models {
                if !seen.contains(model.identifier) {
                    seen.insert(model.identifier)
                    result.append(model)
                }
            }
        }

        // Also include models stored directly in channels (from user config / templates)
        let channels = ChannelStore.shared.channels
        for channel in channels {
            for model in channel.models {
                if !seen.contains(model.identifier) {
                    seen.insert(model.identifier)
                    result.append(model)
                }
            }
        }

        return result
    }

    // MARK: - Internal

    /// Fetches models from every channel concurrently, merges results,
    /// and updates each channel's model list in ChannelStore.
    private func fetchAndMergeAllChannels() async {
        let channels = ChannelStore.shared.channels
        guard !channels.isEmpty else {
            Log.info("[ModelAggregator] No channels configured, skipping fetch")
            return
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

        // Merge results and update channels
        var allUniqueModels: [String: ModelEntry] = [:]
        var updatedChannels: [Channel] = []

        for (channel, models) in results {
            if !models.isEmpty {
                var updatedChannel = channel
                updatedChannel.models = models
                updatedChannels.append(updatedChannel)

                // Add to global dedup map
                for model in models {
                    if allUniqueModels[model.identifier] == nil {
                        allUniqueModels[model.identifier] = model
                    }
                }

                // Update cache
                cachedModels[channel.id] = models
                Log.info("[ModelAggregator] Channel '\(channel.name)': \(models.count) models fetched")
            } else {
                Log.warn("[ModelAggregator] Channel '\(channel.name)': no models returned")
            }
        }

        // Write updated models back to ChannelStore on MainActor
        for updatedChannel in updatedChannels {
            ChannelStore.shared.updateChannel(updatedChannel)
        }

        lastFetchDate = Date()

        let totalUnique = allUniqueModels.count
        Log.info("[ModelAggregator] Aggregation complete: \(totalUnique) unique models from \(updatedChannels.count) channels")
    }

    /// Fetches models from a single channel with appropriate auth headers
    /// and a 5-second timeout.
    private func fetchModelsForChannel(_ channel: Channel) async -> [ModelEntry] {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: channel.id),
              !apiKey.isEmpty
        else {
            Log.warn("[ModelAggregator] No API key for channel '\(channel.name)', skipping")
            return []
        }

        // Build the /v1/models URL
        let baseURL = channel.baseURL
        let modelsURL: URL? = if baseURL.hasSuffix("/v1") || baseURL.hasSuffix("/v1/") {
            URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models")
        } else {
            URL(string: baseURL + "/v1/models")
        }

        guard let url = modelsURL else {
            Log.warn("[ModelAggregator] Invalid URL for channel '\(channel.name)': \(baseURL)")
            return []
        }

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
                return []
            }

            return parseModelsResponse(data: data)
        } catch {
            Log.warn("[ModelAggregator] Fetch failed for '\(channel.name)': \(error.localizedDescription)")
            return []
        }
    }

    /// Parses an OpenAI-style /v1/models JSON response into ModelEntry objects.
    private func parseModelsResponse(data: Data) -> [ModelEntry] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelList = json["data"] as? [[String: Any]]
            else {
                Log.warn("[ModelAggregator] Invalid models response format")
                return []
            }

            return modelList.compactMap { modelDict -> ModelEntry? in
                guard let modelId = modelDict["id"] as? String else { return nil }

                return ModelEntry(
                    id: UUID().uuidString,
                    identifier: modelId,
                    displayName: modelId,
                    contextLength: nil,
                    inputPricePer1M: nil,
                    outputPricePer1M: nil,
                    isEnabled: true
                )
            }
        } catch {
            Log.warn("[ModelAggregator] Failed to parse models response: \(error.localizedDescription)")
            return []
        }
    }
}
