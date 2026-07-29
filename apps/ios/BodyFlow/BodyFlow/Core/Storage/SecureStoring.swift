import Foundation

protocol SecureStoring: Sendable {
    func data(forKey key: String) async throws -> Data?
    func store(_ data: Data, forKey key: String) async throws
    func removeData(forKey key: String) async throws
}

actor InMemorySecureStore: SecureStoring {
    private var values: [String: Data] = [:]

    func data(forKey key: String) throws -> Data? {
        values[key]
    }

    func store(_ data: Data, forKey key: String) throws {
        values[key] = data
    }

    func removeData(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}
