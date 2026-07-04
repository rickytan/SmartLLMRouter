import Swifter
import XCTest
@testable import SmartLLMRouter

final class HTTPForwardingClientTests: XCTestCase {
    private var server: HttpServer?
    private var port: in_port_t = 0

    override func tearDown() {
        server?.stop()
        server = nil
        port = 0
        super.tearDown()
    }

    func testForwardSyncRetriesNextAPIKeyAfterRateLimit() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            authorizations.append(request.headers["authorization"] ?? "")
            if authorizations.count == 1 {
                return Self.jsonResponse(
                    statusCode: 429,
                    json: ["error": ["message": "rate limit exceeded"]]
                )
            }
            return Self.jsonResponse(statusCode: 200, json: ["ok": true])
        }

        let port = try start(server)
        let client = HTTPForwardingClient()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))

        let forwardResult = client.forwardSyncWithAPIKeyFailover(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{}".utf8),
            timeout: 5,
            apiKeys: ["key-a", "key-b"],
            targetProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#test"
        )

        guard case let .success(_, statusCode, _) = forwardResult.result else {
            XCTFail("Expected success after retry")
            return
        }
        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(forwardResult.apiKey, "key-b")
        XCTAssertEqual(forwardResult.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer key-a", "Bearer key-b"])
    }

    func testForwardSyncDoesNotRetryAfterSuccess() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            authorizations.append(request.headers["authorization"] ?? "")
            return Self.jsonResponse(statusCode: 200, json: ["ok": true])
        }

        let port = try start(server)
        let client = HTTPForwardingClient()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))

        let forwardResult = client.forwardSyncWithAPIKeyFailover(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{}".utf8),
            timeout: 5,
            apiKeys: ["key-a", "key-b"],
            targetProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#test"
        )

        guard case let .success(_, statusCode, _) = forwardResult.result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(forwardResult.apiKey, "key-a")
        XCTAssertEqual(forwardResult.keyIndex, 0)
        XCTAssertEqual(authorizations, ["Bearer key-a"])
    }

    func testStreamingForwarderConvertsOpenAIStreamToAnthropicEvents() throws {
        let server = HttpServer()
        server.post["/v1/chat/completions"] = { _ in
            .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data("data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-test\",\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n".utf8))
                try writer.write(Data("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\n".utf8))
                try writer.write(Data("data: [DONE]\n\n".utf8))
            }
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))
        let writer = CapturingBodyWriter()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 5,
            apiKeys: ["key-a"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#stream-test",
            model: "gpt-test"
        )

        let completion = forwarder.stream(to: writer)
        let output = writer.string

        XCTAssertTrue(completion.isSuccess)
        XCTAssertTrue(output.contains("event: message_start"))
        XCTAssertTrue(output.contains("event: content_block_delta"))
        XCTAssertTrue(output.contains("\"text\":\"ok\""))
        XCTAssertTrue(output.contains("event: message_stop"))
    }

    func testStreamingForwarderLimitsAPIKeyFailoverAttempts() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            authorizations.append(request.headers["authorization"] ?? "")
            return Self.jsonResponse(
                statusCode: 401,
                json: ["error": ["message": "invalid token"]]
            )
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))
        let writer = CapturingBodyWriter()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 5,
            apiKeys: ["key-a", "key-b", "key-c"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#stream-test",
            model: "gpt-test",
            maxAPIKeyAttempts: 2
        )

        let completion = forwarder.stream(to: writer)

        XCTAssertFalse(completion.isSuccess)
        XCTAssertEqual(authorizations, ["Bearer key-a", "Bearer key-b"])
        XCTAssertTrue(writer.string.contains("event: error"))
        XCTAssertTrue(writer.string.contains("invalid token"))
    }

    func testStreamingForwarderRetriesNextAPIKeyAndStreamsSuccess() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            authorizations.append(request.headers["authorization"] ?? "")
            if authorizations.count == 1 {
                return Self.jsonResponse(
                    statusCode: 401,
                    json: ["error": ["message": "invalid token"]]
                )
            }

            return .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data("data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-test\",\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n".utf8))
                try writer.write(Data("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\n".utf8))
                try writer.write(Data("data: [DONE]\n\n".utf8))
            }
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))
        let writer = CapturingBodyWriter()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 5,
            apiKeys: ["bad-key", "good-key"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#stream-test",
            model: "gpt-test"
        )

        let completion = forwarder.stream(to: writer)
        let output = writer.string

        XCTAssertTrue(completion.isSuccess)
        XCTAssertEqual(completion.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer bad-key", "Bearer good-key"])
        XCTAssertTrue(output.contains("event: message_start"))
        XCTAssertTrue(output.contains("\"text\":\"ok\""))
        XCTAssertFalse(output.contains("invalid token"))
    }

    func testStreamingForwarderPassesThroughAnthropicStreamAndHeaders() throws {
        let server = HttpServer()
        var capturedAPIKey: String?
        var capturedVersion: String?
        var capturedAuthorization: String?
        let upstreamEvent = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-test\",\"usage\":{\"input_tokens\":1,\"output_tokens\":0}}}\n\n"

        server.post["/v1/messages"] = { request in
            capturedAPIKey = request.headers["x-api-key"]
            capturedVersion = request.headers["anthropic-version"]
            capturedAuthorization = request.headers["authorization"]
            return .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data(upstreamEvent.utf8))
            }
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/messages"))
        let writer = CapturingBodyWriter()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 5,
            apiKeys: ["anthropic-key"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .anthropic,
            channelName: "Anthropic Channel",
            requestID: "#stream-test",
            model: "claude-test"
        )

        let completion = forwarder.stream(to: writer)

        XCTAssertTrue(completion.isSuccess)
        XCTAssertEqual(capturedAPIKey, "anthropic-key")
        XCTAssertEqual(capturedVersion, "2023-06-01")
        XCTAssertNil(capturedAuthorization)
        XCTAssertEqual(writer.string, upstreamEvent)
    }

    func testStreamingForwarderCanDeferErrorBodyForChannelFailover() throws {
        let server = HttpServer()
        server.post["/v1/chat/completions"] = { _ in
            Self.jsonResponse(
                statusCode: 401,
                json: ["error": ["message": "invalid token"]]
            )
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))
        let writer = CapturingBodyWriter()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 5,
            apiKeys: ["key-a"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#stream-test",
            model: "gpt-test"
        )

        let completion = forwarder.stream(to: writer, writesErrorOnFailure: false)

        XCTAssertFalse(completion.isSuccess)
        XCTAssertFalse(completion.didWriteBody)
        XCTAssertTrue(writer.string.isEmpty)
        XCTAssertEqual(StreamingForwarder.errorMessage(from: completion), "invalid token")
    }

    private func start(_ server: HttpServer) throws -> in_port_t {
        for candidate in in_port_t(31_000)...in_port_t(31_100) {
            do {
                try server.start(candidate, forceIPv4: true)
                self.server = server
                port = candidate
                return candidate
            } catch {
                continue
            }
        }
        throw NSError(
            domain: "HTTPForwardingClientTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No available local test port"]
        )
    }

    private static func jsonResponse(statusCode: Int, json: [String: Any]) -> HttpResponse {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let bytes = [UInt8](body)
        return .raw(statusCode, "OK", ["content-type": "application/json"]) { writer in
            try writer.write(bytes)
        }
    }

    private final class CapturingBodyWriter: HttpResponseBodyWriter {
        private(set) var data = Data()

        var string: String {
            String(data: data, encoding: .utf8) ?? ""
        }

        func write(_ file: String.File) throws {}

        func write(_ data: [UInt8]) throws {
            self.data.append(contentsOf: data)
        }

        func write(_ data: ArraySlice<UInt8>) throws {
            self.data.append(contentsOf: data)
        }

        func write(_ data: NSData) throws {
            self.data.append(data as Data)
        }

        func write(_ data: Data) throws {
            self.data.append(data)
        }
    }
}
