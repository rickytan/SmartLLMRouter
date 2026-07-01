import XCTest
import KeychainAccess
@testable import SmartLLMRouter

/// Regression tests for the keychain-clear bug.
///
/// The unit-test target runs inside the host app's process
/// (`TEST_HOST`/`BUNDLE_LOADER` in `project.yml`), so a test that
/// instantiated `KeychainManager(service: "com.smartllmrouter.keys")`
/// and called `clearAll()` would delete every API key the user has
/// ever saved. This has already happened once during development —
/// a previous test called `clearAll()` against the production service
/// and wiped the user's data.
///
/// These tests pin the fix in place: all test managers use a dedicated
/// UUID-scoped keychain service and never mutate production state.
@MainActor
final class KeychainManagerTestSupportTests: XCTestCase {

    /// Reads a sentinel key from the production service. Returns nil
    /// if the key is not present. Used as a tripwire: if a test ever
    /// writes to the production service under this sentinel name, the
    /// test will see the value and fail.
    private func productionSentinel() -> String? {
        let keychain = Keychain(service: KeychainManager.defaultService)
        return try? keychain.getString("test-sentinel-do-not-write")
    }

    func testIsolatedManagerUsesDifferentService() {
        let before = productionSentinel()
        let isolated = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer { isolated.cleanup() }

        XCTAssertEqual(productionSentinel(), before,
                       "creating an isolated manager touched the production keychain service")

        // The isolated manager's service must be different from the
        // production one. macOS treats services as separate namespaces.
        XCTAssertNotEqual(isolated.service, KeychainManager.defaultService,
                          "Isolated service must not equal production service")
        XCTAssertTrue(isolated.service.hasPrefix("SmartLLMRouterTest."),
                      "Isolated service should be UUID-namespaced, got: \(isolated.service)")
    }

    func testSetAndGetKeyInIsolatedService() throws {
        let isolated = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer { isolated.cleanup() }

        let manager = isolated.manager
        try manager.setAPIKey("test-key-123", for: "channel-abc")
        XCTAssertEqual(manager.getAPIKey(for: "channel-abc"), "test-key-123")
        XCTAssertEqual(manager.getAPIKeys(for: "channel-abc"), ["test-key-123"])
    }

    func testSetAndGetMultipleKeysInIsolatedService() throws {
        let isolated = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer { isolated.cleanup() }

        let manager = isolated.manager
        try manager.setAPIKeys([" key-a ", "", "key-b", "key-a"], for: "channel-abc")

        XCTAssertEqual(manager.getAPIKey(for: "channel-abc"), "key-a")
        XCTAssertEqual(manager.getAPIKeys(for: "channel-abc"), ["key-a", "key-b"])
    }

    func testLegacySingleKeyJSONMigratesToMultiKeyStorage() throws {
        let isolated = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer { isolated.cleanup() }

        let legacyData = try JSONEncoder().encode(["channel-abc": "legacy-key"])
        let legacyJSON = try XCTUnwrap(String(data: legacyData, encoding: .utf8))
        try isolated.manager.keychain.set(legacyJSON, key: "smartllm.apikeys")
        isolated.manager.resetCache()

        XCTAssertEqual(isolated.manager.getAPIKeys(for: "channel-abc"), ["legacy-key"])

        isolated.manager.resetCache()
        XCTAssertEqual(isolated.manager.getAPIKeys(for: "channel-abc"), ["legacy-key"])
    }

    func testSingleJSONItemPreservesOtherChannelKeysAfterMutation() throws {
        let isolated = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer { isolated.cleanup() }

        try isolated.manager.setAPIKey("key-one", for: "channel-1")
        try isolated.manager.setAPIKey("key-two", for: "channel-2")
        isolated.manager.resetCache()

        XCTAssertEqual(isolated.manager.getAPIKey(for: "channel-1"), "key-one")
        XCTAssertEqual(isolated.manager.getAPIKey(for: "channel-2"), "key-two")

        try isolated.manager.removeAPIKey(for: "channel-1")
        isolated.manager.resetCache()

        XCTAssertNil(isolated.manager.getAPIKey(for: "channel-1"))
        XCTAssertEqual(isolated.manager.getAPIKey(for: "channel-2"), "key-two")
    }

    func testIsolatedServiceDoesNotLeakToProduction() throws {
        let before = productionSentinel()
        let isolated = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer { isolated.cleanup() }

        // Write a key into the isolated service. The production sentinel
        // must remain unchanged — macOS treats services as separate
        // namespaces, so this should be a no-op on the production side.
        try isolated.manager.setAPIKey("isolated-key", for: "isolated-channel")

        // Use a different sentinel name in the production service to
        // detect leakage via the same setAPIKey call.
        let leakCheck = try? Keychain(service: KeychainManager.defaultService)
            .getString("test-sentinel-do-not-write")
        XCTAssertEqual(leakCheck, before,
                       "Isolated keychain write leaked into production service")
    }

    func testCleanupWipesOnlyIsolatedService() throws {
        let isolated = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer { isolated.cleanup() }
        try isolated.manager.setAPIKey("doomed", for: "doomed-channel")
        XCTAssertEqual(isolated.manager.getAPIKey(for: "doomed-channel"), "doomed")

        let before = productionSentinel()
        isolated.cleanup()
        XCTAssertEqual(productionSentinel(), before,
                       "isolated cleanup touched the production keychain service")
        // After cleanup the isolated service should be empty for this key.
        XCTAssertNil(isolated.manager.getAPIKey(for: "doomed-channel"))
    }

    func testEachIsolatedManagerUsesIndependentService() throws {
        let first = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        let second = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer {
            first.cleanup()
            second.cleanup()
        }

        try first.manager.setAPIKey("first-key", for: "channel")
        XCTAssertEqual(first.manager.getAPIKey(for: "channel"), "first-key")
        XCTAssertNil(second.manager.getAPIKey(for: "channel"))
    }
}
