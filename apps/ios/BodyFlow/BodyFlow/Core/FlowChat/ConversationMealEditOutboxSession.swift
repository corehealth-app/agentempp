import CryptoKit
import Foundation

struct ConversationMealEditOutboxTicket: Sendable, CustomStringConvertible, CustomReflectable {
  let operation: ConversationMealEditOperation
  let ownerHash: String
  let localSessionGeneration: UInt64
  fileprivate let scope: UUID
  var id: ConversationMealEditOutboxID { .init(operation: operation) }
  var commandID: UUID { operation.commandID }
  var operationID: UUID { operation.operationID }
  var originalPatientOwnerID: UUID { operation.ownerID }
  var originalServerEpoch: UUID { operation.epoch }
  var originalInputHash: String { operation.originalInputHash }
  var operationInputHash: String { operation.operationInputHash }
  var wireBody: Data { operation.wireBody }
  var idempotencyKey: String { operation.idempotencyKey }
  var description: String { "ConversationMealEditOutboxTicket(redacted)" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
struct ConversationMealEditOutboxSavedPublication: Sendable {
  let result: ConversationMealEditResultSnapshot
}
struct ConversationMealEditOutboxViewSnapshot: Sendable {
  struct Held: Sendable {
    let id: ConversationMealEditOutboxID
    let state: ConversationOutboxState
    let canDiscardUnsent: Bool
  }
  let entries: [ConversationMealEditOutboxEntry]
  let held: [Held]
}
private final class MealEditOutboxLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false
  private var closedIDs: Set<ConversationMealEditOutboxID> = []
  func close() { lock.withLock { closed = true } }
  func check() throws {
    try lock.withLock { if closed { throw ConversationOutboxError.sessionClosed } }
  }
  func requireNew(_ id: ConversationMealEditOutboxID) throws {
    try lock.withLock {
      guard !closed else { throw ConversationOutboxError.sessionClosed }
      guard !closedIDs.contains(id) else { throw ConversationOutboxError.invalidTransition }
    }
  }
  // Called inside the actual patient mutation gate immediately after rename,
  // before the await boundary can report cancellation and hide the commit.
  func recordClosed(_ id: ConversationMealEditOutboxID) {
    lock.withLock { _ = closedIDs.insert(id) }
  }
}

/// Durable operation core only: no network, retry, new UUID/CAS, nutrition or XP.
/// A group read is required by the actual controller before making new intent;
/// a factual ACK never depends on another group refresh succeeding afterward.
actor ConversationMealEditOutboxSession {
  static let keychainService = "app.performe.conversation-meal-edit-outbox.v1"
  private let lifecycle: any SessionLifecycleProviding
  private let store: EncryptedConversationMealEditOutboxStore
  private let owner: ConversationOutboxOwner
  private let scope = UUID()
  private let lifetime: MealEditOutboxLifetime
  private var lease: SessionLease?
  private var key: SymmetricKey?
  private var workID: UUID?
  private init(
    lifecycle: any SessionLifecycleProviding, lease: SessionLease,
    store: EncryptedConversationMealEditOutboxStore, owner: ConversationOutboxOwner,
    key: SymmetricKey, lifetime: MealEditOutboxLifetime
  ) {
    self.lifecycle = lifecycle
    self.lease = lease
    self.store = store
    self.owner = owner
    self.key = key
    self.lifetime = lifetime
  }
  static func open(
    lifecycle: any SessionLifecycleProviding,
    store: EncryptedConversationMealEditOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(service: keychainService),
    expectedLease: SessionLease? = nil
  ) async throws -> Self {
    guard keyVault.service == keychainService else { throw ConversationOutboxError.keyUnavailable }
    let lease = try await lifecycle.leaseForRequest()
    if let expectedLease {
      guard lease.userID == expectedLease.userID, lease.generation == expectedLease.generation
      else { throw SessionLifecycleError.sessionSuperseded }
      try await lifecycle.validate(expectedLease)
    }
    let owner = try ConversationOutboxOwner(lease: lease)
    let exists = try await lifecycle.performPatientStateOperation(lease: lease) {
      try store.containsCiphertext(owner: owner)
    }
    let key = try await keyVault.key(owner: owner, mayCreate: !exists)
    _ = try await lifecycle.performPatientStateOperation(lease: lease) {
      try store.load(owner: owner, key: key)
    }
    let lifetime = MealEditOutboxLifetime()
    let session = Self(
      lifecycle: lifecycle, lease: lease, store: store, owner: owner, key: key, lifetime: lifetime)
    do {
      let workID = try await lifecycle.beginPatientWork(lease: lease) { [weak session] in
        lifetime.close()
        Task { await session?.invalidate() }
      }
      try await session.installWork(workID)
      try await lifecycle.validate(lease)
      try lifetime.check()
      try Task.checkCancellation()
      return session
    } catch {
      await session.invalidate()
      throw error
    }
  }
  private func installWork(_ id: UUID) async throws {
    do {
      try lifetime.check()
      workID = id
    } catch {
      await lifecycle.finishPatientWork(id)
      throw error
    }
  }
  @discardableResult func enqueue(
    operation: ConversationMealEditOperation, server: ConversationOutboxServerObservation
  ) async throws -> ConversationMealEditOutboxID {
    try validateObservation(server, forEnqueue: true)
    guard operation.ownerID == server.ownerID, operation.epoch == server.epoch else {
      throw ConversationOutboxError.invalidServerObservation
    }
    let id = ConversationMealEditOutboxID(operation: operation)
    let lifetime = lifetime
    try await stateOperation(server: server) { store, owner, key in
      try lifetime.requireNew(id)
      try store.update(owner: owner, key: key) { entries in
        if let existing = entries.first(where: { $0.id == id }) {
          guard editOutboxSame(existing.operation, operation) else {
            throw ConversationOutboxError.invalidTransition
          }
        } else {
          entries.append(.init(operation: operation))
        }
      }
    }
    return id
  }
  func prepareDispatch(
    id: ConversationMealEditOutboxID, server: ConversationOutboxServerObservation
  ) async throws -> ConversationMealEditOutboxTicket {
    try validateObservation(server)
    let entry = try await stateOperation(server: server) { store, owner, key in
      try store.update(owner: owner, key: key) { entries in
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
          throw ConversationOutboxError.commandNotFound
        }
        let entry = entries[index]
        guard entry.operation.ownerID == server.ownerID, entry.operation.epoch == server.epoch
        else { throw ConversationOutboxError.invalidServerObservation }
        guard entry.state == .queued, entry.hold == nil else {
          throw ConversationOutboxError.reconciliationRequired
        }
        entries[index].state = .dispatchedUnknown
        return entries[index]
      }
    }
    return try ticket(entry)
  }
  func reconciliationTicket(id: ConversationMealEditOutboxID) async throws
    -> ConversationMealEditOutboxTicket
  {
    let entry = try await stateOperation { store, owner, key in
      guard let entry = try store.load(owner: owner, key: key).first(where: { $0.id == id }) else {
        throw ConversationOutboxError.commandNotFound
      }
      guard entry.state != .queued else { throw ConversationOutboxError.invalidTransition }
      return entry
    }
    return try ticket(entry)
  }
  func markWaiting(
    ticket: ConversationMealEditOutboxTicket, hold: ConversationMealEditOutboxHold,
    server: ConversationOutboxServerObservation? = nil
  )
    async throws
  {
    try validateTicket(ticket)
    if let server {
      try validateObservation(server)
      guard ticket.originalPatientOwnerID == server.ownerID,
        ticket.originalServerEpoch == server.epoch
      else { throw ConversationOutboxError.invalidServerObservation }
    }
    try await stateOperation(server: server) { store, owner, key in
      try store.update(owner: owner, key: key) { entries in
        let index = try editOutboxIndex(ticket, in: entries)
        guard entries[index].state != .queued else {
          throw ConversationOutboxError.invalidTransition
        }
        entries[index].state = .waitingReconciliation
        if entries[index].hold.map({ $0.priority < hold.priority }) ?? true {
          entries[index].hold = hold
        }
      }
    }
  }
  func authorizeResubmission(
    ticket: ConversationMealEditOutboxTicket, absent: ConversationMealEditAbsentSnapshot,
    server: ConversationOutboxServerObservation
  ) async throws {
    try validateObservation(server)
    try validateTicket(ticket)
    guard ticket.originalPatientOwnerID == server.ownerID,
      ticket.originalServerEpoch == server.epoch, absent.matches(operation: ticket.operation)
    else { throw ConversationOutboxError.invalidTransition }
    try await stateOperation(server: server) { store, owner, key in
      let entries = try store.load(owner: owner, key: key)
      let index = try editOutboxIndex(ticket, in: entries)
      guard entries[index].state != .queued, editOutboxCanResolve(entries[index].hold) else {
        throw ConversationOutboxError.reconciliationRequired
      }
    }
  }
  func acknowledgeSaved(
    ticket: ConversationMealEditOutboxTicket, result: ConversationMealEditResultSnapshot,
    server: ConversationOutboxServerObservation,
    publish: @escaping @MainActor @Sendable (ConversationMealEditOutboxSavedPublication) -> Void
  ) async throws {
    try validateObservation(server)
    try validateTicket(ticket)
    guard ticket.originalPatientOwnerID == server.ownerID,
      ticket.originalServerEpoch == server.epoch, result.matches(operation: ticket.operation)
    else { throw ConversationOutboxError.invalidTransition }
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    let lifetime = lifetime
    try await stateOperation(server: server) { store, owner, key in
      try store.update(owner: owner, key: key) { entries in
        let index = try editOutboxIndex(ticket, in: entries)
        guard entries[index].state != .queued, editOutboxCanResolve(entries[index].hold) else {
          throw ConversationOutboxError.reconciliationRequired
        }
        entries.remove(at: index)
      }
      lifetime.recordClosed(ticket.id)
    }
    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
      try lifetime.check()
      try Task.checkCancellation()
      try server.withCurrentAuthority { publish(.init(result: result)) }
    }
  }
  func discardUnsent(
    id: ConversationMealEditOutboxID, server: ConversationOutboxServerObservation? = nil
  ) async throws {
    if let server { try validateObservation(server) }
    let lifetime = lifetime
    try await stateOperation(server: server) { store, owner, key in
      try store.update(owner: owner, key: key) { entries in
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
          throw ConversationOutboxError.commandNotFound
        }
        if let server {
          guard entries[index].operation.ownerID == server.ownerID,
            entries[index].operation.epoch == server.epoch
          else { throw ConversationOutboxError.invalidServerObservation }
        }
        guard entries[index].state == .queued else {
          throw ConversationOutboxError.reconciliationRequired
        }
        entries.remove(at: index)
      }
      lifetime.recordClosed(id)
    }
  }
  func holdForLocalReset(
    id: ConversationMealEditOutboxID, server: ConversationOutboxServerObservation? = nil
  ) async throws {
    if let server { try validateObservation(server) }
    try await stateOperation(server: server) { store, owner, key in
      try store.update(owner: owner, key: key) { entries in
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
          throw ConversationOutboxError.commandNotFound
        }
        if let server {
          guard entries[index].operation.ownerID == server.ownerID,
            entries[index].operation.epoch == server.epoch
          else { throw ConversationOutboxError.invalidServerObservation }
        }
        if entries[index].state != .queued { entries[index].state = .waitingReconciliation }
        entries[index].hold = .reset
      }
    }
  }
  func publishSnapshot(
    server: ConversationOutboxServerObservation,
    _ publish: @escaping @MainActor @Sendable (ConversationMealEditOutboxViewSnapshot) -> Void
  ) async throws {
    try validateObservation(server)
    guard let lease, let key else { throw ConversationOutboxError.sessionClosed }
    let store = store
    let owner = owner
    let lifetime = lifetime
    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
      try lifetime.check()
      try Task.checkCancellation()
      try server.withCurrentAuthority {
        let entries = try store.load(owner: owner, key: key)
        var visible: [ConversationMealEditOutboxEntry] = []
        var held: [ConversationMealEditOutboxViewSnapshot.Held] = []
        for entry in entries {
          if entry.operation.ownerID == server.ownerID, entry.operation.epoch == server.epoch {
            visible.append(entry)
          } else {
            held.append(
              .init(id: entry.id, state: entry.state, canDiscardUnsent: entry.state == .queued))
          }
        }
        publish(.init(entries: visible, held: held))
      }
    }
  }
  func invalidate() async {
    lifetime.close()
    key = nil
    lease = nil
    if let id = workID {
      workID = nil
      await lifecycle.finishPatientWork(id)
    }
  }
  private func validateTicket(_ ticket: ConversationMealEditOutboxTicket) throws {
    try lifetime.check()
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    guard ticket.scope == scope, ticket.ownerHash == owner.hash,
      ticket.localSessionGeneration == lease.generation
    else { throw ConversationOutboxError.invalidTransition }
  }
  private func ticket(_ entry: ConversationMealEditOutboxEntry) throws
    -> ConversationMealEditOutboxTicket
  {
    try lifetime.check()
    try Task.checkCancellation()
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    return .init(
      operation: entry.operation, ownerHash: owner.hash, localSessionGeneration: lease.generation,
      scope: scope)
  }
  private func validateObservation(
    _ server: ConversationOutboxServerObservation, forEnqueue: Bool = false
  ) throws {
    try lifetime.check()
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    guard !server.isEnqueueOnly || forEnqueue, UUID(uuidString: lease.userID) == server.authUserID,
      lease.generation == server.localSessionGeneration
    else { throw ConversationOutboxError.invalidServerObservation }
    try server.withCurrentAuthority {}
  }
  private func stateOperation<Value: Sendable>(
    server: ConversationOutboxServerObservation? = nil,
    _ operation:
      @escaping @Sendable (
        EncryptedConversationMealEditOutboxStore, ConversationOutboxOwner, SymmetricKey
      ) throws -> Value
  ) async throws -> Value {
    guard let lease, let key else { throw ConversationOutboxError.sessionClosed }
    let store = store
    let owner = owner
    let lifetime = lifetime
    let result = try await lifecycle.performPatientStateOperation(lease: lease) {
      try lifetime.check()
      try Task.checkCancellation()
      if let server { return try server.withCurrentAuthority { try operation(store, owner, key) } }
      return try operation(store, owner, key)
    }
    try lifetime.check()
    try Task.checkCancellation()
    return result
  }
}
private func editOutboxCanResolve(_ hold: ConversationMealEditOutboxHold?) -> Bool {
  hold != .reset && hold != .staleEpoch && hold != .serverChanged
}
private func editOutboxSame(_ a: ConversationMealEditOperation, _ b: ConversationMealEditOperation)
  -> Bool
{
  a.ownerID == b.ownerID && a.commandID == b.commandID && a.originalInputHash == b.originalInputHash
    && a.epoch == b.epoch && a.operationID == b.operationID
    && a.operationInputHash == b.operationInputHash && a.wireBody == b.wireBody
    && a.expectedRevision == b.expectedRevision && a.expectedVersion == b.expectedVersion
}
private func editOutboxIndex(
  _ ticket: ConversationMealEditOutboxTicket, in entries: [ConversationMealEditOutboxEntry]
) throws -> Int {
  guard let index = entries.firstIndex(where: { $0.id == ticket.id }) else {
    throw ConversationOutboxError.commandNotFound
  }
  guard editOutboxSame(entries[index].operation, ticket.operation) else {
    throw ConversationOutboxError.invalidTransition
  }
  return index
}
