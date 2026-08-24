import Foundation
import Security
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

    @Test("Keychain add uses device-only non-synchronizable generic-password attributes")
    func keychainAddUsesRequiredAttributes() async throws {
        let security = KeychainSecurityStub(updateStatuses: [errSecItemNotFound])
        let store = KeychainSecureStore(service: "com.bodyflow.app.auth-session.v1", security: security)

        try await store.store(Data("fixture".utf8), forKey: "session")

        let added = try #require(await security.addedItems.first)
        #expect(added.descriptor.itemClass == .genericPassword)
        #expect(added.descriptor.accessibility == .whenUnlockedThisDeviceOnly)
        #expect(added.descriptor.synchronizable == false)
        #expect(added.descriptor.accessGroup == nil)
    }

    @Test("Keychain updates an existing item without adding a duplicate")
    func keychainUpdatesExistingItem() async throws {
        let security = KeychainSecurityStub(updateStatuses: [errSecSuccess])
        let store = KeychainSecureStore(service: "com.bodyflow.app.auth-session.v1", security: security)

        try await store.store(Data("updated".utf8), forKey: "session")

        #expect(await security.updatedItems.count == 1)
        #expect(await security.addedItems.isEmpty)
    }

    @Test("Keychain update failures are typed and never attempt add", arguments: [
        errSecInteractionNotAllowed,
        errSecAuthFailed,
        OSStatus(-9_998),
    ])
    func keychainUpdateFailuresAreTyped(status: OSStatus) async {
        let security = KeychainSecurityStub(updateStatuses: [status])
        let store = KeychainSecureStore(service: "com.bodyflow.app.auth-session.v1", security: security)

        await #expect(throws: SecureStorageError.updateFailed(status)) {
            try await store.store(Data("fixture".utf8), forKey: "session")
        }
        #expect(await security.addedItems.isEmpty)
    }

    @Test("Keychain duplicate add and operation failures are typed", arguments: [
        (errSecDuplicateItem, SecureStorageError.addFailed(errSecDuplicateItem)),
        (errSecInteractionNotAllowed, SecureStorageError.addFailed(errSecInteractionNotAllowed)),
        (errSecAuthFailed, SecureStorageError.addFailed(errSecAuthFailed)),
        (OSStatus(-9_999), SecureStorageError.addFailed(OSStatus(-9_999))),
    ])
    func keychainAddFailuresAreTyped(status: OSStatus, expected: SecureStorageError) async {
        let security = KeychainSecurityStub(
            updateStatuses: [errSecItemNotFound],
            addStatus: status
        )
        let store = KeychainSecureStore(service: "com.bodyflow.app.auth-session.v1", security: security)

        await #expect(throws: expected) {
            try await store.store(Data("token-do-not-print".utf8), forKey: "session")
        }
        #expect(!String(reflecting: expected).contains("token-do-not-print"))
    }

    @Test("Keychain read failures are typed and never delete the item")
    func keychainReadFailureDoesNotDelete() async {
        let security = KeychainSecurityStub(readResult: .failure(errSecInteractionNotAllowed))
        let store = KeychainSecureStore(service: "com.bodyflow.app.auth-session.v1", security: security)

        await #expect(throws: SecureStorageError.readFailed(errSecInteractionNotAllowed)) {
            _ = try await store.data(forKey: "session")
        }
        #expect(await security.deleteCount == 0)
    }

    @Test("Keychain delete is idempotent but unexpected failures are typed")
    func keychainDeleteBehavior() async throws {
        let missing = KeychainSecurityStub(deleteStatuses: [errSecItemNotFound])
        try await KeychainSecureStore(service: "fixture", security: missing)
            .removeData(forKey: "session")

        let failing = KeychainSecurityStub(deleteStatuses: [errSecAuthFailed])
        await #expect(throws: SecureStorageError.deleteFailed(errSecAuthFailed)) {
            try await KeychainSecureStore(service: "fixture", security: failing)
                .removeData(forKey: "session")
        }
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

private actor KeychainSecurityStub: KeychainSecurityClient {
    private var readResult: KeychainReadResult
    private var updateStatuses: [OSStatus]
    private var addStatus: OSStatus
    private var deleteStatuses: [OSStatus]
    private(set) var updatedItems: [(descriptor: KeychainItemDescriptor, data: Data)] = []
    private(set) var addedItems: [(descriptor: KeychainItemDescriptor, data: Data)] = []
    private(set) var deleteCount = 0

    init(
        readResult: KeychainReadResult = .notFound,
        updateStatuses: [OSStatus] = [errSecSuccess],
        addStatus: OSStatus = errSecSuccess,
        deleteStatuses: [OSStatus] = [errSecSuccess]
    ) {
        self.readResult = readResult
        self.updateStatuses = updateStatuses
        self.addStatus = addStatus
        self.deleteStatuses = deleteStatuses
    }

    func read(_ descriptor: KeychainItemDescriptor) -> KeychainReadResult {
        readResult
    }

    func update(_ descriptor: KeychainItemDescriptor, data: Data) -> OSStatus {
        updatedItems.append((descriptor, data))
        return updateStatuses.isEmpty ? errSecSuccess : updateStatuses.removeFirst()
    }

    func add(_ descriptor: KeychainItemDescriptor, data: Data) -> OSStatus {
        addedItems.append((descriptor, data))
        return addStatus
    }

    func delete(_ descriptor: KeychainItemDescriptor) -> OSStatus {
        deleteCount += 1
        return deleteStatuses.isEmpty ? errSecSuccess : deleteStatuses.removeFirst()
    }
}
