import Foundation
@testable import SmartLLMRouter

/// Test helpers for `KeychainManager`.
///
/// The unit-test target inherits the host app's bundle ID (via
/// `TEST_HOST`/`BUNDLE_LOADER` in `project.yml`), so any test that
/// uses the production keychain service would also touch the
/// user's real keychain. Concretely: calling `clearAll()` on the
/// production `KeychainManager` would delete every API key the user
/// has ever saved. That regression has already happened once during
/// development — a test once called `clearAll()` against the production
/// service and wiped the user's data.
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
