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
struct FlowConversationTerminalQuestion: Sendable {
  let commandID: UUID
  let reason: String?
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

/// New command feature, separate from the existing legacy Flow sender. Its
/// asynchronous factory uses the actual authenticated controller/lifecycle;
/// no demo repository or successful-save placeholder is installed here.
@MainActor @Observable
final class FlowConversationModel {
  private struct PreparedDraft: Sendable {
    let command: ConversationMealCommand
    let context: ConversationCommandContext.Identity
    let revision: UInt64
  }
  private let controller: any ConversationMealCommandControlling
  private let lifecycle: any SessionLifecycleProviding
  private let history: MobileConversationHistoryRepository
  private let historyPageSize: Int
  private var historyEntries: [ConversationJournalPageSnapshot.Entry] = []
  private var historyIdentity: ConversationCommandContext.Identity?
  private var historyCursor: String?
  private var historyHasMore = false
  private var historyRequestID: UUID?
  private(set) var isLoadingHistory = false
  private(set) var historyUnavailable = false
  private var dismissedQuestions: Set<UUID> = []
  private var currentGroups: [UUID: ConversationMealGroupSnapshot] = [:]
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
  var mealType: ConversationMealCommand.MealType?

  var composer: String {
    get { isClosed ? "" : draft }
    set {
      guard !isClosed else { return }
      draft = newValue
      draftRevision &+= 1
    }
  }
  var isClosed: Bool { closed || lifetime.isClosed }
  var canSubmit: Bool {
    guard !isClosed, !isWorking, lastIdentity != nil, blockedDecisionID == nil else { return false }
    if selectedAttachment != nil { return composer.utf16.count <= 1_000 }
    return !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && composer.utf16.count <= 2_000
  }
  var terminalQuestion: FlowConversationTerminalQuestion? {
    guard hasCurrentScope, let id = blockedDecisionID else { return nil }
    return .init(
      commandID: id, reason: latestDecision?.commandID == id ? latestDecision?.reason : nil)
  }
  func beginIndependentReport() {
    guard hasCurrentScope, !isWorking else { return }
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
    guard !isWorking, !isClosed, let context, context.identity == expectedContext,
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
    guard !isWorking, let selected = selectedAttachment else { return }
    selectedAttachment = nil
    preparedDraft = nil
    draftRevision &+= 1
    mediaDependencies?.staging.remove(selected.staged.fileURL)
    if let context, context.identity == selected.identity {
      try? await mediaService?.discard(captureID: selected.id, context: context)
    }
  }
  var pendingDraftID: UUID? { isClosed ? nil : preparedDraft?.command.commandID }
  var journalRows: [ConversationJournalPageSnapshot.Entry] {
    hasCurrentScope && historyIdentity == lastIdentity ? historyEntries : []
  }
  var hasMoreHistory: Bool { hasCurrentScope && historyHasMore }
  var pendingRows: [FlowConversationPendingRow] {
    hasCurrentScope ? pending.filter { !isInJournal($0.command) } : []
  }
  var savedRows: [FlowConversationSavedRow] {
    hasCurrentScope ? saved.filter { !isInJournal($0.command) } : []
  }
  private func isInJournal(_ command: ConversationMealCommand) -> Bool {
    historyIdentity == lastIdentity
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
  func hasLocalUnresolved(commandID: UUID) -> Bool {
    hasCurrentScope && pending.contains { $0.id == commandID }
  }
  private var hasCurrentScope: Bool {
    guard !isClosed, let context else { return false }
    return (try? context.withCurrentAuthority { true }) == true
  }

  private init(
    controller: any ConversationMealCommandControlling, lifecycle: any SessionLifecycleProviding,
    lease: SessionLease, media: FlowConversationMediaDependencies?,
    history: MobileConversationHistoryRepository, historyPageSize: Int
  ) {
    self.controller = controller
    self.lifecycle = lifecycle
    self.lease = lease
    self.mediaDependencies = media
    self.history = history
    self.historyPageSize = historyPageSize
  }
  static func open(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    store: EncryptedConversationOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(), media: FlowConversationMediaDependencies? = nil,
    historyPageSize: Int = 10
  ) async throws -> FlowConversationModel {
    guard (1...25).contains(historyPageSize) else { throw ConversationOutboxError.invalidCommand }
    let lease = try await lifecycle.leaseForRequest()
    let history = try await MobileConversationHistoryRepository.scoped(
      transport: transport, lifecycle: lifecycle, lease: lease)
    let controller = try await ConversationMealCommandController.open(
      transport: transport, lifecycle: lifecycle, store: store, keyVault: keyVault)
    let model = FlowConversationModel(
      controller: controller, lifecycle: lifecycle, lease: lease, media: media, history: history,
      historyPageSize: historyPageSize)
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
      return model
    } catch {
      await model.close()
      throw error
    }
  }

  func loadHistory(reset: Bool = true) async {
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
            }
          }
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

  func currentGroup(commandID: UUID) -> ConversationMealGroupSnapshot? {
    hasCurrentScope ? currentGroups[commandID] : nil
  }
  func groupUnavailable(commandID: UUID) -> Bool {
    hasCurrentScope && groupFailures.contains(commandID)
  }
  func loadCurrentGroup(commandID: UUID) async {
    guard !isClosed, let lease, let context, hasCurrentScope, let command = commands[commandID]
    else { return }
    let requestID = UUID()
    groupRequests[commandID] = requestID
    groupFailures.remove(commandID)
    do {
      let group = try await history.group(
        commandID: commandID, originalInputHash: command.inputHash, context: context)
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try self.lifetime.check()
        try Task.checkCancellation()
        try context.withCurrentAuthority {
          guard self.groupRequests[commandID] == requestID, self.lastIdentity == context.identity
          else { throw ConversationOutboxError.staleObservation }
          self.currentGroups[commandID] = group
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
    await refresh()
    if hasCurrentScope { await loadHistory() }
  }
  func submit() async {
    guard canSubmit, let identity = lastIdentity else { return }
    if let selected = selectedAttachment {
      let caption = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft
      let revision = draftRevision
      let mealType = mealType
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
  func cancelTransientWork() { operation?.cancel() }
  func close() async {
    lifetime.close()
    closed = true
    publicationID = UUID()
    refreshingID = nil
    operation?.cancel()
    operation = nil
    operationID = nil
    lease = nil
    context = nil
    lastIdentity = nil
    draft = ""
    preparedDraft = nil
    if let selected = selectedAttachment {
      mediaDependencies?.staging.remove(selected.staged.fileURL)
    }
    selectedAttachment = nil
    mediaPhase = nil
    resetHistory()
    dismissedQuestions.removeAll()
    currentGroups.removeAll()
    groupRequests.removeAll()
    groupFailures.removeAll()
    pending.removeAll()
    saved.removeAll()
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
      if let old = lastIdentity, old != value.identity {
        draft = ""
        draftRevision &+= 1
        preparedDraft = nil
        if let selected = selectedAttachment {
          mediaDependencies?.staging.remove(selected.staged.fileURL)
        }
        selectedAttachment = nil
        resetHistory()
        dismissedQuestions.removeAll()
        currentGroups.removeAll()
        groupRequests.removeAll()
        groupFailures.removeAll()
        pending.removeAll()
        saved.removeAll()
        commands.removeAll()
        heldRows.removeAll()
        queuedMetadata.removeAll()
        blockedDecisionID = nil
        latestDecision = nil
      }
      context = value
      lastIdentity = value.identity
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
      pending.removeAll { $0.id == id }
      queuedMetadata.removeAll { $0 == id }
      replayAllowed.remove(id)
      if !saved.contains(where: { $0.id == id }) {
        saved.append(.init(command: command, receipt: value.receipt, feedback: value.feedback))
        savedEffectRevision &+= 1
      }
    case .state(let value, let canResubmit):
      guard let context, hasCurrentScope, value.ownerID == context.ownerID,
        value.epoch == context.epoch
      else { return }
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
    historyEntries.removeAll()
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
