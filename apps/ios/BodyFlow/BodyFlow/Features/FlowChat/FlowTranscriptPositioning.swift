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
    var activeSendID: UUID? = nil
    var opening = false
  }

  static let latestAnchor = "conversation.latest"
  private var owner: ObjectIdentifier?
  private var initiallyPositioned = false
  private var seenLocalResults: Set<ResultID> = []
  private var awaitingHistoryResult: ResultID?
  private var awaitingSendHistory: ResultID?
  private var activeSendID: UUID?
  private var followedSend = false
  private var readingEarlier = false
  private var userIsMoving = false
  var followsSendingMessage: Bool { activeSendID != nil && followedSend }

  static func intakeAnchor(_ id: UUID) -> String {
    "intake/" + id.uuidString.lowercased()
  }

  static func canAppendTerminal(admittedAt: String?, oldestVisibleAt: String?) -> Bool {
    guard let admittedAt, let oldestVisibleAt,
      let admission = ConversationProtocolInstant(admittedAt),
      let oldest = ConversationProtocolInstant(oldestVisibleAt)
    else { return true }
    return admission >= oldest
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
      awaitingSendHistory = nil
      activeSendID = nil
      followedSend = false
      readingEarlier = false
      userIsMoving = false
    }

    let newResults = observation.localResultIDs.filter { !seenLocalResults.contains($0) }
    seenLocalResults.formUnion(observation.localResultIDs)
    guard !observation.opening else { return nil }
    if let sending = observation.activeSendID {
      guard activeSendID != sending else { return nil }
      activeSendID = sending
      followedSend = !readingEarlier
      initiallyPositioned = true
      awaitingHistoryResult = nil
      awaitingSendHistory = nil
      return followedSend ? Self.latestAnchor : nil
    }
    if let sent = activeSendID {
      activeSendID = nil
      guard followedSend else { return nil }
      let result = ResultID.intake(sent)
      awaitingSendHistory = historicalAnchor(result, in: observation) == nil ? result : nil
      return Self.latestAnchor
    }
    if let result = awaitingSendHistory,
      historicalAnchor(result, in: observation) != nil
    {
      awaitingSendHistory = nil
      return Self.latestAnchor
    }
    if !readingEarlier, let latest = newResults.last {
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
    guard !observation.historyIDs.isEmpty || !observation.localResultIDs.isEmpty else { return nil }
    initiallyPositioned = true
    return Self.latestAnchor
  }

  mutating func userScrolled() {
    initiallyPositioned = true
    userIsMoving = true
    readingEarlier = true
    awaitingHistoryResult = nil
    awaitingSendHistory = nil
    followedSend = false
  }

  /// Only a completed manual move can opt back into following the newest turn.
  mutating func userScrollSettled(atLatest: Bool) -> Bool {
    guard userIsMoving else { return false }
    userIsMoving = false
    readingEarlier = !atLatest
    if atLatest && activeSendID != nil { followedSend = true }
    return atLatest
  }
}
