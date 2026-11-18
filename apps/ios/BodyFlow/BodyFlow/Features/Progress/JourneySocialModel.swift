import Foundation
import Observation

/// Visible state belongs to one original login. All writes cross the protected
/// pending session and every publication crosses the lifecycle's MainActor gate.
@MainActor @Observable final class JourneySocialModel {
  enum Phase: Equatable { case idle, loading, ready, failed, closed }
  enum Issue: Equatable { case invalidInput, unavailable }
  enum Outcome: Equatable { case saved, recovered, cancelledBeforeApply }
  private var provider: (any JourneySocialProviding)?
  private var session: JourneySocialPendingSession?
  private let pageSize: Int
  private var work: Task<Void, Never>?
  private var workID: UUID?
  private var savedOperationID: UUID?
  private(set) var phase = Phase.idle
  private(set) var issue: Issue?
  private(set) var outcome: Outcome?
  private(set) var profile: JourneySocialProfile?
  private(set) var pending: JourneySocialPendingOperation?
  private(set) var rankings: [JourneySocialRankingPage.Entry] = []
  private(set) var rankingPage: JourneySocialRankingPage?
  private(set) var blocked: [JourneySocialBlocksPage.Entry] = []
  private(set) var blocksPage: JourneySocialBlocksPage?
  var isWorking: Bool { work != nil }
  var isClosed: Bool { phase == .closed }
  var canEdit: Bool { phase == .ready && !isWorking && pending == nil && profile != nil }
  var hasRetainedCapabilities: Bool { provider != nil || session != nil || work != nil }

  init(provider: any JourneySocialProviding, store: JourneySocialPendingStore, pageSize: Int = 20)
    throws
  {
    try socialRequire((1...100).contains(pageSize))
    self.provider = provider
    self.session = try JourneySocialPendingSession(provider: provider, store: store)
    self.pageSize = pageSize
  }
  func publishIfCurrent(_ action: @escaping @MainActor @Sendable () throws -> Void) async throws {
    guard !isClosed, let provider else { throw CancellationError() }
    try Task.checkCancellation()
    try await provider.publish { [self] in
      guard !isClosed else { throw CancellationError() }
      try action()
    }
  }
  func load() async {
    await run { model, provider, session in
      model.clearAudience()
      let held = try await session.pending()
      let profile = try await provider.profile()
      try profile.validate(binding: provider.binding)
      try await model.publishIfCurrent {
        model.profile = profile
        model.pending = held
      }
      if held == nil { try await model.readLists(profile, provider: provider) }
    }
  }
  func saveParticipation(nickname: String, accepted: Bool) async {
    guard canEdit else { return }
    guard accepted, profile?.moderation == .active else {
      await rejectInput()
      return
    }
    await mutate(.participation(nickname: nickname, consentVersion: "journey-social.v1"))
  }
  func withdraw() async {
    guard canEdit, profile?.optedIn == true else { return }
    await mutate(.participation(nickname: nil, consentVersion: nil))
  }
  func block(memberID: UUID) async {
    guard canEdit else { return }
    guard visiblePeer(memberID) else {
      await rejectInput()
      return
    }
    await mutate(.block(memberID: memberID, blocked: true))
  }
  func unblock(memberID: UUID) async {
    guard canEdit else { return }
    guard blocked.contains(where: { $0.memberID == memberID }) else {
      await rejectInput()
      return
    }
    await mutate(.block(memberID: memberID, blocked: false))
  }
  @discardableResult func report(memberID: UUID, reason: JourneySocialReportReason) async -> Bool {
    guard canEdit else { return false }
    guard visiblePeer(memberID) else {
      await rejectInput()
      return false
    }
    return await mutate(.report(memberID: memberID, reason: reason))
  }
  private func visiblePeer(_ id: UUID) -> Bool {
    profile?.optedIn == true && profile?.moderation == .active
      && rankings.contains { $0.memberID == id && !$0.isYou }
  }
  private func rejectInput() async {
    do {
      try await publishIfCurrent {
        self.issue = .invalidInput
        self.outcome = nil
      }
    } catch {
      invalidateSynchronously()
    }
  }
  @discardableResult private func mutate(_ action: JourneySocialOperation.Action) async -> Bool {
    guard canEdit, let profile, let provider else { return false }
    let operation: JourneySocialOperation
    do {
      operation = try .init(
        binding: provider.binding, id: UUID(), expectedRevision: profile.revision, action: action)
    } catch {
      await rejectInput()
      return false
    }
    await run { model, provider, session in
      model.clearAudience()
      model.outcome = nil
      model.savedOperationID = nil
      let result = try await session.submit(operation)
      try await model.publishIfCurrent {
        model.profile = result.profile
        model.pending = nil
        model.outcome = .saved
        model.savedOperationID = operation.id
      }
      try await model.readLists(result.profile, provider: provider)
    }
    return !isClosed && savedOperationID == operation.id
  }
  func resolvePending() async {
    guard !isClosed, !isWorking, let pending else { return }
    await run { model, provider, session in
      model.clearAudience()
      model.outcome = nil
      let result = try await session.recover(pending)
      try await model.publishIfCurrent {
        model.profile = result.profile
        model.pending = nil
        model.outcome = result.status == .fenced ? .cancelledBeforeApply : .recovered
      }
      try await model.readLists(result.profile, provider: provider)
    }
  }
  func loadMoreRanking() async {
    guard canEdit, let cursor = rankingPage?.nextCursor, let previous = rankingPage else { return }
    let rows = rankings
    await run { model, provider, _ in
      let page = try await provider.ranking(cursor: cursor, limit: model.pageSize)
      try page.validate(binding: provider.binding, cursor: cursor, limit: model.pageSize)
      try socialRequire(
        page.weekStart == previous.weekStart && page.weekEnd == previous.weekEnd
          && page.throughDate == previous.throughDate)
      let merged = rows + page.entries
      try socialRequire(
        Set(merged.map(\.memberID)).count == merged.count && merged.filter(\.isYou).count <= 1)
      if let last = rows.last, let first = page.entries.first {
        try socialRequire(first.weeklyXP <= last.weeklyXP)
        if first.weeklyXP == last.weeklyXP {
          try socialRequire(
            first.rank == last.rank && first.memberID.uuidString > last.memberID.uuidString)
        } else {
          try socialRequire(first.rank == rows.count + 1)
        }
      }
      try model.validateViewer(page)
      try await model.publishIfCurrent {
        model.rankings = merged
        model.rankingPage = page
      }
    }
  }
  func loadMoreBlocks() async {
    guard canEdit, let cursor = blocksPage?.nextCursor else { return }
    let rows = blocked
    await run { model, provider, _ in
      let page = try await provider.blocks(cursor: cursor, limit: model.pageSize)
      try page.validate(binding: provider.binding, cursor: cursor, limit: model.pageSize)
      try socialRequire(page.revision == model.profile?.revision)
      let merged = rows + page.entries
      try socialRequire(Set(merged.map(\.memberID)).count == merged.count)
      try await model.publishIfCurrent {
        model.blocked = merged
        model.blocksPage = page
      }
    }
  }
  private func readLists(_ profile: JourneySocialProfile, provider: any JourneySocialProviding)
    async throws
  {
    var page: JourneySocialRankingPage?
    var blocks: JourneySocialBlocksPage?
    if profile.optedIn && profile.moderation == .active {
      let fresh = try await provider.ranking(cursor: nil, limit: pageSize)
      try fresh.validate(binding: provider.binding, cursor: nil, limit: pageSize)
      try validateViewer(fresh)
      page = fresh
    }
    if profile.revision > 0 {
      let fresh = try await provider.blocks(cursor: nil, limit: pageSize)
      try fresh.validate(binding: provider.binding, cursor: nil, limit: pageSize)
      try socialRequire(fresh.revision == profile.revision)
      blocks = fresh
    }
    let ranking = page
    let blockList = blocks
    try await publishIfCurrent {
      self.rankings = ranking?.entries ?? []
      self.rankingPage = ranking
      self.blocked = blockList?.entries ?? []
      self.blocksPage = blockList
    }
  }
  private func validateViewer(_ page: JourneySocialRankingPage) throws {
    guard let member = profile?.memberID else { throw JourneySocialInvalid.value }
    try socialRequire(page.entries.allSatisfy { $0.isYou == ($0.memberID == member) })
    if let cursor = page.nextCursor { try socialRequire(cursor.viewerMemberID == member) }
  }
  private func clearAudience() {
    rankings = []
    rankingPage = nil
    blocked = []
    blocksPage = nil
  }
  private func run(
    _ action:
      @escaping @MainActor (
        JourneySocialModel, any JourneySocialProviding, JourneySocialPendingSession
      ) async throws -> Void
  ) async {
    guard !isClosed, work == nil, let provider, let session, !Task.isCancelled else { return }
    let id = UUID()
    workID = id
    phase = .loading
    issue = nil
    let task = Task { @MainActor [self] in
      do {
        try Task.checkCancellation()
        try await action(self, provider, session)
        try await publishIfCurrent { self.phase = .ready }
      } catch {
        if error is SessionLifecycleError || (error as? JourneySocialPendingError) == .scopeChanged
        {
          invalidateSynchronously()
          return
        }
        if Task.isCancelled || error is CancellationError {
          if !isClosed { phase = .idle }
          return
        }
        do {
          var held = pending
          do { held = try await session.pending() } catch {
            if error is SessionLifecycleError || error is CancellationError { throw error }
          }
          let retained = held
          try await publishIfCurrent {
            self.pending = retained
            self.clearAudience()
            self.phase = .failed
            self.issue = .unavailable
          }
        } catch { invalidateSynchronously() }
      }
    }
    work = task
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    if workID == id {
      work = nil
      workID = nil
    }
  }
  func cancelWork() { work?.cancel() }
  func invalidateSynchronously() {
    phase = .closed
    work?.cancel()
    profile = nil
    pending = nil
    issue = nil
    outcome = nil
    savedOperationID = nil
    clearAudience()
  }
  func close() async {
    invalidateSynchronously()
    await work?.value
    work = nil
    workID = nil
    session = nil
    provider = nil
  }
}
