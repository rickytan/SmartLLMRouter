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
}
