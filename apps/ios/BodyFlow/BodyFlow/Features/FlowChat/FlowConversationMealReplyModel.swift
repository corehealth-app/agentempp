import Foundation
import Observation

@MainActor struct FlowConversationMealReplyPresentation: Identifiable {
  let id: UUID
  let model: FlowConversationMealReplyModel
}
private final class FlowMealReplyLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false
  func close() { lock.withLock { closed = true } }
  func check() throws {
    try lock.withLock { if closed { throw ConversationOutboxError.sessionClosed } }
  }
}

/// A typed question/answer form around the real encrypted controller. It owns
/// no Auth/patient grant and never converts an answer into a new meal report.
@MainActor @Observable final class FlowConversationMealReplyModel {
  typealias Delivered =
    @MainActor @Sendable (ConversationMealReplyResultSnapshot, ConversationCommandContext) -> Void
  private struct Head {
    let revision: Int
    let questionKey: String?
  }
  private var heads: [UUID: Head] = [:]
  private var fulfilledParents: Set<UUID> = []
  private struct Offer {
    let parent: ConversationThreadPageSnapshot.Binding
    let decisionHash: String
    let question: ConversationThreadPageSnapshot.Question
  }
  private let controller: ConversationMealReplyController
  private let lifecycle: any SessionLifecycleProviding
  private let onDelivered: Delivered
  private let lifetime = FlowMealReplyLifetime()
  private var lease: SessionLease?
  private var workID: UUID?
  private var context: ConversationCommandContext?
  private var identity: ConversationCommandContext.Identity?
  private var offer: Offer?
  private var preparation: ConversationMealReplyPreparation?
  private var intent: ConversationMealReplyIntent?
  private var requestedID: UUID?
  private var frozenAnswer: ConversationMealReplyIntent.Answer?
  private var text = ""
  private var unit = ""
  private var selectedMeal: ConversationMealCommand.MealType?
  private var language: SupportedAppLanguage = .portugueseBrazil
  private var presented = false
  private var formID: UUID?
  private var entries: [ConversationMealReplyOutboxEntry] = []
  private var held: [ConversationMealReplyOutboxViewSnapshot.Held] = []
  private var replay: Set<UUID> = []
  private var mayHaveDispatched = false
  private var hasSnapshot = false
  private var acknowledgement: ConversationMealReplyResultSnapshot?
  private var storedFailure: FlowConversationFailure?
  private var task: Task<Void, Never>?
  private var taskID: UUID?
  private(set) var isWorking = false
  private var hasScope: Bool {
    guard let context, !context.observation.isEnqueueOnly, let lease,
      (try? lifetime.check()) != nil,
      context.authUserID == UUID(uuidString: lease.userID),
      context.sessionGeneration == lease.generation
    else { return false }
    return (try? context.withCurrentAuthority { true }) == true
  }
  var question: ConversationThreadPageSnapshot.Question? { hasScope ? offer?.question : nil }
  var presentation: FlowConversationMealReplyPresentation? {
    guard hasScope, presented, let formID else { return nil }
    return .init(id: formID, model: self)
  }
  var failure: FlowConversationFailure? { hasScope ? storedFailure : nil }
  var lastDelivered: ConversationMealReplyResultSnapshot? { hasScope ? acknowledgement : nil }
  var pendingIntent: ConversationMealReplyIntent? { hasScope ? intent : nil }
  var pendingEntries: [ConversationMealReplyOutboxEntry] { hasScope ? entries : [] }
  var heldCount: Int { hasScope ? held.count : 0 }
  var heldEntries: [ConversationMealReplyOutboxViewSnapshot.Held] { hasScope ? held : [] }
  var isLocked: Bool { hasScope && (requestedID != nil || isWorking) }
  var canBegin: Bool { hasScope && !isWorking && requestedID == nil && entries.isEmpty }
  var amountText: String {
    get { hasScope ? text : "" }
    set {
      guard hasScope, !isLocked else { return }
      text = newValue
    }
  }
  var quantityUnit: String {
    get { hasScope ? unit : "" }
    set {
      guard hasScope, !isLocked, offer?.question.allowedUnits.contains(newValue) == true else {
        return
      }
      unit = newValue
    }
  }
  var mealType: ConversationMealCommand.MealType? {
    get { hasScope ? selectedMeal : nil }
    set {
      guard hasScope, !isLocked else { return }
      selectedMeal = newValue
    }
  }
  var canSubmit: Bool {
    guard hasScope, !isWorking, let offer, accepts(offer) else { return false }
    if requestedID != nil {
      if let intent, let row = entries.first(where: { $0.intent.replyID == intent.replyID }) {
        return row.state == .queued && row.hold == nil && !mayHaveDispatched
      }
      return !mayHaveDispatched
    }
    return answer() != nil
  }
  var canCheckStatus: Bool { hasScope && !isWorking && intent != nil && mayHaveDispatched }
  var canResume: Bool {
    hasScope && !isWorking && intent.map { replay.contains($0.replyID) } == true
  }
  var canDiscardUnsent: Bool {
    guard hasScope, !isWorking, requestedID != nil, !mayHaveDispatched else { return false }
    if let intent, let row = entries.first(where: { $0.intent.replyID == intent.replyID }) {
      return row.state == .queued
    }
    return true
  }
  private init(
    controller: ConversationMealReplyController, lifecycle: any SessionLifecycleProviding,
    lease: SessionLease, onDelivered: @escaping Delivered
  ) {
    self.controller = controller
    self.lifecycle = lifecycle
    self.lease = lease
    self.onDelivered = onDelivered
  }
  static func open(
    controller: ConversationMealReplyController, lifecycle: any SessionLifecycleProviding,
    lease: SessionLease, onDelivered: @escaping Delivered
  ) async throws -> Self {
    try await lifecycle.validate(lease)
    let model = Self(
      controller: controller, lifecycle: lifecycle, lease: lease, onDelivered: onDelivered)
    do {
      let lifetime = model.lifetime
      let id = try await lifecycle.beginPatientWork(lease: lease) { [weak model] in
        lifetime.close()
        Task { @MainActor in await model?.close() }
      }
      guard model.lease != nil, (try? lifetime.check()) != nil else {
        await lifecycle.finishPatientWork(id)
        throw ConversationOutboxError.sessionClosed
      }
      model.workID = id
      try await lifecycle.validate(lease)
      try lifetime.check()
      try Task.checkCancellation()
      return model
    } catch {
      await model.close()
      throw error
    }
  }
  func accept(_ value: ConversationCommandContext) {
    guard !value.observation.isEnqueueOnly, let lease, (try? lifetime.check()) != nil,
      value.authUserID == UUID(uuidString: lease.userID),
      value.sessionGeneration == lease.generation,
      (try? value.withCurrentAuthority { true }) == true
    else {
      suspend()
      return
    }
    if let identity, identity != value.identity {
      task?.cancel()
      task = nil
      taskID = nil
      isWorking = false
      clearForm()
      entries.removeAll()
      held.removeAll()
      acknowledgement = nil
      heads.removeAll()
      fulfilledParents.removeAll()
      storedFailure = nil
    }
    if context?.observation.isSameGrant(as: value.observation) != true {
      if requestedID == nil { clearForm() }
      replay.removeAll()
      hasSnapshot = false
      acknowledgement = acknowledgement?.withoutFeedback()
    }
    context = value
    identity = value.identity
  }
  func suspend() {
    if requestedID == nil { clearForm() }
    acknowledgement = acknowledgement?.withoutFeedback()
    context = nil
    replay.removeAll()
    hasSnapshot = false
  }
  func restore() async {
    guard let context, hasScope else { return }
    do { try await controller.publishSnapshot(context: context, publish: publisher(context)) } catch
    { if current(context) { storedFailure = failure(error) } }
  }
  func begin(
    parentBinding: ConversationThreadPageSnapshot.Binding, parentDecisionHash: String,
    question: ConversationThreadPageSnapshot.Question, replyID: UUID? = nil
  ) throws {
    guard canBegin, let context, parentBinding.ownerID == context.ownerID,
      parentBinding.epoch == context.epoch, !parentBinding.isChild
    else { throw ConversationMealReplyControllerError.unavailable }
    if let previous = acknowledgement, previous.parentBinding.commandID == parentBinding.commandID {
      guard previous.receipt == nil, let next = previous.question,
        question.revision >= next.revision,
        question.revision != next.revision || question.hasSameContent(as: next)
      else { throw ConversationMealReplyControllerError.changed }
    }
    let proposed = Offer(
      parent: parentBinding, decisionHash: parentDecisionHash, question: question)
    guard accepts(proposed) else { throw ConversationMealReplyControllerError.changed }
    offer = proposed
    // A supplied ID is used only by a controlled fixture/caller preparing an
    // original intent. It is not persisted or dispatchable before Submit.
    formID = replyID ?? UUID()
    presented = true
    text = ""
    selectedMeal = nil
    unit = question.allowedUnits.first ?? ""
    storedFailure = nil
  }
  func presentPending(replyID: UUID) throws {
    guard hasScope, !isWorking, let row = entries.first(where: { $0.intent.replyID == replyID }),
      requestedID == nil || requestedID == replyID
    else { throw ConversationMealReplyControllerError.reconciliationRequired }
    intent = row.intent
    requestedID = replyID
    preparation = nil
    offer = .init(
      parent: row.intent.parentBinding, decisionHash: row.intent.parentDecisionHash,
      question: row.intent.question)
    formID = replyID
    presented = true
    mayHaveDispatched = row.state != .queued
    restoreAnswer(row.intent)
  }
  var nextQuestion: ConversationThreadPageSnapshot.Question? {
    guard hasScope, let result = acknowledgement, result.receipt == nil,
      let question = result.question,
      accepts(
        .init(
          parent: result.parentBinding, decisionHash: result.parentDecisionHash, question: question)
      )
    else { return nil }
    return question
  }
  func beginNextQuestion() throws {
    guard let result = lastDelivered, let question = nextQuestion else {
      throw ConversationMealReplyControllerError.unavailable
    }
    try begin(
      parentBinding: result.parentBinding, parentDecisionHash: result.parentDecisionHash,
      question: question)
  }
  func presentOriginalIntent() {
    guard hasScope, requestedID != nil else { return }
    presented = true
  }
  func dismiss() {
    presented = false
    if requestedID == nil { clearForm() }
  }
  func submit(language: SupportedAppLanguage = .portugueseBrazil) async {
    self.language = language
    guard canSubmit, let context, let offer else { return }
    if requestedID == nil {
      guard let answer = answer() else {
        storedFailure = .invalidInput
        return
      }
      requestedID = formID ?? UUID()
      frozenAnswer = answer
    }
    guard let replyID = requestedID else { return }
    await run(context) {
      if self.preparation == nil, self.intent == nil {
        guard let answer = self.frozenAnswer else {
          throw ConversationMealReplyControllerError.unavailable
        }
        let prepared = try await self.controller.prepare(
          parentBinding: offer.parent, parentDecisionHash: offer.decisionHash,
          question: offer.question, answer: answer, context: context, replyID: replyID)
        try self.check(context)
        self.preparation = prepared
        self.intent = prepared.intent
      }
      if let prepared = self.preparation {
        _ = try await self.controller.enqueue(
          preparation: prepared, context: context, publish: self.publisher(context))
      } else {
        // A cold-restored queued intent already exists; never recreate it.
        guard
          self.entries.contains(where: {
            $0.intent.replyID == replyID && $0.state == .queued && $0.hold == nil
          })
        else { throw ConversationMealReplyControllerError.reconciliationRequired }
      }
      try self.check(context)
      self.mayHaveDispatched = true
      try await self.controller.send(
        replyID: replyID, context: context, publish: self.publisher(context))
    }
  }
  func checkStatus() async {
    guard canCheckStatus, let id = intent?.replyID, let context else { return }
    await run(context) {
      try await self.controller.reconcile(
        replyID: id, context: context, publish: self.publisher(context))
    }
  }
  func resume() async {
    guard canResume, let id = intent?.replyID, let context else { return }
    replay.remove(id)
    await run(context) {
      try await self.controller.resume(
        replyID: id, context: context, publish: self.publisher(context))
    }
  }
  func discardUnsent() async {
    guard canDiscardUnsent, let id = requestedID, let context else { return }
    await run(context) {
      do {
        try await self.controller.discardUnsent(
          replyID: id, context: context, publish: self.publisher(context))
      } catch ConversationOutboxError.commandNotFound {
        // Atomic read proved no stored intent.
      }
      try self.check(context)
      self.clearForm()
    }
  }
  /// The metadata carries no previous patient's body. The core repeats the
  /// never-dispatched check under this current Auth/grant and the file lock.
  func discardProtectedUnsent(replyID: UUID) async {
    guard hasScope, !isWorking, let context,
      held.contains(where: { $0.id == replyID && $0.canDiscardUnsent })
    else { return }
    await run(context) {
      try await self.controller.discardUnsent(
        replyID: replyID, context: context, publish: self.publisher(context))
    }
  }
  func invalidateSynchronously() {
    lifetime.close()
    lease = nil
    task?.cancel()
  }
  func close() async {
    invalidateSynchronously()
    context = nil
    identity = nil
    task = nil
    taskID = nil
    clearForm()
    entries.removeAll()
    held.removeAll()
    replay.removeAll()
    acknowledgement = nil
    heads.removeAll()
    fulfilledParents.removeAll()
    storedFailure = nil
    isWorking = false
    await controller.close()
    if let id = workID {
      workID = nil
      await lifecycle.finishPatientWork(id)
    }
  }
  /// Only an actual delivered reply or validated current head marks fulfillment.
  func hasFulfilledParent(_ parentID: UUID) -> Bool {
    hasScope && fulfilledParents.contains(parentID)
  }
  func currentQuestion(parentID: UUID, fallback: ConversationThreadPageSnapshot.Question?)
    -> ConversationThreadPageSnapshot.Question?
  {
    guard hasScope, !fulfilledParents.contains(parentID) else { return nil }
    guard let result = acknowledgement, result.parentBinding.commandID == parentID else {
      return fallback
    }
    if result.receipt != nil { return nil }
    guard let question = result.question,
      accepts(
        .init(
          parent: result.parentBinding, decisionHash: result.parentDecisionHash, question: question)
      )
    else { return fallback }
    if let fallback, fallback.revision > question.revision { return fallback }
    return question
  }
  var deliveredFeedback: ConversationFeedbackPresentationSnapshot.Bound? {
    guard hasScope, let context, let result = acknowledgement else { return nil }
    return result.boundFeedback(
      scope: .init(
        ownerID: context.ownerID.uuidString.lowercased(),
        sessionGeneration: context.sessionGeneration, epoch: context.epoch.uuidString.lowercased()))
  }
  /// Called only while publishing a validated owned v2 page. This does not
  /// acknowledge ciphertext or reconstruct a response from historical JSON.
  func observeThread(_ thread: ConversationThreadPageSnapshot.Thread) {
    guard hasScope, let context, thread.parentBinding.ownerID == context.ownerID,
      thread.parentBinding.epoch == context.epoch, let continuation = thread.continuation
    else { return }
    if continuation.fulfilledBy != nil {
      fulfilledParents.insert(thread.threadID)
      replay.removeAll()
      return
    }
    if fulfilledParents.contains(thread.threadID) { return }
    if let old = heads[thread.threadID], old.revision > continuation.revision { return }
    heads[thread.threadID] = .init(
      revision: continuation.revision, questionKey: continuation.question?.questionKey)
    if let offer, !accepts(offer) {
      storedFailure = .changed
      replay.removeAll()
    }
  }
  /// Current pure parent observation. Never rewrites a protected prepared answer.
  func observeParentHead(_ read: ConversationMealParentQuestionSnapshot) {
    guard hasScope, let context, read.authUserID == context.authUserID,
      read.ownerID == context.ownerID, read.epoch == context.epoch,
      let observed = ConversationProtocolInstant(read.observedAt),
      let accepted = ConversationProtocolInstant(context.observedAt), observed >= accepted
    else { return }
    let parent = read.parentCommandID
    if read.reason == "parent_fulfilled" { fulfilledParents.insert(parent) }
    if let old = heads[parent], old.revision > read.headRevision { return }
    heads[parent] = .init(revision: read.headRevision, questionKey: read.question?.questionKey)
    if let offer, !accepts(offer) { storedFailure = .changed; replay.removeAll() }
  }
  private func accepts(_ offer: Offer) -> Bool {
    guard !fulfilledParents.contains(offer.parent.commandID) else { return false }
    guard let head = heads[offer.parent.commandID] else { return true }
    return offer.question.revision >= head.revision
      && (offer.question.revision != head.revision
        || head.questionKey == offer.question.questionKey)
  }
  private func answer() -> ConversationMealReplyIntent.Answer? {
    guard let q = offer?.question else { return nil }
    if q.kind == "meal_type" { return selectedMeal.map { .mealType($0) } }
    guard q.allowedUnits.contains(unit),
      let n = MealProposalNumberParser.parse(text, language: language), n > 0, n <= 9999
    else { return nil }
    return .quantity(amount: n, unit: unit)
  }
  private func restoreAnswer(_ value: ConversationMealReplyIntent) {
    // The closed original body is decoded for display only; the stored Data
    // is the only body used by dispatch/reconciliation.
    guard let root = try? JSONSerialization.jsonObject(with: value.wireBody) as? [String: Any],
      let input = root["input"] as? [String: Any], let answer = input["answer"] as? [String: Any]
    else { return }
    if let type = answer["meal_type"] as? String { selectedMeal = .init(rawValue: type) }
    if let amount = answer["amount"] as? NSNumber { text = amount.stringValue }
    if let unit = answer["unit"] as? String { self.unit = unit }
  }
  private func clearForm() {
    offer = nil
    preparation = nil
    intent = nil
    requestedID = nil
    frozenAnswer = nil
    text = ""
    unit = ""
    selectedMeal = nil
    presented = false
    formID = nil
    mayHaveDispatched = false
  }
  private func current(_ value: ConversationCommandContext) -> Bool {
    hasScope && context?.observation.isSameGrant(as: value.observation) == true
  }
  private func check(_ value: ConversationCommandContext) throws {
    guard current(value) else { throw ConversationOutboxError.staleObservation }
  }
  private func publisher(_ context: ConversationCommandContext)
    -> ConversationMealReplyController.Publisher
  {
    { [weak self] event in self?.receive(event, context: context) }
  }
  private func receive(_ event: ConversationMealReplyEvent, context: ConversationCommandContext) {
    guard current(context) else { return }
    switch event {
    case .snapshot(let value):
      entries = value.entries
      held = value.held
      hasSnapshot = true
      if let intent, let row = entries.first(where: { $0.intent.replyID == intent.replyID }) {
        mayHaveDispatched = row.state != .queued
      }
    case .queued: break
    case .delivered(let value):
      let result = value.result
      entries.removeAll { $0.intent.replyID == result.replyID }
      replay.remove(result.replyID)
      if requestedID == result.replyID { clearForm() }
      acknowledgement = result
      if result.receipt != nil {
        fulfilledParents.insert(result.parentBinding.commandID)
      } else if let question = result.question {
        heads[result.parentBinding.commandID] = .init(
          revision: question.revision, questionKey: question.questionKey)
      }
      storedFailure = nil
      onDelivered(result, context)
    case .held(let id, _, let allowed):
      if allowed { replay.insert(id) } else { replay.remove(id) }
      storedFailure = .reconciliationRequired
    case .deferred(_, let reason):
      switch reason {
      case .offline: storedFailure = .offline
      case .rateLimited: storedFailure = .rateLimited
      case .changed: storedFailure = .changed
      case .storage: storedFailure = .storage
      case .unavailable: storedFailure = .unavailable
      }
    }
  }
  private func run(
    _ context: ConversationCommandContext, operation: @escaping @MainActor () async throws -> Void
  ) async {
    guard hasScope, !isWorking else { return }
    let id = UUID()
    taskID = id
    isWorking = true
    storedFailure = nil
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        if self.taskID == id {
          self.isWorking = false
          self.task = nil
          self.taskID = nil
        }
      }
      do {
        try self.check(context)
        try await operation()
      } catch is CancellationError { return } catch {
        guard self.current(context), self.taskID == id else { return }
        self.storedFailure = self.failure(error)
        try? await self.controller.publishSnapshot(
          context: context, publish: self.publisher(context))
      }
    }
    self.task = task
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }
  private func failure(_ error: any Error) -> FlowConversationFailure {
    switch error {
    case ConversationOutboxError.storageUnavailable, ConversationOutboxError.keyUnavailable,
      ConversationOutboxError.integrityFailure:
      .storage
    case ConversationOutboxError.reconciliationRequired,
      ConversationMealReplyControllerError.reconciliationRequired:
      .reconciliationRequired
    case ConversationMealReplyControllerError.changed, MobileAPITransportError.conflict: .changed
    case MobileAPITransportError.network, MobileAPITransportError.timeout: .offline
    case MobileAPITransportError.rateLimited: .rateLimited
    default: .unavailable
    }
  }
}
