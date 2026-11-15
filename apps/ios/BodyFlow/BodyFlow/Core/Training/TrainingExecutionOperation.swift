import Foundation

/// The complete command is fixed before any network call. Retrying it keeps
/// the same operation ID, original account scope and server-compatible digest.
struct TrainingExecutionOperation: Codable, Sendable, Equatable {
  let binding: TrainingExecutionBinding
  let wireBody: Data
  let sessionID: UUID, operationID: UUID, expectedRevision: Int?, kind: String
  let inputHash: String
  var idempotencyKey: String { "\(kind == "finish" ? "tfinish1" : "texecution1"):\(operationID.uuidString.lowercased())" }

  init(binding: TrainingExecutionBinding, wireBody: Data) throws {
    let raw = try TrainingExecutionJSON(data: wireBody, limit: 16_384)
    guard case .object(let fields) = raw else { throw TrainingExecutionError.invalidResponse }
    let schema = try fields.field("schema").text(max: 40)
    let o: [String: TrainingExecutionJSON]
    if schema == "training.execution.start.v1" {
      o = try raw.object(["schema", "session_id", "operation_id", "expected_epoch", "expected_local_date", "plan_id", "plan_hash", "day_index"])
      _ = try o.field("expected_local_date").date()
      _ = try o.field("plan_id").uuid(); _ = try o.field("plan_hash").hash()
      _ = try o.field("day_index").integer(max: 6)
      kind = "start"; expectedRevision = nil
    } else if schema == "training.execution.update.v1" {
      o = try raw.object(["schema", "session_id", "operation_id", "expected_epoch", "expected_revision", "action"])
      expectedRevision = try o.field("expected_revision").integer(max: 2_147_483_647)
      guard case .object(let a) = try o.field("action") else { throw TrainingExecutionError.invalidResponse }
      kind = try a.field("kind").text(max: 30)
      switch kind {
      case "save_set":
        let action = try o.field("action").object(["kind", "exercise_index", "set"])
        _ = try action.field("exercise_index").integer(max: 19)
        _ = try TrainingExecutionSet(json: action.field("set"))
      case "remove_set":
        let action = try o.field("action").object(["kind", "exercise_index", "set_id"])
        _ = try action.field("exercise_index").integer(max: 19)
        _ = try action.field("set_id").uuid()
      case "mark_exercise":
        let action = try o.field("action").object(["kind", "exercise_index", "completed"])
        _ = try action.field("exercise_index").integer(max: 19)
        _ = try action.field("completed").boolean()
      case "abandon": _ = try o.field("action").object(["kind"])
      default: throw TrainingExecutionError.invalidResponse
      }
    } else if schema == "training.execution.finish.v1" {
      o = try raw.object([
        "schema", "session_id", "operation_id", "expected_epoch", "expected_revision", "source",
      ])
      expectedRevision = try o.field("expected_revision").integer(max: 2_147_483_646)
      let source = try o.field("source").object(["channel", "text"])
      try trainingRequire(source.field("channel").text(max: 10) == "text")
      let report = try source.field("text").text(max: 2_000)
      try trainingRequire(!report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      try trainingRequire(
        !report.unicodeScalars.contains {
          ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127
        })
      kind = "finish"
    } else {
      throw TrainingExecutionError.invalidResponse
    }
    sessionID = try o.field("session_id").uuid(); operationID = try o.field("operation_id").uuid()
    try trainingRequire(o.field("expected_epoch").uuid() == binding.epoch)
    try trainingRequire(TimeZone(identifier: binding.timezone) != nil)
    if kind == "start" { try trainingRequire(sessionID == operationID) }
    self.binding = binding
    self.wireBody = try raw.data()
    inputHash = try raw.digest
  }

  static func start(home: TrainingExecutionHomeSnapshot, dayIndex: Int, id: UUID = UUID()) throws -> Self {
    guard home.scope.recordingAllowed, home.scope.openLocalDate == home.scope.currentLocalDate,
          let plan = home.plan, plan.days.indices.contains(dayIndex), plan.days[dayIndex].startable else {
      throw TrainingExecutionError.unavailable
    }
    return try .init(binding: .init(home.scope), wireBody: TrainingExecutionJSON.object([
      "schema": .string("training.execution.start.v1"),
      "session_id": .string(id.uuidString.lowercased()), "operation_id": .string(id.uuidString.lowercased()),
      "expected_epoch": .string(home.scope.epoch.uuidString.lowercased()),
      "expected_local_date": .string(home.scope.currentLocalDate),
      "plan_id": .string(plan.planID.uuidString.lowercased()), "plan_hash": .string(plan.definitionHash),
      "day_index": .number(Double(dayIndex))
    ]).data())
  }

  static func update(session: TrainingExecutionSession, action: Action, id: UUID = UUID()) throws -> Self {
    guard session.phase == .inProgress else { throw TrainingExecutionError.unavailable }
    return try .init(binding: .init(ownerID: session.ownerID, authUserID: session.authUserID, epoch: session.epoch, timezone: session.timezone),
      wireBody: TrainingExecutionJSON.object([
        "schema": .string("training.execution.update.v1"), "session_id": .string(session.id.uuidString.lowercased()),
        "operation_id": .string(id.uuidString.lowercased()), "expected_epoch": .string(session.epoch.uuidString.lowercased()),
        "expected_revision": .number(Double(session.revision)), "action": action.json
      ]).data())
  }

  static func finish(session: TrainingExecutionSession, report: String, id: UUID = UUID()) throws
    -> Self
  {
    guard session.phase == .inProgress, session.revision <= 2_147_483_646 else {
      throw TrainingExecutionError.unavailable
    }
    return try .init(
      binding: .init(
        ownerID: session.ownerID, authUserID: session.authUserID, epoch: session.epoch,
        timezone: session.timezone),
      wireBody: TrainingExecutionJSON.object([
        "schema": .string("training.execution.finish.v1"),
        "session_id": .string(session.id.uuidString.lowercased()),
        "operation_id": .string(id.uuidString.lowercased()),
        "expected_epoch": .string(session.epoch.uuidString.lowercased()),
        "expected_revision": .number(Double(session.revision)),
        "source": .object(["channel": .string("text"), "text": .string(report)]),
      ]).data())
  }

  enum Action: Sendable {
    case saveSet(exercise: Int, set: TrainingExecutionSet)
    case removeSet(exercise: Int, setID: UUID)
    case markExercise(index: Int, completed: Bool)
    case abandon
    var json: TrainingExecutionJSON {
      switch self {
      case .saveSet(let index, let set): return .object(["kind": .string("save_set"), "exercise_index": .number(Double(index)), "set": set.json])
      case .removeSet(let index, let id): return .object(["kind": .string("remove_set"), "exercise_index": .number(Double(index)), "set_id": .string(id.uuidString.lowercased())])
      case .markExercise(let index, let completed): return .object(["kind": .string("mark_exercise"), "exercise_index": .number(Double(index)), "completed": .bool(completed)])
      case .abandon: return .object(["kind": .string("abandon")])
      }
    }
  }

  private enum CodingKeys: String, CodingKey { case binding, wireBody }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(binding: c.decode(TrainingExecutionBinding.self, forKey: .binding), wireBody: c.decode(Data.self, forKey: .wireBody))
  }
  func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(binding, forKey: .binding); try c.encode(wireBody, forKey: .wireBody)
  }
}
