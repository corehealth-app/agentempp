import Foundation
import Testing

@testable import BodyFlow

@Suite("Flow transcript position without stealing older reading")
struct FlowTranscriptPositioningTests {
  private final class Owner {}
  private let first = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  private let second = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
  private func snapshot(
    _ owner: Owner, history: [String] = [], loading: Bool = false,
    local: [UUID] = []
  ) -> FlowTranscriptPositioning.Observation {
    .init(
      owner: ObjectIdentifier(owner), historyIDs: history, historyLoading: loading,
      localResultIDs: local.map(FlowTranscriptPositioning.ResultID.intake))
  }
  private func intake(_ id: UUID) -> String { "intake/" + id.uuidString.lowercased() }

  @Test func initialHistoryPositionsNewestOnlyAfterItsPageSettles() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    #expect(policy.observe(snapshot(owner)) == nil)
    #expect(policy.observe(snapshot(owner, history: ["new", "old"], loading: true)) == nil)
    #expect(policy.observe(snapshot(owner, history: ["new", "old"])) == "new")
    #expect(policy.observe(snapshot(owner, history: ["new", "old"])) == nil)
  }
  @Test func olderPaginationAndNewRemoteHistoryDoNotMoveTheReader() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    #expect(policy.observe(snapshot(owner, history: ["new"])) == "new")
    #expect(policy.observe(snapshot(owner, history: ["new", "older", "oldest"])) == nil)
    #expect(policy.observe(snapshot(owner, history: ["remote", "new", "older"])) == nil)
  }
  @Test func ownNewResultIsFocusedAndItsHistoryReplacementKeepsTheSameAnchor() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    _ = policy.observe(snapshot(owner, history: ["old"]))
    #expect(policy.observe(snapshot(owner, history: ["old"], local: [first])) == intake(first))
    #expect(
      policy.observe(snapshot(owner, history: [intake(first), "old"], local: [first]))
        == intake(first))
    #expect(
      policy.observe(snapshot(owner, history: [intake(first), "old"], local: [first])) == nil)
  }
  @Test func visibilitySuspendAndRefreshDoNotRefocusAnAlreadySeenLocalResult() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    _ = policy.observe(snapshot(owner, history: ["old"]))
    _ = policy.observe(snapshot(owner, history: [intake(first)], local: [first]))
    #expect(policy.observe(snapshot(owner, loading: true)) == nil)
    #expect(policy.observe(snapshot(owner, history: [intake(first)], local: [first])) == nil)
  }
  @Test func userReadingCancelsDelayedMigrationButANewOwnResponseStillFocuses() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    _ = policy.observe(snapshot(owner, history: ["old"]))
    _ = policy.observe(snapshot(owner, history: ["old"], local: [first]))
    policy.userScrolled()
    #expect(policy.observe(snapshot(owner, history: [intake(first)], local: [first])) == nil)
    #expect(
      policy.observe(snapshot(owner, history: [intake(first)], local: [first, second]))
        == intake(second))
  }
  @Test func readingBeforeInitialPageArrivesPreventsTheInitialJump() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    _ = policy.observe(snapshot(owner, loading: true))
    policy.userScrolled()
    #expect(policy.observe(snapshot(owner, history: ["new", "old"])) == nil)
  }
  @Test func ownerReplacementResetsOnlyViewPositionAndIgnoresPreviousLocalIDs() {
    let a = Owner()
    let b = Owner()
    var policy = FlowTranscriptPositioning()
    _ = policy.observe(snapshot(a, history: ["a"], local: [first]))
    #expect(policy.observe(snapshot(b, history: ["b"], local: [first])) == "b")
    #expect(policy.observe(snapshot(b, history: ["b"], local: [first])) == nil)
  }
  @Test func existingLocalResultCanBeShownWhenHistoryIsUnavailable() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    #expect(policy.observe(snapshot(owner, local: [first])) == intake(first))
    #expect(policy.observe(snapshot(owner, local: [first])) == nil)
  }
  @Test func alreadyMigratedNewResultDoesNotScheduleASecondJump() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    _ = policy.observe(snapshot(owner, history: ["old"]))
    #expect(
      policy.observe(snapshot(owner, history: [intake(first)], local: [first])) == intake(first))
    #expect(
      policy.observe(snapshot(owner, history: [intake(first), "old"], local: [first])) == nil)
  }

  @Test func commandAcknowledgementUsesItsOwnAnchorAndThenTheActualHistoricalEventID() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    _ = policy.observe(snapshot(owner, history: ["old"]))
    let id = FlowTranscriptPositioning.ResultID.command(first)
    var observation = FlowTranscriptPositioning.Observation(
      owner: ObjectIdentifier(owner), historyIDs: ["old"], historyLoading: false,
      localResultIDs: [id])
    #expect(policy.observe(observation) == "local-command/" + first.uuidString.lowercased())
    observation = .init(
      owner: ObjectIdentifier(owner), historyIDs: ["actual-command-event", "old"],
      historyLoading: false, localResultIDs: [])
    observation.historicalAnchors[id] = "actual-command-event"
    #expect(policy.observe(observation) == "actual-command-event")
    #expect(policy.observe(observation) == nil)
  }

  @Test func replyUsesTheWholeParentReplyIdentityAndSurvivesLocalCardRemoval() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    _ = policy.observe(snapshot(owner, history: ["old"]))
    let id = FlowTranscriptPositioning.ResultID.reply(parent: first, reply: second)
    var observation = FlowTranscriptPositioning.Observation(
      owner: ObjectIdentifier(owner), historyIDs: ["old"], historyLoading: false,
      localResultIDs: [id])
    #expect(
      policy.observe(observation) == "local-reply/" + first.uuidString.lowercased()
        + "/" + second.uuidString.lowercased())
    observation = .init(
      owner: ObjectIdentifier(owner), historyIDs: ["observed-fulfillment"],
      historyLoading: false, localResultIDs: [])
    observation.historicalAnchors[id] = "observed-fulfillment"
    #expect(policy.observe(observation) == "observed-fulfillment")
    #expect(policy.observe(observation) == nil)
  }

  @Test func equalUUIDsInDifferentLanesAreStillDifferentResultsAndManualReadingWins() {
    let owner = Owner()
    var policy = FlowTranscriptPositioning()
    _ = policy.observe(snapshot(owner, history: ["old"]))
    _ = policy.observe(snapshot(owner, history: ["old"], local: [first]))
    let command = FlowTranscriptPositioning.ResultID.command(first)
    var observation = FlowTranscriptPositioning.Observation(
      owner: ObjectIdentifier(owner), historyIDs: ["old"], historyLoading: false,
      localResultIDs: [.intake(first), command])
    #expect(policy.observe(observation) == "local-command/" + first.uuidString.lowercased())
    policy.userScrolled()
    observation = .init(
      owner: ObjectIdentifier(owner), historyIDs: ["command-history"],
      historyLoading: false, localResultIDs: [])
    observation.historicalAnchors[command] = "command-history"
    #expect(policy.observe(observation) == nil)
  }
  @Test func historicalProjectionUsesFactualResponseNotUserReplyOrLaterEdit() throws {
    let parent = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
    let reply = UUID(uuidString: "10000000-0000-4000-8000-000000000041")!
    let pages = try publicJournalV3Pages()
    let unified = try JSONDecoder().decode(
      ConversationJournalV3PageSnapshot.self,
      from: JSONSerialization.data(withJSONObject: pages[5]))
    let expected =
      "fulfillment/" + parent.uuidString.lowercased() + "/" + reply.uuidString.lowercased()
    let map = FlowTranscriptPositioning.historicalAnchors(unified: unified.items)
    #expect(map[.reply(parent: parent, reply: reply)] == expected)
    #expect(map[.command(parent)] == "command/" + parent.uuidString.lowercased())
    #expect(map.count == 2)
    let inputsOnly = unified.items.filter { $0.kind == .reply || $0.kind == .edit }
    #expect(FlowTranscriptPositioning.historicalAnchors(unified: inputsOnly).isEmpty)

    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures")
    let raw =
      try JSONSerialization.jsonObject(
        with: Data(
          contentsOf: fixtures.appendingPathComponent(
            "ConversationThreadPagePublicFixtures.json"))) as! [String: Any]
    let thread = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.self,
      from: JSONSerialization.data(withJSONObject: raw["data"]!))
    let threadMap = FlowTranscriptPositioning.historicalAnchors(threads: thread.items)
    #expect(threadMap[.reply(parent: parent, reply: reply)] == expected)
    #expect(threadMap[.command(parent)] == "command/" + parent.uuidString.lowercased())
    #expect(threadMap.count == 2)

    let journalRaw =
      try JSONSerialization.jsonObject(
        with: Data(
          contentsOf: fixtures.appendingPathComponent(
            "ConversationJournalPublicFixtures.json"))) as! [String: Any]
    let journal = try JSONDecoder().decode(
      ConversationJournalPageSnapshot.self,
      from: JSONSerialization.data(withJSONObject: journalRaw["data"]!))
    let journalMap = FlowTranscriptPositioning.historicalAnchors(journal: journal.items)
    #expect(journalMap[.command(parent)] == "command/" + parent.uuidString.lowercased())
    #expect(journalMap.count == 3)
  }

}
