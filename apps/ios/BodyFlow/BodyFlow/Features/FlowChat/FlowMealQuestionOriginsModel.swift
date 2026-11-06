import Foundation
import Observation

/// Current scoped lookup pages, separate from historical display and every
/// command/outbox writer. Empty pages can still carry an older-history cursor.
@MainActor @Observable
final class FlowMealQuestionOriginsModel {
  private let repository: MobileConversationIntakeRepository
  private let lifecycle: any SessionLifecycleProviding
  private var context: ConversationCommandContext?
  private var identity: ConversationCommandContext.Identity?
  private var entries: [FlowMealQuestionOriginsPageSnapshot.Origin] = []
  private var pins: [UUID: Data] = [:]
  private var cursor: String?
  private var seenCursors: Set<String> = []
  private var more = false
  private var observedAt: String?
  private var requestID: UUID?
  private var task: Task<FlowMealQuestionOriginsPageSnapshot, any Error>?
  private var closed = false
  private(set) var isLoading = false
  private(set) var unavailable = false
  private var visible: Bool {
    !closed && context.map { (try? $0.withCurrentAuthority { true }) == true } == true
  }
  var rows: [FlowMealQuestionOriginsPageSnapshot.Origin] { visible ? entries : [] }
  var hasMore: Bool { visible && more }
  init(repository: MobileConversationIntakeRepository, lifecycle: any SessionLifecycleProviding) {
    self.repository = repository
    self.lifecycle = lifecycle
  }
  func matches(_ incoming: ConversationCommandContext) -> Bool {
    visible && context?.observation.isSameGrant(as: incoming.observation) == true
  }
  func origin(_ id: UUID) -> FlowMealQuestionOriginsPageSnapshot.Origin? {
    rows.first { $0.id == id }
  }
  func prune(_ id: UUID) { entries.removeAll { $0.id == id } }
  func load(
    context incoming: ConversationCommandContext, lease: SessionLease, limit: Int,
    reset: Bool, current: @escaping @MainActor (ConversationCommandContext) -> Bool
  ) async {
    guard !closed, !incoming.observation.isEnqueueOnly, current(incoming),
      (try? incoming.withCurrentAuthority { true }) == true else { return }
    if identity != incoming.identity { clear() }
    guard reset || (!isLoading && more && cursor != nil) else { return }
    let requestedCursor = reset ? nil : cursor
    if reset { cancel(); entries.removeAll(); cursor = nil; more = false; seenCursors.removeAll() }
    identity = incoming.identity
    context = incoming
    let id = UUID()
    requestID = id
    isLoading = true
    unavailable = false
    defer { if requestID == id { requestID = nil; task = nil; isLoading = false } }
    do {
      let repository = repository
      let operation = Task { try await repository.questionOrigins(cursor: requestedCursor, limit: limit, context: incoming) }
      task = operation
      let page = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
      try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
        try Task.checkCancellation()
        try incoming.withCurrentAuthority {
          guard !self.closed, self.requestID == id, self.matches(incoming), current(incoming)
          else { throw ConversationOutboxError.staleObservation }
          if let old = self.observedAt {
            guard let previous = ConversationProtocolInstant(old), let next = ConversationProtocolInstant(page.observedAt), next >= previous
            else { throw MobileAPITransportError.invalidResponse }
          }
          if !reset {
            guard self.cursor == requestedCursor, Set(self.entries.map(\.id)).isDisjoint(with: Set(page.items.map(\.id)))
            else { throw MobileAPITransportError.invalidResponse }
            if let last = self.entries.last, let first = page.items.first {
              guard FlowMealQuestionOriginsPageSnapshot.precedes(last.intake.admittedAt, last.eventID, first.intake.admittedAt, first.eventID)
              else { throw MobileAPITransportError.invalidResponse }
            }
          }
          if let next = page.nextCursor, self.seenCursors.contains(next) || next == requestedCursor {
            throw MobileAPITransportError.invalidResponse
          }
          var pins = self.pins
          for origin in page.items {
            if let old = pins[origin.id], old != origin.pin { throw MobileAPITransportError.invalidResponse }
            pins[origin.id] = origin.pin
          }
          self.entries = reset ? page.items : self.entries + page.items
          self.pins = pins
          if let requestedCursor { self.seenCursors.insert(requestedCursor) }
          self.cursor = page.nextCursor
          self.more = page.hasMore
          self.observedAt = page.observedAt
        }
      }
    } catch {
      guard !closed, requestID == id, matches(incoming), current(incoming) else { return }
      if !(error is CancellationError) { unavailable = true }
    }
  }
  func cancel() { task?.cancel(); task = nil; requestID = nil; isLoading = false }
  func suspend() { cancel(); context = nil; entries.removeAll(); cursor = nil; more = false; unavailable = false }
  func clear() { suspend(); identity = nil; pins.removeAll(); seenCursors.removeAll(); observedAt = nil }
  func close() { clear(); closed = true }
}
