import Foundation

/// View-local positioning only; never changes conversation or dispatch state.
struct FlowTranscriptPositioning {
  enum ResultID: Hashable {
    case intake(UUID)
    case command(UUID)
    case reply(parent: UUID, reply: UUID)
  }
  struct Observation: Equatable {
    let owner: ObjectIdentifier
    let historyIDs: [String]
    let historyLoading: Bool
    let localResultIDs: [ResultID]
    var historicalAnchors: [ResultID: String] = [:]
  }

  private var owner: ObjectIdentifier?
  private var initiallyPositioned = false
  private var seenLocalResults: Set<ResultID> = []
  private var awaitingHistoryResult: ResultID?

  static func intakeAnchor(_ id: UUID) -> String {
    "intake/" + id.uuidString.lowercased()
  }

  static func historicalAnchors(
    unified: [ConversationJournalV3PageSnapshot.Entry] = [],
    journal: [ConversationJournalPageSnapshot.Entry] = [],
    threads: [ConversationThreadPageSnapshot.Entry] = []
  ) -> [ResultID: String] {
    var anchors: [ResultID: String] = [:]
    func keep(_ id: ResultID, _ eventID: String) {
      if anchors[id] == nil { anchors[id] = eventID }
    }
    // Pages are newest first. A response may have both a result and a
    // fulfillment; prefer its newest factual response, never its input/edit.
    for entry in unified {
      switch entry.kind {
      case .intake:
        if let id = entry.intakeID { keep(.intake(id), entry.eventID) }
      case .report:
        if let id = entry.commandID { keep(.command(id), entry.eventID) }
      case .replyResult, .fulfillment:
        if let parent = entry.parentCommandID, let reply = entry.commandID {
          keep(.reply(parent: parent, reply: reply), entry.eventID)
        }
      case .workout, .reply, .edit: break
      }
    }
    for entry in journal {
      if case .command(let command) = entry {
        keep(.command(command.originalCommand.commandID), entry.eventID)
      }
    }
    for entry in threads {
      switch entry.detail {
      case .report: keep(.command(entry.threadID), entry.eventID)
      case .replyResult, .fulfillment:
        if let child = entry.childBinding {
          keep(.reply(parent: entry.threadID, reply: child.commandID), entry.eventID)
        }
      case .reply, .edit: break
      }
    }
    return anchors
  }

  static func localAnchor(_ id: ResultID) -> String {
    switch id {
    case .intake(let value): intakeAnchor(value)
    case .command(let value): "local-command/" + value.uuidString.lowercased()
    case .reply(let parent, let reply):
      "local-reply/" + parent.uuidString.lowercased() + "/" + reply.uuidString.lowercased()
    }
  }

  private func historicalAnchor(_ id: ResultID, in observation: Observation) -> String? {
    let anchor = observation.historicalAnchors[id] ?? Self.localAnchor(id)
    return observation.historyIDs.contains(anchor) ? anchor : nil
  }

  mutating func observe(_ observation: Observation) -> String? {
    if owner != observation.owner {
      owner = observation.owner
      initiallyPositioned = false
      seenLocalResults = Set(observation.localResultIDs)
      awaitingHistoryResult = nil
    }

    let newResults = observation.localResultIDs.filter { !seenLocalResults.contains($0) }
    seenLocalResults.formUnion(observation.localResultIDs)
    if let latest = newResults.last {
      initiallyPositioned = true
      let historical = historicalAnchor(latest, in: observation)
      awaitingHistoryResult = historical == nil ? latest : nil
      return historical ?? Self.localAnchor(latest)
    }

    // A RAM acknowledgement can be replaced by a differently named historical
    // card. Follow its observed event once, unless the person moved.
    if let result = awaitingHistoryResult,
      let anchor = historicalAnchor(result, in: observation)
    {
      awaitingHistoryResult = nil
      return anchor
    }

    guard !initiallyPositioned, !observation.historyLoading else { return nil }
    let initial =
      observation.historyIDs.first
      ?? observation.localResultIDs.last.map(Self.localAnchor)
    if initial != nil { initiallyPositioned = true }
    return initial
  }

  mutating func userScrolled() {
    initiallyPositioned = true
    awaitingHistoryResult = nil
  }
}
