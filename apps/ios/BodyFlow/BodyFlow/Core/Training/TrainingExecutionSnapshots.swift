import Foundation

struct TrainingExecutionScope: Sendable, Equatable {
  let ownerID: UUID, authUserID: UUID, epoch: UUID
  let timezone: String, currentLocalDate: String, openLocalDate: String?, observedAt: String
  let recordingAllowed: Bool
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["owner_id", "auth_user_id", "epoch", "time_zone", "current_local_date", "open_local_date", "observed_at", "recording_allowed"])
    ownerID = try o.field("owner_id").uuid(); authUserID = try o.field("auth_user_id").uuid()
    epoch = try o.field("epoch").uuid(); timezone = try o.field("time_zone").text(max: 100)
    currentLocalDate = try o.field("current_local_date").date()
    let opened = try o.field("open_local_date")
    openLocalDate = opened.isNull ? nil : try opened.date()
    observedAt = try o.field("observed_at").clock()
    recordingAllowed = try o.field("recording_allowed").boolean()
    try trainingRequire(try trainingExecutionDate(observedAt, zone: timezone) == currentLocalDate)
    try trainingRequire(openLocalDate.map { $0 <= currentLocalDate } ?? true)
  }
}

struct TrainingExecutionBinding: Codable, Sendable, Equatable {
  let ownerID: UUID, authUserID: UUID, epoch: UUID
  let timezone: String
  init(_ scope: TrainingExecutionScope) {
    ownerID = scope.ownerID; authUserID = scope.authUserID; epoch = scope.epoch; timezone = scope.timezone
  }
  init(ownerID: UUID, authUserID: UUID, epoch: UUID, timezone: String) {
    self.ownerID = ownerID; self.authUserID = authUserID; self.epoch = epoch; self.timezone = timezone
  }
  func matches(_ scope: TrainingExecutionScope) -> Bool { self == Self(scope) }
}

struct TrainingExecutionPrescription: Sendable, Equatable, Identifiable {
  var id: Int { index }
  let index: Int, fingerprint: String, name: String
  let muscleGroup: String?, recommendedSets: Int?, repsReference: String?, restSeconds: Int?
  let rpeTarget: String?, notes: String?, executionSteps: [String], commonMistakes: [String]
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["index", "fingerprint", "name", "muscle_group", "recommended_sets", "reps_reference", "rest_seconds", "rpe_target", "notes", "execution_steps", "common_mistakes"])
    index = try o.field("index").integer(max: 19); fingerprint = try o.field("fingerprint").hash()
    name = try o.field("name").text(max: 120); muscleGroup = try o.nullableText("muscle_group", max: 80)
    recommendedSets = try o.nullableInt("recommended_sets", max: 15, min: 1)
    repsReference = try o.nullableText("reps_reference", max: 80)
    restSeconds = try o.nullableInt("rest_seconds", max: 600)
    rpeTarget = try o.nullableText("rpe_target", max: 40); notes = try o.nullableText("notes", max: 300)
    executionSteps = try o.field("execution_steps").array(max: 10).map { try $0.text(max: 300, empty: true) }
    commonMistakes = try o.field("common_mistakes").array(max: 10).map { try $0.text(max: 300, empty: true) }
  }
}

struct TrainingExecutionPlanDay: Sendable, Equatable, Identifiable {
  var id: Int { index }
  let index: Int, label: String, focus: String?, recommendedDurationMin: Int?
  let startable: Bool, exercises: [TrainingExecutionPrescription]
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["index", "label", "focus", "recommended_duration_min", "startable", "exercises"])
    index = try o.field("index").integer(max: 6); label = try o.field("label").text(max: 80)
    focus = try o.nullableText("focus", max: 80)
    recommendedDurationMin = try o.nullableInt("recommended_duration_min", max: 1440, min: 1)
    startable = try o.field("startable").boolean()
    exercises = try o.field("exercises").array(max: 20).map(TrainingExecutionPrescription.init)
    try trainingRequire(startable == !exercises.isEmpty)
    try trainingRequire(exercises.enumerated().allSatisfy { $0.offset == $0.element.index })
  }
}

struct TrainingExecutionPlan: Sendable, Equatable {
  let planID: UUID, planVersion: Int, definitionHash: String
  let days: [TrainingExecutionPlanDay]
  init(_ raw: TrainingExecutionJSON, scope: TrainingExecutionScope) throws {
    let o = try raw.object(["schema", "owner_id", "auth_user_id", "epoch", "time_zone", "current_local_date", "observed_at", "plan_id", "plan_version", "definition_hash", "days"])
    try trainingRequire(o.field("schema").text(max: 40) == "training.execution-plan.v1")
    try trainingRequire(o.field("owner_id").uuid() == scope.ownerID)
    try trainingRequire(o.field("auth_user_id").uuid() == scope.authUserID)
    try trainingRequire(o.field("epoch").uuid() == scope.epoch)
    try trainingRequire(o.field("time_zone").text(max: 100) == scope.timezone)
    try trainingRequire(o.field("current_local_date").date() == scope.currentLocalDate)
    try trainingRequire(o.field("observed_at").clock() == scope.observedAt)
    planID = try o.field("plan_id").uuid(); planVersion = try o.field("plan_version").integer(max: Int32.max.int, min: 1)
    definitionHash = try o.field("definition_hash").hash()
    days = try o.field("days").array(max: 7, min: 1).map(TrainingExecutionPlanDay.init)
    try trainingRequire(days.enumerated().allSatisfy { $0.offset == $0.element.index })
  }
}

struct TrainingExecutionDefinition: Sendable, Equatable {
  let planID: UUID, planVersion: Int, planHash: String, dayIndex: Int, dayLabel: String
  let focus: String?, recommendedDurationMin: Int?, exercises: [TrainingExecutionPrescription]
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["plan_id", "plan_version", "plan_hash", "day_index", "day_label", "focus", "recommended_duration_min", "exercises"])
    planID = try o.field("plan_id").uuid(); planVersion = try o.field("plan_version").integer(max: Int32.max.int, min: 1)
    planHash = try o.field("plan_hash").hash(); dayIndex = try o.field("day_index").integer(max: 6)
    dayLabel = try o.field("day_label").text(max: 80); focus = try o.nullableText("focus", max: 80)
    recommendedDurationMin = try o.nullableInt("recommended_duration_min", max: 1440, min: 1)
    exercises = try o.field("exercises").array(max: 20, min: 1).map(TrainingExecutionPrescription.init)
    try trainingRequire(exercises.enumerated().allSatisfy { $0.offset == $0.element.index })
  }
}

struct TrainingExecutionSet: Sendable, Equatable, Identifiable {
  let id: UUID, index: Int, repetitions: Int?, loadKg: Double?, durationSeconds: Int?, completed: Bool
  init(id: UUID, index: Int, repetitions: Int?, loadKg: Double?, durationSeconds: Int?, completed: Bool) throws {
    self.id = id; self.index = index; self.repetitions = repetitions; self.loadKg = loadKg
    self.durationSeconds = durationSeconds; self.completed = completed
    _ = try TrainingExecutionSet(json: json)
  }
  init(json raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["id", "index", "repetitions", "load_kg", "duration_seconds", "completed"])
    id = try o.field("id").uuid(); index = try o.field("index").integer(max: 99)
    repetitions = try o.nullableInt("repetitions", max: 10000)
    let load = try o.field("load_kg"); loadKg = load.isNull ? nil : try load.number(max: 10000)
    durationSeconds = try o.nullableInt("duration_seconds", max: 86400)
    completed = try o.field("completed").boolean()
  }
  var json: TrainingExecutionJSON {
    .object(["id": .string(id.uuidString.lowercased()), "index": .number(Double(index)),
      "repetitions": repetitions.map { .number(Double($0)) } ?? .null,
      "load_kg": loadKg.map { .number($0) } ?? .null,
      "duration_seconds": durationSeconds.map { .number(Double($0)) } ?? .null,
      "completed": .bool(completed)])
  }
}

struct TrainingExecutionExercise: Sendable, Equatable, Identifiable {
  var id: Int { index }
  let index: Int, completed: Bool, sets: [TrainingExecutionSet]
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["index", "completed", "sets"])
    index = try o.field("index").integer(max: 19); completed = try o.field("completed").boolean()
    sets = try o.field("sets").array(max: 100).map { try TrainingExecutionSet(json: $0) }
    try trainingRequire(Set(sets.map(\.index)).count == sets.count)
  }
}

struct TrainingExecutionSession: Sendable, Equatable, Identifiable {
  enum Phase: String, Sendable { case inProgress = "in_progress", abandoned, completed }
  let id: UUID, ownerID: UUID, authUserID: UUID, epoch: UUID, timezone: String, localDate: String
  let startedAt: String, updatedAt: String, phase: Phase, revision: Int
  let definition: TrainingExecutionDefinition, exercises: [TrainingExecutionExercise]
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["schema", "id", "owner_id", "auth_user_id", "epoch", "time_zone", "local_date", "started_at", "updated_at", "phase", "revision", "definition", "exercises"])
    try trainingRequire(o.field("schema").text(max: 40) == "training.execution.v1")
    id = try o.field("id").uuid(); ownerID = try o.field("owner_id").uuid()
    authUserID = try o.field("auth_user_id").uuid(); epoch = try o.field("epoch").uuid()
    timezone = try o.field("time_zone").text(max: 100); localDate = try o.field("local_date").date()
    startedAt = try o.field("started_at").clock(); updatedAt = try o.field("updated_at").clock()
    guard let p = Phase(rawValue: try o.field("phase").text(max: 20)), p != .completed else { throw TrainingExecutionError.invalidResponse }
    phase = p; revision = try o.field("revision").integer(max: Int32.max.int)
    definition = try .init(o.field("definition"))
    exercises = try o.field("exercises").array(max: 20, min: 1).map(TrainingExecutionExercise.init)
    try trainingRequire(definition.exercises.count == exercises.count)
    try trainingRequire(exercises.enumerated().allSatisfy { $0.offset == $0.element.index })
    let sets = exercises.flatMap(\.sets)
    try trainingRequire(Set(sets.map(\.id)).count == sets.count)
    try trainingRequire(try trainingExecutionDate(startedAt, zone: timezone) == localDate)
    try trainingRequire(ConversationProtocolInstant(startedAt)! <= ConversationProtocolInstant(updatedAt)!)
  }
  func validate(scope: TrainingExecutionScope) throws {
    try trainingRequire(ownerID == scope.ownerID && authUserID == scope.authUserID
      && epoch == scope.epoch && timezone == scope.timezone && localDate <= scope.currentLocalDate)
    try trainingRequire(ConversationProtocolInstant(updatedAt)! <= ConversationProtocolInstant(scope.observedAt)!)
  }
}

struct TrainingExecutionSummary: Sendable, Equatable, Identifiable {
  let id: UUID, revision: Int, localDate: String, startedAt: String, updatedAt: String, planID: UUID
  let dayIndex: Int, dayLabel: String, totalExercises: Int, completedExercises: Int
  init(_ raw: TrainingExecutionJSON, scope: TrainingExecutionScope) throws {
    let o = try raw.object(["id", "revision", "local_date", "started_at", "updated_at", "plan_id", "day_index", "day_label", "total_exercises", "completed_exercises"])
    id = try o.field("id").uuid(); revision = try o.field("revision").integer(max: Int32.max.int)
    localDate = try o.field("local_date").date(); startedAt = try o.field("started_at").clock()
    updatedAt = try o.field("updated_at").clock(); planID = try o.field("plan_id").uuid()
    dayIndex = try o.field("day_index").integer(max: 6); dayLabel = try o.field("day_label").text(max: 80)
    totalExercises = try o.field("total_exercises").integer(max: 20, min: 1)
    completedExercises = try o.field("completed_exercises").integer(max: totalExercises)
    try trainingRequire(localDate <= scope.currentLocalDate && (try trainingExecutionDate(startedAt, zone: scope.timezone)) == localDate)
    try trainingRequire(ConversationProtocolInstant(startedAt)! <= ConversationProtocolInstant(updatedAt)!
      && ConversationProtocolInstant(updatedAt)! <= ConversationProtocolInstant(scope.observedAt)!)
  }
}

struct TrainingExecutionCursor: Sendable, Equatable {
  let ownerID: UUID, epoch: UUID, timezone: String, updatedAt: String, sessionID: UUID
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["owner_id", "epoch", "time_zone", "updated_at", "session_id"])
    ownerID = try o.field("owner_id").uuid(); epoch = try o.field("epoch").uuid()
    timezone = try o.field("time_zone").text(max: 100); updatedAt = try o.field("updated_at").clock()
    sessionID = try o.field("session_id").uuid()
  }
  var json: TrainingExecutionJSON {
    .object(["owner_id": .string(ownerID.uuidString.lowercased()), "epoch": .string(epoch.uuidString.lowercased()), "time_zone": .string(timezone), "updated_at": .string(updatedAt), "session_id": .string(sessionID.uuidString.lowercased())])
  }
}

struct TrainingExecutionHomeSnapshot: Decodable, Sendable, Equatable {
  let scope: TrainingExecutionScope, plan: TrainingExecutionPlan?, sessions: [TrainingExecutionSummary], nextCursor: TrainingExecutionCursor?
  init(data: Data) throws { try self.init(TrainingExecutionJSON(data: data)) }
  init(from decoder: any Decoder) throws { try self.init(TrainingExecutionJSON(from: decoder)) }
  private init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["schema", "scope", "plan", "sessions", "next_cursor"])
    try trainingRequire(o.field("schema").text(max: 40) == "training.execution-home.v1")
    scope = try .init(o.field("scope"))
    let p = try o.field("plan"); plan = p.isNull ? nil : try .init(p, scope: scope)
    let readScope = scope
    sessions = try o.field("sessions").array(max: 20).map { try TrainingExecutionSummary($0, scope: readScope) }
    try trainingRequire(Set(sessions.map(\.id)).count == sessions.count)
    let c = try o.field("next_cursor"); nextCursor = c.isNull ? nil : try .init(c)
    if let cursor = nextCursor {
      try trainingRequire(sessions.count == 20 && cursor.ownerID == scope.ownerID && cursor.epoch == scope.epoch
        && cursor.timezone == scope.timezone && cursor.updatedAt == sessions.last?.updatedAt && cursor.sessionID == sessions.last?.id)
    }
  }
}

struct TrainingExecutionReadSnapshot: Decodable, Sendable, Equatable {
  let scope: TrainingExecutionScope, session: TrainingExecutionSession
  init(data: Data) throws { try self.init(TrainingExecutionJSON(data: data)) }
  init(from decoder: any Decoder) throws { try self.init(TrainingExecutionJSON(from: decoder)) }
  private init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["schema", "scope", "session"])
    try trainingRequire(o.field("schema").text(max: 40) == "training.execution-read.v1")
    scope = try .init(o.field("scope")); session = try .init(o.field("session"))
    try session.validate(scope: scope)
  }
}

struct TrainingExecutionReceipt: Sendable, Equatable {
  let ownerID: UUID, epoch: UUID, sessionID: UUID, operationID: UUID, inputHash: String
  let beforeRevision: Int?, afterRevision: Int, kind: String, at: String
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["schema", "owner_id", "epoch", "session_id", "operation_id", "input_hash", "before_revision", "after_revision", "kind", "at"])
    try trainingRequire(o.field("schema").text(max: 40) == "training.execution.receipt.v1")
    ownerID = try o.field("owner_id").uuid(); epoch = try o.field("epoch").uuid()
    sessionID = try o.field("session_id").uuid(); operationID = try o.field("operation_id").uuid()
    inputHash = try o.field("input_hash").hash(); beforeRevision = try o.nullableInt("before_revision", max: Int32.max.int)
    afterRevision = try o.field("after_revision").integer(max: Int32.max.int)
    kind = try o.field("kind").text(max: 30); at = try o.field("at").clock()
    try trainingRequire(["start", "save_set", "remove_set", "mark_exercise", "abandon"].contains(kind))
  }
}

struct TrainingExecutionMutationSnapshot: Decodable, Sendable, Equatable {
  enum Status: String, Sendable { case created, updated, replayed }
  let status: Status, session: TrainingExecutionSession, receipt: TrainingExecutionReceipt
  init(data: Data) throws { try self.init(TrainingExecutionJSON(data: data)) }
  init(from decoder: any Decoder) throws { try self.init(TrainingExecutionJSON(from: decoder)) }
  private init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["status", "session", "receipt", "audit"])
    guard let s = Status(rawValue: try o.field("status").text(max: 20)) else { throw TrainingExecutionError.invalidResponse }
    status = s; session = try .init(o.field("session")); receipt = try .init(o.field("receipt"))
    try trainingRequire(receipt.ownerID == session.ownerID && receipt.epoch == session.epoch && receipt.sessionID == session.id
      && receipt.afterRevision <= session.revision
      && ConversationProtocolInstant(receipt.at)! >= ConversationProtocolInstant(session.startedAt)!
      && ConversationProtocolInstant(receipt.at)! <= ConversationProtocolInstant(session.updatedAt)!)
    let audit = try o.field("audit")
    if status == .replayed {
      try trainingRequire(audit.isNull)
    } else {
      try trainingRequire(receipt.afterRevision == session.revision)
      guard case .object(let fields) = audit else { throw TrainingExecutionError.invalidResponse }
      let keys: Set<String> = fields["exercise_index"] == nil ? ["kind", "before", "after"] : ["kind", "exercise_index", "before", "after"]
      let closed = try audit.object(keys)
      try trainingRequire(closed.field("kind").text(max: 30) == receipt.kind)
      if let index = closed["exercise_index"] { _ = try index.integer(max: 19) }
    }
  }
  func validate(for operation: TrainingExecutionOperation) throws {
    try trainingRequire(session.ownerID == operation.binding.ownerID && session.authUserID == operation.binding.authUserID
      && session.epoch == operation.binding.epoch && session.timezone == operation.binding.timezone
      && receipt.operationID == operation.operationID && receipt.sessionID == operation.sessionID
      && receipt.inputHash == operation.inputHash && receipt.kind == operation.kind
      && receipt.beforeRevision == operation.expectedRevision)
    try trainingRequire(receipt.afterRevision == (operation.expectedRevision.map { $0 + 1 } ?? 0))
    if status != .replayed { try trainingRequire(status == (operation.kind == "start" ? .created : .updated)) }
  }
}

private func trainingExecutionDate(_ instant: String, zone: String) throws -> String {
  guard let clock = ConversationProtocolInstant(instant), let timezone = TimeZone(identifier: zone) else {
    throw TrainingExecutionError.invalidResponse
  }
  return NutritionCivilDate.string(Date(timeIntervalSince1970: Double(clock.seconds)), zone: timezone)
}
private extension Int32 { var int: Int { Int(self) } }
