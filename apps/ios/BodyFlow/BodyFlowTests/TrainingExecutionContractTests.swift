import Foundation
import Testing

@testable import BodyFlow

@Suite("Persistent training preserves official prescriptions and actual execution")
struct TrainingExecutionContractTests {
  @Test func recommendedSeriesNeverBecomeActualSetsByDecodingOrReopening() throws {
    let f = try TrainingExecutionFixture()
    let home = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let created = try TrainingExecutionMutationSnapshot(data: f.data("created"))
    #expect(home.plan?.days[0].exercises[0].recommendedSets == 3)
    #expect(home.plan?.days[0].exercises[1].recommendedSets == 2)
    #expect(created.session.exercises.count == 2)
    #expect(created.session.exercises.allSatisfy { $0.sets.isEmpty && !$0.completed })
    let reopened = try TrainingExecutionReadSnapshot(data: f.data("read"))
    #expect(reopened.session.revision == 1)
    #expect(reopened.session.exercises[0].sets.first?.loadKg == 15.5)
    #expect(reopened.session.exercises[1].sets.isEmpty)
    #expect(reopened.session.definition.exercises[0].fingerprint != reopened.session.definition.exercises[1].fingerprint)
  }

  @Test func zeroLoadAndUnknownRepetitionsRemainDifferentFacts() throws {
    let f = try TrainingExecutionFixture()
    var r = try f.object("read")
    var session = try #require(r["session"] as? [String: Any])
    var exercises = try #require(session["exercises"] as? [[String: Any]])
    var sets = try #require(exercises[0]["sets"] as? [[String: Any]])
    sets[0]["load_kg"] = 0
    sets[0]["repetitions"] = NSNull()
    exercises[0]["sets"] = sets
    session["exercises"] = exercises
    r["session"] = session
    let value = try TrainingExecutionReadSnapshot(data: JSONSerialization.data(withJSONObject: r))
    #expect(value.session.exercises[0].sets[0].loadKg == 0)
    #expect(value.session.exercises[0].sets[0].repetitions == nil)
  }

  @Test(arguments: ["foreign-owner", "epoch", "zone", "future-clock", "ordinal", "duplicate-set", "negative-load", "missing-null", "unknown-calories"])
  func malformedOrMixedExecutionCannotBePresented(_ kind: String) throws {
    let f = try TrainingExecutionFixture()
    var root = try f.object("read")
    var session = try #require(root["session"] as? [String: Any])
    var exercises = try #require(session["exercises"] as? [[String: Any]])
    var sets = try #require(exercises[0]["sets"] as? [[String: Any]])
    switch kind {
    case "foreign-owner": session["owner_id"] = "13700000-0000-4000-8000-000000000099"
    case "epoch": session["epoch"] = "13700000-0000-4000-8000-000000000099"
    case "zone": session["time_zone"] = "America/New_York"
    case "future-clock": session["updated_at"] = "2026-11-14T20:00:02.000001Z"
    case "ordinal": exercises[0]["index"] = 1
    case "duplicate-set": exercises[1]["sets"] = sets
    case "negative-load": sets[0]["load_kg"] = -1
    case "missing-null": sets[0].removeValue(forKey: "duration_seconds")
    default: session["calories"] = 900
    }
    exercises[0]["sets"] = sets
    session["exercises"] = exercises
    root["session"] = session
    #expect(throws: (any Error).self) {
      try TrainingExecutionReadSnapshot(data: JSONSerialization.data(withJSONObject: root))
    }
  }

  @Test func immutableOperationUsesServerCompatibleHashAndOriginalIdentity() throws {
    let f = try TrainingExecutionFixture()
    let h = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let values = try #require(f.root["numericHashes"] as? [[String: Any]])
    for value in values {
      let bytes = try JSONSerialization.data(withJSONObject: #require(value["command"]))
      let operation = try TrainingExecutionOperation(binding: .init(h.scope), wireBody: bytes)
      #expect(operation.inputHash == value["hash"] as? String)
      #expect(operation.idempotencyKey == "texecution1:\(operation.operationID.uuidString.lowercased())")
      #expect(operation.binding.ownerID == h.scope.ownerID)
      #expect(operation.binding.authUserID == h.scope.authUserID)
    }
  }

  @Test func replayReceiptDoesNotRestoreTheStateBeforeAbandonment() throws {
    let f = try TrainingExecutionFixture()
    let home = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let command = try TrainingExecutionOperation(binding: .init(home.scope), wireBody: f.command("save"))
    let replay = try TrainingExecutionMutationSnapshot(data: f.data("replay"))
    try replay.validate(for: command)
    #expect(replay.status == .replayed)
    #expect(replay.receipt.afterRevision == 1)
    #expect(replay.session.revision == 2 && replay.session.phase == .abandoned)
    var bad = try f.object("replay")
    var receipt = try #require(bad["receipt"] as? [String: Any])
    receipt["operation_id"] = "13700000-0000-4000-8000-000000000099"
    bad["receipt"] = receipt
    #expect(throws: (any Error).self) {
      try TrainingExecutionMutationSnapshot(data: JSONSerialization.data(withJSONObject: bad)).validate(for: command)
    }
  }
}

struct TrainingExecutionFixture {
  let root: [String: Any]
  init() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/TrainingExecutionControlledFixture.json")
    root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }
  func data(_ name: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: #require(root[name]))
  }
  func object(_ name: String) throws -> [String: Any] {
    try #require(root[name] as? [String: Any])
  }
  func command(_ name: String) throws -> Data {
    let commands = try object("commands")
    return try JSONSerialization.data(withJSONObject: #require(commands[name]))
  }
}

extension TrainingExecutionContractTests {
  @Test(arguments: ["path", "body", "key", "query", "refresh", "conversation", "media-owner"])
  func trainingHeadersCannotBeReusedForOtherRoutesOrBodies(_ attack: String) throws {
    let f = try TrainingExecutionFixture()
    let home = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let operation = try TrainingExecutionOperation(binding: .init(home.scope), wireBody: f.command("save"))
    let path = attack == "path" ? "/api/mobile/v1/workouts" : "/api/mobile/v1/training/execution/commands"
    let bytes = try (attack == "body" ? f.command("start") : operation.wireBody)
    let key = try IdempotencyKey(validating: attack == "key" ? "wrong-operation-0001" : operation.idempotencyKey)
    #expect(throws: MobileAPIRequestError.invalidTrainingExecutionHeaders) {
      try MobileAPIRequest<TrainingExecutionMutationSnapshot>(method: .post, path: path,
        queryItems: attack == "query" ? [.init(name: "owner", value: "other")] : [],
        body: bytes, idempotencyKey: key,
        conversation: attack == "conversation" ? .session : nil,
        unauthorizedReplay: attack == "refresh" ? .standard : .never,
        conversationMediaOwnerID: attack == "media-owner" ? home.scope.ownerID : nil,
        trainingExecution: .mutation(operation))
    }
  }

  @Test func unresolvedTrainingCommandCannotInventOwnerCaloriesOrCompletion() throws {
    let f = try TrainingExecutionFixture(), home = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let base = try #require(JSONSerialization.jsonObject(with: f.command("save")) as? [String: Any])
    for key in ["owner_id", "calories", "xp", "prepared_state"] {
      var command = base; command[key] = "client-value"
      #expect(throws: (any Error).self) {
        try TrainingExecutionOperation(binding: .init(home.scope), wireBody: JSONSerialization.data(withJSONObject: command))
      }
    }
    var command = base; command["action"] = ["kind": "finish"]
    #expect(throws: (any Error).self) {
      try TrainingExecutionOperation(binding: .init(home.scope), wireBody: JSONSerialization.data(withJSONObject: command))
    }
  }
}


extension TrainingExecutionContractTests {
  @Test func corruptAuditCannotTurnAnOldReceiptIntoANewWrite() throws {
    let f = try TrainingExecutionFixture()
    for name in ["created", "updated", "replay"] {
      var value = try f.object(name)
      value["audit"] = ["kind": "unexpected", "before": NSNull(), "after": NSNull()]
      #expect(throws: (any Error).self) {
        try TrainingExecutionMutationSnapshot(data: JSONSerialization.data(withJSONObject: value))
      }
    }
  }
}
