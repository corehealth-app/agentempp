import Foundation
import Observation

@MainActor @Observable
final class TrainingExecutionModel {
  enum Failure: Equatable { case changed, pending, unavailable, finishFenced, finishWithdrawn }
  private var provider: (any TrainingExecutionProviding)?
  private let store: TrainingExecutionPendingStore
  private let makeCompletionID: @Sendable () -> UUID
  private var work: Task<Bool, Never>?
  private var workID: UUID?
  private(set) var isClosed = false
  private(set) var isWorking = false
  private(set) var failure: Failure?
  private(set) var home: TrainingExecutionHomeSnapshot?
  private(set) var session: TrainingExecutionSession?
  private(set) var completion: TrainingExecutionCompletionSnapshot?
  var supportsCompletion: Bool { provider is any TrainingExecutionCompletionProviding }
  private(set) var pending: TrainingExecutionOperation?
  private(set) var resumableSessions: [TrainingExecutionSummary] = []
  private(set) var nextCursor: TrainingExecutionCursor?
  var canEdit: Bool {
    guard !isClosed, !isWorking, pending == nil, let home, let session else { return false }
    return session.phase == .inProgress && completion?.status != .reserved
      && home.scope.recordingAllowed
      && session.localDate == home.scope.openLocalDate
      && TrainingExecutionBinding(home.scope) == binding(session)
  }
  init(
    provider: any TrainingExecutionProviding, store: TrainingExecutionPendingStore,
    makeCompletionID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.provider = provider
    self.store = store
    self.makeCompletionID = makeCompletionID
  }
  func publishIfCurrent(_ publish: @escaping @MainActor @Sendable () throws -> Void) async throws {
    guard !isClosed, let provider else { throw CancellationError() }
    try await provider.publish { [self] in
      guard !isClosed else { throw CancellationError() }
      try publish()
    }
  }
  func load() async {
    _ = await run { model, provider in
      let fresh = try await provider.home(cursor: nil)
      let held = try await model.store.load(authUserID: provider.authUserID)
      var selected: TrainingExecutionSession?
      var selectedCompletion: TrainingExecutionCompletionSnapshot?
      let oldScopeChanged =
        model.home.map { !TrainingExecutionBinding($0.scope).matches(fresh.scope) } ?? false
      let retainedID = model.session.flatMap {
        model.binding($0).matches(fresh.scope) ? $0.id : nil
      }
      let id = held?.sessionID ?? retainedID
      if let id, held.map({ $0.binding.matches(fresh.scope) }) ?? true {
        do {
          let result = try await model.readCurrent(provider, id: id, scope: fresh.scope)
          selected = result.session
          selectedCompletion = result.completion
        } catch MobileAPITransportError.http(status: 404, code: _, requestID: _) { selected = nil }
      }
      let current = selected
      let currentCompletion = selectedCompletion
      try await model.publishIfCurrent {
        try model.accept(fresh)
        model.pending = held
        model.session = current
        model.completion = currentCompletion
        model.resumableSessions = fresh.sessions
        model.nextCursor = fresh.nextCursor
        model.failure =
          held.map { $0.binding.matches(fresh.scope) ? .pending : .changed }
          ?? (oldScopeChanged ? .changed : nil)
      }
      return true
    }
  }
  func loadMore() async {
    guard let cursor = nextCursor else { return }
    _ = await run { model, provider in
      let page = try await provider.home(cursor: cursor)
      guard let old = model.home, TrainingExecutionBinding(old.scope).matches(page.scope) else {
        throw TrainingExecutionError.scopeChanged
      }
      var known = Dictionary(uniqueKeysWithValues: model.resumableSessions.map { ($0.id, $0) })
      for item in page.sessions {
        if let previous = known[item.id], previous.revision > item.revision {
          throw TrainingExecutionError.scopeChanged
        }
        known[item.id] = item
      }
      let merged = known.values.sorted {
        if $0.updatedAt == $1.updatedAt { return $0.id.uuidString > $1.id.uuidString }
        return ConversationProtocolInstant($0.updatedAt)! > ConversationProtocolInstant(
          $1.updatedAt)!
      }
      try await model.publishIfCurrent {
        try model.accept(page)
        model.resumableSessions = merged
        model.nextCursor = page.nextCursor
      }
      return true
    }
  }
  func select(_ id: UUID) async {
    _ = await run { model, provider in
      let fresh = try await provider.home(cursor: nil)
      let result = try await model.readCurrent(provider, id: id, scope: fresh.scope)
      try await model.publishIfCurrent {
        try model.accept(fresh)
        model.session = result.session
        model.completion = result.completion
        model.failure = nil
      }
      return true
    }
  }
  func showPlan() async {
    guard !isWorking else { return }
    session = nil
    completion = nil
    await load()
  }
  func start(dayIndex: Int) async -> Bool {
    guard pending == nil, let shown = home else { return false }
    return await run { model, provider in
      let fresh = try await provider.home(cursor: nil)
      guard TrainingExecutionBinding(shown.scope).matches(fresh.scope),
        shown.scope.currentLocalDate == fresh.scope.currentLocalDate,
        shown.plan?.planID == fresh.plan?.planID,
        shown.plan?.definitionHash == fresh.plan?.definitionHash
      else {
        try await model.publishIfCurrent {
          try model.accept(fresh)
          model.session = nil
          model.completion = nil
          model.failure = .changed
        }
        return false
      }
      try await model.publishIfCurrent { try model.accept(fresh) }
      let operation = try TrainingExecutionOperation.start(home: fresh, dayIndex: dayIndex)
      return try await model.send(operation, provider: provider)
    }
  }
  func saveSet(exercise: Int, set: TrainingExecutionSet) async -> Bool {
    await update(.saveSet(exercise: exercise, set: set))
  }
  func removeSet(exercise: Int, setID: UUID) async -> Bool {
    await update(.removeSet(exercise: exercise, setID: setID))
  }
  func markExercise(_ index: Int, completed: Bool) async -> Bool {
    await update(.markExercise(index: index, completed: completed))
  }
  func abandon() async -> Bool { await update(.abandon) }
  func retryPending() async -> Bool {
    guard let held = pending else { return false }
    return await run { model, provider in
      let fresh = try await provider.home(cursor: nil)
      if held.kind == "finish", let modern = provider as? any TrainingExecutionCompletionProviding {
        guard fresh.scope.ownerID == held.binding.ownerID,
          fresh.scope.authUserID == held.binding.authUserID
        else { throw TrainingExecutionError.scopeChanged }
        try await model.publishIfCurrent { try model.accept(fresh) }
        return try await model.resolvePendingFinish(held, provider: modern, mode: .observe)
      }
      guard held.binding.matches(fresh.scope) else {
        try await model.publishIfCurrent {
          try model.accept(fresh)
          model.session = nil
          model.completion = nil
          model.failure = .changed
        }
        return false
      }
      try await model.publishIfCurrent { try model.accept(fresh) }
      return try await model.send(held, provider: provider, recovering: true)
    }
  }
  private func update(_ action: TrainingExecutionOperation.Action) async -> Bool {
    guard canEdit, let shown = session else { return false }
    return await run { model, provider in
      let fresh = try await provider.home(cursor: nil)
      let current = try await model.readCurrent(provider, id: shown.id, scope: fresh.scope)
      guard model.binding(shown).matches(fresh.scope), model.binding(shown).matches(current.scope),
        current.session.revision == shown.revision, current.session == shown
      else {
        try await model.publishIfCurrent {
          try model.accept(fresh)
          model.session = current.session
          model.completion = current.completion
          model.failure = .changed
        }
        return false
      }
      guard fresh.scope.recordingAllowed, current.completion?.status != .reserved,
        current.session.localDate == fresh.scope.openLocalDate
      else {
        try await model.publishIfCurrent {
          try model.accept(fresh)
          model.session = current.session
          model.completion = current.completion
          model.failure = .changed
        }
        return false
      }
      try await model.publishIfCurrent { try model.accept(fresh) }
      let operation = try TrainingExecutionOperation.update(
        session: current.session, action: action)
      return try await model.send(operation, provider: provider)
    }
  }
  private func send(
    _ operation: TrainingExecutionOperation, provider: any TrainingExecutionProviding,
    recovering: Bool = false
  ) async throws -> Bool {
    try await provider.validate()
    do { try await store.claim(operation) }  // protected before the first physical POST
    catch TrainingExecutionError.pendingOperation {
      let held = try await store.load(authUserID: provider.authUserID)
      try await publishIfCurrent {
        self.pending = held
        self.failure = .pending
      }
      return false
    }
    try await publishIfCurrent {
      self.pending = operation
      self.failure = nil
    }
    if let modern = provider as? any TrainingExecutionCompletionProviding {
      return try await sendV2(operation, provider: modern, recovering: recovering)
    }
    do {
      let result = try await provider.submit(operation)
      try await provider.validate()
      try await store.acknowledge(operation, result: result)
      try await publishIfCurrent {
        self.session = result.session
        self.pending = nil
        self.failure = nil
      }
      return true
    } catch let rejected as TrainingExecutionRejectedOperation {
      let proof = try await provider.reconcile(rejected)
      try await provider.validate()
      try await store.retireRejected(proof)
      try await publishIfCurrent {
        try self.accept(proof.home)
        self.session = proof.session
        self.pending = nil
        self.failure = .changed
      }
      return false
    }
  }
  private struct Current {
    let scope: TrainingExecutionScope, session: TrainingExecutionSession,
      completion: TrainingExecutionCompletionSnapshot?
  }
  private func readCurrent(
    _ provider: any TrainingExecutionProviding, id: UUID, scope: TrainingExecutionScope
  ) async throws -> Current {
    if let modern = provider as? any TrainingExecutionCompletionProviding {
      let value = try await modern.current(id, binding: .init(scope))
      return .init(scope: value.scope, session: value.session, completion: value.completion)
    }
    let value = try await provider.read(id)
    guard TrainingExecutionBinding(scope).matches(value.scope) else {
      throw TrainingExecutionError.scopeChanged
    }
    return .init(scope: value.scope, session: value.session, completion: nil)
  }
  func finish(report: String) async -> Bool {
    guard supportsCompletion, canEdit, let shown = session else { return false }
    return await run { model, provider in
      let fresh = try await provider.home(cursor: nil)
      let current = try await model.readCurrent(provider, id: shown.id, scope: fresh.scope)
      guard model.binding(shown).matches(fresh.scope), current.session == shown,
        current.completion == nil, fresh.scope.recordingAllowed,
        shown.localDate == fresh.scope.openLocalDate
      else {
        try await model.publishIfCurrent {
          try model.accept(fresh)
          model.session = current.session
          model.completion = current.completion
          model.failure = .changed
        }
        return false
      }
      try await model.publishIfCurrent { try model.accept(fresh) }
      let op = try TrainingExecutionOperation.finish(
        session: current.session, report: report, id: model.makeCompletionID())
      return try await model.send(op, provider: provider)
    }
  }
  func cancelPendingCompletion() async -> Bool {
    guard let held = pending, held.kind == "finish" else { return false }
    return await run { model, provider in
      guard let modern = provider as? any TrainingExecutionCompletionProviding else { return false }
      let fresh = try await modern.home(cursor: nil)
      guard fresh.scope.ownerID == held.binding.ownerID,
        fresh.scope.authUserID == held.binding.authUserID
      else { throw TrainingExecutionError.scopeChanged }
      try await model.publishIfCurrent { try model.accept(fresh) }
      _ = try await model.resolvePendingFinish(held, provider: modern, mode: .withdraw)
      return model.pending == nil
    }
  }
  private func sendV2(
    _ operation: TrainingExecutionOperation, provider: any TrainingExecutionCompletionProviding,
    recovering: Bool
  ) async throws -> Bool {
    if operation.kind == "finish" {
      if recovering {
        return try await resolvePendingFinish(operation, provider: provider, mode: .observe)
      }
      let value = try await provider.finish(operation)
      return try await acceptCompletion(value, operation: operation, provider: provider)
    }
    let value = try await provider.progress(operation)
    try await provider.validate()
    if value.status != .pending { try await store.acknowledgeProgress(operation, result: value) }
    try await publishIfCurrent {
      self.session = value.current?.session
      self.completion = value.current?.completion
      if value.status == .pending {
        self.failure = .pending
      } else {
        self.pending = nil
        self.failure = value.status == .notApplied ? .changed : nil
      }
    }
    return value.status != .pending && value.status != .notApplied
  }
  private func resolvePendingFinish(
    _ operation: TrainingExecutionOperation, provider: any TrainingExecutionCompletionProviding,
    mode: TrainingExecutionFinishResolutionMode
  ) async throws -> Bool {
    let resolution = try await provider.resolveFinish(operation, mode: mode)
    try resolution.validate(for: operation, mode: mode)
    try await provider.validate()
    if mode == .observe
      && (resolution.status == .ready || resolution.completion?.status == .reserved)
    {
      // One explicit retry of the identical command, only after its dedicated
      // observation. A failed POST never triggers another automatic write.
      let value = try await provider.finish(operation)
      return try await acceptCompletion(value, operation: operation, provider: provider)
    }
    if resolution.status == .pending {
      try await publishIfCurrent {
        self.session = resolution.current?.session
        self.completion = resolution.current?.completion
        self.failure = .pending
      }
      return false
    }
    let fresh = try await provider.home(cursor: nil)
    guard fresh.scope.ownerID == operation.binding.ownerID,
      fresh.scope.authUserID == operation.binding.authUserID
    else { throw TrainingExecutionError.scopeChanged }
    try await provider.validate()
    if resolution.status == .available, let own = resolution.completion {
      try await store.acknowledgeCompletion(operation, result: own)
    } else {
      try await store.retireFinish(operation, resolution: resolution)
    }
    try await publishIfCurrent {
      try self.accept(fresh)
      // Keep a later/current completion independent of the cancelled original
      // receipt. Never relabel an old execution under a newly observed epoch.
      if TrainingExecutionBinding(resolution.scope).matches(fresh.scope) {
        self.session = resolution.current?.session
        self.completion = resolution.current?.completion ?? resolution.completion
      } else {
        self.session = nil
        self.completion = nil
      }
      self.pending = nil
      self.failure =
        resolution.status == .withdrawn
        ? .finishWithdrawn
        : resolution.status == .fenced
          ? .finishFenced
          : resolution.completion?.status == .completed ? nil : .changed
    }
    return resolution.completion?.status == .completed
  }
  private func acceptCompletion(
    _ value: TrainingExecutionCompletionSnapshot, operation: TrainingExecutionOperation,
    provider: any TrainingExecutionCompletionProviding
  ) async throws -> Bool {
    try value.validate(for: operation)
    try await provider.validate()
    if value.status == .reserved {
      try await publishIfCurrent {
        self.completion = value
        self.session = value.session
        self.failure = .pending
      }
      return false
    }
    let current: Current?
    if value.status == .cancelled {
      current = try await readCurrent(provider, id: operation.sessionID, scope: value.scope)
    } else {
      current = nil
    }
    try await provider.validate()
    try await store.acknowledgeCompletion(operation, result: value)
    try await publishIfCurrent {
      self.completion = current?.completion ?? value
      self.session = current?.session ?? value.session
      self.pending = nil
      self.failure = value.status == .cancelled ? .changed : nil
    }
    return value.status == .completed
  }
  private func accept(_ fresh: TrainingExecutionHomeSnapshot) throws {
    guard let provider, fresh.scope.ownerID == provider.ownerID,
      fresh.scope.authUserID == provider.authUserID
    else { throw TrainingExecutionError.scopeChanged }
    if let previous = home {
      guard previous.scope.ownerID == fresh.scope.ownerID,
        ConversationProtocolInstant(fresh.scope.observedAt)! >= ConversationProtocolInstant(
          previous.scope.observedAt)!
      else { throw TrainingExecutionError.scopeChanged }
    }
    home = fresh
  }
  private func binding(_ s: TrainingExecutionSession) -> TrainingExecutionBinding {
    .init(ownerID: s.ownerID, authUserID: s.authUserID, epoch: s.epoch, timezone: s.timezone)
  }
  private func run(
    _ action:
      @escaping @MainActor (TrainingExecutionModel, any TrainingExecutionProviding) async throws ->
      Bool
  ) async -> Bool {
    guard !isClosed, work == nil, let provider else { return false }
    let id = UUID()
    workID = id
    isWorking = true
    let task = Task { @MainActor [self] in
      do {
        try Task.checkCancellation()
        return try await action(self, provider)
      } catch {
        if error is CancellationError || error is SessionLifecycleError {
          if !Task.isCancelled { invalidateSynchronously() }
          return false
        }
        do {
          try await publishIfCurrent {
            self.failure =
              self.pending != nil
              ? .pending
              : (error as? TrainingExecutionError == .scopeChanged ? .changed : .unavailable)
          }
        } catch { invalidateSynchronously() }
        return false
      }
    }
    work = task
    let result = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    if workID == id {
      work = nil
      workID = nil
      isWorking = false
    }
    return result
  }
  func invalidateSynchronously() {
    isClosed = true
    work?.cancel()
    home = nil
    session = nil
    completion = nil
    pending = nil
    resumableSessions = []
    nextCursor = nil
  }
  func close() async {
    invalidateSynchronously()
    await work?.value
    work = nil
    workID = nil
    isWorking = false
    provider = nil
  }
}
