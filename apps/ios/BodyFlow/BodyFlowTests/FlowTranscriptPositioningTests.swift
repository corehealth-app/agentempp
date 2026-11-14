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
      localResultIDs: local)
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
}
