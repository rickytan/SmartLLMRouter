import Foundation
@testable import SmartLLMRouter

/// Test helpers for `KeychainManager`.
///
/// The unit-test target inherits the host app's bundle ID (via
/// `TEST_HOST`/`BUNDLE_LOADER` in `project.yml`), so any test that
/// touches `KeychainManager.shared` directly would also touch the
/// user's real keychain. Concretely: calling `clearAll()` on the
/// production `KeychainManager` would delete every API key the user
/// has ever saved. That regression has already happened once during
/// development — `ChannelExportImportTests` originally called
/// `clearAll()` on `.shared` and wiped the user's data.
///
/// The fix is to give every test its own `KeychainManager` with a
/// UUID-based service. macOS treats each service as a separate
/// namespace, so the production keychain is never touched.
@MainActor
enum KeychainManagerTestSupport {

    /// Create a fresh `KeychainManager` with a unique service.
    /// Caller is responsible for calling `cleanup()` to delete the
    /// service's items.
    static func makeIsolatedKeychainManager() -> IsolatedKeychainManager {
        let service = "SmartLLMRouterTest.\(UUID().uuidString)"
        let manager = KeychainManager(service: service)
        return IsolatedKeychainManager(manager: manager, service: service)
    }

    /// Install an isolated `KeychainManager` as the shared instance
    /// for the duration of a test. Returns a closure that restores the
    /// previous state. Callers should invoke the closure in `tearDown`.
    @discardableResult
    static func installAsShared() -> (IsolatedKeychainManager, () -> Void) {
        let isolated = makeIsolatedKeychainManager()
        // Capture the previous shared instance (production or a prior
        // test override) so we can restore it. The override memory is
        // safe because each test process is single-threaded for setup.
        let previous = KeychainManager.testOverride
        KeychainManager.setSharedForTesting(isolated.manager)
        let restore = {
            KeychainManager.setSharedForTesting(previous)
            isolated.cleanup()
        }
        return (isolated, restore)
    }
}

/// Bundle returned by `makeIsolatedKeychainManager`. Holds the manager
/// + service name so tests can clean up.
@MainActor
final class IsolatedKeychainManager {
    let manager: KeychainManager
    let service: String

    fileprivate init(manager: KeychainManager, service: String) {
        self.manager = manager
        self.service = service
    }

    /// Delete every key in this service's namespace. Idempotent.
    func cleanup() {
        try? manager.keychain.removeAll()
        manager.resetCache()
    }
}
