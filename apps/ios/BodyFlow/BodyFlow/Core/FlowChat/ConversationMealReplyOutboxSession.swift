import CryptoKit
import Foundation

struct ConversationMealReplyOutboxTicket: Sendable, CustomStringConvertible, CustomReflectable {
  let intent: ConversationMealReplyIntent
  let ownerHash: String
  let localSessionGeneration: UInt64
  fileprivate let scope: UUID
  var id: UUID { intent.replyID }
  var parentCommandID: UUID { intent.parentBinding.commandID }
  var replyID: UUID { intent.replyID }
  var originalPatientOwnerID: UUID { intent.parentBinding.ownerID }
  var originalServerEpoch: UUID { intent.parentBinding.epoch }
  var parentInputHash: String { intent.parentBinding.inputHash }
  var replyInputHash: String { intent.replyInputHash }
  var wireBody: Data { intent.wireBody }
  var idempotencyKey: String { intent.idempotencyKey }
  var description: String { "ConversationMealReplyOutboxTicket(redacted)" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
struct ConversationMealReplyDeliveryPublication: Sendable {
  let result: ConversationMealReplyResultSnapshot
}
struct ConversationMealReplyOutboxViewSnapshot: Sendable {
  struct Held: Sendable {
    let id: UUID
    let state: ConversationOutboxState
    let canDiscardUnsent: Bool
  }
  let entries: [ConversationMealReplyOutboxEntry]
  let held: [Held]
}
private final class MealReplyOutboxLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false
  private var closedIDs: Set<UUID> = []
  func close() { lock.withLock { closed = true } }
  func check() throws {
    try lock.withLock { if closed { throw ConversationOutboxError.sessionClosed } }
  }
  func requireNew(_ id: UUID) throws {
    try lock.withLock {
      guard !closed else { throw ConversationOutboxError.sessionClosed }
      guard !closedIDs.contains(id) else { throw ConversationOutboxError.invalidTransition }
    }
  }
  // Called inside the actual patient mutation gate immediately after rename,
  // before the await boundary can report cancellation and hide the commit.
  func recordClosed(_ id: UUID) {
    lock.withLock { _ = closedIDs.insert(id) }
  }
}

/// Same protected store/key/capacity as reports, with a distinct typed intent.
/// No network, new report, nutrition, reward or automatic resubmission.
actor ConversationMealReplyOutboxSession {
  static let keychainService = "app.performe.conversation-outbox.v1"
  private let lifecycle: any SessionLifecycleProviding
  private let store: EncryptedConversationOutboxStore
  private let owner: ConversationOutboxOwner
  private let scope = UUID()
  private let lifetime: MealReplyOutboxLifetime
  private var lease: SessionLease?
  private var key: SymmetricKey?
  private var workID: UUID?
  private init(
    lifecycle: any SessionLifecycleProviding, lease: SessionLease,
    store: EncryptedConversationOutboxStore, owner: ConversationOutboxOwner,
    key: SymmetricKey, lifetime: MealReplyOutboxLifetime
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
    store: EncryptedConversationOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(service: keychainService),
    expectedLease: SessionLease? = nil
  ) async throws -> Self {
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
      try store.loadReplies(owner: owner, key: key)
    }
    let lifetime = MealReplyOutboxLifetime()
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
    intent: ConversationMealReplyIntent, server: ConversationOutboxServerObservation
  ) async throws -> UUID {
    try validateObservation(server, forEnqueue: true)
    guard intent.parentBinding.ownerID == server.ownerID, intent.parentBinding.epoch == server.epoch
    else {
      throw ConversationOutboxError.invalidServerObservation
    }
    let id = intent.replyID
    let lifetime = lifetime
    try await stateOperation(server: server) { store, owner, key in
      try lifetime.requireNew(id)
      try store.updateReplies(owner: owner, key: key) { entries in
        if let existing = entries.first(where: { $0.intent.replyID == id }) {
          guard replyOutboxSame(existing.intent, intent) else {
            throw ConversationOutboxError.invalidTransition
          }
        } else {
          entries.append(.init(intent: intent))
        }
      }
    }
    return id
  }
  func prepareDispatch(
    replyID id: UUID, server: ConversationOutboxServerObservation
  ) async throws -> ConversationMealReplyOutboxTicket {
    try validateObservation(server)
    let entry = try await stateOperation(server: server) { store, owner, key in
      try store.updateReplies(owner: owner, key: key) { entries in
        guard let index = entries.firstIndex(where: { $0.intent.replyID == id }) else {
          throw ConversationOutboxError.commandNotFound
        }
        let entry = entries[index]
        guard entry.intent.parentBinding.ownerID == server.ownerID,
          entry.intent.parentBinding.epoch == server.epoch
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
  func reconciliationTicket(replyID id: UUID) async throws
    -> ConversationMealReplyOutboxTicket
  {
    let entry = try await stateOperation { store, owner, key in
      guard
        let entry = try store.loadReplies(owner: owner, key: key).first(where: {
          $0.intent.replyID == id
        })
      else {
        throw ConversationOutboxError.commandNotFound
      }
      guard entry.state != .queued else { throw ConversationOutboxError.invalidTransition }
      return entry
    }
    return try ticket(entry)
  }
  func markWaiting(
    ticket: ConversationMealReplyOutboxTicket, hold: ConversationOutboxHold,
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
      try store.updateReplies(owner: owner, key: key) { entries in
        let index = try replyOutboxIndex(ticket, in: entries)
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
  /// A read creates no dispatch. Only the controller may consume this check
  /// once after a separate, explicit user action, retaining the same bytes.
  func authorizeResubmission(
    ticket: ConversationMealReplyOutboxTicket, result: ConversationMealReplyResultSnapshot,
    server: ConversationOutboxServerObservation
  ) async throws {
    try validateObservation(server)
    try validateTicket(ticket)
    guard ticket.originalPatientOwnerID == server.ownerID,
      ticket.originalServerEpoch == server.epoch,
      result.matches(intent: ticket.intent, authUserID: server.authUserID),
      result.status == .held, result.childBinding != nil, result.receipt == nil,
      result.reason == "ready_for_explicit_resume" || result.reason == "awaiting_explicit_resume"
    else { throw ConversationOutboxError.invalidTransition }
    try await stateOperation(server: server) { store, owner, key in
      let entries = try store.loadReplies(owner: owner, key: key)
      let index = try replyOutboxIndex(ticket, in: entries)
      guard entries[index].state != .queued, replyOutboxCanResolve(entries[index].hold) else {
        throw ConversationOutboxError.reconciliationRequired
      }
    }
  }
  func acknowledgeDelivery(
    ticket: ConversationMealReplyOutboxTicket, result: ConversationMealReplyResultSnapshot,
    server: ConversationOutboxServerObservation,
    publish: @escaping @MainActor @Sendable (ConversationMealReplyDeliveryPublication) -> Void
  ) async throws {
    try validateObservation(server)
    try validateTicket(ticket)
    guard ticket.originalPatientOwnerID == server.ownerID,
      ticket.originalServerEpoch == server.epoch
    else { throw ConversationOutboxError.invalidServerObservation }
    guard conversationReplyIsDelivery(result, intent: ticket.intent, authUserID: server.authUserID)
    else { throw ConversationOutboxError.invalidTransition }
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    let lifetime = lifetime
    try await stateOperation(server: server) { store, owner, key in
      try store.updateReplies(owner: owner, key: key) { entries in
        let index = try replyOutboxIndex(ticket, in: entries)
        guard entries[index].state != .queued, replyOutboxCanResolve(entries[index].hold) else {
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
    replyID id: UUID, server: ConversationOutboxServerObservation? = nil
  ) async throws {
    if let server { try validateObservation(server) }
    let lifetime = lifetime
    try await stateOperation(server: server) { store, owner, key in
      try store.updateReplies(owner: owner, key: key) { entries in
        guard let index = entries.firstIndex(where: { $0.intent.replyID == id }) else {
          throw ConversationOutboxError.commandNotFound
        }
        // Explicit local discard is permitted for a protected foreign context
        // only while the actual file proves this intent was never dispatched.
        // Auth/key/lifecycle/current grant remain checked inside this gate.
        guard entries[index].state == .queued else {
          throw ConversationOutboxError.reconciliationRequired
        }
        entries.remove(at: index)
      }
      lifetime.recordClosed(id)
    }
  }
  func holdForLocalReset(
    replyID id: UUID, server: ConversationOutboxServerObservation? = nil
  ) async throws {
    if let server { try validateObservation(server) }
    try await stateOperation(server: server) { store, owner, key in
      try store.updateReplies(owner: owner, key: key) { entries in
        guard let index = entries.firstIndex(where: { $0.intent.replyID == id }) else {
          throw ConversationOutboxError.commandNotFound
        }
        if let server {
          guard entries[index].intent.parentBinding.ownerID == server.ownerID,
            entries[index].intent.parentBinding.epoch == server.epoch
          else { throw ConversationOutboxError.invalidServerObservation }
        }
        if entries[index].state != .queued { entries[index].state = .waitingReconciliation }
        entries[index].hold = .reset
      }
    }
  }
  func publishSnapshot(
    server: ConversationOutboxServerObservation,
    _ publish: @escaping @MainActor @Sendable (ConversationMealReplyOutboxViewSnapshot) -> Void
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
        let entries = try store.loadReplies(owner: owner, key: key)
        var visible: [ConversationMealReplyOutboxEntry] = []
        var held: [ConversationMealReplyOutboxViewSnapshot.Held] = []
        for entry in entries {
          if entry.intent.parentBinding.ownerID == server.ownerID,
            entry.intent.parentBinding.epoch == server.epoch
          {
            visible.append(entry)
          } else {
            held.append(
              .init(
                id: entry.intent.replyID, state: entry.state,
                canDiscardUnsent: entry.state == .queued))
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
  private func validateTicket(_ ticket: ConversationMealReplyOutboxTicket) throws {
    try lifetime.check()
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    guard ticket.scope == scope, ticket.ownerHash == owner.hash,
      ticket.localSessionGeneration == lease.generation
    else { throw ConversationOutboxError.invalidTransition }
  }
  private func ticket(_ entry: ConversationMealReplyOutboxEntry) throws
    -> ConversationMealReplyOutboxTicket
  {
    try lifetime.check()
    try Task.checkCancellation()
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    return .init(
      intent: entry.intent, ownerHash: owner.hash, localSessionGeneration: lease.generation,
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
    _ intent:
      @escaping @Sendable (
        EncryptedConversationOutboxStore, ConversationOutboxOwner, SymmetricKey
      ) throws -> Value
  ) async throws -> Value {
    guard let lease, let key else { throw ConversationOutboxError.sessionClosed }
    let store = store
    let owner = owner
    let lifetime = lifetime
    let result = try await lifecycle.performPatientStateOperation(lease: lease) {
      try lifetime.check()
      try Task.checkCancellation()
      if let server { return try server.withCurrentAuthority { try intent(store, owner, key) } }
      return try intent(store, owner, key)
    }
    try lifetime.check()
    try Task.checkCancellation()
    if let server { try server.withCurrentAuthority {} }
    return result
  }
}
private func replyOutboxCanResolve(_ hold: ConversationOutboxHold?) -> Bool {
  hold != .reset && hold != .staleEpoch && hold != .serverChanged
}
private func replyOutboxSame(_ a: ConversationMealReplyIntent, _ b: ConversationMealReplyIntent)
  -> Bool
{
  a.parentBinding == b.parentBinding && a.parentDecisionHash == b.parentDecisionHash
    && a.question.encodedData == b.question.encodedData && a.replyID == b.replyID
    && a.replyInputHash == b.replyInputHash && a.wireBody == b.wireBody
}
private func replyOutboxIndex(
  _ ticket: ConversationMealReplyOutboxTicket, in entries: [ConversationMealReplyOutboxEntry]
) throws -> Int {
  guard let index = entries.firstIndex(where: { $0.intent.replyID == ticket.id }) else {
    throw ConversationOutboxError.commandNotFound
  }
  guard replyOutboxSame(entries[index].intent, ticket.intent) else {
    throw ConversationOutboxError.invalidTransition
  }
  return index
}

/// Saved food and non-food accepted-answer delivery use different mandatory
/// proofs. Only their exact authenticated reply result may close this intent.
func conversationReplyIsDelivery(
  _ result: ConversationMealReplyResultSnapshot, intent: ConversationMealReplyIntent,
  authUserID: UUID
) -> Bool {
  guard result.matches(intent: intent, authUserID: authUserID) else { return false }
  if result.status == .saved, let child = result.childBinding, let receipt = result.receipt {
    return receipt.matches(
      child: child, parent: intent.parentBinding, decisionHash: intent.parentDecisionHash)
  }
  return result.isAcceptedAnswerDelivery(for: intent)
}
