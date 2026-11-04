import CryptoKit
import Foundation
import Security
import Testing
@testable import BodyFlow

@Suite("Conversation outbox native session and Keychain")
struct ConversationOutboxNativeLifecycleTests {
    @Test func actualLifecycleRejectsOldAccountCallbacksAndPreservesBothQueues() async throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        let authStore = AuthenticationSessionStore(secureStore: InMemorySecureStore(), now: { Date(timeIntervalSince1970: 1_000) })
        let a = record(userID: fixture.lease.userID)
        try await authStore.replace(with: a)
        let lifecycle = SessionLifecycleCoordinator(store: authStore, remote: OutboxNoNetworkAuth(), refreshPolicy: .init(now: { Date(timeIntervalSince1970: 1_000) }, leeway: 60))
        let vault = ConversationOutboxKeyVault(service: "synthetic", security: OutboxKeychainFake())
        let first = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        let id = try await first.enqueue(source: .text("private account A"), server: try server(await lifecycle.leaseForRequest(), epoch: fixture.epoch))
        let ticket = try await first.prepareDispatch(commandID: id, server: try server(await lifecycle.leaseForRequest(), epoch: fixture.epoch))
        let originalA = try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner))
        try await lifecycle.switch(to: record(userID: "00000000-0000-0000-0000-000000000002"))
        let second = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        _ = try await second.enqueue(source: .text("private account B"), server: try server(await lifecycle.leaseForRequest(), epoch: fixture.epoch))
        let ownerB = try ConversationOutboxOwner(lease: await lifecycle.leaseForRequest())
        let originalB = try Data(contentsOf: fixture.store.fileURL(owner: ownerB))
        await #expect(throws: (any Error).self) { try await first.markWaiting(ticket: ticket, hold: .reset) }
        await #expect(throws: (any Error).self) { try await first.discardUnsent(commandID: id) }
        let probe = await MainActor.run { OutboxSnapshotProbe() }
        await #expect(throws: (any Error).self) { try await first.publishSnapshot { probe.entries = $0 } }
        #expect(await probe.entries?.count == nil)
        #expect(try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner)) == originalA)
        #expect(try Data(contentsOf: fixture.store.fileURL(owner: ownerB)) == originalB)
        #expect(await lifecycle.signOut() == .unconfirmed)
        #expect(try Data(contentsOf: fixture.store.fileURL(owner: ownerB)) == originalB)
        try await lifecycle.switch(to: a)
        let restored = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        #expect(try await restored.reconciliationTicket(commandID: id).wireBody == ticket.wireBody)
        await first.invalidate(); await second.invalidate(); await restored.invalidate()
    }

    @Test func actualLifecycleAcknowledgesOnlyTypedFactualPacketAndPublishesOwnedFeedback() async throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        #if SWIFT_PACKAGE
        let url = try #require(Bundle.module.url(forResource: "ConversationMealCommandResultFixtures", withExtension: "json"))
        #else
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/ConversationMealCommandResultFixtures.json")
        #endif
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let wire = try #require(root["wire_command"] as? [String: Any])
        let command = try ConversationMealCommand(wireBody: JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys, .withoutEscapingSlashes]))
        let ownerID = try #require(root["owner_id"] as? String)
        let epoch = try #require(root["epoch"] as? String)
        let payload = try #require((root["cases"] as? [[String: Any]])?.first?["payload"] as? [String: Any])
        let resultData = try JSONSerialization.data(withJSONObject: payload)
        let authStore = AuthenticationSessionStore(secureStore: InMemorySecureStore(), now: { Date(timeIntervalSince1970: 1_000) })
        try await authStore.replace(with: record(userID: ownerID))
        let lifecycle = SessionLifecycleCoordinator(store: authStore, remote: OutboxNoNetworkAuth(), refreshPolicy: .init(now: { Date(timeIntervalSince1970: 1_000) }, leeway: 60))
        let lease = try await lifecycle.leaseForRequest(), owner = try ConversationOutboxOwner(lease: lease)
        let keychain = OutboxKeychainFake()
        await keychain.seed(fixture.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
        let vault = ConversationOutboxKeyVault(service: "synthetic", security: keychain)
        let observed = try server(lease, epoch: #require(UUID(uuidString: epoch)))
        try fixture.store.update(owner: owner, key: fixture.key) { $0.append(.init(command: command, originalServerEpoch: observed.epoch)) }
        let session = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        let ticket = try await session.prepareDispatch(commandID: command.commandID, server: observed)
        let probe = await MainActor.run { NativeOutboxSavedProbe() }
        try await session.acknowledgeSaved(ticket: ticket, resultData: resultData, server: observed) { probe.values.append($0) }
        #expect(try fixture.store.load(owner: owner, key: fixture.key).isEmpty)
        let published = await probe.values
        #expect(published.count == 1)
        #expect(published.first?.feedback?.scope.ownerID == ownerID)
        #expect(published.first?.feedback?.scope.sessionGeneration == lease.generation)
        await session.invalidate()
    }

    @Test func realKeychainRoundTripUsesUniqueSyntheticServiceAndCleansItsItem() async throws {
        let service = "app.performe.synthetic-outbox-test.\(UUID().uuidString.lowercased())"
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        let descriptor = KeychainItemDescriptor(itemClass: .genericPassword, service: service, account: fixture.owner.hash, accessibility: .whenUnlockedThisDeviceOnly, synchronizable: false, accessGroup: nil)
        let security = SystemKeychainSecurityClient()
        do {
            let vault = ConversationOutboxKeyVault(service: service, security: security)
            let key = try await vault.key(owner: fixture.owner, mayCreate: true)
            try fixture.store.update(owner: fixture.owner, key: key) {
                $0.append(.init(command: try ConversationMealCommand(source: .text("synthetic Keychain round trip")), originalServerEpoch: fixture.epoch))
            }
            let reopened = try await ConversationOutboxKeyVault(service: service, security: security).key(owner: fixture.owner, mayCreate: false)
            #expect(try fixture.store.load(owner: fixture.owner, key: reopened).count == 1)
        } catch {
            _ = await security.delete(descriptor)
            throw error
        }
        #expect(await security.delete(descriptor) == errSecSuccess)
        guard case .notFound = await security.read(descriptor) else {
            Issue.record("Task-owned synthetic Keychain item was not removed")
            return
        }
    }

    private func server(_ lease: SessionLease, epoch: UUID) throws -> ConversationOutboxServerObservation {
        .init(ownerID: try #require(UUID(uuidString: lease.userID)), localSessionGeneration: lease.generation, epoch: epoch)
    }

    private func record(userID: String) -> AuthenticationSessionRecord {
        func base64(_ value: String) -> String {
            Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return AuthenticationSessionRecord(userID: userID, email: "synthetic@fixture.invalid", isEmailConfirmed: true, isOnboardingCompleted: true,
                                           accessToken: "\(base64("{\"alg\":\"none\"}")).\(base64("{\"sub\":\"\(userID)\"}")).synthetic",
                                           refreshToken: "synthetic-only", expiresAt: Date(timeIntervalSince1970: 1_200))
    }
}

private struct OutboxNoNetworkAuth: SupabaseAuthRemoteOperating {
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord { throw AuthenticationError.operationUnavailable }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult { throw AuthenticationError.operationUnavailable }
    func requestPasswordRecovery(email: String) throws { throw AuthenticationError.operationUnavailable }
}

@MainActor private final class NativeOutboxSavedProbe { var values: [ConversationOutboxSavedPublication] = [] }
