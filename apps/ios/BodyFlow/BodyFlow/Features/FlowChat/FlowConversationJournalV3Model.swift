import Foundation
import Observation

/// Session-owned historical observations, separate from every dispatch controller.
@MainActor @Observable
final class FlowConversationJournalV3Model {
  private struct Pin {
    let immutable: Data
    let outcome: Data
    let status: ConversationJournalV3PageSnapshot.Status
    let commandID: UUID?
  }
  private let history: MobileConversationHistoryRepository
  private let lifecycle: any SessionLifecycleProviding
  private var context: ConversationCommandContext?
  private var pinnedIdentity: ConversationCommandContext.Identity?
  private var operation: Task<[ConversationJournalV3PageSnapshot], any Error>?
  private var entries: [ConversationJournalV3PageSnapshot.Entry] = []
  private var pins: [String: Pin] = [:]
  private var observedAt: String?
  private var cursor: String?
  private var more = false
  private var loadedPages = 0
  private var requestID: UUID?
  private var closed = false
  private var commentaryCurrent = false
  private var commentaryEventIDs: Set<String> = []
  private(set) var isLoading = false
  private(set) var unavailable = false
  var rows: [ConversationJournalV3PageSnapshot.Entry] { visible ? entries : [] }
  var hasMore: Bool { visible && more }
  var acceptedIdentity: ConversationCommandContext.Identity? { visible ? context?.identity : nil }
  private var visible: Bool {
    !closed && context.map { (try? $0.withCurrentAuthority { true }) == true } == true
  }
  init(history: MobileConversationHistoryRepository, lifecycle: any SessionLifecycleProviding) {
    self.history = history
    self.lifecycle = lifecycle
  }
  func feedback(for entry: ConversationJournalV3PageSnapshot.Entry)
    -> ConversationFeedbackPresentationSnapshot.Bound?
  {
    guard visible, commentaryCurrent, commentaryEventIDs.contains(entry.eventID), let context,
      let observedAt,
      let current = entries.first(where: { $0.eventID == entry.eventID }),
      current.immutablePin == entry.immutablePin, current.outcomePin == entry.outcomePin,
      current.commandID == entry.commandID, current.feedback == entry.feedback
    else { return nil }
    guard let feedback = entry.feedback,
      let accepted = ConversationProtocolInstant(context.observedAt),
      let shown = ConversationProtocolInstant(feedback.provenance.observedAt), shown >= accepted
    else { return nil }
    return feedback.boundHistorical(
      entry, ownerID: context.ownerID, epoch: context.epoch,
      sessionGeneration: context.sessionGeneration, pageObservedAt: observedAt)
  }
  func load(
    context incoming: ConversationCommandContext, lease: SessionLease, limit: Int,
    reset: Bool, current: @escaping @MainActor (ConversationCommandContext.Identity) -> Bool
  ) async {
    guard !closed, !incoming.observation.isEnqueueOnly, current(incoming.identity),
      (try? incoming.withCurrentAuthority { true }) == true
    else { return }
    if pinnedIdentity != incoming.identity { clear() }
    pinnedIdentity = incoming.identity
    guard reset || (!isLoading && more && cursor != nil) else { return }
    context = incoming
    let id = UUID()
    let requestedCursor = reset ? nil : cursor
    let oldestLoaded = reset && loadedPages > 1 ? entries.last : nil
    let pageBudget = oldestLoaded == nil ? 1 : loadedPages + 1
    operation?.cancel()
    requestID = id
    isLoading = true
    unavailable = false
    // A routine refresh under the same grant keeps the rendered cards until
    // a current response replaces them or an error withholds commentary.
    defer {
      if requestID == id {
        requestID = nil
        isLoading = false
        operation = nil
      }
    }
    do {
      let history = self.history
      let task = Task {
        var pages: [ConversationJournalV3PageSnapshot] = []
        var next = requestedCursor
        for _ in 0..<pageBudget {
          let page = try await history.unifiedJournal(cursor: next, limit: limit, context: incoming).page
          if let previous = pages.last {
            guard let previousAt = ConversationProtocolInstant(previous.observedAt),
              let currentAt = ConversationProtocolInstant(page.observedAt), currentAt >= previousAt
            else { throw MobileAPITransportError.invalidResponse }
            if let last = previous.items.last, let first = page.items.first {
              guard ConversationJournalV3PageSnapshot.precedes(last, first) else {
                throw MobileAPITransportError.invalidResponse
              }
            }
          }
          pages.append(page)
          guard let oldestLoaded, let cursor = page.nextCursor, let last = page.items.last,
            ConversationJournalV3PageSnapshot.precedes(last, oldestLoaded)
          else { return pages }
          next = cursor
        }
        // Preserve the current range if the new head cannot reach it within
        // the number of pages already loaded plus one page for new messages.
        throw MobileAPITransportError.invalidResponse
      }
      operation = task
      let pages = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard let recentPage = pages.last, let firstPage = pages.first else {
        throw MobileAPITransportError.invalidResponse
      }
      let items = pages.flatMap(\.items)
      guard Set(items.map(\.eventID)).count == items.count else {
        throw MobileAPITransportError.invalidResponse
      }
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try Task.checkCancellation()
        try incoming.withCurrentAuthority {
          guard !self.closed, self.requestID == id, self.context?.identity == incoming.identity,
            current(incoming.identity)
          else { throw ConversationOutboxError.staleObservation }
          if let old = self.observedAt {
            guard let a = ConversationProtocolInstant(old),
              let b = ConversationProtocolInstant(firstPage.observedAt), b >= a
            else { throw MobileAPITransportError.invalidResponse }
          }
          if !reset {
            guard self.cursor == requestedCursor,
              Set(self.entries.map(\.eventID)).isDisjoint(with: Set(items.map(\.eventID)))
            else { throw MobileAPITransportError.invalidResponse }
            if let last = self.entries.last, let first = items.first {
              guard ConversationJournalV3PageSnapshot.precedes(last, first) else {
                throw MobileAPITransportError.invalidResponse
              }
            }
          }
          var nextPins = self.pins
          for entry in items {
            if let known = nextPins[entry.eventID] {
              let childUnchanged = known.commandID == entry.commandID
              let childAssigned =
                entry.kind == .intake && known.commandID == nil
                && known.status == .pending && entry.commandID != nil
              let observingPending =
                known.status == .pending
                && [.intake, .workout, .report].contains(entry.kind)
              guard known.immutable == entry.immutablePin, childUnchanged || childAssigned,
                known.outcome == entry.outcomePin || observingPending
              else { throw MobileAPITransportError.invalidResponse }
            }
            nextPins[entry.eventID] = .init(
              immutable: entry.immutablePin, outcome: entry.outcomePin, status: entry.status,
              commandID: entry.commandID)
          }
          self.entries = reset ? items : self.entries + items
          self.pins = nextPins
          self.cursor = recentPage.nextCursor
          self.more = recentPage.hasMore
          self.observedAt = recentPage.observedAt
          self.loadedPages = reset ? pages.count : self.loadedPages + 1
          // A read validates the wrappers on THIS page only. A profile or
          // reevaluation can change policy without changing the epoch, so an
          // older page retains facts but cannot regain clinical commentary.
          self.commentaryEventIDs = Set(recentPage.items.map(\.eventID))
          self.commentaryCurrent = true
        }
      }
    } catch {
      guard !closed, requestID == id, self.context?.identity == incoming.identity,
        current(incoming.identity), (try? incoming.withCurrentAuthority { true }) == true
      else { return }
      if !(error is CancellationError) { unavailable = true }
      clearCommentary()
    }
  }
  func cancel() {
    operation?.cancel()
    operation = nil
    requestID = nil
    isLoading = false
  }
  private func clearCommentary() {
    commentaryCurrent = false
    commentaryEventIDs.removeAll()
  }
  /// A real edit ACK fences commentary and in-flight pages before its effect.
  /// Existing facts and their original receipt identities remain visible.
  func invalidateCommentary(appliedAt: String) {
    cancel()
    clearCommentary()
    guard let applied = ConversationProtocolInstant(appliedAt) else { return }
    if observedAt.flatMap(ConversationProtocolInstant.init).map({ $0 < applied }) ?? true {
      observedAt = appliedAt
    }
  }
  /// A grant refresh hides all bodies but retains same-identity factual pins.
  /// Profile/reevaluation changes do not imply a new conversation epoch.
  func suspend() {
    cancel()
    clearCommentary()
    context = nil
    entries.removeAll()
    cursor = nil
    more = false
    loadedPages = 0
    unavailable = false
  }
  func clear() {
    suspend()
    pinnedIdentity = nil
    pins.removeAll()
    observedAt = nil
  }
  func close() {
    clear()
    closed = true
  }
}
