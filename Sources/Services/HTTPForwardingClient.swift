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
        timeout: TimeInterval
    ) -> Result {
        let resultBox = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = method
                if !body.isEmpty {
                    urlRequest.httpBody = body
                }
                urlRequest.timeoutInterval = timeout
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

        _ = semaphore.wait(timeout: .now() + timeout + 5)

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
        requestID: String
    ) -> APIKeyForwardResult {
        let keys = apiKeys.filter { !$0.isEmpty }
        guard let firstKey = keys.first else {
            return APIKeyForwardResult(
                result: .failure(NSError(
                    domain: "HTTPForwardingClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "No API key"]
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
        var lastKey = firstKey
        var lastIndex = 0

        for (index, apiKey) in keys.enumerated() {
            var keyedHeaders = headers
            ProxyEndpointSupport.setAuthHeaders(&keyedHeaders, apiKey: apiKey, protocol: targetProtocol)
            let result = forwardSync(
                url: url,
                method: method,
                headers: keyedHeaders,
                body: body,
                timeout: timeout
            )

            lastResult = result
            lastKey = apiKey
            lastIndex = index

            if case let .success(data, statusCode, _) = result,
               ProxyEndpointSupport.shouldRetryWithNextAPIKey(statusCode: statusCode, body: data),
               index < keys.count - 1 {
                Log.warn("[\(requestID)] \(channelName) API key #\(index + 1) returned HTTP \(statusCode); retrying next key")
                continue
            }

            break
        }

        return APIKeyForwardResult(result: lastResult, apiKey: lastKey, keyIndex: lastIndex)
    }
}
