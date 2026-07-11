import Foundation
import Swifter

final class StreamingForwarder {
    struct Completion {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let keyIndex: Int
        let didWriteBody: Bool
        let error: Error?

        var isSuccess: Bool {
            error == nil && statusCode >= 200 && statusCode < 300
        }
    }

    private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private let writer: HttpResponseBodyWriter
        private let incomingProtocol: RequestForwarder.RequestProtocol
        private let upstreamProtocol: RequestForwarder.RequestProtocol
        private var parser = SSEParser()
        private var converter: OpenAIToAnthropicSSEConverter
        private var statusCode = 200
        private var headers: [String: String] = [:]
        private var errorBody = Data()
        private var wroteBody = false
        private var completed = false
        private var completionError: Error?

        init(
            writer: HttpResponseBodyWriter,
            incomingProtocol: RequestForwarder.RequestProtocol,
            upstreamProtocol: RequestForwarder.RequestProtocol,
            messageID: String,
            model: String
        ) {
            self.writer = writer
            self.incomingProtocol = incomingProtocol
            self.upstreamProtocol = upstreamProtocol
            self.converter = OpenAIToAnthropicSSEConverter(messageID: messageID, model: model)
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            if let httpResponse = response as? HTTPURLResponse {
                lock.lock()
                statusCode = httpResponse.statusCode
                headers = httpResponse.allHeaderFields.reduce(into: [:]) { dict, pair in
                    if let key = pair.key as? String, let value = pair.value as? String {
                        dict[key] = value
                    }
                }
                lock.unlock()
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            let currentStatus = statusCode
            lock.unlock()

            guard currentStatus >= 200 && currentStatus < 300 else {
                lock.lock()
                errorBody.append(data)
                lock.unlock()
                return
            }

            do {
                if incomingProtocol == .anthropic, upstreamProtocol == .openai {
                    for event in parser.parse(data) {
                        let converted = converter.convert(event: event)
                        if !converted.isEmpty {
                            try writer.write(Data(converted.utf8))
                            markWroteBody()
                        }
                    }
                } else {
                    try writer.write(data)
                    markWroteBody()
                }
            } catch {
                lock.lock()
                completionError = error
                lock.unlock()
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            if completionError == nil {
                completionError = error
            }
            let shouldFinishConvertedStream = completionError == nil
                && statusCode >= 200 && statusCode < 300
                && incomingProtocol == .anthropic
                && upstreamProtocol == .openai
            lock.unlock()

            if shouldFinishConvertedStream {
                let tail = converter.finishIfNeeded()
                if !tail.isEmpty {
                    do {
                        try writer.write(Data(tail.utf8))
                        markWroteBody()
                    } catch {
                        lock.lock()
                        completionError = error
                        lock.unlock()
                    }
                }
            }

            lock.lock()
            completed = true
            lock.unlock()
            semaphore.signal()
        }

        func wait(timeout: TimeInterval) -> Completion {
            let waitResult = semaphore.wait(timeout: .now() + timeout + 5)
            lock.lock()
            if waitResult == .timedOut, completionError == nil {
                completionError = NSError(
                    domain: "StreamingForwarder",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Streaming request timed out"]
                )
            }
            let completion = Completion(
                statusCode: statusCode,
                headers: headers,
                body: errorBody,
                keyIndex: 0,
                didWriteBody: wroteBody,
                error: completionError
            )
            lock.unlock()
            return completion
        }

        private func markWroteBody() {
            lock.lock()
            wroteBody = true
            lock.unlock()
        }
    }

    private let url: URL
    private let method: String
    private let headers: [String: String]
    private let body: Data
    private let timeout: TimeInterval
    private let apiKeys: [String]
    private let incomingProtocol: RequestForwarder.RequestProtocol
    private let upstreamProtocol: RequestForwarder.RequestProtocol
    private let channelName: String
    private let channelID: String?
    private let apiKeyAvailabilityStore: APIKeyAvailabilityStore?
    private let requestID: String
    private let model: String
    private let maxAPIKeyAttempts: Int

    init(
        url: URL,
        method: String = "POST",
        headers: [String: String],
        body: Data,
        timeout: TimeInterval,
        apiKeys: [String],
        incomingProtocol: RequestForwarder.RequestProtocol,
        upstreamProtocol: RequestForwarder.RequestProtocol,
        channelName: String,
        channelID: String? = nil,
        apiKeyAvailabilityStore: APIKeyAvailabilityStore? = nil,
        requestID: String,
        model: String,
        maxAPIKeyAttempts: Int = 3
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.apiKeys = apiKeys.filter { !$0.isEmpty }
        self.incomingProtocol = incomingProtocol
        self.upstreamProtocol = upstreamProtocol
        self.channelName = channelName
        self.channelID = channelID
        self.apiKeyAvailabilityStore = apiKeyAvailabilityStore
        self.requestID = requestID
        self.model = model
        self.maxAPIKeyAttempts = max(1, maxAPIKeyAttempts)
    }

    func stream(to writer: HttpResponseBodyWriter, writesErrorOnFailure: Bool = true) -> Completion {
        let availableKeys: [(index: Int, key: String)]
        if let channelID, let apiKeyAvailabilityStore {
            availableKeys = apiKeyAvailabilityStore.availableKeys(for: channelID, apiKeys: apiKeys)
        } else {
            availableKeys = apiKeys.enumerated().compactMap { index, key in
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedKey.isEmpty ? nil : (index, trimmedKey)
            }
        }

        guard !availableKeys.isEmpty else {
            if writesErrorOnFailure {
                writeError("No available API key", to: writer)
            }
            return Completion(statusCode: 502, headers: [:], body: Data(), keyIndex: 0, didWriteBody: writesErrorOnFailure, error: nil)
        }

        var lastCompletion = Completion(statusCode: 502, headers: [:], body: Data(), keyIndex: 0, didWriteBody: false, error: nil)
        let attempts = Array(availableKeys.prefix(maxAPIKeyAttempts))

        for (attemptIndex, keyEntry) in attempts.enumerated() {
            let apiKey = keyEntry.key
            var keyedHeaders = headers
            ProxyEndpointSupport.setAuthHeaders(&keyedHeaders, apiKey: apiKey, protocol: upstreamProtocol)

            let delegate = StreamDelegate(
                writer: writer,
                incomingProtocol: incomingProtocol,
                upstreamProtocol: upstreamProtocol,
                messageID: "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
                model: model
            )
            let session = URLSession(configuration: streamingConfiguration(), delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request(headers: keyedHeaders))
            task.resume()

            var completion = delegate.wait(timeout: timeout)
            session.invalidateAndCancel()
            completion = Completion(
                statusCode: completion.statusCode,
                headers: completion.headers,
                body: completion.body,
                keyIndex: keyEntry.index,
                didWriteBody: completion.didWriteBody,
                error: completion.error
            )
            lastCompletion = completion

            if completion.didWriteBody || completion.isSuccess {
                return completion
            }

            if ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: completion.statusCode, body: completion.body),
               let channelID,
               let apiKeyAvailabilityStore {
                apiKeyAvailabilityStore.markUnauthorized(channelID: channelID, apiKey: apiKey)
                Log.warn("[\(requestID)] \(channelName) streaming API key #\(keyEntry.index + 1) returned non-recoverable HTTP \(completion.statusCode); marking unavailable for this app session")
            }

            if ProxyEndpointSupport.shouldRetryWithNextAPIKey(statusCode: completion.statusCode, body: completion.body),
               attemptIndex < attempts.count - 1 {
                Log.warn("[\(requestID)] \(channelName) streaming API key #\(keyEntry.index + 1) returned HTTP \(completion.statusCode); retrying next key")
                continue
            }

            break
        }

        let message = Self.errorMessage(from: lastCompletion)
        if writesErrorOnFailure {
            writeError(message, to: writer)
        }
        return Completion(
            statusCode: lastCompletion.statusCode,
            headers: lastCompletion.headers,
            body: lastCompletion.body,
            keyIndex: lastCompletion.keyIndex,
            didWriteBody: writesErrorOnFailure,
            error: lastCompletion.error
        )
    }

    private func request(headers: [String: String]) -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = timeout
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        return urlRequest
    }

    private func streamingConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return configuration
    }

    static func errorMessage(from completion: Completion) -> String {
        if let error = completion.error {
            return error.localizedDescription
        }

        if let json = try? JSONSerialization.jsonObject(with: completion.body) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let text = String(data: completion.body, encoding: .utf8), !text.isEmpty {
            return String(text.prefix(500))
        }

        return "Upstream streaming request failed with HTTP \(completion.statusCode)"
    }

    static func writeErrorEvent(_ message: String, requestID: String, to writer: HttpResponseBodyWriter) {
        let object: [String: Any] = [
            "type": "error",
            "error": [
                "type": "api_error",
                "message": message,
            ],
        ]
        let jsonData = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        let json = String(data: jsonData, encoding: .utf8) ?? "{\"type\":\"error\"}"
        let event = SSEEncoder.encode(event: "error", data: json)

        do {
            try writer.write(Data(event.utf8))
        } catch {
            Log.error("[\(requestID)] Failed to write streaming error: \(error.localizedDescription)")
        }
    }

    private func writeError(_ message: String, to writer: HttpResponseBodyWriter) {
        Self.writeErrorEvent(message, requestID: requestID, to: writer)
    }
}
