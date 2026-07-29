import Foundation
import Testing

@testable import BodyFlow

@Suite("Secure Storage Boundary")
struct SecureStorageTests {
    @Test("stores, reads, and removes data only in memory")
    func storesReadsAndRemovesData() async throws {
        let store = InMemorySecureStore()
        let expected = Data([1, 2, 3])

        try await store.store(expected, forKey: "fixture-key")
        let stored = try await store.data(forKey: "fixture-key")
        #expect(stored == expected)

        try await store.removeData(forKey: "fixture-key")
        let removed = try await store.data(forKey: "fixture-key")
        #expect(removed == nil)
    }

    @Test("propagates secure storage failures")
    func propagatesSecureStorageFailures() async {
        let store = FailingSecureStore()

        await #expect(throws: SecureStorageFixtureError.unavailable) {
            try await store.store(Data([9]), forKey: "fixture-key")
        }
    }

    @Test("Keychain round trips and removes data")
    func keychainRoundTrip() async throws {
        let service = "com.bodyflow.app.tests.\(UUID().uuidString)"
        let store = KeychainSecureStore(service: service)
        let key = "session"
        let payload = Data("fixture".utf8)

        try await store.store(payload, forKey: key)
        #expect(try await store.data(forKey: key) == payload)
        try await store.removeData(forKey: key)
        #expect(try await store.data(forKey: key) == nil)
    }

    @Test("Keychain removal is idempotent for a fresh reset")
    func keychainRemovalIsIdempotent() async throws {
        let service = "com.bodyflow.app.tests.\(UUID().uuidString)"
        let store = KeychainSecureStore(service: service)

        try await store.removeData(forKey: "missing-session")
        try await store.removeData(forKey: "missing-session")

        #expect(try await store.data(forKey: "missing-session") == nil)
    }
}

private enum SecureStorageFixtureError: Error, Equatable, Sendable {
    case unavailable
}

private actor FailingSecureStore: SecureStoring {
    func data(forKey key: String) async throws -> Data? {
        throw SecureStorageFixtureError.unavailable
    }

    func store(_ data: Data, forKey key: String) async throws {
        throw SecureStorageFixtureError.unavailable
    }

    func removeData(forKey key: String) async throws {
        throw SecureStorageFixtureError.unavailable
    }
}
