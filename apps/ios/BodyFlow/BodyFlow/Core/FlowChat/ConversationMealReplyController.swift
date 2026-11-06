import Foundation

enum ConversationMealReplyControllerError: Error, Equatable, Sendable {
  case unavailable, changed, busy, reconciliationRequired
}
enum ConversationMealReplyEvent: Sendable {
  enum DeferredReason: Sendable { case offline, rateLimited, changed, storage, unavailable }
  case snapshot(ConversationMealReplyOutboxViewSnapshot)
  case queued(UUID)
  case delivered(ConversationMealReplyDeliveryPublication)
  case held(UUID, reason: String?, canResume: Bool)
  case deferred(UUID, DeferredReason)
}

/// Original typed answer bound to an actual owned question and this controller.
/// A retry preserves its exact ID/body; the server alone admits the current CAS.
struct ConversationMealReplyPreparation: Sendable, CustomStringConvertible, CustomReflectable {
  let intent: ConversationMealReplyIntent
  fileprivate let originalContext: ConversationCommandContext
  fileprivate let controllerScope: UUID
  fileprivate init(
    intent: ConversationMealReplyIntent, context: ConversationCommandContext, scope: UUID
  ) {
    self.intent = intent
    originalContext = context
    controllerScope = scope
  }
  var description: String { "ConversationMealReplyPreparation(redacted)" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
private final class MealReplyControllerLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false
  func close() { lock.withLock { closed = true } }
  func check() throws {
    try lock.withLock { if closed { throw ConversationOutboxError.sessionClosed } }
  }
}

/// Real typed protocol under the existing dormant runtime gate. No legacy
/// writer, automatic POST retry, new server observation or local nutrition.
actor ConversationMealReplyController {
  typealias Publisher = @MainActor @Sendable (ConversationMealReplyEvent) -> Void
  private struct Permission: Sendable {
    let ticket: ConversationMealReplyOutboxTicket
    let result: ConversationMealReplyResultSnapshot
    let context: ConversationCommandContext
  }
  private let repository: MobileConversationMealReplyRepository
  private let lifecycle: any SessionLifecycleProviding
  private let outbox: ConversationMealReplyOutboxSession
  private let lifetime: MealReplyControllerLifetime
  private let scope = UUID()
  private var lease: SessionLease?
  private var workID: UUID?
  private var permissions: [UUID: Permission] = [:]
  private var inFlight: Set<UUID> = []
  private var cancellations: [UUID: @Sendable () -> Void] = [:]
  private init(
    repository: MobileConversationMealReplyRepository,
    lifecycle: any SessionLifecycleProviding, outbox: ConversationMealReplyOutboxSession,
    lifetime: MealReplyControllerLifetime, lease: SessionLease
  ) {
    self.repository = repository
    self.lifecycle = lifecycle
    self.outbox = outbox
    self.lifetime = lifetime
    self.lease = lease
  }
  static func open(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    store: EncryptedConversationOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(
      service: ConversationMealReplyOutboxSession.keychainService),
    expectedLease: SessionLease? = nil,
    feedbackPresentation: ConversationFeedbackPresentationSelection? = nil
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
    let repository = try await MobileConversationMealReplyRepository.scoped(
      transport: transport, lifecycle: lifecycle, lease: lease, feedbackPresentation: feedbackPresentation)
    let outbox = try await ConversationMealReplyOutboxSession.open(
      lifecycle: lifecycle, store: store, keyVault: keyVault, expectedLease: lease)
    let lifetime = MealReplyControllerLifetime()
    let controller = Self(
      repository: repository, lifecycle: lifecycle,
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

  /// The exact question came from an owned v2 read/result; it is a server
  /// precondition, never local evidence that a meal was consumed or saved.
  func prepare(
    parentBinding: ConversationThreadPageSnapshot.Binding, parentDecisionHash: String,
    question: ConversationThreadPageSnapshot.Question, answer: ConversationMealReplyIntent.Answer,
    context: ConversationCommandContext, replyID: UUID = UUID()
  ) async throws -> ConversationMealReplyPreparation {
    let lease = try await validate(context)
    let scope = scope
    let lifetime = lifetime
    let preparation: ConversationMealReplyPreparation =
      try await lifecycle.performPatientStateOperation(lease: lease) {
        try lifetime.check()
        try Task.checkCancellation()
        return try context.withCurrentAuthority {
          guard parentBinding.ownerID == context.ownerID, parentBinding.epoch == context.epoch,
            !parentBinding.isChild
          else {
            throw ConversationOutboxError.invalidServerObservation
          }
          let intent = try ConversationMealReplyIntent(
            parentBinding: parentBinding, parentDecisionHash: parentDecisionHash,
            question: question, replyID: replyID, answer: answer)
          return .init(intent: intent, context: context, scope: scope)
        }
      }
    _ = try await validate(context)
    return preparation
  }
  @discardableResult func enqueue(
    preparation: ConversationMealReplyPreparation, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws -> UUID {
    let intent = preparation.intent
    let id = intent.replyID
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    guard preparation.controllerScope == scope,
      preparation.originalContext.identity == context.identity
    else { throw ConversationOutboxError.invalidServerObservation }
    // A new current grant for the SAME identity may preserve original intent;
    // this is storage only. Its original CAS/epoch/body are never renewed.
    let stored = try await outbox.enqueue(intent: intent, server: context.observation)
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
    replyID id: UUID, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    permissions.removeValue(forKey: id)
    let ticket = try await outbox.prepareDispatch(replyID: id, server: context.observation)
    try await transmit(ticket, context: context, publish: publish)
  }
  func reconcile(
    replyID id: UUID, context: ConversationCommandContext, publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    permissions.removeValue(forKey: id)
    let ticket = try await outbox.reconciliationTicket(replyID: id)
    try matches(ticket, context: context)
    let repository = repository
    do {
      let result = try await network(context: context) {
        try await repository.reconcile(ticket, context: context)
      }
      try await process(
        ticket, result: result, context: context, mayAuthorizeResume: true, publish: publish)
    } catch {
      try await handleFailure(error, ticket: ticket, context: context, publish: publish)
      throw error
    }
  }
  func resume(
    replyID id: UUID, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    guard let permission = permissions.removeValue(forKey: id),
      permission.context.observation.isSameGrant(as: context.observation)
    else { throw ConversationMealReplyControllerError.reconciliationRequired }
    try await outbox.authorizeResubmission(
      ticket: permission.ticket, result: permission.result, server: context.observation)
    try await transmit(permission.ticket, context: context, publish: publish)
  }
  func discardUnsent(
    replyID id: UUID, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    try await outbox.discardUnsent(replyID: id, server: context.observation)
    permissions.removeValue(forKey: id)
    try await publishSnapshot(context: context, publish: publish)
  }
  func holdForLocalReset(
    replyID id: UUID, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try begin(id)
    defer { inFlight.remove(id) }
    _ = try await validate(context)
    try await outbox.holdForLocalReset(replyID: id, server: context.observation)
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
  private func begin(_ id: UUID) throws {
    try lifetime.check()
    guard inFlight.insert(id).inserted else { throw ConversationMealReplyControllerError.busy }
  }
  private func transmit(
    _ ticket: ConversationMealReplyOutboxTicket, context: ConversationCommandContext,
    publish: @escaping Publisher
  ) async throws {
    try matches(ticket, context: context)
    let repository = repository
    do {
      let result = try await network(context: context) {
        try await repository.submit(ticket, context: context)
      }
      try await process(
        ticket, result: result, context: context, mayAuthorizeResume: false, publish: publish)
    } catch {
      try await handleFailure(error, ticket: ticket, context: context, publish: publish)
      throw error
    }
  }
  private func process(
    _ ticket: ConversationMealReplyOutboxTicket, result: ConversationMealReplyResultSnapshot,
    context: ConversationCommandContext, mayAuthorizeResume: Bool, publish: @escaping Publisher
  ) async throws {
    _ = try await validate(context)
    try matches(ticket, context: context)
    if conversationReplyIsDelivery(result, intent: ticket.intent, authUserID: context.authUserID) {
      try await outbox.acknowledgeDelivery(
        ticket: ticket, result: result, server: context.observation
      ) {
        publish(.delivered($0))
      }
      permissions.removeValue(forKey: ticket.id)
      // Factual delivery already happened; a later history/panel read cannot undo it.
      try? await publishSnapshot(context: context, publish: publish)
      return
    }
    try await outbox.markWaiting(ticket: ticket, hold: .unknownOutcome, server: context.observation)
    var allowed = false
    if mayAuthorizeResume, result.status == .held {
      do {
        try await outbox.authorizeResubmission(
          ticket: ticket, result: result, server: context.observation)
        _ = try await validate(context)
        permissions[ticket.id] = .init(ticket: ticket, result: result, context: context)
        allowed = true
      } catch ConversationOutboxError.invalidTransition {
        // Unbound/conflicting/current-head-only results never grant a POST.
      } catch ConversationOutboxError.reconciliationRequired {
        // Permanent holds survive all later reads.
      }
    }
    try await deliver(
      .held(ticket.id, reason: result.reason, canResume: allowed), context: context,
      publish: publish)
  }
  private func handleFailure(
    _ error: any Error, ticket: ConversationMealReplyOutboxTicket,
    context: ConversationCommandContext, publish: @escaping Publisher
  ) async throws {
    if error is CancellationError { throw error }
    _ = try await validate(context)
    try matches(ticket, context: context)
    permissions.removeValue(forKey: ticket.id)
    var hold: ConversationOutboxHold = .unknownOutcome
    var reason: ConversationMealReplyEvent.DeferredReason = .unavailable
    if case MobileAPITransportError.conflict(let code, _) = error {
      if code == "conversation_meal_reply_stale_epoch" || code == "conversation_stale_epoch" {
        hold = .staleEpoch
        reason = .changed
      } else if [
        "conversation_patient_changed", "conversation_meal_reply_input_conflict",
        "conversation_meal_reply_decision_conflict", "conversation_meal_reply_event_conflict",
        "conversation_meal_reply_ineligible",
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
    _ ticket: ConversationMealReplyOutboxTicket, context: ConversationCommandContext
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
    _ event: ConversationMealReplyEvent, context: ConversationCommandContext,
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
    context: ConversationCommandContext, _ intent: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    _ = try await validate(context)
    let id = UUID()
    let task = Task { try await intent() }
    cancellations[id] = { task.cancel() }
    defer { cancellations.removeValue(forKey: id) }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }
}
