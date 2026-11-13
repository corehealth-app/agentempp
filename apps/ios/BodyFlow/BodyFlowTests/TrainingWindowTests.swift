import Foundation
import Testing

@testable import BodyFlow

@MainActor @Suite("Training Day/Week uses recorded official activity, distinct from its plan")
struct TrainingWindowTests {
  @Test func currentRecordedWorkoutAppearsInTheOfficialDayWithItsOriginalValues() throws {
    let s = try TrainingWindowFixture().snapshot()
    #expect(s.schema == "training.window.v1")
    #expect(s.days.count == 7 && s.weekStart == "2026-11-02" && s.weekEnd == "2026-11-08")
    let w = try #require(s.days[2].workouts.first)
    #expect(
      w.workoutType == "Caminhada" && w.durationMin == 30 && w.estimatedKcal == 116
        && w.intensity == "leve")
    #expect(s.days[0].workouts.isEmpty)
  }
  @Test(arguments: [
    "zone", "week", "duplicate", "wrong-day", "future-microsecond", "policy-clock",
    "negative-energy", "zero-duration", "source-version",
  ])
  func malformedOrUnqualifiedActivityCannotBecomeVisible(_ attack: String) throws {
    let f = try TrainingWindowFixture()
    var r = try f.raw()
    var days = try #require(r["days"] as? [[String: Any]])
    var workouts = try #require(days[2]["workouts"] as? [[String: Any]])
    switch attack {
    case "zone": r["timezone"] = "Invalid/Unknown"
    case "week": r["week_start"] = "2026-11-03"
    case "duplicate": workouts.append(workouts[0])
    case "wrong-day": workouts[0]["performed_at"] = "2026-11-03T14:00:00Z"
    case "future-microsecond": workouts[0]["performed_at"] = "2026-11-04T15:00:00.000002Z"
    case "policy-clock":
      var p = try #require(r["clinical_policy"] as? [String: Any])
      p["observed_at"] = "2026-11-04T15:00:01Z"
      r["clinical_policy"] = p
    case "negative-energy": workouts[0]["estimated_kcal"] = -1
    case "zero-duration": workouts[0]["duration_min"] = 0
    default: r["source_version"] = "unproved"
    }
    days[2]["workouts"] = workouts
    r["days"] = days
    #expect(throws: (any Error).self) { try f.snapshot(r) }
  }
  @Test func unknownValuesStayUnknownInsteadOfBecomingZero() throws {
    let f = try TrainingWindowFixture()
    var r = try f.raw()
    var days = try #require(r["days"] as? [[String: Any]])
    var workouts = try #require(days[2]["workouts"] as? [[String: Any]])
    for k in ["workout_type", "duration_min", "estimated_kcal", "intensity"] {
      workouts[0][k] = NSNull()
    }
    days[2]["workouts"] = workouts
    r["days"] = days
    let w = try #require(f.snapshot(r).days[2].workouts.first)
    #expect(
      w.estimatedKcal == nil && w.durationMin == nil && w.workoutType == nil && w.intensity == nil)
  }
  @Test func revisionsRefreshEditedOrUndoneActivityAndKeepTheSelectedOfficialDate() async throws {
    let f = try TrainingWindowFixture()
    let before = try f.snapshot()
    var r = try f.raw()
    var days = try #require(r["days"] as? [[String: Any]])
    days[2]["workouts"] = [] as [[String: Any]]
    r["days"] = days
    r["observed_at"] = "2026-11-04T15:00:01Z"
    r["source_version"] = String(repeating: "b", count: 64)
    let model = TrainingWindowModel(
      provider: TrainingWindowQueue([before, try f.snapshot(r)]),
      expectedAuthUserID: before.authUserID)
    await model.load(revision: 0)
    #expect(model.selectedDay?.workouts.count == 1)
    await model.load(revision: 1)
    #expect(
      model.selectedDay?.localDate == "2026-11-04" && model.selectedDay?.workouts.isEmpty == true)
  }
  @Test func lateOlderRevisionDoesNotReplaceACompletedNewerRead() async throws {
    let f = try TrainingWindowFixture()
    let old = try f.snapshot()
    var r = try f.raw()
    r["observed_at"] = "2026-11-04T15:00:01Z"
    r["source_version"] = String(repeating: "b", count: 64)
    let newer = try f.snapshot(r)
    let barrier = ConversationControllerBarrier()
    let model = TrainingWindowModel(
      provider: TrainingWindowBlocked(old: old, newer: newer, barrier: barrier),
      expectedAuthUserID: old.authUserID)
    let first = Task { await model.load(revision: 0) }
    #expect(await barrier.waitEnteredOrFinished())
    await model.load(revision: 1)
    await barrier.release()
    await first.value
    #expect(model.snapshot?.sourceVersion == newer.sourceVersion)
  }
  @Test func accountInvalidationHidesPreviouslyDisplayedActivityImmediately() async throws {
    let s = try TrainingWindowFixture().snapshot()
    let scope = TrainingWindowActiveScope()
    let m = TrainingWindowModel(
      provider: TrainingWindowQueue([s]), expectedAuthUserID: s.authUserID,
      isCurrent: { scope.active })
    await m.load(revision: 0)
    #expect(m.snapshot != nil)
    scope.active = false
    #expect(m.snapshot == nil && m.phase == .unavailable)
  }
  @Test func actualShellOwnerReleasesTrainingAndRefusesEveryReadAfterLogout() async throws {
    let f = try TrainingWindowFixture()
    let snapshot = try f.snapshot()
    let dependencies = AppDependencies.scaffold()
    let provider = TrainingWindowQueue([snapshot])
    let bundle = CurrentClinicalReaderSession(
      userID: snapshot.authUserID.uuidString.lowercased(), today: dependencies.today,
      history: dependencies.history, plan: dependencies.plan, progress: dependencies.progress,
      me: dependencies.me, currentObjective: TrainingNoObjective(), training: provider)
    let owner = Prompt14SessionOwner(
      userID: bundle.userID, dependencies: dependencies, readerSession: bundle)
    #expect(
      try await owner.training.trainingWindow(date: nil).sourceVersion == snapshot.sourceVersion)
    await owner.endSession()
    #expect(owner.isInvalidated && !owner.hasRetainedCapabilities)
    await #expect(throws: CancellationError.self) {
      try await owner.training.trainingWindow(date: nil)
    }
  }
  @Test func originalSessionTransportUsesClosedGETAndRefusesAReplacedLogin() async throws {
    let f = try TrainingWindowFixture()
    let s = try f.snapshot()
    let life = ConversationHTTPTestLifecycle()
    await life.replace(
      .init(
        userID: s.authUserID.uuidString.lowercased(), generation: 7, bearer: "synthetic-training"))
    let http = try ConversationHTTPFixture(lifecycle: life)
    let body = try f.envelope()
    await http.stub.respond { _, _ in .init(status: 200, body: body) }
    let p = try await MobileTrainingWindowRepository.scoped(
      transport: http.transport, lifecycle: life, lease: await life.leaseForRequest())
    #expect(try await p.trainingWindow(date: "2026-11-04").sourceVersion == s.sourceVersion)
    let request = try #require(await http.stub.requests.first)
    #expect(
      request.httpMethod == "GET" && request.httpBody == nil
        && request.url?.path == "/api/mobile/v1/training/window")
    let u = try #require(request.url)
    let q = try #require(URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(Set(q.map(\.name)) == ["date", "clinical_policy"])
    await life.replace(
      .init(userID: s.authUserID.uuidString.lowercased(), generation: 8, bearer: "replacement"))
    let count = await http.stub.requests.count
    await #expect(throws: (any Error).self) {
      try await p.rebindTrainingWindow(.init(s), date: nil)
    }
    #expect(await http.stub.requests.count == count)
  }
}
struct TrainingWindowFixture {
  let data: Data
  init() throws {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "TrainingWindowControlledFixture", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/TrainingWindowControlledFixture.json")
    #endif
    data = try Data(contentsOf: url)
  }
  func raw() throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  func snapshot(_ raw: [String: Any]? = nil) throws -> TrainingWindowSnapshot {
    try .init(data: raw.map { try JSONSerialization.data(withJSONObject: $0) } ?? data)
  }
  func envelope() throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "data": try raw(), "meta": ["api_version": "v1", "request_id": "controlled-training"],
    ])
  }
}
actor TrainingWindowQueue: TrainingWindowProviding {
  var values: [TrainingWindowSnapshot]
  init(_ values: [TrainingWindowSnapshot]) { self.values = values }
  func trainingWindow(date: String?) async throws -> TrainingWindowSnapshot {
    guard !values.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
    return values.removeFirst()
  }
}
actor TrainingWindowBlocked: TrainingWindowProviding {
  let old: TrainingWindowSnapshot, newer: TrainingWindowSnapshot
  let barrier: ConversationControllerBarrier
  var count = 0
  init(
    old: TrainingWindowSnapshot, newer: TrainingWindowSnapshot,
    barrier: ConversationControllerBarrier
  ) {
    self.old = old
    self.newer = newer
    self.barrier = barrier
  }
  func trainingWindow(date: String?) async throws -> TrainingWindowSnapshot {
    count += 1
    if count == 1 {
      await barrier.enter()
      return old
    }
    return newer
  }
}
@MainActor final class TrainingWindowActiveScope { var active = true }

private struct TrainingNoObjective: CurrentObjectiveProviding {
  func currentObjective() async throws -> CurrentObjectiveSnapshot {
    throw BodyFlowCapabilityError.serviceUnavailable
  }
}
