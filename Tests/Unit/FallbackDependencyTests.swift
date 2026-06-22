import Foundation
import Swifter
import XCTest
@testable import SmartLLMRouter

@MainActor
final class FallbackDependencyTests: XCTestCase {
    private var isolatedStore: IsolatedChannelStore!
    private var isolatedKeychain: IsolatedKeychainManager!
    private var channelServices: ChannelServices!
    private var routerServices: RouterServices!

    override func setUp() async throws {
        try await super.setUp()

        let runtimeState = RouterRuntimeState(
            circuitBreaker: CircuitBreaker(),
            switchLock: SwitchLock()
        )
        isolatedStore = ChannelStoreTestSupport.makeIsolatedChannelStore(
            useTempFile: false,
            runtimeState: runtimeState
        )
        isolatedKeychain = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        channelServices = ChannelServices(
            store: isolatedStore.store,
            keychain: isolatedKeychain.manager,
            cooldownEngine: CooldownEngine(channelStore: isolatedStore.store)
        )

        let aggregator = ModelAggregator(channelServices: channelServices)
        let switcher = ModelSwitcher(
            channelServices: channelServices,
            modelOverrideState: ModelOverrideRuntimeState(),
            defaults: isolatedStore.defaults
        )
        routerServices = RouterServices(
            channelServices: channelServices,
            runtimeState: runtimeState,
            modelOverrideState: ModelOverrideRuntimeState(),
            circuitBreaker: CircuitBreaker(),
            switchLock: SwitchLock(),
            modelAggregator: aggregator,
            modelSwitcher: switcher,
            usageTracker: UsageTracker(defaults: isolatedStore.defaults)
        )
    }

    override func tearDown() async throws {
        routerServices = nil
        channelServices = nil
        isolatedKeychain.cleanup()
        isolatedKeychain = nil
        isolatedStore.cleanup()
        isolatedStore = nil
        try await super.tearDown()
    }

    func testModelsEndpointReturnsStaticEnabledModelsWhenAggregationFails() throws {
        let enabledModel = makeModel(identifier: "fallback-model")
        let disabledModel = ModelEntry(
            id: "disabled",
            identifier: "disabled-model",
            displayName: "Disabled",
            isEnabled: false
        )
        let channel = makeChannel(models: [enabledModel, disabledModel])
        isolatedStore.store.addChannel(channel)

        let handler = ModelEndpointHandler(
            services: routerServices,
            modelAggregator: FailingModelAggregator()
        )

        let response = handler.handleListModels()
        let payload = try responseJSON(response)
        let models = payload["data"] as? [[String: Any]]

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(models?.map { $0["id"] as? String }, ["fallback-model"])
        XCTAssertEqual(models?.first?["owned_by"] as? String, channel.name)
    }

    func testConnectionFallsBackFromModelsGetToEmptyPost() async throws {
        let channel = makeChannel(models: [])
        try channelServices.setAPIKey("test-key", for: channel.id)
        let transport = ScriptedConnectionTransport(
            dataResults: [
                .success(payload(statusCode: 403)),
                .success(payload(
                    statusCode: 400,
                    body: errorBody("model is required")
                )),
            ]
        )
        let manager = ChannelManager(
            channelServices: channelServices,
            connectionTransport: transport
        )

        let result = await manager.testConnection(channel: channel)

        XCTAssertTrue(result.success)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests.map(\.httpMethod), ["GET", "POST"])
        XCTAssertEqual(transport.requests.last?.httpBody, Data("{}".utf8))
    }

    func testConnectionFallsThroughStreamingToFullPost() async throws {
        let channel = makeChannel(models: [makeModel(identifier: "known-model")])
        try channelServices.setAPIKey("test-key", for: channel.id)
        let transport = ScriptedConnectionTransport(
            dataResults: [
                .success(payload(statusCode: 500)),
                .success(payload(statusCode: 400, body: errorBody("invalid request"))),
                .success(payload(statusCode: 200)),
            ],
            responseResults: [.success(httpResponse(statusCode: 503))]
        )
        let manager = ChannelManager(
            channelServices: channelServices,
            connectionTransport: transport
        )

        let result = await manager.testConnection(channel: channel)

        XCTAssertTrue(result.success)
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(transport.requests.map(\.httpMethod), ["GET", "POST", "POST", "POST"])
        XCTAssertTrue(requestBody(transport.requests[2])?["stream"] as? Bool ?? false)
        XCTAssertNil(requestBody(transport.requests[3])?["stream"])
    }

    private func makeChannel(models: [ModelEntry]) -> Channel {
        Channel(
            id: UUID().uuidString,
            name: "Fallback Test Channel",
            baseURL: "https://fallback.example.com/v1",
            priority: 1,
            protocol: .openai,
            models: models
        )
    }

    private func makeModel(identifier: String) -> ModelEntry {
        ModelEntry(id: identifier, identifier: identifier, displayName: identifier)
    }

    private func payload(statusCode: Int, body: Data = Data()) -> HTTPPayload {
        HTTPPayload(data: body, response: httpResponse(statusCode: statusCode))
    }

    private func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://fallback.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func errorBody(_ message: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["error": ["message": message]])
    }

    private func requestBody(_ request: URLRequest) -> [String: Any]? {
        guard let body = request.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    private func responseJSON(_ response: HttpResponse) throws -> [String: Any] {
        guard case let .ok(body) = response,
              case let .json(object) = body
        else {
            XCTFail("Expected .ok(.json(...)) response")
            return [:]
        }

        return try XCTUnwrap(object as? [String: Any])
    }
}

private final class FailingModelAggregator: ModelAggregating, @unchecked Sendable {
    func fetchAllModelsIfNeeded() async -> Bool { false }
    func allModels() -> [ModelEntry] { [] }
    func hasCachedModels() -> Bool { false }
}

@MainActor
private final class ScriptedConnectionTransport: ConnectionTestHTTPTransport {
    private var dataResults: [Result<HTTPPayload, Error>]
    private var responseResults: [Result<URLResponse, Error>]
    private(set) var requests: [URLRequest] = []

    init(
        dataResults: [Result<HTTPPayload, Error>],
        responseResults: [Result<URLResponse, Error>] = []
    ) {
        self.dataResults = dataResults
        self.responseResults = responseResults
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !dataResults.isEmpty else {
            throw ScriptedTransportError.missingDataResult
        }
        let payload = try dataResults.removeFirst().get()
        return (payload.data, payload.response)
    }

    func response(for request: URLRequest) async throws -> URLResponse {
        requests.append(request)
        guard !responseResults.isEmpty else {
            throw ScriptedTransportError.missingResponseResult
        }
        return try responseResults.removeFirst().get()
    }
}

private struct HTTPPayload {
    let data: Data
    let response: URLResponse
}

private enum ScriptedTransportError: Error {
    case missingDataResult
    case missingResponseResult
}

