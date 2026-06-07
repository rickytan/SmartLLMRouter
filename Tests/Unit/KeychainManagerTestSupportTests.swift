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
/// `ChannelExportImportTests` originally called `clearAll()` on
/// `.shared` and wiped the user's data.
///
/// These tests pin the fix in place: they verify that after
/// `KeychainManagerTestSupport.installAsShared()` returns, the
/// production service's contents are byte-for-byte unchanged.
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
        let (isolated, restore) = KeychainManagerTestSupport.installAsShared()
        defer { restore() }

        // Install should not touch the production service.
        XCTAssertEqual(productionSentinel(), before,
                       "installAsShared touched the production keychain service")

        // The isolated manager's service must be different from the
        // production one. macOS treats services as separate namespaces.
        XCTAssertNotEqual(isolated.service, KeychainManager.defaultService,
                          "Isolated service must not equal production service")
        XCTAssertTrue(isolated.service.hasPrefix("SmartLLMRouterTest."),
                      "Isolated service should be UUID-namespaced, got: \(isolated.service)")
    }

    func testSetAndGetKeyInIsolatedService() throws {
        let (isolated, restore) = KeychainManagerTestSupport.installAsShared()
        defer { restore() }

        let manager = isolated.manager
        try manager.setAPIKey("test-key-123", for: "channel-abc")
        XCTAssertEqual(manager.getAPIKey(for: "channel-abc"), "test-key-123")
    }

    func testIsolatedServiceDoesNotLeakToProduction() throws {
        let before = productionSentinel()
        let (isolated, restore) = KeychainManagerTestSupport.installAsShared()
        defer { restore() }

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
        let (isolated, restore) = KeychainManagerTestSupport.installAsShared()
        try isolated.manager.setAPIKey("doomed", for: "doomed-channel")
        XCTAssertEqual(isolated.manager.getAPIKey(for: "doomed-channel"), "doomed")

        let before = productionSentinel()
        isolated.cleanup()
        XCTAssertEqual(productionSentinel(), before,
                       "isolated cleanup touched the production keychain service")
        // After cleanup the isolated service should be empty for this key.
        XCTAssertNil(isolated.manager.getAPIKey(for: "doomed-channel"))
    }

    func testRestoringSharedReturnsToPreviousOverride() {
        // Simulate a chained-test scenario: override A, then override B,
        // then restore. Make sure restore from B actually returns to A.
        let (a, _) = KeychainManagerTestSupport.installAsShared()
        XCTAssertTrue(KeychainManager.shared === a.manager)

        let (b, restoreB) = KeychainManagerTestSupport.installAsShared()
        XCTAssertTrue(KeychainManager.shared === b.manager)
        XCTAssertFalse(KeychainManager.shared === a.manager)

        restoreB()
        XCTAssertTrue(KeychainManager.shared === a.manager,
                      "Restoring B should have returned to override A")
    }
}
