import CryptoKit
import Foundation
import Security
import Testing

@testable import BodyFlow

@Suite("Authenticated durable edit operation session")
struct ConversationMealEditOutboxSessionTests {
  @Test func persistBeforeFlightAndRestartKeepSameOperationForReadOnlyReconciliation() async throws
  {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let life = EditLifecycleFake(lease: f.lease)
    let keys = EditKeychainFake()
    let vault = editVault(keys)
    let a = try await ConversationMealEditOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: vault)
    let op = try f.operation()
    let id = try await a.enqueue(operation: op, server: f.server)
    let ticket = try await a.prepareDispatch(id: id, server: f.server)
    #expect(ticket.operation.wireBody == op.wireBody && ticket.idempotencyKey == op.idempotencyKey)
    await a.invalidate()
    let b = try await ConversationMealEditOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: vault)
    let restored = try await b.reconciliationTicket(id: id)
    #expect(
      restored.wireBody == ticket.wireBody
        && restored.operationInputHash == ticket.operationInputHash
        && restored.originalInputHash == ticket.originalInputHash)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await b.prepareDispatch(id: id, server: f.server)
    }
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await b.discardUnsent(id: id)
    }
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await b.markWaiting(ticket: ticket, hold: .unknownOutcome)
    }
    await b.invalidate()
  }
  @Test func replayPermissionRequiresExactActualAbsentAndNeverRebases() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store,
      keyVault: editVault(EditKeychainFake()))
    let op = try f.operation()
    let id = try await session.enqueue(operation: op, server: f.server)
    let ticket = try await session.prepareDispatch(id: id, server: f.server)
    try await session.markWaiting(ticket: ticket, hold: .unknownOutcome)
    let absent = try reply("absent")
    guard case .absent(let proof) = absent else {
      Issue.record("Actual absent required")
      return
    }
    try await session.authorizeResubmission(ticket: ticket, absent: proof, server: f.server)
    let same = try await session.reconciliationTicket(id: id)
    #expect(same.wireBody == op.wireBody && same.operation.operationID == op.operationID)
    var raw = try payload("absent")
    raw["operation_input_hash"] = String(repeating: "f", count: 64)
    let wrong = try JSONDecoder().decode(
      ConversationMealEditAbsentSnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await session.authorizeResubmission(ticket: ticket, absent: wrong, server: f.server)
    }
    try await session.markWaiting(ticket: ticket, hold: .serverChanged)
    try await session.markWaiting(ticket: ticket, hold: .unknownOutcome)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await session.authorizeResubmission(ticket: ticket, absent: proof, server: f.server)
    }
    #expect(try await snapshot(session, server: f.server).entries.first?.hold == .serverChanged)
    await session.invalidate()
  }
  @Test func actualSavedAckRemovesOnlyExactDispatchedOperationAndPublishesOnce() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store,
      keyVault: editVault(EditKeychainFake()))
    let id = try await session.enqueue(operation: f.operation(), server: f.server)
    let ticket = try await session.prepareDispatch(id: id, server: f.server)
    guard case .saved(let saved) = try reply("saved") else {
      Issue.record("Saved required")
      return
    }
    let probe = await MainActor.run { EditPublicationProbe() }
    try await session.acknowledgeSaved(ticket: ticket, result: saved, server: f.server) {
      probe.publications.append($0)
    }
    #expect(await probe.publications.count == 1)
    #expect(try await snapshot(session, server: f.server).entries.isEmpty)
    await #expect(throws: ConversationOutboxError.commandNotFound) {
      try await session.acknowledgeSaved(ticket: ticket, result: saved, server: f.server) {
        probe.publications.append($0)
      }
    }
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await session.enqueue(operation: f.operation(), server: f.server)
    }
    #expect(await probe.publications.count == 1)
    await session.invalidate()
  }
  @Test func cancelledAfterAckRenameCannotResurrectOrPublish() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let life = EditLifecycleFake(lease: f.lease)
    let vault = editVault(EditKeychainFake())
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: vault)
    let op = try f.operation()
    let id = try await session.enqueue(operation: op, server: f.server)
    let ticket = try await session.prepareDispatch(id: id, server: f.server)
    guard case .saved(let saved) = try reply("saved") else {
      Issue.record("Saved required")
      return
    }
    let probe = await MainActor.run { EditPublicationProbe() }
    await life.cancelAfterNextStateOperation()
    let task = Task {
      try await session.acknowledgeSaved(ticket: ticket, result: saved, server: f.server) {
        probe.publications.append($0)
      }
    }
    await #expect(throws: (any Error).self) { try await task.value }
    #expect(await probe.publications.isEmpty)
    #expect(try await snapshot(session, server: f.server).entries.isEmpty)
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await session.enqueue(operation: op, server: f.server)
    }
    await session.invalidate()
  }
  @Test func failedDispatchPersistReturnsNoTicketAndKeepsQueuedCiphertext() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store,
      keyVault: editVault(EditKeychainFake()))
    let id = try await session.enqueue(operation: f.operation(), server: f.server)
    let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.store.root.path)
    await #expect(throws: ConversationOutboxError.storageUnavailable) {
      try await session.prepareDispatch(id: id, server: f.server)
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: f.store.root.path)
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
    #expect(try await snapshot(session, server: f.server).entries.first?.state == .queued)
    await session.invalidate()
  }
  @Test func currentPatientEpochFilterNeverRetagsHeldOriginals() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store,
      keyVault: editVault(EditKeychainFake()))
    let id = try await session.enqueue(operation: f.operation(), server: f.server)
    let changed = ConversationOutboxServerObservation(
      authUserID: f.server.authUserID, ownerID: UUID(), localSessionGeneration: f.lease.generation,
      epoch: UUID())
    let view = try await snapshot(session, server: changed)
    #expect(
      view.entries.isEmpty && view.held.count == 1 && view.held[0].id == id
        && view.held[0].canDiscardUnsent)
    await #expect(throws: ConversationOutboxError.invalidServerObservation) {
      try await session.prepareDispatch(id: id, server: changed)
    }
    await #expect(throws: ConversationOutboxError.invalidServerObservation) {
      try await session.enqueue(operation: f.operation(), server: changed)
    }
    try await session.discardUnsent(id: id)
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await session.enqueue(operation: f.operation(), server: f.server)
    }
    await session.invalidate()
  }
  @Test func revokedAuthorityAndAccountSwapBlockEffectsAndLeaveCiphertext() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let life = EditLifecycleFake(lease: f.lease)
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: editVault(EditKeychainFake()))
    let authority = ConversationOutboxObservationAuthority()
    let refresh = try authority.beginRefresh()
    let server = try authority.accept(
      refreshID: refresh, authUserID: f.server.authUserID, ownerID: f.patient,
      localSessionGeneration: f.lease.generation, epoch: f.epoch)
    let id = try await session.enqueue(operation: f.operation(), server: server)
    let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    _ = try authority.beginRefresh()
    await #expect(throws: ConversationOutboxError.staleObservation) {
      try await session.prepareDispatch(id: id, server: server)
    }
    await life.replace(
      lease: .init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-B"))
    await #expect(throws: (any Error).self) { try await session.discardUnsent(id: id) }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
    await session.invalidate()
  }
  @Test func resetHoldIsMonotonicAndNeverCreatesReplay() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store,
      keyVault: editVault(EditKeychainFake()))
    let id = try await session.enqueue(operation: f.operation(), server: f.server)
    try await session.holdForLocalReset(id: id)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await session.prepareDispatch(id: id, server: f.server)
    }
    #expect(try await snapshot(session, server: f.server).entries.first?.hold == .reset)
    try await session.discardUnsent(id: id)
    await session.invalidate()
  }
  @Test func missingEditKeyNeverCreatesReplacementAndReportVaultIsRefused() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let life = EditLifecycleFake(lease: f.lease)
    let keys = EditKeychainFake()
    let wrong = ConversationOutboxKeyVault(
      service: "app.performe.conversation-outbox.v1", security: keys)
    await #expect(throws: ConversationOutboxError.keyUnavailable) {
      try await ConversationMealEditOutboxSession.open(
        lifecycle: life, store: f.store, keyVault: wrong)
    }
    #expect(await keys.addCount == 0)
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: editVault(keys))
    _ = try await session.enqueue(operation: f.operation(), server: f.server)
    await session.invalidate()
    let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    let empty = EditKeychainFake()
    await #expect(throws: ConversationOutboxError.keyUnavailable) {
      try await ConversationMealEditOutboxSession.open(
        lifecycle: life, store: f.store, keyVault: editVault(empty))
    }
    #expect(await empty.addCount == 0)
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
    #expect(
      await keys.descriptors.allSatisfy {
        $0.service == "app.performe.conversation-meal-edit-outbox.v1"
      })
  }
  @Test func wrongOrCriticallyHeldSavedProofCannotRemoveOrPublish() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store,
      keyVault: editVault(EditKeychainFake()))
    let id = try await session.enqueue(operation: f.operation(), server: f.server)
    let ticket = try await session.prepareDispatch(id: id, server: f.server)
    let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    let probe = await MainActor.run { EditPublicationProbe() }
    var raw = try payload("saved")
    var receipt = try #require(raw["receipt"] as? [String: Any])
    receipt["input_hash"] = String(repeating: "f", count: 64)
    raw["receipt"] = receipt
    let mismatch = try JSONDecoder().decode(
      ConversationMealEditResultSnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await session.acknowledgeSaved(ticket: ticket, result: mismatch, server: f.server) {
        probe.publications.append($0)
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
    try await session.markWaiting(ticket: ticket, hold: .staleEpoch)
    guard case .saved(let saved) = try reply("saved") else {
      Issue.record("Saved required")
      return
    }
    let held = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await session.acknowledgeSaved(ticket: ticket, result: saved, server: f.server) {
        probe.publications.append($0)
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == held)
    #expect(await probe.publications.isEmpty)
    await session.invalidate()
  }
  @Test func accountChangeAfterAckRenameSuppressesPublicationButPreservesCommittedRemoval()
    async throws
  {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let life = EditLifecycleFake(lease: f.lease)
    let vault = editVault(EditKeychainFake())
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: vault)
    let id = try await session.enqueue(operation: f.operation(), server: f.server)
    let ticket = try await session.prepareDispatch(id: id, server: f.server)
    guard case .saved(let saved) = try reply("saved") else {
      Issue.record("Saved required")
      return
    }
    await life.replaceBeforeNextVisible(
      lease: .init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-B"))
    let probe = await MainActor.run { EditPublicationProbe() }
    await #expect(throws: (any Error).self) {
      try await session.acknowledgeSaved(ticket: ticket, result: saved, server: f.server) {
        probe.publications.append($0)
      }
    }
    #expect(await probe.publications.isEmpty)
    let key = try await vault.key(owner: f.owner, mayCreate: false)
    #expect(try f.store.load(owner: f.owner, key: key).isEmpty)
    await session.invalidate()
  }
  private func editVault(_ keys: EditKeychainFake) -> ConversationOutboxKeyVault {
    .init(service: "app.performe.conversation-meal-edit-outbox.v1", security: keys)
  }
  private func snapshot(
    _ session: ConversationMealEditOutboxSession, server: ConversationOutboxServerObservation
  ) async throws -> ConversationMealEditOutboxViewSnapshot {
    let probe = await MainActor.run { EditPublicationProbe() }
    try await session.publishSnapshot(server: server) { probe.snapshot = $0 }
    return try #require(await probe.snapshot)
  }
  private func payload(_ key: String) throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealEditPublicFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealEditPublicFixtures.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let envelope = try #require(root[key] as? [String: Any])
    return try #require(envelope["data"] as? [String: Any])
  }
  private func reply(_ key: String) throws -> ConversationMealEditReply {
    try JSONDecoder().decode(
      ConversationMealEditReply.self, from: JSONSerialization.data(withJSONObject: payload(key)))
  }
}
@MainActor final class EditPublicationProbe {
  var snapshot: ConversationMealEditOutboxViewSnapshot?
  var publications: [ConversationMealEditOutboxSavedPublication] = []
}
actor EditKeychainFake: KeychainSecurityClient {
  private var values: [String: Data] = [:]
  private(set) var descriptors: [KeychainItemDescriptor] = []
  private(set) var addCount = 0
  private func key(_ d: KeychainItemDescriptor) -> String { d.service + "\0" + d.account }
  func read(_ d: KeychainItemDescriptor) -> KeychainReadResult {
    descriptors.append(d)
    return values[key(d)].map(KeychainReadResult.data) ?? .notFound
  }
  func update(_ d: KeychainItemDescriptor, data: Data) -> OSStatus {
    values[key(d)] = data
    return errSecSuccess
  }
  func add(_ d: KeychainItemDescriptor, data: Data) -> OSStatus {
    descriptors.append(d)
    addCount += 1
    guard values[key(d)] == nil else { return errSecDuplicateItem }
    values[key(d)] = data
    return errSecSuccess
  }
  func delete(_ d: KeychainItemDescriptor) -> OSStatus {
    values.removeValue(forKey: key(d))
    return errSecSuccess
  }
}
actor EditLifecycleFake: SessionLifecycleProviding {
  private var lease: SessionLease
  private var work: [UUID: @Sendable () -> Void] = [:]
  private var cancelNextState = false
  private var nextVisibleLease: SessionLease?
  init(lease: SessionLease) { self.lease = lease }
  func replace(lease: SessionLease) {
    self.lease = lease
    let callbacks = work.values
    work.removeAll()
    for callback in callbacks { callback() }
  }
  func cancelAfterNextStateOperation() { cancelNextState = true }
  func replaceBeforeNextVisible(lease: SessionLease) { nextVisibleLease = lease }
  func currentBearerToken() -> String? { lease.bearer }
  func leaseForRequest() -> SessionLease { lease }
  func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease {
    try validate(lease)
    return self.lease
  }
  func validate(_ candidate: SessionLease) throws {
    guard candidate.userID == lease.userID && candidate.generation == lease.generation else {
      throw SessionLifecycleError.sessionSuperseded
    }
  }
  func signOut() -> RemoteRevocationOutcome { .confirmed }
  func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) throws -> UUID
  {
    try validate(lease)
    let id = UUID()
    work[id] = cancel
    return id
  }
  func finishPatientWork(_ id: UUID) { work.removeValue(forKey: id) }
  func performPatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @Sendable () throws -> Value
  ) throws -> Value {
    try validate(lease)
    let value = try operation()
    if cancelNextState {
      cancelNextState = false
      withUnsafeCurrentTask { $0?.cancel() }
    }
    return value
  }
  func performVisiblePatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @MainActor @Sendable () throws -> Value
  ) async throws -> Value {
    if let next = nextVisibleLease {
      nextVisibleLease = nil
      replace(lease: next)
    }
    try validate(lease)
    return try await MainActor.run(body: operation)
  }
}
