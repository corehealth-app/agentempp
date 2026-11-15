import Foundation
import Testing

@testable import BodyFlow

@Suite("Completion keeps original progress receipts and actual performed activity distinct")
struct TrainingExecutionCompletionContractTests {
  @Test func actualServerReceiptCompletesOnceWithoutInventingPrescribedSets() throws {
    let f = try TrainingCompletionFixture()
    let value = try TrainingExecutionCompletionSnapshot(data: f.data("completed_completion"))
    let operation = try f.finish()
    try value.validate(for: operation)
    #expect(
      operation.inputHash == "8d547e156d3fe54c7d9621578ab8b0fc195f1ed9d9ab558fbd76d3dc1ef90c97")
    #expect(value.status == .completed && value.session?.phase == .completed)
    #expect(value.session?.revision == 2)
    #expect(value.session?.exercises[0].sets.count == 1)
    #expect(value.session?.exercises[1].sets.isEmpty == true)
    #expect(value.session?.exercises.allSatisfy { !$0.completed } == true)
    #expect(value.workout?.durationMin == 30 && value.workout?.estimatedKcal == 223)
    #expect(value.workout?.registrationID == operation.operationID)
    #expect(value.feedback?.sections.count == 6)
  }
  @Test func reservationIsNotACompletedWorkoutAndOldV1DecodersStayStrict() throws {
    let f = try TrainingCompletionFixture()
    let reserved = try TrainingExecutionCompletionSnapshot(data: f.data("reserved_completion"))
    try reserved.validate(for: f.finish())
    #expect(reserved.status == .reserved && reserved.receipt == nil && reserved.workout == nil)
    #expect(reserved.session?.phase == .inProgress)
    let root = try f.object("completed_completion")
    #expect(throws: (any Error).self) {
      try TrainingExecutionSession(
        TrainingExecutionJSON(
          data: JSONSerialization.data(withJSONObject: #require(root["session"]))))
    }
  }
  @Test func coldStateAndHistoryIncludeCompletedFactsInsteadOfReconstructingThePlan() throws {
    let f = try TrainingCompletionFixture()
    let state = try TrainingExecutionCurrentV2Snapshot(data: f.data("state_completed"))
    let home = try TrainingExecutionHomeV2Snapshot(data: f.data("home_completed"))
    #expect(state.session.phase == .completed && state.completion?.status == .completed)
    #expect(home.sessions.count == 1 && home.sessions[0].phase == .completed)
    #expect(home.sessions[0].base.completedExercises == 0)
    #expect(home.sessions[0].completion?.id == state.completion?.completionID)
    #expect(state.session.exercises[0].sets[0].loadKg == 15.5)
  }
  @Test func oldProgressACKKeepsNewCompletedStateAndIsNotACompletionACK() throws {
    let f = try TrainingCompletionFixture()
    let value = try TrainingExecutionProgressV2Snapshot(data: f.data("progress_replay_completed"))
    let operation = try f.operation("save")
    try value.validate(for: operation)
    #expect(value.status == .replayed && value.receipt?.afterRevision == 1)
    #expect(value.current?.session.revision == 2 && value.current?.session.phase == .completed)
    #expect(throws: (any Error).self) { try value.validate(for: f.finish()) }
  }
  @Test
  func
    cancellableReservationKeepsUncertainWorkPendingWhileTerminalAbsenceCanResolveOnlyThatExactOperation()
    throws
  {
    let f = try TrainingCompletionFixture()
    let operation = try f.operation("waiting")
    let pending = try TrainingExecutionProgressV2Snapshot(data: f.data("progress_pending"))
    try pending.validate(for: operation)
    #expect(pending.status == .pending && pending.receipt == nil)
    let terminal = try TrainingExecutionProgressV2Snapshot(data: f.data("progress_not_applied"))
    try terminal.validate(for: operation)
    #expect(
      terminal.status == .notApplied && terminal.receipt == nil
        && terminal.current?.session.phase == .completed)
    #expect(throws: (any Error).self) { try terminal.validate(for: f.operation("save")) }
  }
  @Test(arguments: [
    "owner", "auth", "epoch", "revision", "hash", "workout", "session", "future", "private-field",
  ])
  func mixedOrUnprovedCompletionCannotAcknowledgePendingWork(_ attack: String) throws {
    let f = try TrainingCompletionFixture()
    var root = try f.object("completed_completion")
    var receipt = try #require(root["receipt"] as? [String: Any])
    switch attack {
    case "owner": root["owner_id"] = UUID().uuidString.lowercased()
    case "auth": root["auth_user_id"] = UUID().uuidString.lowercased()
    case "epoch": receipt["epoch"] = UUID().uuidString.lowercased()
    case "revision": receipt["after_revision"] = 3
    case "hash": receipt["input_hash"] = String(repeating: "a", count: 64)
    case "workout":
      var workout = try #require(root["workout"] as? [String: Any])
      workout["registration_id"] = UUID().uuidString.lowercased()
      root["workout"] = workout
    case "session":
      var session = try #require(root["session"] as? [String: Any])
      session["phase"] = "in_progress"
      root["session"] = session
    case "future": receipt["at"] = "2099-01-01T00:00:00.000000Z"
    default: root["frozen_state"] = ["clinical": "never publish"]
    }
    root["receipt"] = receipt
    #expect(throws: (any Error).self) {
      try TrainingExecutionCompletionSnapshot(data: JSONSerialization.data(withJSONObject: root))
        .validate(for: f.finish())
    }
  }
  @Test func malformedOptionalEducationCannotInvalidateAnOfficialReceipt() throws {
    let f = try TrainingCompletionFixture()
    var root = try f.object("completed_completion")
    root["feedback"] = ["untrusted": "not a validated presentation"]
    let value = try TrainingExecutionCompletionSnapshot(
      data: JSONSerialization.data(withJSONObject: root))
    try value.validate(for: f.finish())
    #expect(value.status == .completed && value.feedback == nil)
  }
}
struct TrainingCompletionFixture {
  let root: [String: Any]
  init() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
      "Fixtures/TrainingCompletionControlledFixture.json")
    root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }
  func data(_ key: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: #require(root[key]))
  }
  func object(_ key: String) throws -> [String: Any] { try #require(root[key] as? [String: Any]) }
  func operation(_ key: String) throws -> TrainingExecutionOperation {
    let scope = try TrainingExecutionScope(
      TrainingExecutionJSON(data: data("completed_completion")).object([
        "schema", "status", "owner_id", "auth_user_id", "epoch", "session_id", "completion_id",
        "input_hash", "before_revision", "scope", "session", "receipt", "workout", "workout_state",
        "feedback", "decision",
      ]).field("scope"))
    let commands = try object("commands")
    return try .init(
      binding: .init(scope),
      wireBody: JSONSerialization.data(withJSONObject: #require(commands[key])))
  }
  func finish() throws -> TrainingExecutionOperation { try operation("finish") }
}

extension TrainingExecutionCompletionContractTests {
  @Test func cancelledBeforeAnyEffectIsAProvedTerminalReceiptButNotAWorkout() throws {
    let f = try TrainingCompletionFixture()
    let value = try TrainingExecutionCompletionSnapshot(data: f.data("cancelled_before_effect"))
    try value.validate(for: f.operation("cancelFinish"))
    #expect(value.status == .cancelled && value.receipt?.kind == .cancelled)
    #expect(value.workout == nil && value.session == nil && value.feedback == nil)
    let current = try TrainingExecutionCurrentV2Snapshot(data: f.data("cancelled_current"))
    #expect(current.session.phase == .inProgress && current.completion == nil)
  }
  @Test func completionTransportPinsPathBodyKeyEpochAndProtocolWithoutRefresh() throws {
    let f = try TrainingCompletionFixture()
    let operation = try f.finish()
    let identity = try TrainingExecutionCompletionIdentity(operation: operation)
    let cap = MobileTrainingExecutionRequestHeaders.finish(operation)
    let path = "/api/mobile/v1/training/execution-v2/completions"
    try cap.validate(
      method: .post, path: path, query: [], body: operation.wireBody,
      key: IdempotencyKey(validating: operation.idempotencyKey), replay: .never)
    for bad in ["/api/mobile/v1/training/execution/commands", "/api/mobile/v1/workouts"] {
      #expect(throws: (any Error).self) {
        try cap.validate(
          method: .post, path: bad, query: [], body: operation.wireBody,
          key: IdempotencyKey(validating: operation.idempotencyKey), replay: .never)
      }
    }
    #expect(throws: (any Error).self) {
      try cap.validate(
        method: .post, path: path, query: [], body: operation.wireBody,
        key: IdempotencyKey(validating: operation.idempotencyKey), replay: .standard)
    }
    var request = URLRequest(url: URL(string: "https://example.invalid" + path)!)
    cap.apply(to: &request)
    #expect(
      request.value(forHTTPHeaderField: "X-Training-Epoch")
        == operation.binding.epoch.uuidString.lowercased())
    let good = HTTPURLResponse(
      url: request.url!, statusCode: 202, httpVersion: nil,
      headerFields: [
        "X-Training-Execution": "2", "X-Training-Completion": "1", "Cache-Control": "no-store",
      ])!
    try cap.validateResponseProtocol(good)
    #expect(throws: (any Error).self) {
      try MobileTrainingExecutionRequestHeaders.mutation(try f.operation("save"))
        .validateResponseProtocol(good)
    }
    #expect(throws: (any Error).self) {
      try MobileTrainingExecutionRequestHeaders.progressV2(try f.operation("save"))
        .validateResponseProtocol(good)
    }
    let read = MobileTrainingExecutionRequestHeaders.completionRead(identity)
    try read.validate(
      method: .get,
      path: "/api/mobile/v1/training/execution-v2/" + identity.sessionID.uuidString.lowercased()
        + "/completions/" + identity.completionID.uuidString.lowercased(), query: [], body: nil,
      key: nil, replay: .never)
    let cancel = MobileTrainingExecutionRequestHeaders.completionCancel(identity)
    try cancel.validate(
      method: .post,
      path: "/api/mobile/v1/training/execution-v2/" + identity.sessionID.uuidString.lowercased()
        + "/completions/" + identity.completionID.uuidString.lowercased() + "/cancel", query: [],
      body: identity.cancelBody,
      key: IdempotencyKey(validating: "tcancel1:" + identity.completionID.uuidString.lowercased()),
      replay: .never)
    #expect(throws: (any Error).self) {
      try cancel.validate(
        method: .post, path: path, query: [], body: operation.wireBody,
        key: IdempotencyKey(validating: operation.idempotencyKey), replay: .never)
    }
  }
}
