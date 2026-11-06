import Foundation
import Observation

struct FlowConversationPendingRow: Identifiable, Sendable {
  let command: ConversationMealCommand
  let state: ConversationOutboxState
  let hold: ConversationOutboxHold?
  var id: UUID { command.commandID }
}
struct FlowConversationSavedRow: Identifiable, Sendable {
  let command: ConversationMealCommand
  let receipt: SavedConversationMealCommandResultSnapshot.Receipt
  let feedback: ConversationFeedbackPresentationSnapshot.Bound?
  var id: UUID { command.commandID }
}
struct FlowConversationLinkedMealRow: Identifiable, Sendable {
  let reference: ConversationMealLinkedReadReference
  let identity: ConversationMealLinkedIdentity?
  let feedback: ConversationFeedbackPresentationSnapshot.Bound?
  var id: UUID { reference.commandID }
}
struct FlowConversationTerminalQuestion: Sendable {
  let commandID: UUID
  let reason: String?
  let observedQuestion: ConversationThreadPageSnapshot.Question?
}
enum FlowConversationFailure: Equatable, Sendable {
  case offline, storage, unavailable, invalidInput, reconciliationRequired, rateLimited, changed
}

struct FlowConversationMediaDependencies: Sendable {
  let uploader: any StorageUploading
  let staging: MediaStagingStore
}
struct FlowConversationAttachment: Identifiable, Sendable {
  let id: UUID
  let commandID: UUID
  let staged: StagedMedia
  let identity: ConversationCommandContext.Identity
}
enum FlowConversationMediaPhase: Equatable, Sendable { case uploading, processing }
enum FlowConversationHistoryVersion: Sendable { case v1, v2, v3 }

/// New command feature, separate from the existing legacy Flow sender. Its
/// asynchronous factory uses the actual authenticated controller/lifecycle;
/// no demo repository or successful-save placeholder is installed here.
@MainActor @Observable
final class FlowConversationModel {
  private struct ThreadEventPin {
    let digest: String
    let reportStatus: ConversationThreadPageSnapshot.ReportStatus?
  }
  private struct PreparedDraft: Sendable {
    let command: ConversationMealCommand
    let context: ConversationCommandContext.Identity
    let revision: UInt64
  }
  private let controller: any ConversationMealCommandControlling
  private let lifecycle: any SessionLifecycleProviding
  private let history: MobileConversationHistoryRepository
  private let historyPageSize: Int
  private let historyVersion: FlowConversationHistoryVersion
  let unifiedHistory: FlowConversationJournalV3Model
  private var historyEntries: [ConversationJournalPageSnapshot.Entry] = []
  private var threadEntries: [ConversationThreadPageSnapshot.Entry] = []
  private var threadDescriptors: [UUID: ConversationThreadPageSnapshot.Thread] = [:]
  private var threadObservedAt: String?
  private var threadEditReads: [UUID: ConversationThreadJournalRead] = [:]
  private var knownThreadEvents: [String: ThreadEventPin] = [:]
  private var historyIdentity: ConversationCommandContext.Identity?
  private var historyCursor: String?
  private var historyHasMore = false
  private var historyRequestID: UUID?
  private(set) var isLoadingHistory = false
  private(set) var historyUnavailable = false
  private var dismissedQuestions: Set<UUID> = []
  private var currentGroups: [UUID: ConversationMealGroupSnapshot] = [:]
  // Child observations never enter commands, which stores real v1 reports only.
  private var linkedReadReferences: [UUID: ConversationMealLinkedReadReference] = [:]
  private var linkedMealIdentities: [UUID: ConversationMealLinkedIdentity] = [:]
  private var knownGroupInputHashes: [UUID: String] = [:]
  // Highest owned effect survives page/reset replacement within this exact
  // identity. A late group read cannot make a known edit disappear.
  private var knownGroupEdits: [UUID: ConversationMealEditEffectSnapshot] = [:]
  private var acknowledgedEdits: Set<ConversationMealEditOutboxID> = []
  private(set) var mealEditor: FlowConversationMealEditModel?
  private(set) var mealReplies: FlowConversationMealReplyModel?
  private(set) var neutralIntake: FlowNeutralIntakeModel?
  private var deliveredLinkedEffects: Set<UUID> = []
  private var groupRequests: [UUID: UUID] = [:]
  private var groupFailures: Set<UUID> = []
  private let lifetime = FlowConversationLifetime()
  private var mediaService: ConversationMealMediaService?
  private let mediaDependencies: FlowConversationMediaDependencies?
  private var selectedAttachment: FlowConversationAttachment?
  private(set) var mediaPhase: FlowConversationMediaPhase?
  private var lease: SessionLease?
  private var context: ConversationCommandContext?
  private var lastIdentity: ConversationCommandContext.Identity?
  private var workID: UUID?
  private var operation: Task<Void, Never>?
  private var operationID: UUID?
  private var publicationID = UUID()
  private var refreshingID: UUID?
  private var closed = false
  private var draft = ""
  private var draftRevision: UInt64 = 0
  private var preparedDraft: PreparedDraft?
  private var pending: [FlowConversationPendingRow] = []
  private var saved: [FlowConversationSavedRow] = []
  private var savedIdentities: [UUID: ConversationCommandContext.Identity] = [:]
  private var commands: [UUID: ConversationMealCommand] = [:]
  private var replayAllowed: Set<UUID> = []
  private var blockedDecisionID: UUID?
  private var latestDecision: ConversationMealCommandStateSnapshot?
  private(set) var heldRows: [ConversationOutboxViewSnapshot.Held] = []
  private(set) var queuedMetadata: [UUID] = []
  private(set) var failure: FlowConversationFailure?
  private(set) var savedEffectRevision: UInt64 = 0
  var acceptedIdentity: ConversationCommandContext.Identity? {
    hasCurrentScope ? context?.identity : nil
  }
  private(set) var isWorking = false
  private(set) var isRefreshing = false
  private var selectedMealType: ConversationMealCommand.MealType?
  private var preparingMediaIntent = false
  var isComposerLocked: Bool { !isClosed && (preparedDraft != nil || preparingMediaIntent) }
  var mealType: ConversationMealCommand.MealType? {
    get { isClosed ? nil : selectedMealType }
    set {
      guard !isClosed, !isComposerLocked, selectedMealType != newValue else { return }
      selectedMealType = newValue
      draftRevision &+= 1
    }
  }

  var composer: String {
    get { isClosed ? "" : draft }
    set {
      guard !isClosed, !isComposerLocked else { return }
      draft = newValue
      draftRevision &+= 1
    }
  }
  var isClosed: Bool { closed || lifetime.isClosed }
  var canSubmit: Bool {
    guard !isClosed, !isWorking, lastIdentity != nil, blockedDecisionID == nil else { return false }
    if let preparedDraft {
      if let known = pending.first(where: { $0.id == preparedDraft.command.commandID }),
        known.state != .queued || known.hold != nil
      {
        return false
      }
      return preparedDraft.context == lastIdentity
    }
    if selectedAttachment != nil { return composer.utf16.count <= 1_000 }
    return !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && composer.utf16.count <= 2_000
  }
  var terminalQuestion: FlowConversationTerminalQuestion? {
    guard hasCurrentScope, let id = blockedDecisionID else { return nil }
    return .init(
      commandID: id,
      reason: latestDecision?.commandID == id
        ? latestDecision?.reason : threadDescriptors[id]?.terminalReceipt?.reason,
      observedQuestion: currentLinkedQuestion(parentID: id))
  }
  func beginIndependentReport() {
    guard hasCurrentScope, !isWorking, !isComposerLocked, blockedDecisionID != nil else { return }
    if let id = blockedDecisionID { dismissedQuestions.insert(id) }
    blockedDecisionID = nil
    draft = ""
    draftRevision &+= 1
    preparedDraft = nil
    if let selected = selectedAttachment {
      mediaDependencies?.staging.remove(selected.staged.fileURL)
    }
    selectedAttachment = nil
    // The original terminal command remains held and immutable. This action
    // opens an empty independent composer, never copies/relinks its source.
  }
  var captureContext: ConversationCommandContext.Identity? {
    hasCurrentScope && mediaService != nil ? context?.identity : nil
  }
  var attachment: FlowConversationAttachment? { hasCurrentScope ? selectedAttachment : nil }
  func attach(_ staged: StagedMedia, expectedContext: ConversationCommandContext.Identity) throws {
    guard !isWorking, !isClosed, !isComposerLocked, let context,
      context.identity == expectedContext,
      mediaService != nil
    else {
      mediaDependencies?.staging.remove(staged.fileURL)
      throw ConversationOutboxError.invalidServerObservation
    }
    try context.withCurrentAuthority {}
    if let old = selectedAttachment { mediaDependencies?.staging.remove(old.staged.fileURL) }
    selectedAttachment = .init(
      id: UUID(), commandID: UUID(), staged: staged, identity: expectedContext)
    preparedDraft = nil
    draftRevision &+= 1
  }
  func removeAttachment() async {
    guard !isWorking, !isComposerLocked, let selected = selectedAttachment else { return }
    selectedAttachment = nil
    preparedDraft = nil
    draftRevision &+= 1
    mediaDependencies?.staging.remove(selected.staged.fileURL)
    if let context, context.identity == selected.identity {
      try? await mediaService?.discard(captureID: selected.id, context: context)
    }
  }
  var preparedIntent: ConversationMealCommand? { hasCurrentScope ? preparedDraft?.command : nil }
  var pendingDraftID: UUID? { isClosed ? nil : preparedDraft?.command.commandID }
  var journalRows: [ConversationJournalPageSnapshot.Entry] {
    hasCurrentScope && historyIdentity == lastIdentity ? historyEntries : []
  }
  var threadRows: [ConversationThreadPageSnapshot.Entry] {
    hasCurrentScope && historyIdentity == lastIdentity ? threadEntries : []
  }
  func threadDescriptor(_ id: UUID) -> ConversationThreadPageSnapshot.Thread? {
    hasCurrentScope && historyIdentity == lastIdentity ? threadDescriptors[id] : nil
  }
  func observedThreadQuestion(eventID: String) -> ConversationThreadPageSnapshot.Question? {
    guard hasCurrentScope, historyIdentity == lastIdentity, blockedDecisionID == nil,
      let event = threadEntries.first(where: { $0.eventID == eventID }),
      threadEntries.first(where: { $0.threadID == event.threadID })?.eventID == eventID
    else { return nil }
    return currentLinkedQuestion(parentID: event.threadID)
  }
  private func currentLinkedQuestion(parentID: UUID) -> ConversationThreadPageSnapshot.Question? {
    let fallback = threadDescriptors[parentID]?.continuation?.question
    return mealReplies.map { $0.currentQuestion(parentID: parentID, fallback: fallback) }
      ?? fallback
  }
  func canAnswerLinkedQuestion(parentID: UUID) -> Bool {
    guard hasCurrentScope, historyIdentity == lastIdentity, mealReplies?.canBegin == true,
      let descriptor = threadDescriptors[parentID], descriptor.terminalReceipt != nil,
      descriptor.continuation?.fulfilledBy == nil, currentLinkedQuestion(parentID: parentID) != nil
    else { return false }
    return true
  }
  func beginLinkedReply(parentID: UUID) {
    guard canAnswerLinkedQuestion(parentID: parentID), let descriptor = threadDescriptors[parentID],
      let decision = descriptor.terminalReceipt,
      let question = currentLinkedQuestion(parentID: parentID)
    else { return }
    do {
      try mealReplies?.begin(
        parentBinding: descriptor.parentBinding, parentDecisionHash: decision.decisionHash,
        question: question)
    } catch { failure = .changed }
  }
  var hasUnpublishedLinkedDelivery: Bool {
    guard hasCurrentScope, let result = mealReplies?.lastDelivered, let child = result.childBinding,
      result.receipt != nil
    else { return false }
    return !threadEntries.contains { entry in
      guard case .fulfillment(let value) = entry.detail else { return false }
      return value.binding == child
    }
  }
  func linkedMealRow(eventID: String) -> FlowConversationLinkedMealRow? {
    guard hasCurrentScope, historyIdentity == lastIdentity,
      let event = threadEntries.first(where: { $0.eventID == eventID }),
      let child = event.childBinding, child.isChild,
      Self.showsLinkedMeal(event),
      threadEntries.first(where: {
        $0.childBinding?.commandID == child.commandID && Self.showsLinkedMeal($0)
      })?.eventID == eventID,
      let reference = linkedReadReferences[child.commandID]
    else { return nil }
    let feedback = threadEntries.first(where: {
      if case .fulfillment(let value) = $0.detail { return value.binding == child }
      return false
    }).flatMap { threadFeedback(eventID: $0.eventID) }
    return .init(
      reference: reference, identity: linkedMealIdentities[child.commandID], feedback: feedback)
  }
  private static func showsLinkedMeal(_ entry: ConversationThreadPageSnapshot.Entry) -> Bool {
    switch entry.detail {
    case .fulfillment: return true
    case .edit(let edit): return edit.binding.isChild
    default: return false
    }
  }
  var unpublishedLinkedMeal: FlowConversationLinkedMealRow? {
    guard hasUnpublishedLinkedDelivery, let result = mealReplies?.lastDelivered,
      let identity = linkedMealIdentities[result.replyID]
    else { return nil }
    return .init(
      reference: identity.reference, identity: identity, feedback: mealReplies?.deliveredFeedback)
  }
  func threadFeedback(eventID: String) -> ConversationFeedbackPresentationSnapshot.Bound? {
    guard let scope = feedbackPresentationScope, historyIdentity == lastIdentity,
      let entry = threadEntries.first(where: { $0.eventID == eventID }),
      let parent = threadDescriptors[entry.threadID]
    else { return nil }
    let presentation: ConversationFeedbackPresentationSnapshot?
    let binding: ConversationFeedbackPresentationSnapshot.Binding
    switch entry.detail {
    case .report(let report):
      guard let r = report.receipt else { return nil }
      presentation = report.feedback
      binding = .init(
        scope: scope, commandID: r.commandID, registrationID: r.registrationID,
        localDate: r.localDate, mealKind: r.mealType.rawValue, logIDs: r.logIDs,
        admittedAt: parent.parentBinding.admittedAt)
    case .fulfillment(let result):
      return result.receipt.boundFeedback(result.feedback, binding: result.binding, scope: scope)
    default: return nil
    }
    return presentation?.bound(to: binding, current: scope)
  }
  func threadOriginalSavedRow(eventID: String) -> FlowConversationSavedRow? {
    guard hasCurrentScope, historyIdentity == lastIdentity,
      let entry = threadEntries.first(where: { $0.eventID == eventID }),
      case .report(let report) = entry.detail, let receipt = report.receipt,
      let parent = threadDescriptors[entry.threadID]
    else { return nil }
    return .init(
      command: parent.originalCommand, receipt: receipt, feedback: threadFeedback(eventID: eventID))
  }
  var hasMoreHistory: Bool {
    hasCurrentScope && (historyVersion == .v3 ? unifiedHistory.hasMore : historyHasMore)
  }
  var unifiedRows: [ConversationJournalV3PageSnapshot.Entry] {
    hasCurrentScope && historyVersion == .v3 ? unifiedHistory.rows : []
  }
  var isLoadingUnifiedHistory: Bool { historyVersion == .v3 && unifiedHistory.isLoading }
  var unifiedHistoryUnavailable: Bool { historyVersion == .v3 && unifiedHistory.unavailable }
  var pendingRows: [FlowConversationPendingRow] {
    hasCurrentScope ? pending.filter { !isInJournal($0.command) } : []
  }
  var savedRows: [FlowConversationSavedRow] {
    hasCurrentScope ? saved.filter { !isInJournal($0.command) && !isInUnifiedHistory($0) } : []
  }
  /// Only a controller-published RAM ACK can retain operational controls.
  /// History contributes fresh display commentary, never dispatch authority.
  func unifiedOperationalSavedRow(eventID: String) -> FlowConversationSavedRow? {
    guard let entry = unifiedRows.first(where: { $0.eventID == eventID }),
      let row = saved.first(where: { matchesUnifiedSaved($0, entry: entry) })
    else { return nil }
    return .init(
      command: row.command, receipt: row.receipt, feedback: unifiedHistory.feedback(for: entry))
  }
  private func isInUnifiedHistory(_ row: FlowConversationSavedRow) -> Bool {
    unifiedRows.contains { matchesUnifiedSaved(row, entry: $0) }
  }
  private func matchesUnifiedSaved(
    _ row: FlowConversationSavedRow, entry: ConversationJournalV3PageSnapshot.Entry
  ) -> Bool {
    guard let context, hasCurrentScope, unifiedHistory.acceptedIdentity == context.identity,
      savedIdentities[row.id] == context.identity, entry.originEpoch == context.epoch,
      row.receipt.ownerID == context.ownerID.uuidString.lowercased(),
      row.receipt.commandID == row.id.uuidString.lowercased(),
      row.receipt.inputHash == row.command.inputHash,
      entry.commandID == row.id, entry.status == .registered, case .meal(let meal) = entry.record
    else { return false }
    return meal.registrationID.uuidString.lowercased() == row.receipt.registrationID
      && meal.localDate == row.receipt.localDate && meal.mealType == row.receipt.mealType.rawValue
      && Set(meal.logIDs.map { $0.uuidString.lowercased() }) == Set(row.receipt.logIDs)
      && meal.effectVersion == row.receipt.effectVersion
  }
  var unifiedTerminalIntakeIDs: Set<UUID> {
    guard let identity = acceptedIdentity, let neutralIntake else { return [] }
    return Set(
      neutralIntake.terminalRows.filter { row in
        guard row.identity == identity else { return false }
        return unifiedRows.contains { entry in
          entry.kind == .intake && entry.intakeID == row.id && entry.status == .notRecorded
            && entry.commandID == row.response.selection?.child.commandID
            && row.response.deliveryState == .notRecorded
        }
      }.map(\.id))
  }
  var unifiedSavedIntakeIDs: Set<UUID> {
    guard let identity = acceptedIdentity, let neutralIntake else { return [] }
    return Set(
      neutralIntake.savedRows.filter { row in
        guard row.identity == identity else { return false }
        return unifiedRows.contains { entry in
          guard entry.intakeID == row.id, entry.commandID == row.childID else { return false }
          switch (entry.record, row.acknowledgement) {
          case (.meal(let meal), .meal(let saved)):
            return meal.registrationID.uuidString.lowercased() == saved.receipt.registrationID
              && meal.localDate == saved.receipt.localDate
              && meal.mealType == saved.receipt.mealType.rawValue
              && meal.effectVersion == saved.receipt.effectVersion
              && Set(meal.logIDs.map { $0.uuidString.lowercased() }) == Set(saved.receipt.logIDs)
          case (.workout(let workout), .workout(let saved)):
            return workout.registrationID == saved.registration.registrationID
              && workout.workoutID == saved.activity.logID
              && workout.localDate == saved.registration.localDate
              && workout.timeZone == saved.registration.timeZone
              && ConversationProtocolInstant(workout.performedAt)
                == ConversationProtocolInstant(saved.registration.performedAt)
              && ConversationProtocolInstant(workout.committedAt)
                == ConversationProtocolInstant(saved.registration.committedAt)
              && workout.workoutType == saved.activity.workoutType
              && workout.durationMin == saved.activity.durationMin
              && workout.intensity == saved.activity.intensity
              && workout.estimatedKcal == saved.activity.estimatedKcal
          default: return false
          }
        }
      }.map(\.id))
  }
  private func isInJournal(_ command: ConversationMealCommand) -> Bool {
    if historyVersion == .v2 {
      return historyIdentity == lastIdentity
        && threadDescriptors[command.commandID]?.originalCommand.inputHash == command.inputHash
    }
    return historyIdentity == lastIdentity
      && historyEntries.contains {
        if case .command(let row) = $0 {
          return row.originalCommand.commandID == command.commandID
            && row.originalCommand.inputHash == command.inputHash
        }
        return false
      }
  }
  func journalSavedRow(_ entry: ConversationJournalPageSnapshot.CommandEntry)
    -> FlowConversationSavedRow?
  {
    guard let context, hasCurrentScope, case .saved(let value) = entry.result else { return nil }
    let scope = ConversationFeedbackPresentationSnapshot.Scope(
      ownerID: context.ownerID.uuidString.lowercased(),
      sessionGeneration: context.sessionGeneration, epoch: context.epoch.uuidString.lowercased())
    return .init(
      command: entry.originalCommand, receipt: value.receipt,
      feedback: value.boundFeedback(scope: scope))
  }
  func hasJournalChild(_ childID: UUID) -> Bool {
    guard hasCurrentScope, historyIdentity == lastIdentity else { return false }
    if threadDescriptors[childID] != nil { return true }
    return historyEntries.contains { if case let .command(value) = $0 { return value.originalCommand.commandID == childID }; return false }
  }
  func hasLocalUnresolved(commandID: UUID) -> Bool {
    hasCurrentScope && pending.contains { $0.id == commandID }
  }
  private var hasCurrentScope: Bool {
    guard !isClosed, let context else { return false }
    return (try? context.withCurrentAuthority { true }) == true
  }
  func withCurrentAuthority<Value>(_ operation: () throws -> Value) throws -> Value {
    guard !isClosed, let context else { throw ConversationOutboxError.sessionClosed }
    return try context.withCurrentAuthority(operation)
  }

  private init(
    controller: any ConversationMealCommandControlling, lifecycle: any SessionLifecycleProviding,
    lease: SessionLease, media: FlowConversationMediaDependencies?,
    history: MobileConversationHistoryRepository, historyPageSize: Int,
    historyVersion: FlowConversationHistoryVersion
  ) {
    self.controller = controller
    self.lifecycle = lifecycle
    self.lease = lease
    self.mediaDependencies = media
    self.history = history
    self.historyPageSize = historyPageSize
    self.historyVersion = historyVersion
    self.unifiedHistory = .init(history: history, lifecycle: lifecycle)
  }
  static func open(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    store: EncryptedConversationOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(), media: FlowConversationMediaDependencies? = nil,
    editing: FlowConversationMealEditingDependencies? = nil, linkedReplies: Bool = false,
    historyPageSize: Int = 10, historyVersion: FlowConversationHistoryVersion = .v1,
    neutralIntakeEnabled: Bool = false, expectedLease: SessionLease? = nil
  ) async throws -> FlowConversationModel {
    guard (1...25).contains(historyPageSize) else { throw ConversationOutboxError.invalidCommand }
    if linkedReplies {
      guard historyVersion == .v2 || historyVersion == .v3 else { throw ConversationOutboxError.invalidCommand }
    }
    let lease = try await lifecycle.leaseForRequest()
    if let expectedLease {
      guard lease.userID == expectedLease.userID, lease.generation == expectedLease.generation
      else {
        throw SessionLifecycleError.sessionSuperseded
      }
      try await lifecycle.validate(expectedLease)
    }
    let history = try await MobileConversationHistoryRepository.scoped(
      transport: transport, lifecycle: lifecycle, lease: lease, feedbackPresentation: neutralIntakeEnabled ? .v2 : nil)
    let controller = try await ConversationMealCommandController.open(
      transport: transport, lifecycle: lifecycle, store: store, keyVault: keyVault,
      expectedLease: lease)
    let model = FlowConversationModel(
      controller: controller, lifecycle: lifecycle, lease: lease, media: media, history: history,
      historyPageSize: historyPageSize, historyVersion: historyVersion)
    do {
      try await lifecycle.validate(lease)
      try Task.checkCancellation()
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
      if let media {
        model.mediaService = try await ConversationMealMediaService.open(
          transport: transport, lifecycle: lifecycle, lease: lease, uploader: media.uploader,
          staging: media.staging)
      }
      try await controller.publishSnapshot(model.publisher(for: model.publicationID))
      guard model.hasCurrentScope else { throw ConversationMealCommandControllerError.unavailable }
      if let editing {
        let editController = try await ConversationMealEditController.open(
          transport: transport, lifecycle: lifecycle, store: editing.store,
          keyVault: editing.keyVault, expectedLease: lease)
        do {
          let editor = try await FlowConversationMealEditModel.open(
            controller: editController,
            lifecycle: lifecycle, lease: lease,
            onHistorical: { [weak model] value, context in
              model?.receiveHistoricalMealEdit(value, context: context)
            },
            onSaved: { [weak model] result, context in
              model?.receiveMealEdit(result, context: context)
            })
          model.mealEditor = editor
          if let context = model.context { editor.accept(context) }
          await editor.restore()
          try await lifecycle.validate(lease)
          try model.lifetime.check()
          try Task.checkCancellation()
          guard model.hasCurrentScope else {
            throw ConversationMealCommandControllerError.unavailable
          }
        } catch {
          await editController.close()
          throw error
        }
      }
      if linkedReplies {
        let replyController = try await ConversationMealReplyController.open(
          transport: transport, lifecycle: lifecycle, store: store, keyVault: keyVault,
          expectedLease: lease)
        do {
          let replies = try await FlowConversationMealReplyModel.open(
            controller: replyController, lifecycle: lifecycle, lease: lease
          ) { [weak model] result, context in model?.receiveMealReply(result, context: context) }
          model.mealReplies = replies
          if let context = model.context { replies.accept(context) }
          await replies.restore()
          try await lifecycle.validate(lease)
          try model.lifetime.check()
          try Task.checkCancellation()
          guard model.hasCurrentScope else {
            throw ConversationMealCommandControllerError.unavailable
          }
        } catch {
          await replyController.close()
          throw error
        }
      }
      if neutralIntakeEnabled {
        guard let current = model.context else { throw ConversationOutboxError.invalidServerObservation }
        model.neutralIntake = try await FlowNeutralIntakeModel.open(transport: transport, lifecycle: lifecycle, store: store, keyVault: keyVault, expectedLease: lease, parentIdentity: current.identity,
          parentIsCurrent: { [weak model] identity in model?.hasCurrentScope == true && model?.context?.identity == identity },
          onFactualEffect: { [weak model] in guard let model, model.hasCurrentScope else { return }; model.savedEffectRevision &+= 1 })
      }
      return model
    } catch {
      await model.close()
      throw error
    }
  }

  private func loadThreadHistory(reset: Bool) async {
    guard !isClosed, let lease, let context, hasCurrentScope, !context.observation.isEnqueueOnly
    else { return }
    guard
      reset
        || (!isLoadingHistory && historyHasMore && historyCursor != nil
          && historyIdentity == context.identity)
    else { return }
    let requestID = UUID()
    let cursor = reset ? nil : historyCursor
    historyRequestID = requestID
    isLoadingHistory = true
    historyUnavailable = false
    defer {
      if historyRequestID == requestID {
        isLoadingHistory = false
        historyRequestID = nil
      }
    }
    do {
      let read = try await history.threadJournal(
        cursor: cursor, limit: historyPageSize, context: context)
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try self.lifetime.check()
        try Task.checkCancellation()
        try context.withCurrentAuthority {
          guard self.historyRequestID == requestID, self.lastIdentity == context.identity else {
            throw ConversationOutboxError.staleObservation
          }
          if let previous = self.threadObservedAt {
            guard let a = ConversationProtocolInstant(previous),
              let b = ConversationProtocolInstant(read.page.observedAt), b >= a
            else { throw MobileAPITransportError.invalidResponse }
          }
          if !reset {
            guard self.historyCursor == cursor,
              Set(self.threadEntries.map(\.eventID)).isDisjoint(
                with: Set(read.page.items.map(\.eventID)))
            else { throw MobileAPITransportError.invalidResponse }
            if let previous = self.threadEntries.last, let next = read.page.items.first {
              guard let a = ConversationProtocolInstant(previous.at),
                let b = ConversationProtocolInstant(next.at),
                a > b
                  || (a == b && next.eventID.utf8.lexicographicallyPrecedes(previous.eventID.utf8))
              else { throw MobileAPITransportError.invalidResponse }
            }
          }
          var descriptors = reset ? [:] : self.threadDescriptors
          var eventPins = self.knownThreadEvents
          for event in read.page.items {
            if let known = eventPins[event.eventID], known.digest != event.readConsistencyDigest {
              // A pending original may become terminal exactly once. All
              // other factual event bodies remain immutable on refresh/reset.
              guard known.reportStatus == .pending,
                let status = event.reportStatus, status != .pending
              else { throw MobileAPITransportError.invalidResponse }
            }
            eventPins[event.eventID] = .init(
              digest: event.readConsistencyDigest, reportStatus: event.reportStatus)
          }
          for incoming in read.page.threads {
            guard self.linkedReadReferences[incoming.threadID] == nil else {
              throw MobileAPITransportError.invalidResponse
            }
            if let known = self.commands[incoming.threadID],
              known.inputHash != incoming.originalCommand.inputHash
            {
              throw MobileAPITransportError.invalidResponse
            }
            if let known = self.threadDescriptors[incoming.threadID] {
              guard known.parentBinding == incoming.parentBinding else {
                throw MobileAPITransportError.invalidResponse
              }
              if let proof = known.terminalReceipt {
                guard let next = incoming.terminalReceipt, proof.decisionHash == next.decisionHash,
                  proof.reason == next.reason, proof.foodIndexes == next.foodIndexes,
                  proof.sealedAt == next.sealedAt
                else { throw MobileAPITransportError.invalidResponse }
              }
              if let head = known.continuation {
                guard let next = incoming.continuation, next.revision >= head.revision,
                  head.fulfilledBy == nil || head.fulfilledBy == next.fulfilledBy
                else { throw MobileAPITransportError.invalidResponse }
                if next.revision == head.revision {
                  guard head.question?.questionKey == next.question?.questionKey,
                    head.fulfilledBy == next.fulfilledBy
                  else { throw MobileAPITransportError.invalidResponse }
                  if let question = head.question, let nextQuestion = next.question,
                    !question.hasSameContent(as: nextQuestion)
                  {
                    throw MobileAPITransportError.invalidResponse
                  }
                }
              }
            }
            descriptors[incoming.threadID] = incoming
          }
          let combined = reset ? read.page.items : self.threadEntries + read.page.items
          var children: [UUID: (UUID, ConversationThreadPageSnapshot.Binding)] = [:]
          var references = self.linkedReadReferences
          var linkedIdentities = self.linkedMealIdentities
          var hashes = self.knownGroupInputHashes
          var effects = self.knownGroupEdits
          for event in combined {
            if let child = event.childBinding {
              guard descriptors[child.commandID] == nil, self.commands[child.commandID] == nil,
                let parent = descriptors[event.threadID], let decision = parent.terminalReceipt
              else {
                throw MobileAPITransportError.invalidResponse
              }
              if let previous = children[child.commandID],
                previous.0 != event.threadID || previous.1 != child
              {
                throw MobileAPITransportError.invalidResponse
              }
              children[child.commandID] = (event.threadID, child)
              let reference = try ConversationMealLinkedReadReference(
                parentBinding: parent.parentBinding, childBinding: child,
                parentDecisionHash: decision.decisionHash)
              guard references[child.commandID].map({ $0 == reference }) ?? true,
                hashes[child.commandID].map({ $0 == child.inputHash }) ?? true
              else { throw MobileAPITransportError.invalidResponse }
              references[child.commandID] = reference
              if case .fulfillment(let value) = event.detail {
                let identity = try ConversationMealLinkedIdentity(
                  parentBinding: parent.parentBinding, childBinding: child,
                  parentDecisionHash: decision.decisionHash, receipt: value.receipt)
                guard linkedIdentities[child.commandID].map({ $0 == identity }) ?? true else {
                  throw MobileAPITransportError.invalidResponse
                }
                linkedIdentities[child.commandID] = identity
              }
            }
            if case .edit(let edit) = event.detail {
              let id = edit.binding.commandID
              guard hashes[id].map({ $0 == edit.binding.inputHash }) ?? true else {
                throw MobileAPITransportError.invalidResponse
              }
              hashes[id] = edit.binding.inputHash
              if let known = effects[id], known.revision == edit.receipt.revision,
                !Self.sameKnownEdit(known, edit.receipt)
              {
                throw MobileAPITransportError.invalidResponse
              }
              if effects[id].map({ edit.receipt.revision > $0.revision }) ?? true {
                effects[id] = edit.receipt
              }
            }
          }
          self.linkedReadReferences = references
          self.linkedMealIdentities = linkedIdentities
          self.knownGroupInputHashes = hashes
          self.threadEntries = combined
          self.knownThreadEvents = eventPins
          self.threadDescriptors = descriptors
          self.threadObservedAt = read.page.observedAt
          self.historyIdentity = context.identity
          self.historyCursor = read.page.nextCursor
          self.historyHasMore = read.page.hasMore
          for descriptor in read.page.threads {
            self.commands[descriptor.threadID] = descriptor.originalCommand
            self.mealReplies?.observeThread(descriptor)
          }
          if let blocked = self.blockedDecisionID,
            self.threadDescriptors[blocked]?.continuation?.fulfilledBy != nil
          {
            self.blockedDecisionID = nil
            self.latestDecision = nil
          }
          for event in read.page.items {
            guard self.blockedDecisionID == nil,
              let descriptor = self.threadDescriptors[event.threadID],
              descriptor.terminalReceipt != nil, descriptor.continuation?.fulfilledBy == nil,
              descriptor.continuation?.question != nil
                || self.pending.contains(where: { $0.id == descriptor.threadID }),
              !self.dismissedQuestions.contains(descriptor.threadID)
            else { continue }
            // Keep the original immutable. Typed answers require the separate
            // actual question/controller; they never become fresh reports.
            self.blockedDecisionID = descriptor.threadID
            self.latestDecision = nil
          }
          for event in read.page.items {
            // Parent and child edits share one monotonic current-group fence.
            // A history observation never acknowledges protected ciphertext.
            guard case .edit(let edit) = event.detail else { continue }
            let commandID = edit.binding.commandID
            if self.knownGroupEdits[commandID].map({ edit.receipt.revision >= $0.revision }) ?? true
            {
              self.threadEditReads[commandID] = read
            }
            let newlyKnown =
              self.knownGroupEdits[commandID].map { edit.receipt.revision > $0.revision } ?? true
            if newlyKnown { self.knownGroupEdits[commandID] = edit.receipt }
            if newlyKnown
              || self.currentGroups[commandID].map({ !self.satisfiesKnownEdits($0) }) == true
            {
              self.currentGroups.removeValue(forKey: commandID)
              self.groupRequests.removeValue(forKey: commandID)
            }
          }
        }
      }
      if hasCurrentScope, self.context?.observation.isSameGrant(as: context.observation) == true,
        let commandID = mealEditor?.historicalRecoveryCommandID,
        linkedReadReferences[commandID] != nil, threadEditReads[commandID] != nil
      {
        // Recover only the presentation of an already absent local intent.
        // The owned fresh group read cannot ACK ciphertext or grant replay.
        await loadCurrentGroup(commandID: commandID)
      }
    } catch {
      try? await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try self.lifetime.check()
        try context.withCurrentAuthority {
          guard self.historyRequestID == requestID, self.lastIdentity == context.identity else {
            return
          }
          self.historyUnavailable = true
        }
      }
    }
  }

  func loadHistory(reset: Bool = true) async {
    if historyVersion == .v3 {
      guard !isClosed, let lease, let context, hasCurrentScope else { return }
      await unifiedHistory.load(context: context, lease: lease, limit: historyPageSize, reset: reset) { [weak self] identity in
        self?.hasCurrentScope == true && self?.context?.identity == identity
      }
      return
    }
    if historyVersion == .v2 {
      await loadThreadHistory(reset: reset)
      return
    }
    guard !isClosed, let lease, let context, hasCurrentScope, !context.observation.isEnqueueOnly
    else { return }
    guard
      reset
        || (!isLoadingHistory && historyHasMore && historyCursor != nil
          && historyIdentity == context.identity)
    else { return }
    let requestID = UUID()
    let cursor = reset ? nil : historyCursor
    historyRequestID = requestID
    isLoadingHistory = true
    historyUnavailable = false
    defer {
      if historyRequestID == requestID {
        isLoadingHistory = false
        historyRequestID = nil
      }
    }
    do {
      let read = try await history.journal(cursor: cursor, limit: historyPageSize, context: context)
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try self.lifetime.check()
        try Task.checkCancellation()
        try context.withCurrentAuthority {
          guard self.historyRequestID == requestID, self.lastIdentity == context.identity else {
            throw ConversationOutboxError.staleObservation
          }
          if !reset {
            guard self.historyCursor == cursor,
              Set(self.historyEntries.map(\.eventID)).isDisjoint(
                with: Set(read.page.items.map(\.eventID)))
            else { throw MobileAPITransportError.invalidResponse }
            if let previous = self.historyEntries.last, let next = read.page.items.first {
              guard let a = ConversationProtocolInstant(previous.at),
                let b = ConversationProtocolInstant(next.at),
                a > b
                  || (a == b && next.eventID.utf8.lexicographicallyPrecedes(previous.eventID.utf8))
              else { throw MobileAPITransportError.invalidResponse }
            }
          }
          for item in read.page.items {
            if case .command(let row) = item {
              let command = row.originalCommand
              if let known = self.commands[command.commandID], known.inputHash != command.inputHash
              {
                throw MobileAPITransportError.invalidResponse
              }
              if case .saved(let result) = row.result,
                let known = self.saved.first(where: { $0.id == command.commandID }),
                known.receipt != result.receipt
              {
                throw MobileAPITransportError.invalidResponse
              }
            } else if case .edit(let row) = item {
              if let known = self.commands[row.result.commandID],
                known.inputHash != row.result.originalInputHash
              {
                throw MobileAPITransportError.invalidResponse
              }
              if let known = self.knownGroupEdits[row.result.commandID],
                known.revision == row.result.receipt.revision,
                !Self.sameKnownEdit(known, row.result.receipt)
              {
                throw MobileAPITransportError.invalidResponse
              }
            }
          }
          self.historyEntries = reset ? read.page.items : self.historyEntries + read.page.items
          self.historyIdentity = context.identity
          self.historyCursor = read.page.nextCursor
          self.historyHasMore = read.page.hasMore
          for item in read.page.items {
            if case .command(let row) = item {
              self.commands[row.originalCommand.commandID] = row.originalCommand
              if case .state(let state) = row.result, state.status == .notRecorded,
                self.blockedDecisionID == nil, !self.dismissedQuestions.contains(state.commandID),
                self.pending.contains(where: { $0.id == state.commandID })
              {
                self.blockedDecisionID = state.commandID
                self.latestDecision = state
              }
            } else if case .edit(let row) = item {
              let commandID = row.result.commandID
              let effect = row.result.receipt
              let newlyKnown =
                self.knownGroupEdits[commandID].map {
                  effect.revision > $0.revision
                } ?? true
              if newlyKnown { self.knownGroupEdits[commandID] = effect }
              if let current = self.currentGroups[commandID] {
                if !self.satisfiesKnownEdits(current) {
                  self.currentGroups.removeValue(forKey: commandID)
                  self.groupRequests.removeValue(forKey: commandID)
                }
              } else if newlyKnown {
                // Invalidate even an empty-cache GET already in flight. A
                // fresh GET still must pass the publication check below.
                self.groupRequests.removeValue(forKey: commandID)
              }
            }
          }
          self.mealEditor?.observeJournal(read)
        }
      }
      // Page reading itself has no delivery side effect. Each exact local
      // terminal intent explicitly crosses the controller's current-grant
      // delivery capability, separate from factual saved-meal ACK.
      for item in read.page.items {
        guard historyRequestID == requestID, lastIdentity == context.identity else { return }
        if case .command(let row) = item, row.terminalReceipt != nil,
          pending.contains(where: {
            $0.id == row.originalCommand.commandID
              && $0.command.inputHash == row.originalCommand.inputHash
          })
        {
          do {
            try await controller.closeTerminalDelivery(
              read: read, commandID: row.originalCommand.commandID,
              publish: publisher(for: publicationID))
          } catch {
            // Preserve ciphertext and the deduplicated remote decision;
            // a later owned read may retry delivery.
          }
        }
      }
    } catch {
      try? await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try self.lifetime.check()
        try context.withCurrentAuthority {
          guard self.historyRequestID == requestID, self.lastIdentity == context.identity else {
            return
          }
          self.historyUnavailable = true
        }
      }
    }
  }

  var feedbackPresentationScope: ConversationFeedbackPresentationSnapshot.Scope? {
    guard let context, hasCurrentScope else { return nil }
    return .init(
      ownerID: context.ownerID.uuidString.lowercased(),
      sessionGeneration: context.sessionGeneration, epoch: context.epoch.uuidString.lowercased())
  }
  func knownEditRevision(commandID: UUID) -> Int {
    guard hasCurrentScope else { return 0 }
    return knownGroupEdits[commandID]?.revision ?? 0
  }
  private static func sameKnownEdit(
    _ lhs: ConversationMealEditEffectSnapshot, _ rhs: ConversationMealEditEffectSnapshot
  ) -> Bool {
    lhs.hasSameFacts(as: rhs)
  }
  private func satisfiesKnownEdits(_ group: ConversationMealGroupSnapshot) -> Bool {
    guard knownGroupInputHashes[group.commandID].map({ $0 == group.originalInputHash }) ?? true
    else {
      return false
    }
    guard let known = knownGroupEdits[group.commandID] else { return true }
    guard group.revision >= known.revision,
      let observed = ConversationProtocolInstant(group.observedAt),
      let applied = ConversationProtocolInstant(known.appliedAt), observed >= applied
    else { return false }
    return group.revision > known.revision
      || group.lastOperation.map { Self.sameKnownEdit($0, known) } == true
  }
  func currentGroup(commandID: UUID) -> ConversationMealGroupSnapshot? {
    hasCurrentScope ? currentGroups[commandID] : nil
  }
  func groupUnavailable(commandID: UUID) -> Bool {
    hasCurrentScope && groupFailures.contains(commandID)
  }
  func beginMealEdit(commandID: UUID, itemID: UUID) async {
    guard let editor = mealEditor, editor.canBeginEditing, let originalContext = context,
      hasCurrentScope
    else { return }
    await loadCurrentGroup(commandID: commandID)
    guard hasCurrentScope,
      context?.observation.isSameGrant(as: originalContext.observation) == true,
      let group = currentGroups[commandID]
    else { return }
    do {
      if let linked = linkedMealIdentities[commandID] {
        try editor.beginEditing(linked: linked, group: group, itemID: itemID)
      } else {
        try editor.beginEditing(group: group, itemID: itemID)
      }
    } catch { failure = .changed }
  }
  func mealEditActions(commandID: UUID) -> FlowConversationMealEditActions? {
    guard hasCurrentScope, let group = currentGroups[commandID], group.current != nil,
      commands[commandID] != nil || linkedMealIdentities[commandID]?.matches(group: group) == true,
      let editor = mealEditor
    else { return nil }
    let linked = linkedMealIdentities[commandID]
    return .init(
      editItem: { [weak self] item in
        Task { await self?.beginMealEdit(commandID: commandID, itemID: item.id) }
      },
      undoSave: { group in
        Task {
          if let linked {
            await editor.undoSave(linked: linked, group: group)
          } else {
            await editor.undoSave(group: group)
          }
        }
      },
      undoRegistration: { group in
        Task {
          if let linked {
            await editor.undoRegistration(linked: linked, group: group)
          } else {
            await editor.undoRegistration(group: group)
          }
        }
      }, isWorking: !editor.canBeginEditing)
  }
  private func receiveMealReply(
    _ result: ConversationMealReplyResultSnapshot, context: ConversationCommandContext
  ) {
    guard hasCurrentScope, self.context?.observation.isSameGrant(as: context.observation) == true,
      result.authUserID == context.authUserID, result.parentBinding.ownerID == context.ownerID,
      result.parentBinding.epoch == context.epoch
    else { return }
    if let receipt = result.receipt, let child = result.childBinding {
      guard
        let identity = try? ConversationMealLinkedIdentity(
          parentBinding: result.parentBinding, childBinding: child,
          parentDecisionHash: result.parentDecisionHash, receipt: receipt),
        commands[identity.commandID] == nil,
        linkedReadReferences[identity.commandID].map({ $0 == identity.reference }) ?? true,
        linkedMealIdentities[identity.commandID].map({ $0 == identity }) ?? true,
        knownGroupInputHashes[identity.commandID].map({ $0 == identity.inputHash }) ?? true
      else { return }
      linkedReadReferences[identity.commandID] = identity.reference
      linkedMealIdentities[identity.commandID] = identity
      dismissedQuestions.insert(result.parentBinding.commandID)
      if blockedDecisionID == result.parentBinding.commandID {
        blockedDecisionID = nil
        latestDecision = nil
      }
      if deliveredLinkedEffects.insert(result.replyID).inserted { savedEffectRevision &+= 1 }
    } else if result.question != nil {
      blockedDecisionID = result.parentBinding.commandID
      dismissedQuestions.remove(result.parentBinding.commandID)
    }
    // This is an actual reply delivery, not a fabricated v1 saved row/group.
    // Official readers refresh independently; a read outage cannot undo ACK.
    Task { [weak self] in await self?.loadHistory() }
  }
  private func receiveMealEdit(
    _ result: ConversationMealEditResultSnapshot, context value: ConversationCommandContext
  ) {
    guard hasCurrentScope, context?.observation.isSameGrant(as: value.observation) == true,
      result.ownerID == value.ownerID, result.epoch == value.epoch
    else { return }
    // A cold-restored operation already has a fully bound controller ACK;
    // its original journal page may still be unavailable. Missing history
    // cannot suppress factual refresh, while a known contradiction must.
    if let command = commands[result.commandID], command.inputHash != result.originalInputHash {
      return
    }
    guard
      linkedReadReferences[result.commandID].map({ $0.inputHash == result.originalInputHash })
        ?? true,
      knownGroupInputHashes[result.commandID].map({ $0 == result.originalInputHash }) ?? true
    else { return }
    knownGroupInputHashes[result.commandID] = result.originalInputHash
    let effect = result.receipt
    if let known = knownGroupEdits[result.commandID], known.revision == effect.revision,
      !Self.sameKnownEdit(known, effect)
    {
      return
    }
    if knownGroupEdits[result.commandID].map({ effect.revision > $0.revision }) ?? true {
      knownGroupEdits[result.commandID] = effect
    }
    // Factual ACK survives all subsequent refresh failures. Invalidate both
    // cached and in-flight reads before publishing the official-panel signal.
    currentGroups.removeValue(forKey: result.commandID)
    groupRequests.removeValue(forKey: result.commandID)
    groupFailures.remove(result.commandID)
    if acknowledgedEdits.insert(.init(commandID: result.commandID, operationID: effect.operationID))
      .inserted
    {
      savedEffectRevision &+= 1
    }
  }
  private func receiveHistoricalMealEdit(
    _ notice: ConversationMealEditHistoricalNotice, context value: ConversationCommandContext
  ) {
    guard hasCurrentScope, context?.observation.isSameGrant(as: value.observation) == true,
      notice.identity.ownerID == value.ownerID, notice.identity.epoch == value.epoch,
      linkedMealIdentities[notice.identity.commandID] == notice.identity,
      knownGroupInputHashes[notice.identity.commandID].map({ $0 == notice.identity.inputHash })
        ?? true
    else { return }
    let effect = notice.receipt
    if let known = knownGroupEdits[notice.identity.commandID],
      known.revision == effect.revision, !known.hasSameFacts(as: effect)
    {
      return
    }
    if knownGroupEdits[notice.identity.commandID].map({ effect.revision > $0.revision }) ?? true {
      knownGroupEdits[notice.identity.commandID] = effect
    }
    if acknowledgedEdits.insert(
      .init(commandID: notice.identity.commandID, operationID: effect.operationID)
    ).inserted {
      savedEffectRevision &+= 1
    }
  }
  func loadCurrentGroup(commandID: UUID) async {
    guard !isClosed, let lease, let context, hasCurrentScope else { return }
    let command = commands[commandID]
    let reference = linkedReadReferences[commandID]
    let identity = linkedMealIdentities[commandID]
    guard command != nil || reference != nil else { return }
    let requestID = UUID()
    groupRequests[commandID] = requestID
    groupFailures.remove(commandID)
    do {
      let group: ConversationMealGroupSnapshot
      let complete: ConversationMealLinkedIdentity?
      if let reference {
        let read = try await history.linkedGroup(reference: reference, context: context)
        guard identity.map({ $0 == read.identity }) ?? true else {
          throw MobileAPITransportError.invalidResponse
        }
        group = read.group
        complete = read.identity
      } else if let command {
        group = try await history.group(
          commandID: commandID, originalInputHash: command.inputHash, context: context)
        complete = nil
      } else {
        return
      }
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try self.lifetime.check()
        try Task.checkCancellation()
        try context.withCurrentAuthority {
          guard self.groupRequests[commandID] == requestID, self.lastIdentity == context.identity
          else { throw ConversationOutboxError.staleObservation }
          guard self.satisfiesKnownEdits(group),
            reference.map({ self.linkedReadReferences[commandID] == $0 }) ?? true
          else { throw MobileAPITransportError.invalidResponse }
          if let complete {
            guard self.linkedMealIdentities[commandID].map({ $0 == complete }) ?? true else {
              throw MobileAPITransportError.invalidResponse
            }
            self.linkedMealIdentities[commandID] = complete
          }
          self.currentGroups[commandID] = group
          if let complete, let read = self.threadEditReads[commandID] {
            self.mealEditor?.observeThreadJournal(read, linked: complete, group: group)
          }
        }
      }
    } catch {
      try? await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try self.lifetime.check()
        try context.withCurrentAuthority {
          guard self.groupRequests[commandID] == requestID, self.lastIdentity == context.identity
          else { return }
          self.currentGroups.removeValue(forKey: commandID)
          self.groupFailures.insert(commandID)
        }
      }
    }
  }

  func refresh() async {
    guard !isClosed, !Task.isCancelled else { return }
    let id = UUID()
    publicationID = id
    refreshingID = id
    isRefreshing = true
    defer {
      if refreshingID == id {
        refreshingID = nil
        isRefreshing = false
      }
    }
    do { try await controller.refreshSession(publisher(for: id)) } catch is CancellationError {
      return
    } catch { await showFailure(error, publicationID: id) }
  }
  func refreshConversation() async {
    neutralIntake?.suspendVisibility()
    await refresh()
    if hasCurrentScope {
      if let identity = context?.identity { neutralIntake?.acceptParent(identity) }
      await neutralIntake?.refresh()
      await mealEditor?.restore()
      await mealReplies?.restore()
      await loadHistory()
    }
  }
  func submit() async {
    guard canSubmit, let identity = lastIdentity else { return }
    if let selected = selectedAttachment {
      let caption = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft
      let revision = draftRevision
      let mealType = mealType
      preparingMediaIntent = true
      defer { preparingMediaIntent = false }
      await run { requestID in
        guard let media = self.mediaService else { throw MealCaptureFailure.unavailable }
        let context = try await self.freshMediaContext(
          expected: selected.identity, publicationID: requestID)
        self.mediaPhase = .uploading
        defer { self.mediaPhase = nil }
        let prepared: PreparedDraft
        if let old = self.preparedDraft, old.command.commandID == selected.commandID,
          old.context == selected.identity
        {
          prepared = old
        } else {
          let assetID = try await media.upload(
            selected.staged, captureID: selected.id, context: context)
          try await self.visible(publicationID: requestID) { try context.withCurrentAuthority {} }
          prepared = PreparedDraft(
            command: try ConversationMealCommand(
              commandID: selected.commandID, source: .media(assetID: assetID, caption: caption),
              mealType: mealType), context: selected.identity, revision: revision)
          self.preparedDraft = prepared
        }
        try await media.retainForEnqueue(
          captureID: selected.id, command: prepared.command, expectedContext: selected.identity)
        let id = try await self.persist(prepared, publicationID: requestID)
        self.preparingMediaIntent = false
        self.mediaPhase = .processing
        try await media.process(
          command: prepared.command, expectedContext: prepared.context, context: context)
        try await self.controller.send(commandID: id, publish: self.publisher(for: requestID))
      }
      return
    }
    do {
      let prepared: PreparedDraft
      if let previous = preparedDraft, previous.revision == draftRevision,
        previous.context == identity
      {
        prepared = previous
      } else {
        prepared = PreparedDraft(
          command: try ConversationMealCommand(source: .text(draft), mealType: mealType),
          context: identity, revision: draftRevision)
        preparedDraft = prepared
      }
      await run { requestID in
        let id = try await self.persist(prepared, publicationID: requestID)
        try await self.controller.send(commandID: id, publish: self.publisher(for: requestID))
      }
    } catch { await showFailure(error, publicationID: publicationID) }
  }
  func sendQueued(commandID: UUID) async {
    guard
      pendingRows.contains(where: { $0.id == commandID && $0.state == .queued && $0.hold == nil })
    else { return }
    guard let row = pendingRows.first(where: { $0.id == commandID }), let identity = lastIdentity
    else { return }
    await run { id in
      if case .media = row.command.source {
        guard let media = self.mediaService else { throw MealCaptureFailure.unavailable }
        let context = try await self.freshMediaContext(expected: identity, publicationID: id)
        self.mediaPhase = .processing
        defer { self.mediaPhase = nil }
        try await media.process(command: row.command, expectedContext: identity, context: context)
      }
      try await self.controller.send(commandID: commandID, publish: self.publisher(for: id))
    }
  }
  private func freshMediaContext(expected: ConversationCommandContext.Identity, publicationID: UUID)
    async throws -> ConversationCommandContext
  {
    try await controller.refreshSession(publisher(for: publicationID))
    guard self.publicationID == publicationID, let context, context.identity == expected,
      !context.observation.isEnqueueOnly
    else { throw ConversationOutboxError.invalidServerObservation }
    try context.withCurrentAuthority {}
    return context
  }
  private func persist(_ prepared: PreparedDraft, publicationID: UUID) async throws -> UUID {
    let id = try await controller.enqueue(
      command: prepared.command, expectedContext: prepared.context,
      publish: publisher(for: publicationID))
    guard id == prepared.command.commandID else { throw ConversationOutboxError.invalidTransition }
    try await visible(publicationID: publicationID) {
      if let known = self.pending.first(where: { $0.id == id }),
        known.state != .queued || known.hold != nil
      {
        throw ConversationOutboxError.reconciliationRequired
      }
      guard self.lastIdentity == prepared.context else {
        throw ConversationOutboxError.invalidServerObservation
      }
      self.commands[id] = prepared.command
      if self.draftRevision == prepared.revision {
        self.draft = ""
        self.draftRevision &+= 1
      }
      if self.selectedAttachment?.commandID == id { self.selectedAttachment = nil }
      self.preparedDraft = nil
    }
    return id
  }
  func reconcile(commandID: UUID) async {
    await run { id in
      try await self.controller.reconcile(commandID: commandID, publish: self.publisher(for: id))
    }
  }
  func canResubmit(commandID: UUID) -> Bool { hasCurrentScope && replayAllowed.contains(commandID) }
  func resubmit(commandID: UUID) async {
    guard !isWorking, !Task.isCancelled, canResubmit(commandID: commandID) else { return }
    replayAllowed.remove(commandID)
    await run { id in
      try await self.controller.resubmit(commandID: commandID, publish: self.publisher(for: id))
    }
  }
  /// Discard is explicit and uses the actual queued-only disk guard. Missing
  /// local work after that gated read means this prepared source never left
  /// RAM; unresolved/dispatched work is refused and retained without renewal.
  func discardPreparedIntent(commandID expectedID: UUID) async {
    guard !isWorking, hasCurrentScope, let prepared = preparedDraft,
      prepared.command.commandID == expectedID
    else { return }
    await run { requestID in
      do {
        try await self.controller.discardUnsent(
          commandID: prepared.command.commandID, publish: self.publisher(for: requestID))
      } catch ConversationOutboxError.commandNotFound {
        // The serialized local operation proved there is no encrypted intent.
      }
      try await self.visible(publicationID: requestID) {
        guard self.lastIdentity == prepared.context else {
          throw ConversationOutboxError.invalidServerObservation
        }
        self.releasePreparedIntent(commandID: prepared.command.commandID)
      }
    }
  }
  private func releasePreparedIntent(commandID: UUID) {
    guard let prepared = preparedDraft, prepared.command.commandID == commandID else { return }
    if draftRevision == prepared.revision {
      draft = ""
      draftRevision &+= 1
      selectedMealType = nil
    }
    preparedDraft = nil
    if selectedAttachment?.commandID == commandID {
      if let selectedAttachment {
        mediaDependencies?.staging.remove(selectedAttachment.staged.fileURL)
      }
      selectedAttachment = nil
    }
  }
  func discardUnsent(commandID: UUID) async {
    await run { id in
      try await self.controller.discardUnsent(
        commandID: commandID, publish: self.publisher(for: id))
    }
  }
  func holdForLocalReset(commandID: UUID) async {
    await run { id in
      try await self.controller.holdForLocalReset(
        commandID: commandID, publish: self.publisher(for: id))
    }
  }
  func cancelTransientWork() { operation?.cancel(); neutralIntake?.cancelTransientWork(); unifiedHistory.cancel() }
  func invalidateSynchronously() {
    lifetime.close()
    closed = true
    lease = nil
    operation?.cancel()
    mealEditor?.invalidateSynchronously()
    mealReplies?.invalidateSynchronously()
    neutralIntake?.invalidateSynchronously()
    unifiedHistory.close()
  }
  func close() async {
    invalidateSynchronously()
    publicationID = UUID()
    refreshingID = nil
    operation?.cancel()
    operation = nil
    operationID = nil
    lease = nil
    context = nil
    lastIdentity = nil
    draft = ""
    selectedMealType = nil
    preparingMediaIntent = false
    preparedDraft = nil
    if let selected = selectedAttachment {
      mediaDependencies?.staging.remove(selected.staged.fileURL)
    }
    selectedAttachment = nil
    mediaPhase = nil
    resetHistory()
    knownThreadEvents.removeAll()
    dismissedQuestions.removeAll()
    knownGroupEdits.removeAll()
    knownGroupInputHashes.removeAll()
    linkedReadReferences.removeAll()
    linkedMealIdentities.removeAll()
    acknowledgedEdits.removeAll()
    currentGroups.removeAll()
    groupRequests.removeAll()
    groupFailures.removeAll()
    pending.removeAll()
    saved.removeAll()
    savedIdentities.removeAll()
    commands.removeAll()
    replayAllowed.removeAll()
    heldRows.removeAll()
    queuedMetadata.removeAll()
    blockedDecisionID = nil
    latestDecision = nil
    failure = nil
    isWorking = false
    isRefreshing = false
    await mediaService?.close()
    mediaService = nil
    await mealEditor?.close()
    mealEditor = nil
    await mealReplies?.close()
    mealReplies = nil
    deliveredLinkedEffects.removeAll()
    await neutralIntake?.close()
    neutralIntake = nil
    await controller.close()
    if let id = workID {
      workID = nil
      await lifecycle.finishPatientWork(id)
    }
  }

  private func publisher(for id: UUID) -> ConversationMealCommandController.Publisher {
    { [weak self] event in
      guard let self, self.publicationID == id else { return }
      self.receive(event)
    }
  }
  private func receive(_ event: ConversationMealCommandEvent) {
    guard !isClosed else { return }
    switch event {
    case .scopeSuspended:
      mealEditor?.suspend()
      mealReplies?.suspend()
      resetHistory()
      currentGroups.removeAll()
      groupRequests.removeAll()
      groupFailures.removeAll()
      context = nil
      replayAllowed.removeAll()
      pending.removeAll()
      // Food effects remain factual; old clinical guidance is unavailable
      // until a fresh history presentation is supplied by the backend.
      saved = saved.map { .init(command: $0.command, receipt: $0.receipt, feedback: nil) }
    case .scopeAccepted(let value):
      guard let lease, value.authUserID == UUID(uuidString: lease.userID),
        value.sessionGeneration == lease.generation,
        (try? value.withCurrentAuthority { true }) == true
      else { return }
      neutralIntake?.acceptParent(value.identity)
      if let old = lastIdentity, old != value.identity {
        draft = ""
        selectedMealType = nil
        preparingMediaIntent = false
        draftRevision &+= 1
        preparedDraft = nil
        if let selected = selectedAttachment {
          mediaDependencies?.staging.remove(selected.staged.fileURL)
        }
        selectedAttachment = nil
        resetHistory()
        knownThreadEvents.removeAll()
        dismissedQuestions.removeAll()
        knownGroupEdits.removeAll()
        knownGroupInputHashes.removeAll()
        linkedReadReferences.removeAll()
        linkedMealIdentities.removeAll()
        acknowledgedEdits.removeAll()
        deliveredLinkedEffects.removeAll()
        currentGroups.removeAll()
        groupRequests.removeAll()
        groupFailures.removeAll()
        pending.removeAll()
        saved.removeAll()
        savedIdentities.removeAll()
        commands.removeAll()
        heldRows.removeAll()
        queuedMetadata.removeAll()
        blockedDecisionID = nil
        latestDecision = nil
      }
      if let previous = context, !previous.observation.isSameGrant(as: value.observation) {
        resetHistory()
        currentGroups.removeAll()
        groupRequests.removeAll()
        groupFailures.removeAll()
        saved = saved.map { .init(command: $0.command, receipt: $0.receipt, feedback: nil) }
      }
      context = value
      lastIdentity = value.identity
      mealEditor?.accept(value)
      mealReplies?.accept(value)
      failure = nil
    case .snapshot(let value):
      guard let context, hasCurrentScope else { return }
      do {
        pending = try value.entries.map { row in
          guard row.originalPatientOwnerID == context.ownerID,
            row.originalServerEpoch == context.epoch
          else { throw ConversationOutboxError.invalidServerObservation }
          let command = try ConversationMealCommand(wireBody: row.wireBody)
          guard command.commandID == row.commandID, command.inputHash == row.inputHash else {
            throw ConversationOutboxError.integrityFailure
          }
          commands[command.commandID] = command
          return .init(command: command, state: row.state, hold: row.hold)
        }
        heldRows = value.held
        queuedMetadata.removeAll()
        if blockedDecisionID == nil {
          blockedDecisionID =
            pending.first(where: { $0.hold == .notRecorded && !dismissedQuestions.contains($0.id) }
            )?.id
        }
      } catch {
        pending.removeAll()
        failure = .unavailable
      }
    case .queued(let id): if !queuedMetadata.contains(id) { queuedMetadata.append(id) }
    case .saved(let value):
      guard let context, hasCurrentScope,
        value.receipt.ownerID == context.ownerID.uuidString.lowercased(),
        let id = UUID(uuidString: value.receipt.commandID), let command = commands[id],
        command.inputHash == value.receipt.inputHash
      else { return }
      releasePreparedIntent(commandID: id)
      pending.removeAll { $0.id == id }
      queuedMetadata.removeAll { $0 == id }
      replayAllowed.remove(id)
      if !saved.contains(where: { $0.id == id }) {
        saved.append(.init(command: command, receipt: value.receipt, feedback: value.feedback))
        savedIdentities[id] = context.identity
        savedEffectRevision &+= 1
      }
    case .state(let value, let canResubmit):
      guard let context, hasCurrentScope, value.ownerID == context.ownerID,
        value.epoch == context.epoch
      else { return }
      if value.status == .notRecorded, preparedDraft?.command.inputHash == value.inputHash {
        releasePreparedIntent(commandID: value.commandID)
      }
      if value.status == .notRecorded, !dismissedQuestions.contains(value.commandID) {
        blockedDecisionID = value.commandID
        latestDecision = value
      }
      markWaiting(
        value.commandID, hold: value.status == .notRecorded ? .notRecorded : .unknownOutcome)
      if canResubmit {
        replayAllowed.insert(value.commandID)
      } else {
        replayAllowed.remove(value.commandID)
      }
    case .deferred(let id, let reason):
      markWaiting(id, hold: reason == .changed ? .serverChanged : .unknownOutcome)
      switch reason {
      case .offline: failure = .offline
      case .rateLimited: failure = .rateLimited
      case .changed: failure = .changed
      case .storage: failure = .storage
      case .unavailable: failure = .unavailable
      }
    }
  }
  private func resetHistory() {
    unifiedHistory.suspend()
    historyEntries.removeAll()
    threadEntries.removeAll()
    threadDescriptors.removeAll()
    threadObservedAt = nil
    threadEditReads.removeAll()
    historyIdentity = nil
    historyCursor = nil
    historyHasMore = false
    historyRequestID = nil
    isLoadingHistory = false
    historyUnavailable = false
  }
  private func markWaiting(_ id: UUID, hold: ConversationOutboxHold) {
    pending = pending.map {
      guard $0.id == id else { return $0 }
      let retained = $0.hold.map { $0.priority >= hold.priority ? $0 : hold } ?? hold
      return .init(command: $0.command, state: .waitingReconciliation, hold: retained)
    }
  }
  private func run(_ action: @escaping @MainActor @Sendable (UUID) async throws -> Void) async {
    guard !isClosed, !isWorking, !Task.isCancelled else { return }
    let id = UUID()
    operationID = id
    publicationID = id
    isWorking = true
    failure = nil
    let task = Task {
      do { try await action(id) } catch is CancellationError {} catch {
        await self.showFailure(error, publicationID: id)
      }
    }
    operation = task
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    if operationID == id {
      operationID = nil
      operation = nil
      isWorking = false
    }
  }
  private func visible(
    publicationID: UUID, _ action: @escaping @MainActor @Sendable () throws -> Void
  ) async throws {
    guard let lease, !isClosed else { throw ConversationOutboxError.sessionClosed }
    let lifetime = lifetime
    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
      try lifetime.check()
      try Task.checkCancellation()
      guard self.publicationID == publicationID else {
        throw ConversationOutboxError.staleObservation
      }
      try action()
    }
  }
  private func showFailure(_ error: any Error, publicationID: UUID) async {
    do {
      try await visible(publicationID: publicationID) {
        if let value = error as? ConversationOutboxError {
          switch value {
          case .invalidCommand: self.failure = .invalidInput
          case .storageUnavailable, .keyUnavailable, .integrityFailure, .queueFull:
            self.failure = .storage
          case .invalidServerObservation, .originalEpochUnavailable, .originalOwnerUnavailable:
            self.failure = .changed
          case .reconciliationRequired, .invalidTransition: self.failure = .reconciliationRequired
          default: self.failure = .unavailable
          }
        } else if case MobileAPITransportError.network = error {
          self.failure = .offline
        } else if case MobileAPITransportError.timeout = error {
          self.failure = .offline
        } else if case MobileAPITransportError.rateLimited = error {
          self.failure = .rateLimited
        } else {
          self.failure = .unavailable
        }
      }
    } catch {
      // A superseded session cannot publish the old error.
    }
  }
}

private final class FlowConversationLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false
  var isClosed: Bool { lock.withLock { closed } }
  func close() { lock.withLock { closed = true } }
  func check() throws { if isClosed { throw ConversationOutboxError.sessionClosed } }
}
