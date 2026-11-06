import Foundation
import Observation

struct FlowNeutralIntakeSavedRow: Identifiable, Sendable {
  let input: FlowNeutralIntakeInput
  let acknowledgement: FlowNeutralIntakeFactualAcknowledgement
  let identity: ConversationCommandContext.Identity
  var feedback: ConversationFeedbackPresentationSnapshot.Bound?
  var id: UUID { input.intakeID }
  var childID: UUID {
    switch acknowledgement {
    case .meal(let value): UUID(uuidString: value.commandID)!
    case .workout(let value): value.commandID
    }
  }
}

/// Recent readonly decision, not queued work or a replacement for remote history.
struct FlowNeutralIntakeTerminalRow: Identifiable, Sendable {
  let input: FlowNeutralIntakeInput
  let response: FlowNeutralIntakeResponseSnapshot
  let identity: ConversationCommandContext.Identity
  var id: UUID { input.intakeID }
}

/// The visible neutral composer owns its literal prepared intent. Existing
/// meal reports remain in FlowConversationModel and its original controller.
@MainActor @Observable
final class FlowNeutralIntakeModel {
  private struct Prepared: Sendable {
    let input: FlowNeutralIntakeInput
    let identity: ConversationCommandContext.Identity
    let revision: UInt64
  }
  private let controller: any ConversationNeutralIntakeControlling
  private let parentIsCurrent: @MainActor (ConversationCommandContext.Identity) -> Bool
  private let onFactualEffect: @MainActor () -> Void
  private var parentIdentity: ConversationCommandContext.Identity
  private var context: ConversationCommandContext?
  private var lastIdentity: ConversationCommandContext.Identity?
  private var prepared: Prepared?
  private var draft = ""
  private var revision: UInt64 = 0
  private var hint: ConversationMealCommand.MealType?
  private var entries: [ConversationNeutralIntakeOutboxEntry] = []
  private var records: [FlowNeutralIntakeSavedRow] = []
  private var terminalRecords: [FlowNeutralIntakeTerminalRow] = []
  private var states: [UUID: FlowNeutralIntakeResponseSnapshot] = [:]
  private var continuationIDs: Set<UUID> = []
  private var delivered: Set<UUID> = []
  private var pendingNotifications: Set<UUID> = []
  private var queuedIDs: Set<UUID> = []
  private var task: Task<Void, Never>?
  private var operationID = UUID()
  private var closed = false
  private(set) var isWorking = false
  private(set) var heldCount = 0
  private(set) var failure: ConversationNeutralIntakeFailure?
  private init(
    controller: any ConversationNeutralIntakeControlling,
    parentIdentity: ConversationCommandContext.Identity,
    parentIsCurrent: @escaping @MainActor (ConversationCommandContext.Identity) -> Bool,
    onFactualEffect: @escaping @MainActor () -> Void
  ) {
    self.controller = controller
    self.parentIdentity = parentIdentity
    self.parentIsCurrent = parentIsCurrent
    self.onFactualEffect = onFactualEffect
  }
  static func open(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    store: EncryptedConversationOutboxStore, keyVault: ConversationOutboxKeyVault,
    expectedLease: SessionLease, parentIdentity: ConversationCommandContext.Identity,
    parentIsCurrent: @escaping @MainActor (ConversationCommandContext.Identity) -> Bool,
    onFactualEffect: @escaping @MainActor () -> Void
  ) async throws -> FlowNeutralIntakeModel {
    let controller = try await ConversationNeutralIntakeController.open(
      transport: transport, lifecycle: lifecycle, store: store, keyVault: keyVault,
      expectedLease: expectedLease)
    let model = Self(
      controller: controller, parentIdentity: parentIdentity, parentIsCurrent: parentIsCurrent,
      onFactualEffect: onFactualEffect)
    do {
      try await controller.publishSnapshot(model.publisher(model.operationID))
      guard model.isVisible else { throw ConversationOutboxError.invalidServerObservation }
      return model
    } catch {
      await model.close()
      throw error
    }
  }
  var isVisible: Bool {
    guard !closed, let context, context.identity == parentIdentity,
      parentIsCurrent(context.identity)
    else { return false }
    return (try? context.withCurrentAuthority { true }) == true
  }
  var isComposerLocked: Bool { prepared != nil }
  var preparedInput: FlowNeutralIntakeInput? { closed ? nil : prepared?.input }
  var composer: String {
    get { closed ? "" : draft }
    set {
      guard !closed, prepared == nil else { return }
      draft = newValue
      revision &+= 1
    }
  }
  var mealTypeHint: ConversationMealCommand.MealType? {
    get { closed ? nil : hint }
    set {
      guard !closed, prepared == nil else { return }
      hint = newValue
      revision &+= 1
    }
  }
  var canSubmit: Bool {
    guard !closed, !isWorking, lastIdentity == parentIdentity else { return false }
    if let prepared {
      return prepared.identity == parentIdentity
        && !entries.contains {
          $0.input.intakeID == prepared.input.intakeID && ($0.state != .queued || $0.hold != nil)
        }
    }
    return neutralText(draft, limit: 2000)
  }
  var pendingRows: [ConversationNeutralIntakeOutboxEntry] { isVisible ? entries : [] }
  var savedRows: [FlowNeutralIntakeSavedRow] { isVisible ? records : [] }
  var terminalRows: [FlowNeutralIntakeTerminalRow] { isVisible ? terminalRecords : [] }
  /// Genuine terminal selection only; journal display fields cannot recover this hash.
  func mealQuestionChild(intakeID: UUID) -> FlowNeutralIntakeChild? {
    guard isVisible, let row = terminalRecords.first(where: { $0.id == intakeID }),
      row.identity == context?.identity, case .meal(.state(let state)) = row.response.result,
      state.status == .notRecorded,
      state.reason.map({ ["missing_quantity", "meal_type_required"].contains($0) }) == true,
      let selection = row.response.selection,
      selection.child.kind == .meal
    else { return nil }
    return selection.child
  }
  var offlineQueuedCount: Int { isVisible ? 0 : queuedIDs.count }
  func state(intakeID: UUID) -> FlowNeutralIntakeResponseSnapshot? {
    isVisible ? states[intakeID] : nil
  }
  func canContinue(intakeID: UUID) -> Bool {
    isVisible && continuationIDs.contains(intakeID) && !isWorking
  }
  func acceptParent(_ identity: ConversationCommandContext.Identity) {
    guard parentIdentity != identity else { return }
    parentIdentity = identity
    context = nil
    prepared = nil
    draft = ""
    hint = nil
    entries.removeAll()
    records.removeAll()
    terminalRecords.removeAll()
    states.removeAll()
    continuationIDs.removeAll()
    delivered.removeAll()
    pendingNotifications.removeAll()
    queuedIDs.removeAll()
    heldCount = 0
  }
  func suspendVisibility() {
    context = nil
    continuationIDs.removeAll()
    invalidateFeedback()
  }
  /// A new factual effect changes current day commentary, not original ACKs.
  func invalidateFeedback() {
    records = records.map {
      var row = $0
      row.feedback = nil
      return row
    }
  }
  func refresh() async {
    await run { id in
      let publish = self.publisher(id)
      try await self.controller.refreshSession(publish)
    }
  }
  func submit() async {
    guard canSubmit, let identity = lastIdentity else { return }
    do {
      let original =
        try prepared
        ?? Prepared(
          input: FlowNeutralIntakeInput(intakeID: UUID(), source: .text(draft), mealTypeHint: hint),
          identity: identity, revision: revision)
      prepared = original
      await run { id in
        let publish = self.publisher(id)
        let id = try await self.controller.enqueue(
          input: original.input, expectedContext: original.identity, publish: publish)
        guard id == original.input.intakeID, self.parentIdentity == original.identity else {
          throw ConversationOutboxError.invalidTransition
        }
        if self.revision == original.revision {
          self.draft = ""
          self.hint = nil
          self.revision &+= 1
        }
        self.prepared = nil
        try await self.controller.send(intakeID: id, publish: publish)
      }
    } catch { failure = .invalidInput }
  }
  func sendQueued(intakeID: UUID) async {
    guard
      pendingRows.contains(where: {
        $0.input.intakeID == intakeID && $0.state == .queued && $0.hold == nil
      })
    else { return }
    await run { id in
      let publish = self.publisher(id)
      try await self.controller.send(intakeID: intakeID, publish: publish)
    }
  }
  func reconcile(intakeID: UUID) async {
    await run { id in
      let publish = self.publisher(id)
      try await self.controller.reconcile(intakeID: intakeID, publish: publish)
    }
  }
  func continueOriginal(intakeID: UUID) async {
    guard canContinue(intakeID: intakeID) else { return }
    continuationIDs.remove(intakeID)
    await run { id in
      let publish = self.publisher(id)
      try await self.controller.continueOriginal(intakeID: intakeID, publish: publish)
    }
  }
  func discardUnsent(intakeID: UUID) async {
    await run { id in
      let publish = self.publisher(id)
      do {
        try await self.controller.discardUnsent(intakeID: intakeID, publish: publish)
      } catch ConversationOutboxError.commandNotFound {
        // Proven local absence; no transport is invoked.
      }
      if self.prepared?.input.intakeID == intakeID {
        self.prepared = nil
        self.draft = ""
        self.hint = nil
      }
    }
  }
  func cancelTransientWork() { task?.cancel() }
  func invalidateSynchronously() {
    closed = true
    operationID = UUID()
    task?.cancel()
    context = nil
    prepared = nil
    draft = ""
    records.removeAll()
    terminalRecords.removeAll()
    entries.removeAll()
    states.removeAll()
    continuationIDs.removeAll()
  }
  func close() async {
    invalidateSynchronously()
    await controller.close()
  }
  private func publisher(_ id: UUID) -> ConversationNeutralIntakeController.Publisher {
    { [weak self] event in
      guard let self, !self.closed, self.operationID == id else { return }
      self.receive(event)
    }
  }
  private func receive(_ event: ConversationNeutralIntakeEvent) {
    switch event {
    case .scopeSuspended: suspendVisibility()
    case .scopeAccepted(let value):
      guard value.identity == parentIdentity, (try? value.withCurrentAuthority { true }) == true
      else {
        context = nil
        failure = .changed
        return
      }
      if let old = lastIdentity, old != value.identity {
        records.removeAll()
        terminalRecords.removeAll()
        entries.removeAll()
        states.removeAll()
        prepared = nil
        draft = ""
        hint = nil
        delivered.removeAll()
        pendingNotifications.removeAll()
      }
      lastIdentity = value.identity
      context = value
    case .snapshot(let snapshot):
      guard snapshot.context.identity == parentIdentity,
        (try? snapshot.context.withCurrentAuthority { true }) == true
      else { return }
      entries = snapshot.entries
      heldCount = snapshot.heldIDs.count
      queuedIDs = Set(entries.map { $0.input.intakeID })
    case .queued(let id): queuedIDs.insert(id)
    case .saved(let publication):
      guard publication.context.identity == parentIdentity,
        (try? publication.context.withCurrentAuthority { true }) == true
      else { return }
      let scope = ConversationFeedbackPresentationSnapshot.Scope(
        ownerID: publication.context.ownerID.uuidString.lowercased(),
        sessionGeneration: publication.context.sessionGeneration,
        epoch: publication.context.epoch.uuidString.lowercased())
      let feedback: ConversationFeedbackPresentationSnapshot.Bound?
      switch publication.acknowledgement {
      case .meal(let saved): feedback = saved.boundFeedback(scope: scope)
      case .workout(let saved):
        feedback = ConversationFeedbackPresentationSnapshot.boundWorkout(saved, scope: scope)
      }
      if delivered.insert(publication.input.intakeID).inserted {
        records.append(
          .init(
            input: publication.input, acknowledgement: publication.acknowledgement,
            identity: publication.context.identity,
            feedback: parentIsCurrent(publication.context.identity) ? feedback : nil))
        if records.count > 50 { records.removeFirst(records.count - 50) }
        pendingNotifications.insert(publication.input.intakeID)
      }
      entries.removeAll { $0.input.intakeID == publication.input.intakeID }
      queuedIDs.remove(publication.input.intakeID)
      states.removeValue(forKey: publication.input.intakeID)
      continuationIDs.remove(publication.input.intakeID)
    case .resolvedWithoutRegistration(let input, let response, let current):
      guard current.identity == parentIdentity, response.deliveryState == .notRecorded,
        (try? current.withCurrentAuthority { true }) == true
      else { return }
      terminalRecords.removeAll { $0.id == input.intakeID }
      terminalRecords.append(.init(input: input, response: response, identity: current.identity))
      if terminalRecords.count > 50 { terminalRecords.removeFirst(terminalRecords.count - 50) }
      entries.removeAll { $0.input.intakeID == input.intakeID }
      queuedIDs.remove(input.intakeID)
      states.removeValue(forKey: input.intakeID)
      continuationIDs.remove(input.intakeID)
    case .state(let input, let response, let canContinue, let current):
      guard current.identity == parentIdentity, (try? current.withCurrentAuthority { true }) == true
      else { return }
      states[input.intakeID] = response
      if canContinue {
        continuationIDs.insert(input.intakeID)
      } else {
        continuationIDs.remove(input.intakeID)
      }
    case .deferred(_, let reason): failure = reason
    }
    if isVisible {
      let count = pendingNotifications.count
      pendingNotifications.removeAll()
      for _ in 0..<count { onFactualEffect() }
    }
  }
  private func run(_ action: @escaping @MainActor @Sendable (UUID) async throws -> Void) async {
    guard !closed, !isWorking, !Task.isCancelled else { return }
    let id = UUID()
    operationID = id
    isWorking = true
    failure = nil
    let operation = Task {
      do { try await action(id) } catch is CancellationError {} catch {
        guard !self.closed, self.operationID == id else { return }
        if case MobileAPITransportError.network = error {
          self.failure = .offline
        } else if case MobileAPITransportError.timeout = error {
          self.failure = .offline
        } else if case ConversationOutboxError.queueFull = error {
          self.failure = .storage
        } else if case ConversationOutboxError.storageUnavailable = error {
          self.failure = .storage
        } else if case ConversationOutboxError.reconciliationRequired = error {
          self.failure = .reconciliationRequired
        } else {
          self.failure = .unavailable
        }
      }
    }
    task = operation
    await withTaskCancellationHandler {
      await operation.value
    } onCancel: {
      operation.cancel()
    }
    if operationID == id {
      task = nil
      isWorking = false
    }
  }
}
