import Foundation

/// View-local positioning only; never changes conversation or dispatch state.
struct FlowTranscriptPositioning {
  struct Observation: Equatable {
    let owner: ObjectIdentifier
    let historyIDs: [String]
    let historyLoading: Bool
    let localResultIDs: [UUID]
  }

  private var owner: ObjectIdentifier?
  private var initiallyPositioned = false
  private var seenLocalResults: Set<UUID> = []
  private var awaitingHistoryAnchor: String?

  static func intakeAnchor(_ id: UUID) -> String {
    "intake/" + id.uuidString.lowercased()
  }

  mutating func observe(_ observation: Observation) -> String? {
    if owner != observation.owner {
      owner = observation.owner
      initiallyPositioned = false
      seenLocalResults = Set(observation.localResultIDs)
      awaitingHistoryAnchor = nil
    }

    let newResults = observation.localResultIDs.filter { !seenLocalResults.contains($0) }
    seenLocalResults.formUnion(observation.localResultIDs)
    if let latest = newResults.last {
      let anchor = Self.intakeAnchor(latest)
      initiallyPositioned = true
      awaitingHistoryAnchor = observation.historyIDs.contains(anchor) ? nil : anchor
      return anchor
    }

    // A RAM acknowledgement is replaced by its historical card using the
    // same identity. Follow that replacement once, unless the person moved.
    if let anchor = awaitingHistoryAnchor, observation.historyIDs.contains(anchor) {
      awaitingHistoryAnchor = nil
      return anchor
    }

    guard !initiallyPositioned, !observation.historyLoading else { return nil }
    let initial =
      observation.historyIDs.first
      ?? observation.localResultIDs.last.map(Self.intakeAnchor)
    if initial != nil { initiallyPositioned = true }
    return initial
  }

  mutating func userScrolled() {
    initiallyPositioned = true
    awaitingHistoryAnchor = nil
  }
}
