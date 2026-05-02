import Foundation
import KeychainAccess

class KeychainManager {
    static let shared = KeychainManager()
    private let keychain = Keychain(service: "com.smartllmrouter.keys")
    
    private init() {}
    
    func saveKey(id: String, key: String) throws {
        try keychain.set(key, key: id)
    }
    
    func getKey(id: String) -> String? {
        return try? keychain.get(id)
    }
    
    func deleteKey(id: String) throws {
        try keychain.remove(id)
    }
}
