import Foundation
import Swifter

final class StreamingForwarder {
    struct Completion {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let keyIndex: Int
        let didWriteBody: Bool
        let didWriteKeepalive: Bool
        let error: Error?
        let inputTokens: Int
        let outputTokens: Int
        let responseHeaderLatency: TimeInterval?
        let timeToFirstByte: TimeInterval?
        let clientDisconnected: Bool
        let requiresTerminalEvent: Bool
        let hasTerminalEvent: Bool
        let didSynthesizeTerminalEvent: Bool

        var isSuccess: Bool {
            error == nil
                && statusCode >= 200
                && statusCode < 300
                && didWriteBody
                && (!requiresTerminalEvent || hasTerminalEvent)
        }

        var isTimeout: Bool {
            guard let error else { return false }
            let nsError = error as NSError
            return (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut)
                || error.localizedDescription.localizedCaseInsensitiveContains("timed out")
                || error.localizedDescription.localizedCaseInsensitiveContains("budget exhausted")
        }
    }

    private final class SynchronizedWriter: @unchecked Sendable {
        private let lock = NSLock()
        private let writer: HttpResponseBodyWriter

        init(_ writer: HttpResponseBodyWriter) {
            self.writer = writer
        }

        func write(_ data: Data) throws {
            lock.lock()
            defer { lock.unlock() }
            try writer.write(data)
        }
    }

    private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private let writer: SynchronizedWriter
        private let incomingProtocol: RequestForwarder.RequestProtocol
        private let upstreamProtocol: RequestForwarder.RequestProtocol
        private var parser = SSEParser()
        private var usageParser = SSEParser()
        private var converter: OpenAIToAnthropicSSEConverter
        private var statusCode = 200
        private var headers: [String: String] = [:]
        private var errorBody = Data()
        private var wroteBody = false
        private var wroteKeepalive = false
        private var completed = false
        private var completionError: Error?
        private var capturedInputTokens = 0
        private var capturedOutputTokens = 0
        private var responseHeaderLatency: TimeInterval?
        private var timeToFirstByte: TimeInterval?
        private var clientDisconnected = false
        private var sawTerminalEvent = false
        private var synthesizedTerminalEvent = false
        private let startedAt = Date()

        init(
            writer: SynchronizedWriter,
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
                responseHeaderLatency = Date().timeIntervalSince(startedAt)
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

            // Parse SSE events for usage extraction (non-destructive, separate parser)
            for event in usageParser.parse(data) {
                extractUsage(from: event.data)
                if event.event == "message_stop" || event.data.contains(#""type":"message_stop""#) {
                    lock.lock()
                    sawTerminalEvent = true
                    lock.unlock()
                }
            }

            do {
                if incomingProtocol == .anthropic, upstreamProtocol == .openai {
                    for event in parser.parse(data) {
                        let converted = converter.convert(event: event)
                        if !converted.isEmpty {
                            try writeBody(Data(converted.utf8))
                            markWroteBody()
                            if converted.contains("event: message_stop")
                                || converted.contains(#""type":"message_stop""#) {
                                markTerminalEvent(synthesized: false)
                            }
                        }
                    }
                } else {
                    try writeBody(data)
                    markWroteBody()
                }
            } catch {
                lock.lock()
                completionError = error
                clientDisconnected = true
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
            let shouldFinishAnthropicStream = completionError == nil
                && statusCode >= 200 && statusCode < 300
                && wroteBody
                && incomingProtocol == .anthropic
                && upstreamProtocol == .anthropic
                && !sawTerminalEvent
            lock.unlock()

            if shouldFinishConvertedStream {
                let tail = converter.finishIfNeeded()
                if !tail.isEmpty {
                    do {
                        try writeBody(Data(tail.utf8))
                        markWroteBody()
                        markTerminalEvent(synthesized: true)
                    } catch {
                        lock.lock()
                        completionError = error
                        clientDisconnected = true
                        lock.unlock()
                    }
                }
            }

            if shouldFinishAnthropicStream {
                let messageStop = SSEEncoder.encode(
                    event: "message_stop",
                    data: #"{"type":"message_stop"}"#
                )
                do {
                    try writeBody(Data(messageStop.utf8))
                    markWroteBody()
                    markTerminalEvent(synthesized: true)
                    Log.warn("Synthesized missing Anthropic message_stop event after clean upstream close")
                } catch {
                    lock.lock()
                    completionError = error
                    clientDisconnected = true
                    lock.unlock()
                }
            }

            lock.lock()
            completed = true
            lock.unlock()
            semaphore.signal()
        }

        func wait(
            firstByteTimeout: TimeInterval,
            streamTimeout: TimeInterval,
            requestDeadline: Date,
            keepaliveInterval: TimeInterval,
            requestID: String
        ) -> Completion {
            let firstByteDeadline = min(requestDeadline, Date().addingTimeInterval(firstByteTimeout))
            let streamDeadline = Date().addingTimeInterval(streamTimeout)

            while true {
                lock.lock()
                let hasBody = wroteBody
                let hasCompleted = completed
                let currentError = completionError
                lock.unlock()

                if hasCompleted || currentError != nil {
                    break
                }

                let deadline = hasBody ? streamDeadline : firstByteDeadline
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 {
                    lock.lock()
                    if completionError == nil {
                        let message = hasBody ? "Streaming request timed out" : "Upstream first byte timed out"
                        completionError = NSError(
                            domain: "StreamingForwarder",
                            code: hasBody ? -2 : -1,
                            userInfo: [NSLocalizedDescriptionKey: message]
                        )
                    }
                    lock.unlock()
                    break
                }

                let pollInterval = hasBody ? remaining : min(keepaliveInterval, remaining)
                if semaphore.wait(timeout: .now() + pollInterval) == .success {
                    break
                }

                if !hasBody, pollInterval >= keepaliveInterval - 0.001 {
                    do {
                        try writer.write(Data(": keep-alive\n\n".utf8))
                        lock.lock()
                        wroteKeepalive = true
                        lock.unlock()
                        Log.info("[\(requestID)] Sent SSE keepalive while waiting for upstream first byte")
                    } catch {
                        lock.lock()
                        completionError = error
                        clientDisconnected = true
                        lock.unlock()
                        break
                    }
                }
            }

            lock.lock()
            let completion = Completion(
                statusCode: statusCode,
                headers: headers,
                body: errorBody,
                keyIndex: 0,
                didWriteBody: wroteBody,
                didWriteKeepalive: wroteKeepalive,
                error: completionError,
                inputTokens: capturedInputTokens,
                outputTokens: capturedOutputTokens,
                responseHeaderLatency: responseHeaderLatency,
                timeToFirstByte: timeToFirstByte,
                clientDisconnected: clientDisconnected,
                requiresTerminalEvent: incomingProtocol == .anthropic,
                hasTerminalEvent: sawTerminalEvent,
                didSynthesizeTerminalEvent: synthesizedTerminalEvent
            )
            lock.unlock()
            return completion
        }

        private func markWroteBody() {
            lock.lock()
            wroteBody = true
            if timeToFirstByte == nil {
                timeToFirstByte = Date().timeIntervalSince(startedAt)
            }
            lock.unlock()
        }

        private func writeBody(_ data: Data) throws {
            try writer.write(data)
        }

        private func markTerminalEvent(synthesized: Bool) {
            lock.lock()
            sawTerminalEvent = true
            synthesizedTerminalEvent = synthesizedTerminalEvent || synthesized
            lock.unlock()
        }

        private func extractUsage(from data: String) {
            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return }

            if upstreamProtocol == .anthropic {
                // Anthropic SSE: message_start has input_tokens, message_delta has output_tokens
                if let type = json["type"] as? String {
                    if type == "message_start", let message = json["message"] as? [String: Any],
                       let usage = message["usage"] as? [String: Any] {
                        lock.lock()
                        if let input = usage["input_tokens"] as? Int { capturedInputTokens = input }
                        lock.unlock()
                    }
                    if type == "message_delta", let usage = json["usage"] as? [String: Any] {
                        lock.lock()
                        if let output = usage["output_tokens"] as? Int { capturedOutputTokens = output }
                        lock.unlock()
                    }
                }
            } else {
                // OpenAI SSE: last chunk may contain usage
                if let usage = json["usage"] as? [String: Any] {
                    lock.lock()
                    if let input = usage["prompt_tokens"] as? Int { capturedInputTokens = input }
                    if let output = usage["completion_tokens"] as? Int { capturedOutputTokens = output }
                    lock.unlock()
                }
            }
        }
    }

    private let url: URL
    private let method: String
    private let headers: [String: String]
    private let body: Data
    private let firstByteTimeout: TimeInterval
    private let streamTimeout: TimeInterval
    private let requestDeadline: Date
    private let keepaliveInterval: TimeInterval
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
        firstByteTimeout: TimeInterval? = nil,
        streamTimeout: TimeInterval? = nil,
        requestDeadline: Date? = nil,
        keepaliveInterval: TimeInterval = 15,
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
        self.firstByteTimeout = firstByteTimeout ?? timeout
        self.streamTimeout = streamTimeout ?? timeout
        self.requestDeadline = requestDeadline ?? Date().addingTimeInterval(timeout)
        self.keepaliveInterval = max(0.01, keepaliveInterval)
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
        let synchronizedWriter = SynchronizedWriter(writer)
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
            return emptyCompletion(statusCode: 502, didWriteBody: writesErrorOnFailure)
        }

        var lastCompletion = emptyCompletion(statusCode: 502)
        var wroteAnyKeepalive = false
        let attempts = Array(availableKeys.prefix(maxAPIKeyAttempts))

        for (attemptIndex, keyEntry) in attempts.enumerated() {
            let remainingBudget = requestDeadline.timeIntervalSinceNow
            guard remainingBudget > 0 else {
                lastCompletion = emptyCompletion(
                    statusCode: 408,
                    error: NSError(
                        domain: "StreamingForwarder",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Streaming retry budget exhausted"]
                    )
                )
                break
            }

            let apiKey = keyEntry.key
            var keyedHeaders = headers
            ProxyEndpointSupport.setAuthHeaders(&keyedHeaders, apiKey: apiKey, protocol: upstreamProtocol)

            let delegate = StreamDelegate(
                writer: synchronizedWriter,
                incomingProtocol: incomingProtocol,
                upstreamProtocol: upstreamProtocol,
                messageID: "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
                model: model
            )
            let attemptFirstByteTimeout = min(firstByteTimeout, remainingBudget)
            let configuration = streamingConfiguration(firstByteTimeout: attemptFirstByteTimeout)
            let session = URLSession(
                configuration: configuration,
                delegate: delegate,
                delegateQueue: nil
            )
            let task = session.dataTask(with: request(headers: keyedHeaders))
            let attemptDescription = "first-byte timeout=\(String(format: "%.1f", attemptFirstByteTimeout))s "
                + "budget=\(String(format: "%.1f", remainingBudget))s"
            Log.info("[\(requestID)] Starting \(channelName) streaming API key #\(keyEntry.index + 1); \(attemptDescription)")
            task.resume()

            var completion = delegate.wait(
                firstByteTimeout: attemptFirstByteTimeout,
                streamTimeout: streamTimeout,
                requestDeadline: requestDeadline,
                keepaliveInterval: keepaliveInterval,
                requestID: requestID
            )
            session.invalidateAndCancel()
            completion = Completion(
                statusCode: completion.statusCode,
                headers: completion.headers,
                body: completion.body,
                keyIndex: keyEntry.index,
                didWriteBody: completion.didWriteBody,
                didWriteKeepalive: wroteAnyKeepalive || completion.didWriteKeepalive,
                error: completion.error,
                inputTokens: completion.inputTokens,
                outputTokens: completion.outputTokens,
                responseHeaderLatency: completion.responseHeaderLatency,
                timeToFirstByte: completion.timeToFirstByte,
                clientDisconnected: completion.clientDisconnected,
                requiresTerminalEvent: completion.requiresTerminalEvent,
                hasTerminalEvent: completion.hasTerminalEvent,
                didSynthesizeTerminalEvent: completion.didSynthesizeTerminalEvent
            )
            wroteAnyKeepalive = completion.didWriteKeepalive
            lastCompletion = completion

            if completion.didWriteBody {
                return completion
            }

            if completion.clientDisconnected {
                return completion
            }

            if ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: completion.statusCode, body: completion.body),
               let channelID,
               let apiKeyAvailabilityStore {
                apiKeyAvailabilityStore.markUnauthorized(channelID: channelID, apiKey: apiKey)
                Log.warn("[\(requestID)] \(channelName) streaming API key #\(keyEntry.index + 1) returned non-recoverable HTTP \(completion.statusCode); marking unavailable for this app session")
            }

            let shouldRetryKey = completion.isTimeout
                || ProxyEndpointSupport.shouldRetryWithNextAPIKey(
                    statusCode: completion.statusCode,
                    body: completion.body
                )
            if shouldRetryKey,
               attemptIndex < attempts.count - 1 {
                let failure = completion.error?.localizedDescription ?? "no error"
                let budget = String(format: "%.1f", max(0, requestDeadline.timeIntervalSinceNow))
                Log.warn(
                    "[\(requestID)] \(channelName) streaming API key #\(keyEntry.index + 1) "
                        + "failed before first byte (HTTP \(completion.statusCode), \(failure)); "
                        + "retrying next key with \(budget)s budget"
                )
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
            didWriteKeepalive: wroteAnyKeepalive,
            error: lastCompletion.error,
            inputTokens: lastCompletion.inputTokens,
            outputTokens: lastCompletion.outputTokens,
            responseHeaderLatency: lastCompletion.responseHeaderLatency,
            timeToFirstByte: lastCompletion.timeToFirstByte,
            clientDisconnected: lastCompletion.clientDisconnected,
            requiresTerminalEvent: lastCompletion.requiresTerminalEvent,
            hasTerminalEvent: lastCompletion.hasTerminalEvent,
            didSynthesizeTerminalEvent: lastCompletion.didSynthesizeTerminalEvent
        )
    }

    private func request(headers: [String: String]) -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = firstByteTimeout
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        return urlRequest
    }

    private func streamingConfiguration(firstByteTimeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = firstByteTimeout
        configuration.timeoutIntervalForResource = streamTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return configuration
    }

    private func emptyCompletion(statusCode: Int, didWriteBody: Bool = false, error: Error? = nil) -> Completion {
        Completion(
            statusCode: statusCode,
            headers: [:],
            body: Data(),
            keyIndex: 0,
            didWriteBody: didWriteBody,
            didWriteKeepalive: false,
            error: error,
            inputTokens: 0,
            outputTokens: 0,
            responseHeaderLatency: nil,
            timeToFirstByte: nil,
            clientDisconnected: false,
            requiresTerminalEvent: incomingProtocol == .anthropic,
            hasTerminalEvent: false,
            didSynthesizeTerminalEvent: false
        )
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
