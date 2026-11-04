import CryptoKit
import Foundation

/// A transport preparation ticket, not a receipt or permission to use the
/// legacy Flow writer. Reconciliation carries the exact original command.
struct ConversationOutboxTicket: Sendable, CustomStringConvertible, CustomReflectable {
    let commandID: UUID
    let inputHash: String
    let wireBody: Data
    let idempotencyKey: String
    let ownerHash: String
    let localSessionGeneration: UInt64
    fileprivate let scope: UUID

    var description: String { "ConversationOutboxTicket(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}

/// Explicit close also fences synchronous operations already queued at the
/// lifecycle gate. No plaintext queue or authentication token is cached here.
private final class ConversationOutboxLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    func close() { lock.withLock { closed = true } }
    func check() throws {
        try lock.withLock { if closed { throw ConversationOutboxError.sessionClosed } }
    }
}

/// Candidate core only. There is deliberately no transport call, HTTP-success
/// acknowledgement, new registration, reward, automatic resend or UUID renewal.
actor ConversationOutboxSession {
    private let lifecycle: any SessionLifecycleProviding
    private let store: EncryptedConversationOutboxStore
    private let owner: ConversationOutboxOwner
    private let scope = UUID()
    private let lifetime = ConversationOutboxLifetime()
    private var lease: SessionLease?
    private var key: SymmetricKey?
    private var workID: UUID?

    private init(lifecycle: any SessionLifecycleProviding, lease: SessionLease, store: EncryptedConversationOutboxStore, owner: ConversationOutboxOwner, key: SymmetricKey) {
        self.lifecycle = lifecycle; self.lease = lease; self.store = store; self.owner = owner; self.key = key
    }

    static func open(
        lifecycle: any SessionLifecycleProviding,
        store: EncryptedConversationOutboxStore = .device,
        keyVault: ConversationOutboxKeyVault = .init()
    ) async throws -> ConversationOutboxSession {
        let lease = try await lifecycle.leaseForRequest()
        let owner = try ConversationOutboxOwner(lease: lease)
        let exists = try await lifecycle.performPatientStateOperation(lease: lease) {
            try store.containsCiphertext(owner: owner)
        }
        // A lost key with existing ciphertext is an error, never an empty queue
        // or a reason to create a replacement key and overwrite unknown work.
        let key = try await keyVault.key(owner: owner, mayCreate: !exists)
        _ = try await lifecycle.performPatientStateOperation(lease: lease) { try store.load(owner: owner, key: key) }
        let session = ConversationOutboxSession(lifecycle: lifecycle, lease: lease, store: store, owner: owner, key: key)
        do {
            let id = try await lifecycle.beginPatientWork(lease: lease) { [weak session] in
                Task { await session?.invalidate() }
            }
            try await session.installWork(id)
            try await lifecycle.validate(lease)
            try await session.checkOpen()
            return session
        } catch { await session.invalidate(); throw error }
    }

    private func installWork(_ id: UUID) async throws {
        do { try lifetime.check(); workID = id }
        catch { await lifecycle.finishPatientWork(id); throw error }
    }

    private func checkOpen() throws { try lifetime.check() }

    /// Every actual new user intent gets a fresh UUID, even identical source.
    /// Failed persistence returns no enqueue success and preserves prior disk.
    func enqueue(source: ConversationMealCommand.Source, mealType: ConversationMealCommand.MealType? = nil) async throws -> UUID {
        let command = try ConversationMealCommand(source: source, mealType: mealType)
        try await stateOperation { store, owner, key in
            try store.update(owner: owner, key: key) { $0.append(.init(command: command)) }
        }
        return command.commandID
    }

    /// Persist unknown BEFORE returning bytes to a future transport. A crash
    /// before or after send consequently restores an unresolved original ID.
    func prepareDispatch(commandID: UUID) async throws -> ConversationOutboxTicket {
        let entry = try await stateOperation { store, owner, key in
            try store.update(owner: owner, key: key) { entries in
                guard let index = entries.firstIndex(where: { $0.commandID == commandID }) else { throw ConversationOutboxError.commandNotFound }
                guard entries[index].state == .queued else { throw ConversationOutboxError.reconciliationRequired }
                entries[index].state = .dispatchedUnknown
                return entries[index]
            }
        }
        return try ticket(entry)
    }

    /// This ticket permits a future status/reconciliation adapter to identify
    /// original work. It does not authorize blindly POSTing a held command.
    func reconciliationTicket(commandID: UUID) async throws -> ConversationOutboxTicket {
        let entry = try await stateOperation { store, owner, key in
            guard let entry = try store.load(owner: owner, key: key).first(where: { $0.commandID == commandID }) else { throw ConversationOutboxError.commandNotFound }
            guard entry.state != .queued else { throw ConversationOutboxError.invalidTransition }
            return entry
        }
        return try ticket(entry)
    }

    func markWaiting(ticket: ConversationOutboxTicket, hold: ConversationOutboxHold) async throws {
        guard let lease else { throw ConversationOutboxError.sessionClosed }
        guard ticket.scope == scope, ticket.ownerHash == owner.hash, ticket.localSessionGeneration == lease.generation else {
            throw ConversationOutboxError.invalidTransition
        }
        try await stateOperation { store, owner, key in
            try store.update(owner: owner, key: key) { entries in
                guard let index = entries.firstIndex(where: { $0.commandID == ticket.commandID }) else { throw ConversationOutboxError.commandNotFound }
                guard entries[index].wireBody == ticket.wireBody, entries[index].inputHash == ticket.inputHash,
                      entries[index].state != .queued else { throw ConversationOutboxError.invalidTransition }
                entries[index].state = .waitingReconciliation
                if entries[index].hold.map({ $0.priority < hold.priority }) ?? true { entries[index].hold = hold }
            }
        }
    }

    func discardUnsent(commandID: UUID) async throws {
        try await stateOperation { store, owner, key in
            try store.update(owner: owner, key: key) { entries in
                guard let index = entries.firstIndex(where: { $0.commandID == commandID }) else { throw ConversationOutboxError.commandNotFound }
                guard entries[index].state == .queued else { throw ConversationOutboxError.reconciliationRequired }
                entries.remove(at: index)
            }
        }
    }

    /// Read and visible publication share the actual session mutation gate;
    /// callers cannot accidentally publish A's plaintext into B after an await.
    func publishSnapshot(_ publish: @escaping @MainActor @Sendable ([ConversationOutboxEntry]) -> Void) async throws {
        guard let lease, let key else { throw ConversationOutboxError.sessionClosed }
        let store = store, owner = owner, lifetime = lifetime
        try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
            try lifetime.check(); try Task.checkCancellation()
            publish(try store.load(owner: owner, key: key))
        }
    }

    /// Logout/account change releases RAM key and bearer handles, retaining
    /// the account-bound Keychain item and ciphertext for later reconciliation.
    func invalidate() async {
        lifetime.close(); key = nil; lease = nil
        if let id = workID { workID = nil; await lifecycle.finishPatientWork(id) }
    }

    private func ticket(_ entry: ConversationOutboxEntry) throws -> ConversationOutboxTicket {
        try lifetime.check(); try Task.checkCancellation()
        guard let lease else { throw ConversationOutboxError.sessionClosed }
        return ConversationOutboxTicket(commandID: entry.commandID, inputHash: entry.inputHash, wireBody: entry.wireBody,
                                        idempotencyKey: "cmsg1:\(entry.commandID.uuidString.lowercased())",
                                        ownerHash: owner.hash, localSessionGeneration: lease.generation, scope: scope)
    }

    private func stateOperation<Value: Sendable>(_ operation: @escaping @Sendable (EncryptedConversationOutboxStore, ConversationOutboxOwner, SymmetricKey) throws -> Value) async throws -> Value {
        guard let lease, let key else { throw ConversationOutboxError.sessionClosed }
        let store = store, owner = owner, lifetime = lifetime
        let result = try await lifecycle.performPatientStateOperation(lease: lease) {
            try lifetime.check(); try Task.checkCancellation()
            return try operation(store, owner, key)
        }
        try lifetime.check(); try Task.checkCancellation()
        return result
    }
}
