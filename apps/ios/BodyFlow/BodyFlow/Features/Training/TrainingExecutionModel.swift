import Foundation
import Observation

@MainActor @Observable
final class TrainingExecutionModel {
  enum Failure: Equatable { case changed, pending, unavailable }
  private var provider: (any TrainingExecutionProviding)?
  private let store: TrainingExecutionPendingStore
  private var work: Task<Bool, Never>?
  private var workID: UUID?
  private(set) var isClosed = false
  private(set) var isWorking = false
  private(set) var failure: Failure?
  private(set) var home: TrainingExecutionHomeSnapshot?
  private(set) var session: TrainingExecutionSession?
  private(set) var pending: TrainingExecutionOperation?
  private(set) var resumableSessions: [TrainingExecutionSummary] = []
  private(set) var nextCursor: TrainingExecutionCursor?
  var canEdit: Bool {
    guard !isClosed, !isWorking, pending == nil, let home, let session else { return false }
    return session.phase == .inProgress && home.scope.recordingAllowed
      && session.localDate == home.scope.openLocalDate
      && TrainingExecutionBinding(home.scope) == binding(session)
  }
  init(provider: any TrainingExecutionProviding, store: TrainingExecutionPendingStore) {
    self.provider = provider
    self.store = store
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
      let oldScopeChanged =
        model.home.map { !TrainingExecutionBinding($0.scope).matches(fresh.scope) } ?? false
      let retainedID = model.session.flatMap {
        model.binding($0).matches(fresh.scope) ? $0.id : nil
      }
      let id = held?.sessionID ?? retainedID
      if let id, held.map({ $0.binding.matches(fresh.scope) }) ?? true {
        do {
          let result = try await provider.read(id)
          guard TrainingExecutionBinding(fresh.scope).matches(result.scope) else {
            throw TrainingExecutionError.scopeChanged
          }
          selected = result.session
        } catch MobileAPITransportError.http(status: 404, code: _, requestID: _) { selected = nil }
      }
      let current = selected
      try await model.publishIfCurrent {
        try model.accept(fresh)
        model.pending = held
        model.session = current
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
      let result = try await provider.read(id)
      guard TrainingExecutionBinding(fresh.scope).matches(result.scope) else {
        throw TrainingExecutionError.scopeChanged
      }
      try await model.publishIfCurrent {
        try model.accept(fresh)
        model.session = result.session
        model.failure = nil
      }
      return true
    }
  }
  func showPlan() async {
    guard !isWorking else { return }
    session = nil
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
      guard held.binding.matches(fresh.scope) else {
        try await model.publishIfCurrent {
          try model.accept(fresh)
          model.session = nil
          model.failure = .changed
        }
        return false
      }
      try await model.publishIfCurrent { try model.accept(fresh) }
      return try await model.send(held, provider: provider)
    }
  }
  private func update(_ action: TrainingExecutionOperation.Action) async -> Bool {
    guard pending == nil, let shown = session, shown.phase == .inProgress else { return false }
    return await run { model, provider in
      let fresh = try await provider.home(cursor: nil)
      let current = try await provider.read(shown.id)
      guard model.binding(shown).matches(fresh.scope), model.binding(shown).matches(current.scope),
        current.session.revision == shown.revision, current.session == shown
      else {
        try await model.publishIfCurrent {
          try model.accept(fresh)
          model.session = current.session
          model.failure = .changed
        }
        return false
      }
      guard fresh.scope.recordingAllowed, current.session.localDate == fresh.scope.openLocalDate
      else {
        try await model.publishIfCurrent {
          try model.accept(fresh)
          model.session = current.session
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
    _ operation: TrainingExecutionOperation, provider: any TrainingExecutionProviding
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
