import Foundation

final class HTTPForwardingClient {
    enum Result {
        case success(data: Data, statusCode: Int, headers: [String: String])
        case failure(Error)
    }

    struct APIKeyForwardResult {
        let result: Result
        let apiKey: String
        let keyIndex: Int
    }

    private final class ResultBox: @unchecked Sendable {
        var data: Data?
        var statusCode = 200
        var headers: [String: String] = [:]
        var error: Error?
    }

    func forwardSync(
        url: URL,
        method: String = "POST",
        headers: [String: String],
        body: Data,
        timeout: TimeInterval,
        deadline: Date? = nil
    ) -> Result {
        let effectiveTimeout = min(timeout, deadline?.timeIntervalSinceNow ?? timeout)
        guard effectiveTimeout > 0 else {
            return .failure(URLError(.timedOut))
        }

        let resultBox = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        let task = Task {
            do {
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = method
                if !body.isEmpty {
                    urlRequest.httpBody = body
                }
                urlRequest.timeoutInterval = effectiveTimeout
                for (key, value) in headers {
                    urlRequest.setValue(value, forHTTPHeaderField: key)
                }

                let (responseData, urlResponse) = try await URLSession.shared.data(for: urlRequest)
                let httpResponse = urlResponse as? HTTPURLResponse

                let responseHeaders: [String: String] = (httpResponse?.allHeaderFields ?? [:])
                    .reduce(into: [:]) { dict, pair in
                        if let key = pair.key as? String, let value = pair.value as? String {
                            dict[key] = value
                        }
                    }

                resultBox.data = responseData
                resultBox.statusCode = httpResponse?.statusCode ?? 200
                resultBox.headers = responseHeaders
            } catch {
                resultBox.error = error
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + effectiveTimeout) == .timedOut {
            task.cancel()
            return .failure(URLError(.timedOut))
        }

        if let error = resultBox.error {
            return .failure(error)
        }

        guard let data = resultBox.data else {
            return .failure(NSError(
                domain: "HTTPForwardingClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No response data"]
            ))
        }

        return .success(data: data, statusCode: resultBox.statusCode, headers: resultBox.headers)
    }

    func forwardSyncWithAPIKeyFailover(
        url: URL,
        method: String = "POST",
        headers: [String: String],
        body: Data,
        timeout: TimeInterval,
        apiKeys: [String],
        targetProtocol: RequestForwarder.RequestProtocol,
        channelName: String,
        requestID: String,
        channelID: String? = nil,
        apiKeyAvailabilityStore: APIKeyAvailabilityStore? = nil,
        deadline: Date? = nil
    ) -> APIKeyForwardResult {
        let keys: [(index: Int, key: String)]
        if let channelID, let apiKeyAvailabilityStore {
            keys = apiKeyAvailabilityStore.availableKeys(for: channelID, apiKeys: apiKeys)
        } else {
            keys = apiKeys.enumerated().compactMap { index, key in
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedKey.isEmpty ? nil : (index, trimmedKey)
            }
        }
        guard let firstKey = keys.first else {
            return APIKeyForwardResult(
                result: .failure(NSError(
                    domain: "HTTPForwardingClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "No available API key"]
                )),
                apiKey: "",
                keyIndex: 0
            )
        }

        var lastResult: Result = .failure(NSError(
            domain: "HTTPForwardingClient",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "No request attempted"]
        ))
        var lastKey = firstKey.key
        var lastIndex = firstKey.index
        let requestDeadline = deadline ?? Date().addingTimeInterval(timeout)

        for (attemptIndex, keyEntry) in keys.enumerated() {
            let remainingTimeout = min(timeout, requestDeadline.timeIntervalSinceNow)
            guard remainingTimeout > 0 else {
                lastResult = .failure(URLError(.timedOut))
                break
            }

            let apiKey = keyEntry.key
            var keyedHeaders = headers
            ProxyEndpointSupport.setAuthHeaders(&keyedHeaders, apiKey: apiKey, protocol: targetProtocol)
            let result = forwardSync(
                url: url,
                method: method,
                headers: keyedHeaders,
                body: body,
                timeout: remainingTimeout,
                deadline: requestDeadline
            )

            lastResult = result
            lastKey = apiKey
            lastIndex = keyEntry.index

            if case let .success(data, statusCode, _) = result {
                if statusCode == 429,
                   let channelID,
                   let apiKeyAvailabilityStore {
                    let expiration = apiKeyAvailabilityStore.markRateLimited(
                        channelID: channelID,
                        apiKey: apiKey,
                        allAPIKeys: apiKeys
                    )
                    let until = expiration.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
                    Log.warn("[\(requestID)] \(channelName) API key #\(keyEntry.index + 1) rate-limited until \(until)")
                }

                if ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: statusCode, body: data),
                   let channelID,
                   let apiKeyAvailabilityStore {
                    apiKeyAvailabilityStore.markUnauthorized(channelID: channelID, apiKey: apiKey)
                    Log.warn("[\(requestID)] \(channelName) API key #\(keyEntry.index + 1) returned non-recoverable HTTP \(statusCode); marking unavailable for this app session")
                }

                if ProxyEndpointSupport.shouldRetryWithNextAPIKey(statusCode: statusCode, body: data),
                   attemptIndex < keys.count - 1 {
                    Log.warn("[\(requestID)] \(channelName) API key #\(keyEntry.index + 1) returned HTTP \(statusCode); retrying next key")
                    continue
                }
            }

            break
        }

        return APIKeyForwardResult(result: lastResult, apiKey: lastKey, keyIndex: lastIndex)
    }
}
