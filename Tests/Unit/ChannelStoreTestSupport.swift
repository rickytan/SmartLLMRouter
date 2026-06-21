import Foundation
@testable import SmartLLMRouter

/// Test helpers for `ChannelStore` and related persistence.
///
/// These utilities guarantee that unit tests do **not** read or write
/// `UserDefaults.standard` or the production `~/Library/Application Support/
/// SmartLLMRouter/channels.json`. Tests that exercise `ChannelStore` must use
/// `makeIsolatedChannelStore()` to get a `ChannelStore` backed by:
///
/// - An in-memory `UserDefaults` suite unique to the test run.
/// - A temporary file URL under `NSTemporaryDirectory()` (or no file at all).
@MainActor
enum ChannelStoreTestSupport {

    /// Create a fresh `ChannelStore` with isolated storage.
    /// - Parameters:
    ///   - useTempFile: if `true` (default), use a temp file URL; if `false`,
    ///     disable file persistence (in-memory only — fastest, no disk I/O).
    /// - Returns: A configured `ChannelStore` plus its storage handles for
    ///   later inspection / cleanup.
    static func makeIsolatedChannelStore(
        useTempFile: Bool = true,
        runtimeState: RouterRuntimeState? = nil
    ) -> IsolatedChannelStore {
        let suiteName = "ChannelStoreTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // Defensive: clear anything left over from a previous run with the
        // same suite name (shouldn't happen with a UUID, but cheap insurance).
        defaults.removePersistentDomain(forName: suiteName)

        let persistence: ChannelsPersistence
        let tempURL: URL?
        if useTempFile {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ChannelStoreTest-\(UUID().uuidString).json")
            tempURL = url
            persistence = ChannelsPersistence(fileURL: url)
        } else {
            tempURL = nil
            persistence = ChannelsPersistence(fileURL: nil)
        }

        let runtimeState = runtimeState ?? RouterRuntimeState(
            circuitBreaker: CircuitBreaker(),
            switchLock: SwitchLock()
        )
        let store = ChannelStore(
            defaults: defaults,
            persistence: persistence,
            runtimeState: runtimeState
        )
        return IsolatedChannelStore(
            store: store,
            defaults: defaults,
            suiteName: suiteName,
            tempFileURL: tempURL
        )
    }

}

/// Bundle returned by `makeIsolatedChannelStore`. Holds the storage handles
/// so tests can inspect them or clean up.
@MainActor
final class IsolatedChannelStore {
    let store: ChannelStore
    let defaults: UserDefaults
    let suiteName: String
    let tempFileURL: URL?

    fileprivate init(store: ChannelStore,
                     defaults: UserDefaults,
                     suiteName: String,
                     tempFileURL: URL?) {
        self.store = store
        self.defaults = defaults
        self.suiteName = suiteName
        self.tempFileURL = tempFileURL
    }

    /// Remove the temp file and clear the in-memory defaults. Idempotent.
    func cleanup() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        defaults.removePersistentDomain(forName: suiteName)
    }
}
