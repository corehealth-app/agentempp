import Foundation
import Observation

struct FlowConversationMealEditingDependencies: Sendable {
  let store: EncryptedConversationMealEditOutboxStore
  let keyVault: ConversationOutboxKeyVault
  init(
    store: EncryptedConversationMealEditOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(
      service: ConversationMealEditOutboxSession.keychainService)
  ) {
    self.store = store
    self.keyVault = keyVault
  }
}
@MainActor struct FlowConversationMealEditPresentation: Identifiable {
  let id: UUID
  let model: FlowConversationMealEditModel
}
struct FlowConversationMealEditPendingItem: Identifiable, Sendable {
  let id: Int
  let foodName: String
  let grams: Decimal
}
@MainActor struct FlowConversationMealEditActions {
  let editItem: (ConversationMealGroupSnapshot.Item) -> Void
  let undoSave: (ConversationMealGroupSnapshot) -> Void
  let undoRegistration: (ConversationMealGroupSnapshot) -> Void
  let isWorking: Bool
}
private final class FlowMealEditLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false
  func close() { lock.withLock { closed = true } }
  func check() throws {
    try lock.withLock { if closed { throw ConversationOutboxError.sessionClosed } }
  }
}

/// Real editor around the concrete encrypted controller. Scope is accepted only
/// from the actual command owner; no patient/epoch observation is constructed.
@MainActor @Observable
final class FlowConversationMealEditModel {
  typealias Saved =
    @MainActor @Sendable (ConversationMealEditResultSnapshot, ConversationCommandContext) -> Void
  private let controller: ConversationMealEditController
  private let lifecycle: any SessionLifecycleProviding
  typealias Historical =
    @MainActor @Sendable (ConversationMealEditHistoricalNotice, ConversationCommandContext) -> Void
  private let onSaved: Saved
  private let onHistorical: Historical
  private let lifetime = FlowMealEditLifetime()
  private var lease: SessionLease?
  private var workID: UUID?
  private var context: ConversationCommandContext?
  private var identity: ConversationCommandContext.Identity?
  private var group: ConversationMealGroupSnapshot?
  private var linkedOrigin: ConversationMealLinkedIdentity?
  private var draft: ConversationMealItemEditDraft?
  private var requestedAction: ConversationMealEditOperation.Action?
  private var preparation: ConversationMealEditPreparation?
  private var intent: ConversationMealEditOperation?
  private var entries: [ConversationMealEditOutboxEntry] = []
  private var held: [ConversationMealEditOutboxViewSnapshot.Held] = []
  private var replay: Set<ConversationMealEditOutboxID> = []
  private var mayHaveDispatched = false
  private var hasSnapshot = false
  private var formID: UUID?
  private var presented = false
  private var task: Task<Void, Never>?
  private var taskID: UUID?
  private var storedFailure: FlowConversationFailure?
  private var acknowledgement: ConversationMealEditResultSnapshot?
  private var recoveredHistory: ConversationMealEditHistoricalNotice?
  private(set) var isWorking = false
  private var isClosed: Bool { lease == nil || (try? lifetime.check()) == nil }
  private var hasScope: Bool {
    guard !isClosed, let context, let lease,
      context.authUserID == UUID(uuidString: lease.userID),
      context.sessionGeneration == lease.generation
    else { return false }
    return (try? context.withCurrentAuthority { true }) == true
  }
  var presentation: FlowConversationMealEditPresentation? {
    guard hasScope, presented, let formID else { return nil }
    return .init(id: formID, model: self)
  }
  var failure: FlowConversationFailure? { hasScope ? storedFailure : nil }
  var lastSaved: ConversationMealEditResultSnapshot? { hasScope ? acknowledgement : nil }
  var historicalNotice: ConversationMealEditHistoricalNotice? { hasScope ? recoveredHistory : nil }
  var pendingOperation: ConversationMealEditOperation? { hasScope ? intent : nil }
  var historicalRecoveryCommandID: UUID? {
    guard hasScope, hasSnapshot, let intent,
      !entries.contains(where: { $0.id == .init(operation: intent) }),
      !held.contains(where: { $0.id == .init(operation: intent) })
    else { return nil }
    return intent.commandID
  }
  var isLocked: Bool { hasScope && (isWorking || intent != nil) }
  var canBeginEditing: Bool {
    hasScope && !isWorking && formID == nil && intent == nil && entries.isEmpty
  }
  var pendingEntries: [ConversationMealEditOutboxEntry] { hasScope ? entries : [] }
  var heldCount: Int { hasScope ? held.count : 0 }
  var hasPreparedIntent: Bool { hasScope && intent != nil }
  var formAction: ConversationMealEditOperation.Action? {
    hasScope ? intent?.action ?? requestedAction : nil
  }
  var isItemForm: Bool {
    guard hasScope else { return false }
    if draft != nil { return true }
    if case .save = formAction { return true }
    return false
  }
  var foodName: String {
    get {
      guard hasScope else { return "" }
      return draft?.foodName ?? pendingItems.first?.foodName ?? ""
    }
    set {
      guard hasScope, !isLocked, var draft else { return }
      draft.foodName = newValue
      self.draft = draft
    }
  }
  var quantityUnit: String { hasScope ? draft?.quantityUnit ?? "g" : "" }
  var usesEstimatedReference: Bool { hasScope && draft?.usesEstimatedReference == true }
  var referenceChanged: Bool { hasScope && draft?.referenceChanged == true }
  var pendingItems: [FlowConversationMealEditPendingItem] {
    guard hasScope, case .save(_, let items) = intent?.action else { return [] }
    return items.enumerated().map {
      .init(id: $0.offset, foodName: $0.element.foodName, grams: $0.element.quantityG)
    }
  }
  var canCheckStatus: Bool { hasScope && intent != nil && mayHaveDispatched && !isWorking }
  var canResubmit: Bool {
    guard hasScope, !isWorking, let intent else { return false }
    return replay.contains(.init(operation: intent))
  }
  var canDiscardUnsent: Bool {
    guard hasScope, !isWorking, let intent else { return false }
    if let entry = entries.first(where: { $0.id == .init(operation: intent) }) {
      return entry.state == .queued && !mayHaveDispatched
    }
    return !mayHaveDispatched
  }
  private init(
    controller: ConversationMealEditController, lifecycle: any SessionLifecycleProviding,
    lease: SessionLease, onHistorical: @escaping Historical, onSaved: @escaping Saved
  ) {
    self.onHistorical = onHistorical
    self.controller = controller
    self.lifecycle = lifecycle
    self.lease = lease
    self.onSaved = onSaved
  }
  static func open(
    controller: ConversationMealEditController, lifecycle: any SessionLifecycleProviding,
    lease: SessionLease, onHistorical: @escaping Historical = { _, _ in }, onSaved: @escaping Saved
  ) async throws -> FlowConversationMealEditModel {
    try await lifecycle.validate(lease)
    let model = Self(
      controller: controller, lifecycle: lifecycle, lease: lease,
      onHistorical: onHistorical, onSaved: onSaved)
    do {
      let lifetime = model.lifetime
      let id = try await lifecycle.beginPatientWork(lease: lease) { [weak model] in
        lifetime.close()
        Task { @MainActor in await model?.close() }
      }
      guard !model.isClosed else {
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
    guard !isClosed, let lease, value.authUserID == UUID(uuidString: lease.userID),
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
      clearForm()
      entries.removeAll()
      held.removeAll()
      acknowledgement = nil
      recoveredHistory = nil
      storedFailure = nil
      isWorking = false
    }
    let sameGrant = context?.observation.isSameGrant(as: value.observation) == true
    context = value
    identity = value.identity
    if !sameGrant {
      replay.removeAll()
      hasSnapshot = false
    }
  }
  func suspend() {
    context = nil
    replay.removeAll()
    hasSnapshot = false
  }
  func restore() async {
    guard let context, hasScope else { return }
    do { try await controller.publishSnapshot(context: context, publish: publisher(context)) } catch
    { if current(context) { storedFailure = failure(error) } }
  }
  func beginEditing(group: ConversationMealGroupSnapshot, itemID: UUID) throws {
    try beginEditing(linked: nil, group: group, itemID: itemID)
  }
  func beginEditing(
    linked: ConversationMealLinkedIdentity, group: ConversationMealGroupSnapshot, itemID: UUID
  ) throws {
    try beginEditing(linked: Optional(linked), group: group, itemID: itemID)
  }
  private func beginEditing(
    linked: ConversationMealLinkedIdentity?, group: ConversationMealGroupSnapshot, itemID: UUID
  ) throws {
    guard canBeginEditing, matches(group, linked: linked), group.actions.save.allowed,
      let item = group.current?.items.first(where: { $0.id == itemID })
    else { throw ConversationMealEditControllerError.unavailable }
    self.group = group
    linkedOrigin = linked
    draft = .init(item)
    formID = UUID()
    presented = true
    storedFailure = nil
    acknowledgement = nil
    recoveredHistory = nil
  }
  func presentPending(id: ConversationMealEditOutboxID) throws {
    guard hasScope, !isWorking, let entry = entries.first(where: { $0.id == id }),
      intent == nil || intent.map({ ConversationMealEditOutboxID(operation: $0) }) == id
    else { throw ConversationMealEditControllerError.reconciliationRequired }
    group = nil
    linkedOrigin = nil
    draft = nil
    preparation = nil
    intent = entry.operation
    mayHaveDispatched = entry.state != .queued
    formID = formID ?? UUID()
    presented = true
    storedFailure = nil
  }
  func dismiss() {
    presented = false
    if !isWorking && intent == nil { clearForm() }
  }
  func presentOriginalIntent() {
    guard hasScope, intent != nil, formID != nil else { return }
    presented = true
  }
  func quantityText(language: SupportedAppLanguage) -> String {
    guard hasScope else { return "" }
    if let draft { return draft.quantityText(language: language) }
    return pendingItems.first.map { NSDecimalNumber(decimal: $0.grams).stringValue } ?? ""
  }
  func setQuantityText(_ text: String, language: SupportedAppLanguage) {
    guard hasScope, !isLocked, var draft else { return }
    draft.setQuantityText(text, language: language)
    self.draft = draft
  }
  func canToggleQuantityUnit(language: SupportedAppLanguage) -> Bool {
    hasScope && !isLocked && draft?.canToggleQuantityUnit(language: language) == true
  }
  func toggleQuantityUnit(language: SupportedAppLanguage) {
    guard hasScope, !isLocked, var draft else { return }
    draft.toggleQuantityUnit(language: language)
    self.draft = draft
  }
  func canSave(language: SupportedAppLanguage) -> Bool {
    guard hasScope, !isWorking else { return false }
    if let intent {
      if let entry = entries.first(where: { $0.id == .init(operation: intent) }) {
        return entry.state == .queued && entry.hold == nil && !mayHaveDispatched
      }
      return preparation != nil && !mayHaveDispatched
    }
    return draft?.hasChanges(language: language) == true
      && draft?.request(language: language) != nil
  }
  func save(language: SupportedAppLanguage) async {
    guard canSave(language: language), let context else { return }
    await run(context) {
      if self.intent == nil {
        guard let group = self.group, let draft = self.draft,
          let item = draft.request(language: language),
          let version = group.current?.expectedVersion
        else { throw ConversationOutboxError.invalidCommand }
        let preparation = try await self.prepare(
          group: group, version: version, action: .save(recordID: draft.recordID, items: [item]),
          context: context)
        try self.check(context)
        self.preparation = preparation
        self.intent = preparation.operation
      }
      try await self.dispatch(context)
    }
  }
  func undoSave(group: ConversationMealGroupSnapshot) async {
    guard let target = group.lastOperation?.operationID, group.actions.undoSave.allowed else {
      return
    }
    await execute(linked: nil, group: group, action: .undoSave(targetOperationID: target))
  }
  func undoRegistration(group: ConversationMealGroupSnapshot) async {
    guard group.actions.undoRegistration.allowed else { return }
    await execute(linked: nil, group: group, action: .undoRegistration)
  }
  func undoSave(linked: ConversationMealLinkedIdentity, group: ConversationMealGroupSnapshot) async
  {
    guard let target = group.lastOperation?.operationID, group.actions.undoSave.allowed else {
      return
    }
    await execute(linked: linked, group: group, action: .undoSave(targetOperationID: target))
  }
  func undoRegistration(
    linked: ConversationMealLinkedIdentity, group: ConversationMealGroupSnapshot
  ) async {
    guard group.actions.undoRegistration.allowed else { return }
    await execute(linked: linked, group: group, action: .undoRegistration)
  }
  private func execute(
    linked: ConversationMealLinkedIdentity?, group: ConversationMealGroupSnapshot,
    action: ConversationMealEditOperation.Action
  ) async {
    guard canBeginEditing, matches(group, linked: linked), let context,
      let version = group.current?.expectedVersion
    else { return }
    self.group = group
    linkedOrigin = linked
    draft = nil
    requestedAction = action
    formID = UUID()
    presented = true
    await run(context) {
      let prepared = try await self.prepare(
        group: group, version: version, action: action, context: context)
      try self.check(context)
      self.preparation = prepared
      self.intent = prepared.operation
      try await self.dispatch(context)
    }
  }
  private func prepare(
    group: ConversationMealGroupSnapshot, version: String,
    action: ConversationMealEditOperation.Action,
    context: ConversationCommandContext
  ) async throws -> ConversationMealEditPreparation {
    if let linkedOrigin {
      return try await controller.prepare(
        linked: linkedOrigin, expectedRevision: group.revision, expectedVersion: version,
        action: action, context: context)
    }
    return try await controller.prepare(
      commandID: group.commandID, originalInputHash: group.originalInputHash,
      expectedRevision: group.revision, expectedVersion: version, action: action, context: context)
  }
  private func dispatch(_ context: ConversationCommandContext) async throws {
    guard let intent else { throw ConversationOutboxError.invalidCommand }
    let id = ConversationMealEditOutboxID(operation: intent)
    if let preparation {
      _ = try await controller.enqueue(
        preparation: preparation, context: context, publish: publisher(context))
    }
    try check(context)
    if let entry = entries.first(where: { $0.id == id }),
      entry.state != .queued || entry.hold != nil
    {
      throw ConversationMealEditControllerError.reconciliationRequired
    }
    mayHaveDispatched = true
    try await controller.send(id: id, context: context, publish: publisher(context))
  }
  func reconcile() async {
    guard canCheckStatus, let context, let intent else { return }
    let id = ConversationMealEditOutboxID(operation: intent)
    await run(context) {
      try await self.controller.reconcile(
        id: id, context: context, publish: self.publisher(context))
      try await self.controller.publishSnapshot(context: context, publish: self.publisher(context))
    }
  }
  func resubmit() async {
    guard canResubmit, let context, let intent else { return }
    let id = ConversationMealEditOutboxID(operation: intent)
    replay.remove(id)
    await run(context) {
      self.mayHaveDispatched = true
      try await self.controller.resubmit(id: id, context: context, publish: self.publisher(context))
    }
  }
  func discardUnsent(id: ConversationMealEditOutboxID) async {
    guard canDiscardUnsent, let context,
      intent.map({ ConversationMealEditOutboxID(operation: $0) }) == id
    else { return }
    await run(context) {
      do {
        try await self.controller.discardUnsent(
          id: id, context: context, publish: self.publisher(context))
      } catch ConversationOutboxError.commandNotFound {
        guard !self.mayHaveDispatched else {
          throw ConversationMealEditControllerError.reconciliationRequired
        }
      }
      try self.check(context)
      if self.intent.map({ ConversationMealEditOutboxID(operation: $0) }) == id { self.clearForm() }
    }
  }
  func observeJournal(_ read: ConversationJournalRead) {
    guard hasScope, hasSnapshot, let context, let intent,
      context.observation.isSameGrant(as: read.context.observation),
      read.page.matches(
        authUserID: context.authUserID, ownerID: context.ownerID, epoch: context.epoch),
      !entries.contains(where: { $0.id == .init(operation: intent) }),
      !held.contains(where: { $0.id == .init(operation: intent) })
    else { return }
    for entry in read.page.items {
      if case .edit(let event) = entry, event.result.matches(operation: intent) {
        acknowledge(event.result, context: context)
        return
      }
    }
  }
  /// UI-only recovery after local ACK persistence but lost publication. The
  /// actual complete same-grant snapshot must prove the intent already absent
  /// from BOTH visible and held ciphertext. History never ACKs or enables replay.
  func observeThreadJournal(
    _ read: ConversationThreadJournalRead, linked: ConversationMealLinkedIdentity,
    group: ConversationMealGroupSnapshot
  ) {
    guard hasScope, hasSnapshot, let context, let intent,
      context.observation.isSameGrant(as: read.context.observation),
      !entries.contains(where: { $0.id == .init(operation: intent) }),
      !held.contains(where: { $0.id == .init(operation: intent) }),
      let notice = ConversationMealEditHistoricalNotice.qualify(
        operation: intent, read: read, linked: linked, group: group)
    else { return }
    clearForm()
    recoveredHistory = notice
    storedFailure = nil
    onHistorical(notice, context)
  }
  func invalidateSynchronously() {
    lifetime.close()
    lease = nil
    task?.cancel()
    context = nil
    replay.removeAll()
  }
  func close() async {
    invalidateSynchronously()
    task?.cancel()
    task = nil
    taskID = nil
    context = nil
    identity = nil
    lease = nil
    clearForm()
    entries.removeAll()
    held.removeAll()
    acknowledgement = nil
    recoveredHistory = nil
    storedFailure = nil
    isWorking = false
    hasSnapshot = false
    await controller.close()
    if let id = workID {
      workID = nil
      await lifecycle.finishPatientWork(id)
    }
  }
  private func clearForm() {
    group = nil
    linkedOrigin = nil
    draft = nil
    requestedAction = nil
    preparation = nil
    intent = nil
    formID = nil
    presented = false
    mayHaveDispatched = false
    replay.removeAll()
  }
  private func check(_ value: ConversationCommandContext) throws {
    try Task.checkCancellation()
    guard current(value) else { throw ConversationOutboxError.invalidServerObservation }
  }
  private func current(_ value: ConversationCommandContext) -> Bool {
    hasScope && context?.observation.isSameGrant(as: value.observation) == true
  }
  private func matches(
    _ group: ConversationMealGroupSnapshot, linked: ConversationMealLinkedIdentity?
  ) -> Bool {
    guard let context, hasScope, group.ownerID == context.ownerID, group.epoch == context.epoch
    else {
      return false
    }
    return linked.map { $0.matches(group: group) } ?? (group.originalReceipt.report != nil)
  }
  private func publisher(_ context: ConversationCommandContext)
    -> ConversationMealEditController.Publisher
  {
    { [weak self] event in self?.receive(event, context: context) }
  }
  private func receive(_ event: ConversationMealEditEvent, context: ConversationCommandContext) {
    guard current(context) else { return }
    switch event {
    case .snapshot(let value):
      entries = value.entries
      held = value.held
      hasSnapshot = true
      if let intent, let entry = entries.first(where: { $0.id == .init(operation: intent) }) {
        mayHaveDispatched = entry.state != .queued
        if entry.hold == .reset || entry.hold == .staleEpoch || entry.hold == .serverChanged {
          replay.remove(entry.id)
        }
      }
    case .saved(let value): acknowledge(value.result, context: context)
    case .absent(let id, let allowed): if allowed { replay.insert(id) } else { replay.remove(id) }
    case .deferred(_, let reason):
      switch reason {
      case .offline: storedFailure = .offline
      case .rateLimited: storedFailure = .rateLimited
      case .changed: storedFailure = .changed
      case .storage: storedFailure = .storage
      case .unavailable: storedFailure = .unavailable
      }
    case .queued: break
    }
  }
  private func acknowledge(
    _ result: ConversationMealEditResultSnapshot, context: ConversationCommandContext
  ) {
    guard current(context) else { return }
    let id = ConversationMealEditOutboxID(
      commandID: result.commandID, operationID: result.receipt.operationID)
    entries.removeAll { $0.id == id }
    if intent.map({ ConversationMealEditOutboxID(operation: $0) }) == id { clearForm() }
    acknowledgement = result
    recoveredHistory = nil
    storedFailure = nil
    onSaved(result, context)
  }
  private func run(
    _ context: ConversationCommandContext, operation: @escaping @MainActor () async throws -> Void
  ) async {
    guard hasScope, !isWorking else { return }
    let id = UUID()
    taskID = id
    isWorking = true
    storedFailure = nil
    let currentTask = Task { @MainActor [weak self] in
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
    task = currentTask
    await withTaskCancellationHandler {
      await currentTask.value
    } onCancel: {
      currentTask.cancel()
    }
  }
  private func failure(_ error: any Error) -> FlowConversationFailure {
    switch error {
    case ConversationOutboxError.storageUnavailable, ConversationOutboxError.keyUnavailable,
      ConversationOutboxError.integrityFailure:
      .storage
    case ConversationOutboxError.reconciliationRequired,
      ConversationMealEditControllerError.reconciliationRequired:
      .reconciliationRequired
    case ConversationMealEditControllerError.changed: .changed
    case MobileAPITransportError.network, MobileAPITransportError.timeout: .offline
    case MobileAPITransportError.rateLimited: .rateLimited
    case MobileAPITransportError.conflict: .changed
    default: .unavailable
    }
  }
}
