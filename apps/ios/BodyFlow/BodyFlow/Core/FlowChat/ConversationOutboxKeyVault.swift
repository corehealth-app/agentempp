import CryptoKit
import Foundation
import Security

/// Unlike SecureStoring's intentional upsert, encryption key creation is
/// add-only. Concurrent creators re-read the winning item, never replace it.
struct ConversationOutboxKeyVault: Sendable {
    let service: String
    private let security: any KeychainSecurityClient

    init(service: String = "app.performe.conversation-outbox.v1", security: any KeychainSecurityClient = SystemKeychainSecurityClient()) {
        self.service = service; self.security = security
    }

    func key(owner: ConversationOutboxOwner, mayCreate: Bool) async throws -> SymmetricKey {
        let descriptor = KeychainItemDescriptor(
            itemClass: .genericPassword, service: service, account: owner.hash,
            accessibility: .whenUnlockedThisDeviceOnly, synchronizable: false, accessGroup: nil
        )
        switch await security.read(descriptor) {
        case .data(let data): return try decode(data)
        case .failure: throw ConversationOutboxError.keyUnavailable
        case .notFound: break
        }
        guard mayCreate else { throw ConversationOutboxError.keyUnavailable }
        let created = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let status = await security.add(descriptor, data: created)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw ConversationOutboxError.keyUnavailable }
        // Read even after successful add; no local-only key can seal a file
        // before its durable Keychain item is available to the next process.
        guard case .data(let persisted) = await security.read(descriptor) else { throw ConversationOutboxError.keyUnavailable }
        return try decode(persisted)
    }

    private func decode(_ data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw ConversationOutboxError.keyUnavailable }
        return SymmetricKey(data: data)
    }
}
