import CryptoKit
import Foundation
import Security
import Testing
@testable import BodyFlow

@Suite("Conversation outbox immutable account keys")
struct ConversationOutboxKeyVaultTests {
    @Test func concurrentCreationUsesAddOnlyWinnerAndPrivateDescriptor() async throws {
        let security = OutboxKeychainFake()
        let first = ConversationOutboxKeyVault(service: "synthetic-outbox-\(UUID())", security: security)
        let second = ConversationOutboxKeyVault(service: first.service, security: security)
        let owner = try OutboxDiskFixture().owner
        async let a = first.key(owner: owner, mayCreate: true)
        async let b = second.key(owner: owner, mayCreate: true)
        let keys = try await [a, b]
        #expect(keys[0].withUnsafeBytes { Data($0) } == keys[1].withUnsafeBytes { Data($0) })
        #expect(await security.updateCount == 0)
        let descriptor = try #require(await security.descriptors.first)
        #expect(descriptor.accessibility == .whenUnlockedThisDeviceOnly)
        #expect(!descriptor.synchronizable)
        #expect(descriptor.accessGroup == nil)
        #expect(descriptor.account == owner.hash)
    }

    @Test func missingOrMalformedKeyNeverReplacesExistingCiphertextKey() async throws {
        let security = OutboxKeychainFake()
        let vault = ConversationOutboxKeyVault(service: "synthetic", security: security)
        let owner = try OutboxDiskFixture().owner
        await #expect(throws: ConversationOutboxError.keyUnavailable) { try await vault.key(owner: owner, mayCreate: false) }
        #expect(await security.addCount == 0)
        await security.seed(Data(repeating: 1, count: 31), owner: owner.hash)
        await #expect(throws: ConversationOutboxError.keyUnavailable) { try await vault.key(owner: owner, mayCreate: true) }
        #expect(await security.addCount == 0)
        #expect(await security.updateCount == 0)
    }
}

actor OutboxKeychainFake: KeychainSecurityClient {
    private var values: [String: Data] = [:]
    private(set) var descriptors: [KeychainItemDescriptor] = []
    private(set) var updateCount = 0
    private(set) var addCount = 0
    func seed(_ data: Data, owner: String) { values[owner] = data }
    func read(_ descriptor: KeychainItemDescriptor) -> KeychainReadResult {
        descriptors.append(descriptor)
        return values[descriptor.account].map(KeychainReadResult.data) ?? .notFound
    }
    func update(_ descriptor: KeychainItemDescriptor, data: Data) -> OSStatus {
        updateCount += 1; values[descriptor.account] = data; return errSecSuccess
    }
    func add(_ descriptor: KeychainItemDescriptor, data: Data) -> OSStatus {
        descriptors.append(descriptor); addCount += 1
        guard values[descriptor.account] == nil else { return errSecDuplicateItem }
        values[descriptor.account] = data; return errSecSuccess
    }
    func delete(_ descriptor: KeychainItemDescriptor) -> OSStatus {
        values.removeValue(forKey: descriptor.account); return errSecSuccess
    }
}
