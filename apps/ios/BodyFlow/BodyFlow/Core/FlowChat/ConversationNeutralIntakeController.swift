import Foundation

/// New neutral transport lane. Legacy meal commands remain in their original
/// controller/path; neither a routing decision nor GET starts a registration.
actor ConversationNeutralIntakeController: ConversationNeutralIntakeControlling {
  typealias Publisher = @MainActor @Sendable (ConversationNeutralIntakeEvent) -> Void
  private let repository: MobileConversationIntakeRepository
  private let lifecycle: any SessionLifecycleProviding
  private let outbox: ConversationNeutralIntakeOutboxSession
  private let authority = ConversationOutboxObservationAuthority()
  private let enqueueAuthority = ConversationOutboxObservationAuthority()
  private var lease: SessionLease?
  private var context: ConversationCommandContext?
  private var enqueueContext: ConversationOutboxServerObservation?
  private var lastAccepted: (ConversationCommandContext.Identity, ConversationProtocolInstant)?
  private var permissions: [UUID: (FlowNeutralIntakeTicket, ConversationCommandContext)] = [:]
  private var cancellations: [UUID: @Sendable () -> Void] = [:]
  private var workID: UUID?
  private init(
    repository: MobileConversationIntakeRepository, lifecycle: any SessionLifecycleProviding,
    outbox: ConversationNeutralIntakeOutboxSession, lease: SessionLease
  ) {
    self.repository = repository
    self.lifecycle = lifecycle
    self.outbox = outbox
    self.lease = lease
  }
  static func open(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    store: EncryptedConversationOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(), expectedLease: SessionLease? = nil
  ) async throws -> ConversationNeutralIntakeController {
    let lease = try await lifecycle.leaseForRequest()
    if let expectedLease {
      try await lifecycle.validate(expectedLease)
      guard lease.userID == expectedLease.userID, lease.generation == expectedLease.generation
      else { throw SessionLifecycleError.sessionSuperseded }
    }
    let repository = try await MobileConversationIntakeRepository.scoped(
      transport: transport, lease: lease, feedbackPresentation: .v2)
    let outbox = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: lifecycle, store: store, keyVault: keyVault, expectedLease: lease)
    let controller = Self(
      repository: repository, lifecycle: lifecycle, outbox: outbox, lease: lease)
    let authority = controller.authority
    let enqueueAuthority = controller.enqueueAuthority
    do {
      let id = try await lifecycle.beginPatientWork(lease: lease) { [weak controller] in
        authority.close()
        enqueueAuthority.close()
        Task { await controller?.close() }
      }
      try await controller.install(id)
      _ = try await controller.refresh(nil)
      return controller
    } catch {
      await controller.close()
      throw error
    }
  }
  private func install(_ id: UUID) async throws {
    do {
      try authority.checkOpen()
      workID = id
    } catch {
      await lifecycle.finishPatientWork(id)
      throw error
    }
  }
  func enqueue(
    input: FlowNeutralIntakeInput, expectedContext: ConversationCommandContext.Identity,
    publish: @escaping Publisher
  ) async throws -> UUID {
    let lease = try await currentLease()
    guard let captured = enqueueContext, expectedContext == identity(captured) else {
      throw ConversationOutboxError.invalidServerObservation
    }
    let id = try await outbox.enqueue(input: input, server: captured)
    if context != nil {
      try await publishSnapshot(publish)
    } else {
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try Task.checkCancellation()
        try captured.withCurrentAuthority { publish(.queued(id)) }
      }
    }
    return id
  }
  func refreshSession(_ publish: @escaping Publisher) async throws {
    _ = try await refresh(publish)
  }
  func publishSnapshot(_ publish: @escaping Publisher) async throws {
    _ = try await currentLease()
    guard let context else { throw ConversationOutboxError.invalidServerObservation }
    let snapshot = try await outbox.snapshot(context: context)
    try await deliver(.scopeAccepted(context), context, publish)
    try await deliver(.snapshot(snapshot), context, publish)
  }
  func send(intakeID: UUID, publish: @escaping Publisher) async throws {
    let context = try await refresh(publish)
    let ticket = try await outbox.prepareDispatch(intakeID: intakeID, server: context.observation)
    try await transmit(ticket, context, publish)
  }
  func reconcile(intakeID: UUID, publish: @escaping Publisher) async throws {
    let context = try await refresh(publish)
    let ticket = try await outbox.reconciliationTicket(intakeID: intakeID)
    try matches(ticket, context)
    let terminalCAS = try await outbox.captureTerminalCAS(
      ticket: ticket, server: context.observation)
    do {
      let reply = try await network { try await self.repository.read(ticket) }
      try await receive(reply, ticket, context, terminalCAS: terminalCAS, fromRead: true, publish)
    } catch {
      try await failure(error, ticket, context, publish)
      throw error
    }
  }
  func continueOriginal(intakeID: UUID, publish: @escaping Publisher) async throws {
    _ = try await currentLease()
    guard let (original, context) = permissions.removeValue(forKey: intakeID) else {
      throw ConversationOutboxError.reconciliationRequired
    }
    try matches(original, context)
    let ticket = try await outbox.replayTicket(original, server: context.observation)
    try await transmit(ticket, context, publish)
  }
  func discardUnsent(intakeID: UUID, publish: @escaping Publisher) async throws {
    _ = try await currentLease()
    try await outbox.discardUnsent(intakeID: intakeID)
    permissions.removeValue(forKey: intakeID)
    if context != nil { try await publishSnapshot(publish) }
  }
  func close() async {
    authority.close()
    enqueueAuthority.close()
    lease = nil
    context = nil
    enqueueContext = nil
    permissions.removeAll()
    for cancel in cancellations.values { cancel() }
    cancellations.removeAll()
    await outbox.invalidate()
    if let id = workID {
      workID = nil
      await lifecycle.finishPatientWork(id)
    }
  }
  private func identity(_ server: ConversationOutboxServerObservation)
    -> ConversationCommandContext.Identity
  {
    .init(
      authUserID: server.authUserID, ownerID: server.ownerID,
      sessionGeneration: server.localSessionGeneration, epoch: server.epoch)
  }
  private func refresh(_ publish: Publisher?) async throws -> ConversationCommandContext {
    let lease = try await currentLease()
    let id = try authority.beginRefresh()
    context = nil
    permissions.removeAll()
    if let publish {
      let authority = authority
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try authority.withPendingRefresh(id) { publish(.scopeSuspended) }
      }
    }
    let value = try await network { try await self.repository.session() }
    _ = try await currentLease()
    guard value.authUserID == UUID(uuidString: lease.userID),
      let instant = ConversationProtocolInstant(value.observedAt)
    else { throw MobileAPITransportError.invalidResponse }
    let expected = ConversationCommandContext.Identity(
      authUserID: value.authUserID, ownerID: value.ownerID, sessionGeneration: lease.generation,
      epoch: value.epoch)
    if let lastAccepted, lastAccepted.0 == expected, instant < lastAccepted.1 {
      throw MobileAPITransportError.invalidResponse
    }
    let authority = authority
    let enqueueAuthority = enqueueAuthority
    let pair = try await lifecycle.performPatientStateOperation(lease: lease) {
      let server = try authority.accept(
        refreshID: id, authUserID: value.authUserID, ownerID: value.ownerID,
        localSessionGeneration: lease.generation, epoch: value.epoch)
      let enqueueID = try enqueueAuthority.beginRefresh()
      let captured = try enqueueAuthority.accept(
        refreshID: enqueueID, authUserID: value.authUserID, ownerID: value.ownerID,
        localSessionGeneration: lease.generation, epoch: value.epoch, enqueueOnly: true)
      return (server, captured)
    }
    let accepted = ConversationCommandContext(observation: pair.0, observedAt: value.observedAt)
    try pair.0.withCurrentAuthority {}
    enqueueContext = pair.1
    context = accepted
    lastAccepted = (expected, instant)
    if let publish { try await publishSnapshot(publish) }
    return accepted
  }
  private func transmit(
    _ ticket: FlowNeutralIntakeTicket, _ context: ConversationCommandContext,
    _ publish: @escaping Publisher
  ) async throws {
    try matches(ticket, context)
    let terminalCAS = try await outbox.captureTerminalCAS(
      ticket: ticket, server: context.observation)
    do {
      let value = try await network { try await self.repository.submit(ticket) }
      try await receive(value, ticket, context, terminalCAS: terminalCAS, fromRead: false, publish)
    } catch {
      try await failure(error, ticket, context, publish)
      throw error
    }
  }
  private func receive(
    _ response: FlowNeutralIntakeResponseSnapshot, _ ticket: FlowNeutralIntakeTicket,
    _ context: ConversationCommandContext, terminalCAS: ConversationNeutralIntakeTerminalCAS,
    fromRead: Bool, _ publish: @escaping Publisher
  ) async throws {
    _ = try await currentLease()
    try matches(ticket, context)
    guard response.matches(ticket) else { throw MobileAPITransportError.invalidResponse }
    permissions.removeValue(forKey: ticket.input.intakeID)
    if let saved = response.factualAcknowledgement(for: ticket) {
      let publication = ConversationNeutralIntakeSavedPublication(
        input: ticket.input, acknowledgement: saved, context: context)
      try await outbox.acknowledgeSaved(
        ticket: ticket, response: response, server: context.observation
      ) { publish(.saved(publication)) }
    } else if response.deliveryState == .notRecorded {
      try await outbox.resolveTerminal(
        cas: terminalCAS, response: response, server: context.observation
      ) {
        publish(
          .resolvedWithoutRegistration(input: ticket.input, response: response, context: context))
      }
    } else {
      var terminal = response.status == .notRecorded || response.status == .clarificationRequired
      var requiresAnswer = false
      switch response.result {
      case .meal(.state(let value)): terminal = terminal || value.status == .notRecorded
      case .workout(.state(let value)):
        terminal = terminal || value.status == .notRecorded
        requiresAnswer = value.status == .needsReply
      default: break
      }
      let permanent = [
        "stale_epoch", "input_conflict", "source_conflict", "claim_conflict", "decision_conflict",
        "day_changed", "day_closed", "media_projection_required",
      ].contains(response.reason ?? "")
      try await outbox.markWaiting(
        ticket: ticket,
        hold: terminal ? .notRecorded : permanent ? .serverChanged : .unknownOutcome,
        server: context.observation)
      var canContinue = false
      if fromRead && !terminal && !permanent && !requiresAnswer
        && response.reason != "media_temporarily_unavailable"
      {
        // A new read cannot downgrade a stronger hold retained on disk. Probe
        // the same readonly fence used by explicit continuation before offering it.
        do {
          _ = try await outbox.replayTicket(ticket, server: context.observation)
          // Another reconcile may have accepted a newer grant while the local
          // read returned. Never overwrite its permission with the old one.
          try matches(ticket, context)
          canContinue = true
        } catch ConversationOutboxError.reconciliationRequired {
          canContinue = false
        }
      }
      if canContinue { permissions[ticket.input.intakeID] = (ticket, context) }
      try await deliver(
        .state(input: ticket.input, response: response, canContinue: canContinue, context: context),
        context, publish)
    }
    try await publishSnapshot(publish)
  }
  private func failure(
    _ error: any Error, _ ticket: FlowNeutralIntakeTicket, _ context: ConversationCommandContext,
    _ publish: @escaping Publisher
  ) async throws {
    if error is CancellationError { throw error }
    _ = try await currentLease()
    try matches(ticket, context)
    permissions.removeValue(forKey: ticket.input.intakeID)
    let changed: Bool
    if case MobileAPITransportError.conflict(let code, _) = error {
      changed = [
        "conversation_intake_changed", "conversation_patient_changed",
        "conversation_intake_scope_changed",
      ].contains(code)
    } else {
      changed = false
    }
    try await outbox.markWaiting(
      ticket: ticket, hold: changed ? .serverChanged : .unknownOutcome, server: context.observation)
    let reason: ConversationNeutralIntakeFailure
    if changed {
      reason = .changed
    } else if case MobileAPITransportError.network = error {
      reason = .offline
    } else if case MobileAPITransportError.timeout = error {
      reason = .offline
    } else if case MobileAPITransportError.rateLimited = error {
      reason = .rateLimited
    } else {
      reason = .unavailable
    }
    try await deliver(.deferred(ticket.input.intakeID, reason), context, publish)
    try await publishSnapshot(publish)
  }
  private func matches(_ ticket: FlowNeutralIntakeTicket, _ context: ConversationCommandContext)
    throws
  {
    try context.withCurrentAuthority {}
    guard ticket.ownerID == context.ownerID, ticket.epoch == context.epoch,
      ticket.sessionGeneration == context.sessionGeneration
    else { throw ConversationOutboxError.invalidServerObservation }
  }
  private func deliver(
    _ event: ConversationNeutralIntakeEvent, _ context: ConversationCommandContext,
    _ publish: @escaping Publisher
  ) async throws {
    let lease = try await currentLease()
    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
      try Task.checkCancellation()
      try context.withCurrentAuthority { publish(event) }
    }
  }
  private func currentLease() async throws -> SessionLease {
    try Task.checkCancellation()
    try authority.checkOpen()
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    try await lifecycle.validate(lease)
    try Task.checkCancellation()
    try authority.checkOpen()
    return lease
  }
  private func network<Value: Sendable>(_ action: @escaping @Sendable () async throws -> Value)
    async throws -> Value
  {
    _ = try await currentLease()
    let id = UUID()
    let task = Task { try await action() }
    cancellations[id] = { task.cancel() }
    defer { cancellations.removeValue(forKey: id) }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }
}
