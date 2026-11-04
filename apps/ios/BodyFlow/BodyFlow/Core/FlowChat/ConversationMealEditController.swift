import Foundation

enum ConversationMealEditControllerError: Error, Equatable, Sendable {
  case unavailable, changed, busy, reconciliationRequired
}
enum ConversationMealEditEvent: Sendable {
  enum DeferredReason: Sendable { case offline, rateLimited, changed, storage, unavailable }
  case snapshot(ConversationMealEditOutboxViewSnapshot)
  case queued(ConversationMealEditOutboxID)
  case saved(ConversationMealEditOutboxSavedPublication)
  case absent(ConversationMealEditOutboxID, canResubmit: Bool)
  case deferred(ConversationMealEditOutboxID, DeferredReason)
}

/// Constructible only after this controller's actual owned group GET. It is
/// original intent, not current group/policy authority. Retry keeps these bytes.
struct ConversationMealEditPreparation: Sendable, CustomStringConvertible, CustomReflectable {
  let operation: ConversationMealEditOperation
  fileprivate let originalContext: ConversationCommandContext
  fileprivate let controllerScope: UUID
  fileprivate init(
    operation: ConversationMealEditOperation, context: ConversationCommandContext, scope: UUID
  ) {
    self.operation = operation
    originalContext = context
    controllerScope = scope
  }
  var description: String { "ConversationMealEditPreparation(redacted)" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
private final class MealEditControllerLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false
  func close() { lock.withLock { closed = true } }
  func check() throws {
    try lock.withLock { if closed { throw ConversationOutboxError.sessionClosed } }
  }
}

/// Dormant real transport/controller. It never mints a backend observation,
/// renews a CAS/UUID, infers eligibility from device time or writes nutrition.
actor ConversationMealEditController {
  typealias Publisher = @MainActor @Sendable (ConversationMealEditEvent) -> Void
  private struct Permission: Sendable {
    let ticket: ConversationMealEditOutboxTicket
    let absent: ConversationMealEditAbsentSnapshot
    let context: ConversationCommandContext
  }
  private let repository: MobileConversationMealEditRepository
  private let history: MobileConversationHistoryRepository
  private let lifecycle: any SessionLifecycleProviding
  private let outbox: ConversationMealEditOutboxSession
  private let lifetime: MealEditControllerLifetime
  private let scope = UUID()
  private var lease: SessionLease?
  private var workID: UUID?
  private var permissions: [ConversationMealEditOutboxID: Permission] = [:]
  private var inFlight: Set<ConversationMealEditOutboxID> = []
  private var cancellations: [UUID: @Sendable () -> Void] = [:]
  private init(
    repository: MobileConversationMealEditRepository, history: MobileConversationHistoryRepository,
    lifecycle: any SessionLifecycleProviding, outbox: ConversationMealEditOutboxSession,
    lifetime: MealEditControllerLifetime, lease: SessionLease
  ) {
    self.repository = repository
    self.history = history
    self.lifecycle = lifecycle
    self.outbox = outbox
    self.lifetime = lifetime
    self.lease = lease
  }
  static func open(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    store: EncryptedConversationMealEditOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(
      service: ConversationMealEditOutboxSession.keychainService),
    expectedLease: SessionLease? = nil
  ) async throws -> Self {
    let lease = try await lifecycle.leaseForRequest()
    if let expectedLease {
      guard lease.userID == expectedLease.userID, lease.generation == expectedLease.generation
      else {
        throw SessionLifecycleError.sessionSuperseded
      }
      try await lifecycle.validate(expectedLease)
    }
    try await lifecycle.validate(lease)
    let repository = try await MobileConversationMealEditRepository.scoped(
      transport: transport, lifecycle: lifecycle, lease: lease)
    let history = try await MobileConversationHistoryRepository.scoped(
      transport: transport, lifecycle: lifecycle, lease: lease)
    let outbox = try await ConversationMealEditOutboxSession.open(
      lifecycle: lifecycle, store: store, keyVault: keyVault, expectedLease: lease)
    let lifetime = MealEditControllerLifetime()
    let controller = Self(
      repository: repository, history: history, lifecycle: lifecycle,
      outbox: outbox, lifetime: lifetime, lease: lease)
    do {
      let id = try await lifecycle.beginPatientWork(lease: lease) { [weak controller] in
        lifetime.close()
        Task { await controller?.close() }
      }
      try await controller.installWork(id)
      try await lifecycle.validate(lease)
      try lifetime.check()
      try Task.checkCancellation()
      return controller
    } catch {
      await controller.close()
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

  func prepare(
    commandID: UUID, originalInputHash: String, expectedRevision: Int, expectedVersion: String,
    action: ConversationMealEditOperation.Action, context: ConversationCommandContext,
    operationID: UUID = UUID()
  ) async throws -> ConversationMealEditPreparation {
    try await prepare(
      commandID: commandID, originalInputHash: originalInputHash, linked: nil,
      expectedRevision: expectedRevision, expectedVersion: expectedVersion,
      action: action, context: context, operationID: operationID)
  }
  func prepare(
    linked identity: ConversationMealLinkedIdentity, expectedRevision: Int,
    expectedVersion: String, action: ConversationMealEditOperation.Action,
    context: ConversationCommandContext, operationID: UUID = UUID()
  ) async throws -> ConversationMealEditPreparation {
    try await prepare(
      commandID: identity.commandID, originalInputHash: identity.inputHash, linked: identity,
      expectedRevision: expectedRevision, expectedVersion: expectedVersion,
      action: action, context: context, operationID: operationID)
  }
  private func prepare(
    commandID: UUID, originalInputHash: String, linked: ConversationMealLinkedIdentity?,
    expectedRevision: Int, expectedVersion: String, action: ConversationMealEditOperation.Action,
    context: ConversationCommandContext, operationID: UUID
  ) async throws -> ConversationMealEditPreparation {
    let lease = try await validate(context)
    let history = history
    let group = try await network(context: context) {
      if let linked { return try await history.group(linked: linked, context: context) }
      return try await history.group(
        commandID: commandID, originalInputHash: originalInputHash, context: context)
    }
    let scope = scope
    let lifetime = lifetime
    let preparation: ConversationMealEditPreparation =
      try await lifecycle.performPatientStateOperation(lease: lease) {
        try lifetime.check()
        try Task.checkCancellation()
        return try context.withCurrentAuthority {
          guard linked.map({ $0.matches(group: group) }) ?? true else {
            throw ConversationMealEditControllerError.changed
          }
          guard let current = group.current, group.revision == expectedRevision,
            current.expectedVersion == expectedVersion
          else { throw ConversationMealEditControllerError.changed }
          switch action {
          case .save(let recordID, _):
            guard group.actions.save.allowed, current.items.contains(where: { $0.id == recordID })
            else { throw ConversationMealEditControllerError.unavailable }
          case .undoSave(let target):
            guard group.actions.undoSave.allowed, group.lastOperation?.kind == .saved,
              group.lastOperation?.operationID == target
            else { throw ConversationMealEditControllerError.unavailable }
          case .undoRegistration:
            guard group.actions.undoRegistration.allowed else {
              throw ConversationMealEditControllerError.unavailable
            }
          }
          let operation = try ConversationMealEditOperation(
            ownerID: context.ownerID,
            commandID: commandID, originalInputHash: originalInputHash, epoch: context.epoch,
            operationID: operationID, expectedRevision: expectedRevision,
            expectedVersion: expectedVersion, action: action)
          return .init(operation: operation, context: context, scope: scope)
        }
      }
    // The scope may change after the synchronous operation completed but
    // before this actor resumes. Do not return an old patient's payload.
    _ = try await validate(context)
    return preparation
  }
  @discardableResult func enqueue(
    preparation: ConversationMealEditPreparation, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws -> ConversationMealEditOutboxID {
    let operation = preparation.operation
    let id = ConversationMealEditOutboxID(operation: operation)
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    guard preparation.controllerScope == scope,
      preparation.originalContext.identity == context.identity
    else { throw ConversationOutboxError.invalidServerObservation }
    // A new current grant for the SAME identity may preserve original intent;
    // this is storage only. Its original CAS/epoch/body are never renewed.
    let stored = try await outbox.enqueue(operation: operation, server: context.observation)
    try await deliver(.queued(stored), context: context, publish: publish)
    try await publishSnapshot(context: context, publish: publish)
    return stored
  }
  func publishSnapshot(context: ConversationCommandContext, publish: @escaping Publisher)
    async throws
  {
    _ = try await validate(context)
    try await outbox.publishSnapshot(server: context.observation) { publish(.snapshot($0)) }
  }
  func send(
    id: ConversationMealEditOutboxID, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    permissions.removeValue(forKey: id)
    let ticket = try await outbox.prepareDispatch(id: id, server: context.observation)
    try await transmit(ticket, context: context, publish: publish)
  }
  func reconcile(
    id: ConversationMealEditOutboxID, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    permissions.removeValue(forKey: id)
    let ticket = try await outbox.reconciliationTicket(id: id)
    try matches(ticket, context: context)
    let repository = repository
    do {
      let reply = try await network(context: context) {
        try await repository.reconcile(ticket, context: context)
      }
      switch reply {
      case .saved(let result):
        try await acknowledge(ticket, result: result, context: context, publish: publish)
      case .absent(let proof):
        _ = try await validate(context)
        try await outbox.markWaiting(
          ticket: ticket, hold: .unknownOutcome, server: context.observation)
        var allowed = false
        do {
          try await outbox.authorizeResubmission(
            ticket: ticket, absent: proof, server: context.observation)
          try context.withCurrentAuthority {}
          permissions[id] = .init(ticket: ticket, absent: proof, context: context)
          allowed = true
        } catch ConversationOutboxError.reconciliationRequired {
          // Retain the permanent hold.
        }
        try await deliver(.absent(id, canResubmit: allowed), context: context, publish: publish)
      }
    } catch {
      try await handleFailure(error, ticket: ticket, context: context, publish: publish)
      throw error
    }
  }
  func resubmit(
    id: ConversationMealEditOutboxID, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    guard let permission = permissions.removeValue(forKey: id),
      permission.context.observation.isSameGrant(as: context.observation)
    else { throw ConversationMealEditControllerError.reconciliationRequired }
    try await outbox.authorizeResubmission(
      ticket: permission.ticket, absent: permission.absent, server: context.observation)
    try await transmit(permission.ticket, context: context, publish: publish)
  }
  func discardUnsent(
    id: ConversationMealEditOutboxID, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    try await outbox.discardUnsent(id: id, server: context.observation)
    permissions.removeValue(forKey: id)
    try await publishSnapshot(context: context, publish: publish)
  }
  func holdForLocalReset(
    id: ConversationMealEditOutboxID, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    try await outbox.holdForLocalReset(id: id, server: context.observation)
    permissions.removeValue(forKey: id)
    try await publishSnapshot(context: context, publish: publish)
  }
  func close() async {
    lifetime.close()
    lease = nil
    permissions.removeAll()
    inFlight.removeAll()
    let owned = Array(cancellations.values)
    cancellations.removeAll()
    for cancel in owned { cancel() }
    await outbox.invalidate()
    if let id = workID {
      workID = nil
      await lifecycle.finishPatientWork(id)
    }
  }
  private func begin(_ id: ConversationMealEditOutboxID) throws {
    try lifetime.check()
    guard inFlight.insert(id).inserted else { throw ConversationMealEditControllerError.busy }
  }
  private func transmit(
    _ ticket: ConversationMealEditOutboxTicket, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try matches(ticket, context: context)
    let repository = repository
    do {
      let result = try await network(context: context) {
        try await repository.submit(ticket, context: context)
      }
      try await acknowledge(ticket, result: result, context: context, publish: publish)
    } catch {
      try await handleFailure(error, ticket: ticket, context: context, publish: publish)
      throw error
    }
  }
  private func acknowledge(
    _ ticket: ConversationMealEditOutboxTicket, result: ConversationMealEditResultSnapshot,
    context: ConversationCommandContext, publish: @escaping Publisher
  ) async throws {
    _ = try await validate(context)
    try matches(ticket, context: context)
    try await outbox.acknowledgeSaved(ticket: ticket, result: result, server: context.observation) {
      publish(.saved($0))
    }
    permissions.removeValue(forKey: ticket.id)
    // A subsequent read/refresh failure cannot undo factual success.
    try? await publishSnapshot(context: context, publish: publish)
  }
  private func handleFailure(
    _ error: any Error, ticket: ConversationMealEditOutboxTicket,
    context: ConversationCommandContext, publish: @escaping Publisher
  ) async throws {
    if error is CancellationError { throw error }
    _ = try await validate(context)
    try matches(ticket, context: context)
    permissions.removeValue(forKey: ticket.id)
    var hold: ConversationMealEditOutboxHold = .unknownOutcome
    var reason: ConversationMealEditEvent.DeferredReason = .unavailable
    if case MobileAPITransportError.conflict(let code, _) = error {
      if code == "conversation_meal_edit_stale_epoch" {
        hold = .staleEpoch
        reason = .changed
      } else if [
        "conversation_patient_changed", "conversation_meal_edit_input_conflict",
        "conversation_meal_edit_event_conflict", "conversation_meal_edit_version_conflict",
        "conversation_meal_edit_day_closed", "conversation_meal_edit_undo_expired",
        "conversation_meal_edit_absent",
      ].contains(code) {
        hold = .serverChanged
        reason = .changed
      }
    } else if case MobileAPITransportError.rateLimited = error {
      reason = .rateLimited
    } else if case MobileAPITransportError.network = error {
      reason = .offline
    } else if case MobileAPITransportError.timeout = error {
      reason = .offline
    }
    do {
      try await outbox.markWaiting(ticket: ticket, hold: hold, server: context.observation)
    } catch ConversationOutboxError.commandNotFound { return } catch ConversationOutboxError
      .storageUnavailable
    { reason = .storage } catch ConversationOutboxError.integrityFailure {
      reason = .storage
    } catch ConversationOutboxError.keyUnavailable { reason = .storage }
    try await deliver(.deferred(ticket.id, reason), context: context, publish: publish)
  }
  private func matches(
    _ ticket: ConversationMealEditOutboxTicket, context: ConversationCommandContext
  ) throws {
    try context.withCurrentAuthority {}
    guard ticket.originalPatientOwnerID == context.ownerID,
      ticket.originalServerEpoch == context.epoch,
      ticket.localSessionGeneration == context.sessionGeneration
    else { throw ConversationOutboxError.invalidServerObservation }
  }
  private func validate(_ context: ConversationCommandContext) async throws -> SessionLease {
    try Task.checkCancellation()
    try lifetime.check()
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    guard !context.observation.isEnqueueOnly, context.authUserID == UUID(uuidString: lease.userID),
      context.sessionGeneration == lease.generation
    else { throw ConversationOutboxError.invalidServerObservation }
    try await lifecycle.validate(lease)
    try lifetime.check()
    try Task.checkCancellation()
    try context.withCurrentAuthority {}
    return lease
  }
  private func deliver(
    _ event: ConversationMealEditEvent, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    let lease = try await validate(context)
    let lifetime = lifetime
    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
      try lifetime.check()
      try Task.checkCancellation()
      try context.withCurrentAuthority { publish(event) }
    }
  }
  private func network<Value: Sendable>(
    context: ConversationCommandContext, _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    _ = try await validate(context)
    let id = UUID()
    let task = Task { try await operation() }
    cancellations[id] = { task.cancel() }
    defer { cancellations.removeValue(forKey: id) }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }
}
