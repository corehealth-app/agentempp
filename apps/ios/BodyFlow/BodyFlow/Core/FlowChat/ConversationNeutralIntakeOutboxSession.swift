import CryptoKit
import Foundation

/// Opaque local compare-and-swap observation captured before the HTTP call.
/// It is never serialized, sent as authority or used to invent a server clock.
struct ConversationNeutralIntakeTerminalCAS: Sendable {
  fileprivate let ticket: FlowNeutralIntakeTicket
  fileprivate let row: ConversationNeutralIntakeOutboxEntry
  fileprivate let observation: ConversationOutboxServerObservation
  fileprivate let nonce: UUID
}
private struct NeutralTerminalProof: Equatable, Sendable {
  let fields: [String]
  init?(_ value: FlowNeutralIntakeResponseSnapshot) {
    guard value.deliveryState == .notRecorded, let b = value.intake else { return nil }
    var f = [
      value.status.rawValue, b.ownerID.uuidString, b.intakeID.uuidString, b.inputHash,
      b.epoch.uuidString, b.admittedAt,
    ]
    if value.status == .notRecorded {
      guard let source = value.sourceHash, let decision = value.decisionHash,
        let reason = value.reason
      else { return nil }
      f += [source, decision, reason]
    } else {
      guard let selection = value.selection else { return nil }
      let child = selection.child
      f += [
        selection.sourceHash, selection.decisionHash, selection.selectedAt, child.kind.rawValue,
        child.ownerID.uuidString, child.commandID.uuidString, child.inputHash,
        child.epoch.uuidString, child.admittedAt,
      ]
      switch value.result {
      case .meal(.state(let state)) where state.status == .notRecorded:
        f += ["meal", state.reason ?? ""] + state.foodIndexes.map(String.init)
      case .workout(.state(let state)) where state.status == .notRecorded:
        f += ["workout", state.reason ?? ""]
      default: return nil
      }
    }
    fields = f
  }
}

/// Owns only neutral rows in the existing shared encrypted file. Every local
/// transaction stays within the original authentication lifecycle and grant.
actor ConversationNeutralIntakeOutboxSession {
  private let lifecycle: any SessionLifecycleProviding
  private let store: EncryptedConversationOutboxStore
  private let owner: ConversationOutboxOwner
  private let lifetime = NeutralIntakeLifetime()
  private var lease: SessionLease?
  private var key: SymmetricKey?
  private var workID: UUID?
  private var issued: [UUID: String] = [:]
  private init(
    lifecycle: any SessionLifecycleProviding, store: EncryptedConversationOutboxStore,
    owner: ConversationOutboxOwner, lease: SessionLease, key: SymmetricKey
  ) {
    self.lifecycle = lifecycle
    self.store = store
    self.owner = owner
    self.lease = lease
    self.key = key
  }
  static func open(
    lifecycle: any SessionLifecycleProviding, store: EncryptedConversationOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(), expectedLease: SessionLease? = nil
  ) async throws -> ConversationNeutralIntakeOutboxSession {
    let lease = try await lifecycle.leaseForRequest()
    if let expectedLease {
      try await lifecycle.validate(expectedLease)
      guard expectedLease.userID == lease.userID, expectedLease.generation == lease.generation
      else { throw SessionLifecycleError.sessionSuperseded }
    }
    try await lifecycle.validate(lease)
    let owner = try ConversationOutboxOwner(lease: lease)
    let exists = try await lifecycle.performPatientStateOperation(lease: lease) {
      try store.containsCiphertext(owner: owner)
    }
    let key = try await keyVault.key(owner: owner, mayCreate: !exists)
    _ = try await lifecycle.performPatientStateOperation(lease: lease) {
      try store.loadIntakes(owner: owner, key: key)
    }
    let session = Self(lifecycle: lifecycle, store: store, owner: owner, lease: lease, key: key)
    let lifetime = session.lifetime
    do {
      let id = try await lifecycle.beginPatientWork(lease: lease) { [weak session] in
        lifetime.close()
        Task { await session?.invalidate() }
      }
      try await session.install(id)
      try await lifecycle.validate(lease)
      return session
    } catch {
      await session.invalidate()
      throw error
    }
  }
  private func install(_ id: UUID) async throws {
    do {
      try lifetime.check()
      workID = id
    } catch {
      await lifecycle.finishPatientWork(id)
      throw error
    }
  }
  func prepareOriginal(_ original: ConversationMediaOriginal, context: ConversationCommandContext)
    async throws -> ConversationMediaOriginal
  {
    try check(context.observation)
    guard original.ownerID == context.ownerID, original.epoch == context.epoch else {
      throw ConversationOutboxError.invalidServerObservation
    }
    return try await transaction(context.observation) { store, owner, key in
      try store.prepareOriginal(original, owner: owner, key: key)
    }
  }
  func loadOriginal(context: ConversationCommandContext) async throws -> ConversationMediaOriginal?
  {
    try check(context.observation)
    return try await transaction(context.observation) { store, owner, key in
      try store.loadOriginal(owner: owner, key: key)
    }
  }
  func bindOriginalAsset(intakeID: UUID, assetID: UUID, context: ConversationCommandContext)
    async throws -> ConversationMediaOriginal
  {
    try check(context.observation)
    return try await transaction(context.observation) { store, owner, key in
      guard let original = try store.loadOriginal(owner: owner, key: key),
        original.ownerID == context.ownerID, original.epoch == context.epoch
      else { throw ConversationOutboxError.invalidServerObservation }
      return try store.bindOriginalAsset(
        intakeID: intakeID, assetID: assetID, owner: owner, key: key)
    }
  }
  func promoteOriginal(_ input: FlowNeutralIntakeInput, context: ConversationCommandContext)
    async throws
  {
    try check(context.observation)
    try await transaction(context.observation) { store, owner, key in
      try store.promoteOriginal(input, owner: owner, key: key)
    }
  }
  func discardOriginal(intakeID: UUID) async throws {
    try await transaction { store, owner, key in
      try store.discardOriginal(intakeID: intakeID, owner: owner, key: key)
    }
  }
  /// Processing is also gated after an uncertain promotion. Old queued media
  /// without a capsule remains compatible; another original is never retired.
  func prepareQueuedOriginal(_ input: FlowNeutralIntakeInput, context: ConversationCommandContext)
    async throws
  {
    try check(context.observation)
    try await transaction(context.observation) { store, owner, key in
      guard
        let row = try store.loadIntakes(owner: owner, key: key).first(where: {
          $0.input.intakeID == input.intakeID
        }),
        row.input.wireBody == input.wireBody, row.ownerID == context.ownerID,
        row.epoch == context.epoch,
        row.state == .queued, row.hold == nil
      else { throw ConversationOutboxError.reconciliationRequired }
      try store.promoteOriginal(input, ifPresent: true, owner: owner, key: key)
    }
  }
  func enqueue(input: FlowNeutralIntakeInput, server: ConversationOutboxServerObservation)
    async throws -> UUID
  {
    try check(server, enqueue: true)
    let lifetime = lifetime
    try await transaction(server) { store, owner, key in
      try lifetime.refuseDelivered(input.intakeID)
      try store.updateIntakes(owner: owner, key: key) { rows in
        if let row = rows.first(where: { $0.input.intakeID == input.intakeID }) {
          guard row.input.wireBody == input.wireBody, row.input.inputHash == input.inputHash,
            row.ownerID == server.ownerID, row.epoch == server.epoch
          else { throw ConversationOutboxError.invalidTransition }
        } else {
          rows.append(.init(input: input, ownerID: server.ownerID, epoch: server.epoch))
        }
      }
    }
    return input.intakeID
  }
  func prepareDispatch(intakeID: UUID, server: ConversationOutboxServerObservation) async throws
    -> FlowNeutralIntakeTicket
  {
    try check(server)
    let row = try await transaction(server) { store, owner, key in
      try store.updateIntakes(owner: owner, key: key) { rows in
        guard let i = rows.firstIndex(where: { $0.input.intakeID == intakeID }) else {
          throw ConversationOutboxError.commandNotFound
        }
        guard rows[i].ownerID == server.ownerID, rows[i].epoch == server.epoch else {
          throw ConversationOutboxError.invalidServerObservation
        }
        guard rows[i].state == .queued, rows[i].hold == nil else {
          throw ConversationOutboxError.reconciliationRequired
        }
        rows[i].state = .dispatchedUnknown
        return rows[i]
      }
    }
    return try issue(row)
  }
  func reconciliationTicket(intakeID: UUID) async throws -> FlowNeutralIntakeTicket {
    let row = try await transaction { store, owner, key in
      guard
        let row = try store.loadIntakes(owner: owner, key: key).first(where: {
          $0.input.intakeID == intakeID
        })
      else { throw ConversationOutboxError.commandNotFound }
      guard row.state != .queued else { throw ConversationOutboxError.invalidTransition }
      return row
    }
    return try issue(row)
  }
  /// Used only after an explicit trusted GET permission in the Controller.
  /// Waiting work never returns to queued and its identity is never renewed.
  func replayTicket(_ ticket: FlowNeutralIntakeTicket, server: ConversationOutboxServerObservation)
    async throws -> FlowNeutralIntakeTicket
  {
    try matches(ticket, server)
    try await transaction(server) { store, owner, key in
      guard
        let row = try store.loadIntakes(owner: owner, key: key).first(where: {
          $0.input.intakeID == ticket.input.intakeID
        }), Self.same(row, ticket)
      else { throw ConversationOutboxError.commandNotFound }
      guard row.state != .queued,
        row.hold == nil || row.hold == .unknownOutcome || row.hold == .userCancelled
      else { throw ConversationOutboxError.reconciliationRequired }
    }
    return ticket
  }
  func markWaiting(
    ticket: FlowNeutralIntakeTicket, hold: ConversationOutboxHold,
    server: ConversationOutboxServerObservation
  ) async throws {
    try matches(ticket, server)
    try await transaction(server) { store, owner, key in
      try store.updateIntakes(owner: owner, key: key) { rows in
        guard let i = rows.firstIndex(where: { $0.input.intakeID == ticket.input.intakeID }),
          Self.same(rows[i], ticket)
        else { throw ConversationOutboxError.commandNotFound }
        guard rows[i].state != .queued else { throw ConversationOutboxError.invalidTransition }
        let retained = rows[i].hold.map { $0.priority > hold.priority ? $0 : hold } ?? hold
        rows[i].state = .waitingReconciliation
        rows[i].hold = retained
      }
    }
  }
  func captureTerminalCAS(
    ticket: FlowNeutralIntakeTicket, server: ConversationOutboxServerObservation
  ) async throws -> ConversationNeutralIntakeTerminalCAS {
    try matches(ticket, server)
    let row = try await transaction(server) { store, owner, key in
      guard
        let row = try store.loadIntakes(owner: owner, key: key).first(where: {
          $0.input.intakeID == ticket.input.intakeID
        }), Self.same(row, ticket), row.state != .queued
      else { throw ConversationOutboxError.invalidTransition }
      return row
    }
    try matches(ticket, server)
    let nonce = UUID()
    try lifetime.reserveTerminal(ticket.input.intakeID, nonce: nonce)
    return .init(ticket: ticket, row: row, observation: server, nonce: nonce)
  }
  /// Only a fully bound not_recorded can drain sent work. Questions and every
  /// unknown/held/pending outcome remain protected; this publishes no saved ACK.
  func resolveTerminal(
    cas: ConversationNeutralIntakeTerminalCAS, response: FlowNeutralIntakeResponseSnapshot,
    server: ConversationOutboxServerObservation, publish: @escaping @MainActor @Sendable () -> Void
  ) async throws {
    try check(server)
    let ticket = cas.ticket
    guard let lease, ticket.ownerHash == owner.hash, ticket.sessionGeneration == lease.generation,
      ticket.ownerID == server.ownerID, ticket.epoch == server.epoch, response.matches(ticket),
      let proof = NeutralTerminalProof(response)
    else { throw ConversationOutboxError.invalidTransition }
    try cas.observation.withCurrentAuthority {}
    if !lifetime.hasTerminal(ticket.input.intakeID) { try matches(ticket, server) }
    let lifetime = lifetime
    let removed = try await transaction(cas.observation) { store, owner, key in
      try lifetime.resolveTerminal(cas, proof: proof) {
        try store.updateIntakes(owner: owner, key: key) { rows in
          guard let i = rows.firstIndex(where: { $0.input.intakeID == ticket.input.intakeID }),
            Self.same(rows[i], ticket),
            rows[i].state == cas.row.state, rows[i].hold == cas.row.hold, rows[i].state != .queued,
            rows[i].hold == nil || rows[i].hold == .unknownOutcome || rows[i].hold == .userCancelled
              || rows[i].hold == .notRecorded
          else { throw ConversationOutboxError.invalidTransition }
          rows.remove(at: i)
        }
      }
    }
    try check(server)
    try cas.observation.withCurrentAuthority {}
    if removed {
      issued.removeValue(forKey: ticket.input.intakeID)
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try lifetime.check()
        try Task.checkCancellation()
        try cas.observation.withCurrentAuthority { publish() }
      }
    }
  }
  func acknowledgeSaved(
    ticket: FlowNeutralIntakeTicket, response: FlowNeutralIntakeResponseSnapshot,
    server: ConversationOutboxServerObservation, publish: @escaping @MainActor @Sendable () -> Void
  ) async throws {
    try matches(ticket, server)
    guard response.factualAcknowledgement(for: ticket) != nil, let lease else {
      throw ConversationOutboxError.invalidTransition
    }
    let lifetime = lifetime
    try await transaction(server) { store, owner, key in
      try store.updateIntakes(owner: owner, key: key) { rows in
        guard let i = rows.firstIndex(where: { $0.input.intakeID == ticket.input.intakeID }),
          Self.same(rows[i], ticket)
        else { throw ConversationOutboxError.commandNotFound }
        guard rows[i].state != .queued,
          rows[i].hold == nil || rows[i].hold == .unknownOutcome || rows[i].hold == .userCancelled
        else { throw ConversationOutboxError.reconciliationRequired }
        rows.remove(at: i)
      }
      lifetime.recordDelivered(ticket.input.intakeID)
    }
    issued.removeValue(forKey: ticket.input.intakeID)
    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
      try lifetime.check()
      try Task.checkCancellation()
      try server.withCurrentAuthority { publish() }
    }
  }
  func snapshot(context: ConversationCommandContext) async throws
    -> ConversationNeutralIntakeSnapshot
  {
    try check(context.observation)
    let rows = try await transaction(context.observation) { store, owner, key in
      try store.loadIntakes(owner: owner, key: key)
    }
    return .init(
      context: context,
      entries: rows.filter { $0.ownerID == context.ownerID && $0.epoch == context.epoch },
      heldIDs: rows.filter { $0.ownerID != context.ownerID || $0.epoch != context.epoch }.map {
        $0.input.intakeID
      })
  }
  func discardUnsent(intakeID: UUID) async throws {
    try await transaction { store, owner, key in
      try store.updateIntakes(owner: owner, key: key) { rows in
        guard let i = rows.firstIndex(where: { $0.input.intakeID == intakeID }) else {
          throw ConversationOutboxError.commandNotFound
        }
        guard rows[i].state == .queued else { throw ConversationOutboxError.reconciliationRequired }
        rows.remove(at: i)
      }
    }
    issued.removeValue(forKey: intakeID)
  }
  func invalidate() async {
    lifetime.close()
    key = nil
    lease = nil
    issued.removeAll()
    if let id = workID {
      workID = nil
      await lifecycle.finishPatientWork(id)
    }
  }
  private func issue(_ row: ConversationNeutralIntakeOutboxEntry) throws -> FlowNeutralIntakeTicket
  {
    try lifetime.check()
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    issued[row.input.intakeID] = row.input.inputHash
    return .init(
      input: row.input, ownerID: row.ownerID, epoch: row.epoch, ownerHash: owner.hash,
      sessionGeneration: lease.generation)
  }
  private func check(_ server: ConversationOutboxServerObservation, enqueue: Bool = false) throws {
    try lifetime.check()
    guard let lease, server.authUserID == UUID(uuidString: lease.userID),
      server.localSessionGeneration == lease.generation, !server.isEnqueueOnly || enqueue
    else { throw ConversationOutboxError.invalidServerObservation }
    try server.withCurrentAuthority {}
  }
  private func matches(
    _ ticket: FlowNeutralIntakeTicket, _ server: ConversationOutboxServerObservation
  ) throws {
    try check(server)
    guard let lease, ticket.ownerHash == owner.hash, ticket.sessionGeneration == lease.generation,
      ticket.ownerID == server.ownerID, ticket.epoch == server.epoch,
      issued[ticket.input.intakeID] == ticket.input.inputHash
    else { throw ConversationOutboxError.invalidTransition }
  }
  private static func same(
    _ row: ConversationNeutralIntakeOutboxEntry, _ ticket: FlowNeutralIntakeTicket
  ) -> Bool {
    row.input.wireBody == ticket.input.wireBody && row.input.inputHash == ticket.input.inputHash
      && row.ownerID == ticket.ownerID && row.epoch == ticket.epoch
  }
  private func transaction<Value: Sendable>(
    _ server: ConversationOutboxServerObservation? = nil,
    _ action:
      @escaping @Sendable (EncryptedConversationOutboxStore, ConversationOutboxOwner, SymmetricKey)
      throws -> Value
  ) async throws -> Value {
    try lifetime.check()
    guard let lease, let key else { throw ConversationOutboxError.sessionClosed }
    let store = store
    let owner = owner
    let lifetime = lifetime
    let value = try await lifecycle.performPatientStateOperation(lease: lease) {
      try lifetime.check()
      try Task.checkCancellation()
      if let server { return try server.withCurrentAuthority { try action(store, owner, key) } }
      return try action(store, owner, key)
    }
    try lifetime.check()
    try Task.checkCancellation()
    return value
  }
}
private final class NeutralIntakeLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false
  private var delivered: Set<UUID> = []
  private var terminalReservations: [UUID: UUID] = [:]
  private var terminalResults: [UUID: (UUID, NeutralTerminalProof)] = [:]
  func check() throws {
    try lock.withLock { if closed { throw ConversationOutboxError.sessionClosed } }
  }
  func refuseDelivered(_ id: UUID) throws {
    try lock.withLock {
      if delivered.contains(id) || terminalResults[id] != nil {
        throw ConversationOutboxError.invalidTransition
      }
    }
  }
  func hasTerminal(_ id: UUID) -> Bool { lock.withLock { terminalResults[id] != nil } }
  func reserveTerminal(_ id: UUID, nonce: UUID) throws {
    try lock.withLock {
      guard !closed, terminalResults[id] == nil else {
        throw ConversationOutboxError.invalidTransition
      }
      terminalReservations[id] = nonce
    }
  }
  func resolveTerminal(
    _ cas: ConversationNeutralIntakeTerminalCAS, proof: NeutralTerminalProof,
    mutation: () throws -> Void
  ) throws -> Bool {
    try lock.withLock {
      guard !closed else { throw ConversationOutboxError.sessionClosed }
      let id = cas.ticket.input.intakeID
      if let previous = terminalResults[id] {
        guard previous.0 == cas.nonce, previous.1 == proof else {
          throw ConversationOutboxError.invalidTransition
        }
        return false
      }
      guard terminalReservations[id] == cas.nonce else {
        throw ConversationOutboxError.invalidTransition
      }
      try mutation()
      terminalResults[id] = (cas.nonce, proof)
      terminalReservations.removeValue(forKey: id)
      return true
    }
  }
  func recordDelivered(_ id: UUID) { lock.withLock { _ = delivered.insert(id) } }
  func close() {
    lock.withLock {
      closed = true
      delivered.removeAll()
      terminalReservations.removeAll()
      terminalResults.removeAll()
    }
  }
}
