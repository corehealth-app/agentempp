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
  private var operation: Task<ConversationJournalV3Read, any Error>?
  private var entries: [ConversationJournalV3PageSnapshot.Entry] = []
  private var pins: [String: Pin] = [:]
  private var observedAt: String?
  private var cursor: String?
  private var more = false
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
    operation?.cancel()
    requestID = id
    isLoading = true
    unavailable = false
    commentaryCurrent = false
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
        try await history.unifiedJournal(cursor: requestedCursor, limit: limit, context: incoming)
      }
      operation = task
      let read = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try Task.checkCancellation()
        try incoming.withCurrentAuthority {
          guard !self.closed, self.requestID == id, self.context?.identity == incoming.identity,
            current(incoming.identity)
          else { throw ConversationOutboxError.staleObservation }
          if let old = self.observedAt {
            guard let a = ConversationProtocolInstant(old),
              let b = ConversationProtocolInstant(read.page.observedAt), b >= a
            else { throw MobileAPITransportError.invalidResponse }
          }
          if !reset {
            guard self.cursor == requestedCursor,
              Set(self.entries.map(\.eventID)).isDisjoint(with: Set(read.page.items.map(\.eventID)))
            else { throw MobileAPITransportError.invalidResponse }
            if let last = self.entries.last, let first = read.page.items.first {
              guard ConversationJournalV3PageSnapshot.precedes(last, first) else {
                throw MobileAPITransportError.invalidResponse
              }
            }
          }
          var nextPins = self.pins
          for entry in read.page.items {
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
          self.entries = reset ? read.page.items : self.entries + read.page.items
          self.pins = nextPins
          self.cursor = read.page.nextCursor
          self.more = read.page.hasMore
          self.observedAt = read.page.observedAt
          // A read validates the wrappers on THIS page only. A profile or
          // reevaluation can change policy without changing the epoch, so an
          // older page retains facts but cannot regain clinical commentary.
          self.commentaryEventIDs = Set(read.page.items.map(\.eventID))
          self.commentaryCurrent = true
        }
      }
    } catch {
      guard !closed, requestID == id, self.context?.identity == incoming.identity,
        current(incoming.identity), (try? incoming.withCurrentAuthority { true }) == true
      else { return }
      if !(error is CancellationError) { unavailable = true }
      commentaryCurrent = false
    }
  }
  func cancel() {
    operation?.cancel()
    operation = nil
    requestID = nil
    isLoading = false
    commentaryCurrent = false
    commentaryEventIDs.removeAll()
  }
  /// A grant refresh hides all bodies but retains same-identity factual pins.
  /// Profile/reevaluation changes do not imply a new conversation epoch.
  func suspend() {
    cancel()
    context = nil
    entries.removeAll()
    cursor = nil
    more = false
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
