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
        let availability = APIKeyAvailabilityStore()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))

        let forwardResult = client.forwardSyncWithAPIKeyFailover(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{}".utf8),
            timeout: 5,
            apiKeys: ["key-a", "key-b"],
            targetProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#test",
            channelID: "channel-a",
            apiKeyAvailabilityStore: availability
        )

        guard case let .success(_, statusCode, _) = forwardResult.result else {
            XCTFail("Expected success after retry")
            return
        }
        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(forwardResult.apiKey, "key-b")
        XCTAssertEqual(forwardResult.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer key-a", "Bearer key-b"])
        XCTAssertFalse(availability.isUnauthorized(channelID: "channel-a", apiKey: "key-a"))
        XCTAssertTrue(availability.isRateLimited(channelID: "channel-a", apiKey: "key-a"))

        let secondResult = client.forwardSyncWithAPIKeyFailover(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{}".utf8),
            timeout: 5,
            apiKeys: ["key-a", "key-b"],
            targetProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#test-2",
            channelID: "channel-a",
            apiKeyAvailabilityStore: availability
        )

        guard case let .success(_, secondStatusCode, _) = secondResult.result else {
            XCTFail("Expected the healthy key to remain available")
            return
        }
        XCTAssertEqual(secondStatusCode, 200)
        XCTAssertEqual(secondResult.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer key-a", "Bearer key-b", "Bearer key-b"])
    }

    func testForwardSyncProbesAllCoolingKeysInConfiguredOrder() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            let authorization = request.headers["authorization"] ?? ""
            authorizations.append(authorization)
            if authorization == "Bearer key-a" {
                return Self.jsonResponse(
                    statusCode: 429,
                    json: ["error": ["message": "rate limit exceeded"]]
                )
            }
            return Self.jsonResponse(statusCode: 200, json: ["ok": true])
        }

        let port = try start(server)
        let client = HTTPForwardingClient()
        let availability = APIKeyAvailabilityStore()
        for key in ["key-a", "key-b"] {
            availability.markRateLimited(
                channelID: "channel-a",
                apiKey: key,
                allAPIKeys: ["key-a", "key-b"]
            )
        }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))

        let forwardResult = client.forwardSyncWithAPIKeyFailover(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{}".utf8),
            timeout: 5,
            apiKeys: ["key-a", "key-b"],
            targetProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#all-cooling",
            channelID: "channel-a",
            apiKeyAvailabilityStore: availability
        )

        guard case let .success(_, statusCode, _) = forwardResult.result else {
            XCTFail("Expected cooling keys to be probed when no healthy key exists")
            return
        }
        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(forwardResult.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer key-a", "Bearer key-b"])
    }

    func testRateLimitedAPIKeyBecomesAvailableAfterCooldownExpires() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let availability = APIKeyAvailabilityStore(now: { currentDate })
        availability.updateRateLimitCooldown(60)

        let expiration = availability.markRateLimited(
            channelID: "channel-a",
            apiKey: "key-a",
            allAPIKeys: ["key-a", "key-b"]
        )

        XCTAssertEqual(expiration, currentDate.addingTimeInterval(60))
        XCTAssertEqual(
            availability.availableKeys(for: "channel-a", apiKeys: ["key-a", "key-b"]).map(\.key),
            ["key-b"]
        )

        currentDate.addTimeInterval(61)

        XCTAssertFalse(availability.isRateLimited(channelID: "channel-a", apiKey: "key-a"))
        XCTAssertEqual(
            availability.availableKeys(for: "channel-a", apiKeys: ["key-a", "key-b"]).map(\.key),
            ["key-a", "key-b"]
        )
    }

    func testAllRateLimitedKeysNotifyChannelWithEarliestRecovery() {
        let currentDate = Date(timeIntervalSince1970: 2_000)
        let availability = APIKeyAvailabilityStore(now: { currentDate })
        availability.updateRateLimitCooldown(120)
        var notification: (channelID: String, until: Date)?
        availability.setChannelRateLimitHandler { channelID, until in
            notification = (channelID, until)
        }

        availability.markRateLimited(
            channelID: "channel-a",
            apiKey: "key-a",
            allAPIKeys: ["key-a", "key-b"]
        )
        XCTAssertNil(notification)

        availability.markRateLimited(
            channelID: "channel-a",
            apiKey: "key-b",
            allAPIKeys: ["key-a", "key-b"]
        )

        XCTAssertEqual(notification?.channelID, "channel-a")
        XCTAssertEqual(notification?.until, currentDate.addingTimeInterval(120))
        XCTAssertTrue(availability.availableKeys(for: "channel-a", apiKeys: ["key-a", "key-b"]).isEmpty)
    }

    func testRepeatedAllKeysRateLimitedStateDoesNotScheduleDuplicateChannelNotifications() {
        let currentDate = Date(timeIntervalSince1970: 2_500)
        let availability = APIKeyAvailabilityStore(now: { currentDate })
        availability.updateRateLimitCooldown(120)
        var notificationCount = 0
        availability.setChannelRateLimitHandler { _, _ in
            notificationCount += 1
        }

        availability.markRateLimited(
            channelID: "channel-a",
            apiKey: "key-a",
            allAPIKeys: ["key-a", "key-b"]
        )
        availability.markRateLimited(
            channelID: "channel-a",
            apiKey: "key-b",
            allAPIKeys: ["key-a", "key-b"]
        )
        availability.markRateLimited(
            channelID: "channel-a",
            apiKey: "key-b",
            allAPIKeys: ["key-a", "key-b"]
        )

        XCTAssertEqual(notificationCount, 1)
    }

    func testAPIKeyUnavailableDetectionCoversOnlyNonRecoverableCredentialErrors() {
        let invalidKeyBody = Data(#"{"error":{"message":"invalid_api_key"}}"#.utf8)
        let quotaBody = Data(#"{"error":{"code":"insufficient_quota"}}"#.utf8)
        let billingBody = Data(#"{"error":{"message":"billing is not active"}}"#.utf8)
        let rateLimitBody = Data(#"{"error":{"message":"rate limit exceeded"}}"#.utf8)

        XCTAssertTrue(ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: 401, body: nil))
        XCTAssertTrue(ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: 402, body: nil))
        XCTAssertTrue(ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: 400, body: invalidKeyBody))
        XCTAssertTrue(ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: 403, body: quotaBody))
        XCTAssertTrue(ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: 403, body: billingBody))
        XCTAssertFalse(ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: 429, body: rateLimitBody))
        XCTAssertFalse(ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: 500, body: billingBody))
        XCTAssertFalse(ProxyEndpointSupport.shouldMarkAPIKeyUnavailable(statusCode: 403, body: nil))
    }

    func testForwardSyncMarks401KeyUnavailableForLaterRequests() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            let authorization = request.headers["authorization"] ?? ""
            authorizations.append(authorization)
            if authorization == "Bearer bad-key" {
                return Self.jsonResponse(
                    statusCode: 401,
                    json: ["error": ["message": "invalid token"]]
                )
            }
            return Self.jsonResponse(statusCode: 200, json: ["ok": true])
        }

        let port = try start(server)
        let client = HTTPForwardingClient()
        let availability = APIKeyAvailabilityStore()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))

        let firstResult = client.forwardSyncWithAPIKeyFailover(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{}".utf8),
            timeout: 5,
            apiKeys: ["bad-key", "good-key"],
            targetProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#test-1",
            channelID: "channel-a",
            apiKeyAvailabilityStore: availability
        )

        guard case let .success(_, firstStatusCode, _) = firstResult.result else {
            XCTFail("Expected success after retry")
            return
        }
        XCTAssertEqual(firstStatusCode, 200)
        XCTAssertTrue(availability.isUnauthorized(channelID: "channel-a", apiKey: "bad-key"))

        let secondResult = client.forwardSyncWithAPIKeyFailover(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{}".utf8),
            timeout: 5,
            apiKeys: ["bad-key", "good-key"],
            targetProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#test-2",
            channelID: "channel-a",
            apiKeyAvailabilityStore: availability
        )

        guard case let .success(_, secondStatusCode, _) = secondResult.result else {
            XCTFail("Expected success without retrying bad key")
            return
        }
        XCTAssertEqual(secondStatusCode, 200)
        XCTAssertEqual(secondResult.apiKey, "good-key")
        XCTAssertEqual(secondResult.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer bad-key", "Bearer good-key", "Bearer good-key"])
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

    func testForwardSyncSharesDeadlineAcrossAPIKeys() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            let authorization = request.headers["authorization"] ?? ""
            authorizations.append(authorization)
            if authorization == "Bearer key-a" {
                Thread.sleep(forTimeInterval: 0.05)
                return Self.jsonResponse(
                    statusCode: 429,
                    json: ["error": ["message": "rate limit exceeded"]]
                )
            }
            Thread.sleep(forTimeInterval: 1.5)
            return Self.jsonResponse(statusCode: 200, json: ["ok": true])
        }

        let port = try start(server)
        let client = HTTPForwardingClient()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))
        let startedAt = Date()
        let forwardResult = client.forwardSyncWithAPIKeyFailover(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{}".utf8),
            timeout: 1,
            apiKeys: ["key-a", "key-b"],
            targetProtocol: .openai,
            channelName: "Test Channel",
            requestID: "#deadline",
            deadline: startedAt.addingTimeInterval(0.75)
        )

        guard case let .failure(error) = forwardResult.result else {
            XCTFail("Expected the shared request deadline to expire")
            return
        }
        XCTAssertEqual((error as? URLError)?.code, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1.1)
        XCTAssertEqual(authorizations, ["Bearer key-a", "Bearer key-b"])
    }

    func testForwardSyncDoesNotShareUnauthorizedStateAcrossChannels() throws {
        let availability = APIKeyAvailabilityStore()
        availability.markUnauthorized(channelID: "channel-a", apiKey: "shared-key")

        XCTAssertTrue(availability.isUnauthorized(channelID: "channel-a", apiKey: "shared-key"))
        XCTAssertFalse(availability.isUnauthorized(channelID: "channel-b", apiKey: "shared-key"))
        XCTAssertEqual(
            availability.availableKeys(for: "channel-b", apiKeys: ["shared-key"]).map { $0.key },
            ["shared-key"]
        )
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
        let availability = APIKeyAvailabilityStore()
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
            channelID: "channel-a",
            apiKeyAvailabilityStore: availability,
            requestID: "#stream-test",
            model: "gpt-test"
        )

        let completion = forwarder.stream(to: writer)
        let output = writer.string

        XCTAssertTrue(completion.isSuccess)
        XCTAssertEqual(completion.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer bad-key", "Bearer good-key"])
        XCTAssertTrue(availability.isUnauthorized(channelID: "channel-a", apiKey: "bad-key"))
        XCTAssertTrue(output.contains("event: message_start"))
        XCTAssertTrue(output.contains("\"text\":\"ok\""))
        XCTAssertFalse(output.contains("invalid token"))

        let secondWriter = CapturingBodyWriter()
        let secondForwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 5,
            apiKeys: ["bad-key", "good-key"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .openai,
            channelName: "Test Channel",
            channelID: "channel-a",
            apiKeyAvailabilityStore: availability,
            requestID: "#stream-test-2",
            model: "gpt-test"
        )

        let secondCompletion = secondForwarder.stream(to: secondWriter)

        XCTAssertTrue(secondCompletion.isSuccess)
        XCTAssertEqual(secondCompletion.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer bad-key", "Bearer good-key", "Bearer good-key"])
        XCTAssertTrue(secondWriter.string.contains("\"text\":\"ok\""))
    }

    func testStreamingForwarderCoolsDown429KeyForLaterRequests() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            let authorization = request.headers["authorization"] ?? ""
            authorizations.append(authorization)
            if authorization == "Bearer limited-key" {
                return Self.jsonResponse(
                    statusCode: 429,
                    json: ["error": ["message": "rate limit exceeded"]]
                )
            }
            return .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\n".utf8))
                try writer.write(Data("data: [DONE]\n\n".utf8))
            }
        }

        let port = try start(server)
        let availability = APIKeyAvailabilityStore()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))

        func makeForwarder(requestID: String) -> (StreamingForwarder, CapturingBodyWriter) {
            let writer = CapturingBodyWriter()
            return (
                StreamingForwarder(
                    url: url,
                    headers: ["content-type": "application/json"],
                    body: Data("{\"stream\":true}".utf8),
                    timeout: 5,
                    apiKeys: ["limited-key", "healthy-key"],
                    incomingProtocol: .anthropic,
                    upstreamProtocol: .openai,
                    channelName: "Test Channel",
                    channelID: "channel-a",
                    apiKeyAvailabilityStore: availability,
                    requestID: requestID,
                    model: "gpt-test"
                ),
                writer
            )
        }

        let (firstForwarder, firstWriter) = makeForwarder(requestID: "#stream-429-1")
        XCTAssertTrue(firstForwarder.stream(to: firstWriter).isSuccess)
        XCTAssertTrue(availability.isRateLimited(channelID: "channel-a", apiKey: "limited-key"))

        let (secondForwarder, secondWriter) = makeForwarder(requestID: "#stream-429-2")
        XCTAssertTrue(secondForwarder.stream(to: secondWriter).isSuccess)
        XCTAssertEqual(
            authorizations,
            ["Bearer limited-key", "Bearer healthy-key", "Bearer healthy-key"]
        )
    }

    func testStreamingForwarderProbesAllCoolingKeysInConfiguredOrder() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            let authorization = request.headers["authorization"] ?? ""
            authorizations.append(authorization)
            if authorization == "Bearer key-a" {
                return Self.jsonResponse(
                    statusCode: 429,
                    json: ["error": ["message": "rate limit exceeded"]]
                )
            }
            return .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\n".utf8))
                try writer.write(Data("data: [DONE]\n\n".utf8))
            }
        }

        let port = try start(server)
        let availability = APIKeyAvailabilityStore()
        for key in ["key-a", "key-b"] {
            availability.markRateLimited(
                channelID: "channel-a",
                apiKey: key,
                allAPIKeys: ["key-a", "key-b"]
            )
        }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))
        let writer = CapturingBodyWriter()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 5,
            apiKeys: ["key-a", "key-b"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .openai,
            channelName: "Test Channel",
            channelID: "channel-a",
            apiKeyAvailabilityStore: availability,
            requestID: "#stream-all-cooling",
            model: "gpt-test"
        )

        let completion = forwarder.stream(to: writer)

        XCTAssertTrue(completion.isSuccess)
        XCTAssertEqual(completion.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer key-a", "Bearer key-b"])
        XCTAssertTrue(writer.string.contains("\"text\":\"ok\""))
    }

    func testStreamingForwarderSkipsPreviouslyUnauthorizedAPIKey() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/chat/completions"] = { request in
            authorizations.append(request.headers["authorization"] ?? "")
            return .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data("data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-test\",\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\n".utf8))
                try writer.write(Data("data: [DONE]\n\n".utf8))
            }
        }

        let port = try start(server)
        let availability = APIKeyAvailabilityStore()
        availability.markUnauthorized(channelID: "channel-a", apiKey: "bad-key")
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
            channelID: "channel-a",
            apiKeyAvailabilityStore: availability,
            requestID: "#stream-test",
            model: "gpt-test"
        )

        let completion = forwarder.stream(to: writer)

        XCTAssertTrue(completion.isSuccess)
        XCTAssertEqual(completion.keyIndex, 1)
        XCTAssertEqual(authorizations, ["Bearer good-key"])
        XCTAssertTrue(writer.string.contains("\"text\":\"ok\""))
    }

    func testStreamingForwarderPassesThroughAnthropicStreamAndHeaders() throws {
        let server = HttpServer()
        var capturedAPIKey: String?
        var capturedVersion: String?
        var capturedAuthorization: String?
        let upstreamEvent = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-test\",\"usage\":{\"input_tokens\":0,\"cache_creation_input_tokens\":11,\"cache_read_input_tokens\":89,\"output_tokens\":0}}}\n\n"

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
        XCTAssertEqual(capturedAuthorization, "Bearer anthropic-key")
        XCTAssertEqual(completion.inputTokens, 100)
        XCTAssertTrue(writer.string.hasPrefix(upstreamEvent))
        XCTAssertTrue(writer.string.contains("event: message_stop"))
        XCTAssertTrue(completion.hasTerminalEvent)
        XCTAssertTrue(completion.didSynthesizeTerminalEvent)
    }

    func testStreamingForwarderCapturesOpenAICompatibleUsageAliases() throws {
        let server = HttpServer()
        let upstreamStream = """
        data: {"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}

        data: {"choices":[],"usage":{"input_tokens":123,"output_tokens":45}}

        data: [DONE]

        """
        server.post["/v1/chat/completions"] = { _ in
            .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data(upstreamStream.utf8))
            }
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))
        let writer = CapturingBodyWriter()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data(#"{"stream":true}"#.utf8),
            timeout: 5,
            apiKeys: ["openai-key"],
            incomingProtocol: .openai,
            upstreamProtocol: .openai,
            channelName: "OpenAI Channel",
            requestID: "#stream-usage-test",
            model: "gpt-test"
        )

        let completion = forwarder.stream(to: writer)

        XCTAssertTrue(completion.isSuccess)
        XCTAssertEqual(completion.inputTokens, 123)
        XCTAssertEqual(completion.outputTokens, 45)
    }

    func testStreamingForwarderEstimatesUsageWhenOpenAICompatibleProviderOmitsIt() throws {
        let server = HttpServer()
        let upstreamStream = """
        data: {"choices":[{"delta":{"content":"fallback response"},"finish_reason":null}]}

        data: [DONE]

        """
        server.post["/v1/chat/completions"] = { _ in
            .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data(upstreamStream.utf8))
            }
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))
        let writer = CapturingBodyWriter()
        let body = Data(#"{"stream":true,"messages":[{"role":"user","content":"hello from Claude Code"}]}"#.utf8)
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: body,
            timeout: 5,
            apiKeys: ["openai-key"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .openai,
            channelName: "SenseNova-compatible Channel",
            requestID: "#stream-estimated-usage-test",
            model: "sensenova-test"
        )

        let completion = forwarder.stream(to: writer)

        XCTAssertTrue(completion.isSuccess)
        XCTAssertGreaterThan(completion.inputTokens, 0)
        XCTAssertGreaterThan(completion.outputTokens, 0)
    }

    func testStreamingForwarderDoesNotDuplicateAnthropicMessageStop() throws {
        let server = HttpServer()
        let upstreamStream = """
        event: message_start
        data: {"type":"message_start"}

        event: message_stop
        data: {"type":"message_stop"}


        """
        server.post["/v1/messages"] = { _ in
            .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data(upstreamStream.utf8))
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
            requestID: "#terminal-test",
            model: "claude-test"
        )

        let completion = forwarder.stream(to: writer)

        XCTAssertTrue(completion.isSuccess)
        XCTAssertTrue(completion.hasTerminalEvent)
        XCTAssertFalse(completion.didSynthesizeTerminalEvent)
        XCTAssertEqual(writer.string.components(separatedBy: "event: message_stop").count - 1, 1)
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

    func testAnthropicStreamingErrorPreservesCompleteUpstreamBody() {
        let writer = CapturingBodyWriter()
        let body = Data(
            #"{"type":"error","error":{"type":"rate_limit_error","message":"TPM exceeded","code":"quota_tpm"},"request_id":"req_upstream"}"#.utf8
        )

        StreamingForwarder.writeUpstreamErrorEvent(
            body,
            requestID: "#upstream-error",
            targetProtocol: .anthropic,
            to: writer
        )

        XCTAssertEqual(
            writer.string,
            "event: error\ndata: \(String(decoding: body, as: UTF8.self))\n\n"
        )
    }

    func testOpenAIStreamingErrorPreservesCompleteUpstreamBody() {
        let writer = CapturingBodyWriter()
        let body = Data(
            #"{"error":{"message":"rate limited","type":"rate_limit_error","code":"rate_limit_exceeded"},"provider":"upstream"}"#.utf8
        )

        StreamingForwarder.writeUpstreamErrorEvent(
            body,
            requestID: "#upstream-error",
            targetProtocol: .openai,
            to: writer
        )

        XCTAssertEqual(
            writer.string,
            "data: \(String(decoding: body, as: UTF8.self))\n\n"
        )
    }

    func testStreamingForwarderSendsKeepaliveAndRetriesAfterFirstByteTimeout() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/messages"] = { request in
            let authorization = request.headers["x-api-key"] ?? ""
            authorizations.append(authorization)
            if authorization == "slow-key" {
                Thread.sleep(forTimeInterval: 0.25)
            }
            return .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                let event = "event: message_start\ndata: {\"type\":\"message_start\"}\n\n"
                try writer.write(Data(event.utf8))
            }
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/messages"))
        let writer = CapturingBodyWriter()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 1,
            firstByteTimeout: 0.1,
            streamTimeout: 1,
            requestDeadline: Date().addingTimeInterval(0.5),
            keepaliveInterval: 0.03,
            apiKeys: ["slow-key", "fast-key"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .anthropic,
            channelName: "Test Channel",
            requestID: "#keepalive-retry",
            model: "claude-test"
        )

        let completion = forwarder.stream(to: writer)

        XCTAssertTrue(completion.isSuccess)
        XCTAssertTrue(completion.didWriteKeepalive)
        XCTAssertEqual(completion.keyIndex, 1)
        XCTAssertEqual(authorizations, ["slow-key", "fast-key"])
        XCTAssertTrue(writer.string.contains(": keep-alive"))
        XCTAssertTrue(writer.string.contains("event: message_start"))
        XCTAssertNotNil(completion.responseHeaderLatency)
        XCTAssertNotNil(completion.timeToFirstByte)
    }

    func testStreamingForwarderSharesRetryDeadlineAcrossKeys() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/messages"] = { request in
            authorizations.append(request.headers["x-api-key"] ?? "")
            Thread.sleep(forTimeInterval: 0.3)
            return .raw(200, "OK", ["content-type": "text/event-stream"]) { _ in }
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/messages"))
        let writer = CapturingBodyWriter()
        let startedAt = Date()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 1,
            firstByteTimeout: 0.5,
            streamTimeout: 1,
            requestDeadline: Date().addingTimeInterval(0.12),
            keepaliveInterval: 0.03,
            apiKeys: ["key-a", "key-b"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .anthropic,
            channelName: "Test Channel",
            requestID: "#deadline",
            model: "claude-test"
        )

        let completion = forwarder.stream(to: writer, writesErrorOnFailure: false)

        XCTAssertTrue(completion.isTimeout)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.4)
        XCTAssertLessThanOrEqual(authorizations.count, 1)
        XCTAssertTrue(completion.didWriteKeepalive)
        XCTAssertFalse(completion.didWriteBody)
    }

    func testStreamingForwarderHonorsAbsoluteStreamDeadlineAfterFirstBody() throws {
        let server = HttpServer()
        server.post["/v1/messages"] = { _ in
            .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data("event: message_start\ndata: {\"type\":\"message_start\"}\n\n".utf8))
                Thread.sleep(forTimeInterval: 0.3)
                try writer.write(Data("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n".utf8))
            }
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/messages"))
        let writer = CapturingBodyWriter()
        let startedAt = Date()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 1,
            firstByteTimeout: 0.5,
            streamTimeout: 1,
            requestDeadline: startedAt.addingTimeInterval(0.5),
            streamDeadline: startedAt.addingTimeInterval(0.12),
            apiKeys: ["key-a"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .anthropic,
            channelName: "Test Channel",
            requestID: "#stream-deadline",
            model: "claude-test"
        )

        let completion = forwarder.stream(to: writer, writesErrorOnFailure: false)

        XCTAssertTrue(completion.isTimeout)
        XCTAssertTrue(completion.didWriteBody)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.3)
        XCTAssertTrue(writer.string.contains("event: message_start"))
        XCTAssertFalse(writer.string.contains("event: message_stop"))
    }

    func testStreamingForwarderDoesNotRetryAfterWritingModelBody() throws {
        let server = HttpServer()
        var authorizations: [String] = []
        server.post["/v1/messages"] = { request in
            authorizations.append(request.headers["x-api-key"] ?? "")
            return .raw(200, "OK", ["content-type": "text/event-stream"]) { writer in
                try writer.write(Data("event: message_start\n\n".utf8))
                Thread.sleep(forTimeInterval: 0.03)
                try writer.write(Data("event: content_block_delta\n\n".utf8))
            }
        }

        let port = try start(server)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/messages"))
        let writer = ThrowAfterFirstWriteBodyWriter()
        let forwarder = StreamingForwarder(
            url: url,
            headers: ["content-type": "application/json"],
            body: Data("{\"stream\":true}".utf8),
            timeout: 1,
            apiKeys: ["key-a", "key-b"],
            incomingProtocol: .anthropic,
            upstreamProtocol: .anthropic,
            channelName: "Test Channel",
            requestID: "#partial-stream",
            model: "claude-test"
        )

        let completion = forwarder.stream(to: writer, writesErrorOnFailure: false)

        XCTAssertTrue(completion.didWriteBody)
        XCTAssertTrue(completion.clientDisconnected)
        XCTAssertEqual(authorizations, ["key-a"])
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

    private final class ThrowAfterFirstWriteBodyWriter: HttpResponseBodyWriter {
        private var writeCount = 0

        func write(_ file: String.File) throws {}
        func write(_ data: [UInt8]) throws { try write(Data(data)) }
        func write(_ data: ArraySlice<UInt8>) throws { try write(Data(data)) }
        func write(_ data: NSData) throws { try write(data as Data) }

        func write(_ data: Data) throws {
            writeCount += 1
            if writeCount > 1 {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(EPIPE),
                    userInfo: [NSLocalizedDescriptionKey: "Client disconnected"]
                )
            }
        }
    }
}
