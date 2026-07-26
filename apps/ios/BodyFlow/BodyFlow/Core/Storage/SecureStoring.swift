import Foundation

protocol SecureStoring: Sendable {
    func data(forKey key: String) async -> Data?
    func store(_ data: Data, forKey key: String) async
    func removeData(forKey key: String) async
}

actor InMemorySecureStore: SecureStoring {
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func store(_ data: Data, forKey key: String) {
        values[key] = data
    }

    func removeData(forKey key: String) {
        values.removeValue(forKey: key)
    }
}
