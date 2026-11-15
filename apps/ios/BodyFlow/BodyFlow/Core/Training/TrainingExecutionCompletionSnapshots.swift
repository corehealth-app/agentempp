import Foundation

struct TrainingExecutionCompletionReceipt: Sendable, Equatable {
  enum Kind: String, Sendable { case completed, cancelled }
  let kind: Kind, ownerID: UUID, authUserID: UUID, epoch: UUID, sessionID: UUID, completionID: UUID
  let inputHash: String, beforeRevision: Int, afterRevision: Int, at: String
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object([
      "schema", "kind", "owner_id", "auth_user_id", "epoch", "session_id", "completion_id",
      "input_hash", "before_revision", "after_revision", "at",
    ])
    try trainingRequire(
      o.field("schema").text(max: 60) == "training.execution-completion-receipt.v1")
    guard let kind = Kind(rawValue: try o.field("kind").text(max: 20)) else {
      throw TrainingExecutionError.invalidResponse
    }
    self.kind = kind
    ownerID = try o.field("owner_id").uuid()
    authUserID = try o.field("auth_user_id").uuid()
    epoch = try o.field("epoch").uuid()
    sessionID = try o.field("session_id").uuid()
    completionID = try o.field("completion_id").uuid()
    inputHash = try o.field("input_hash").hash()
    beforeRevision = try o.field("before_revision").integer(max: 2_147_483_646)
    afterRevision = try o.field("after_revision").integer(max: Int(Int32.max))
    at = try o.field("at").clock()
    try trainingRequire(afterRevision == beforeRevision + (kind == .completed ? 1 : 0))
  }
}

struct TrainingExecutionCompletedWorkout: Sendable, Equatable {
  let registrationID: UUID, workoutID: UUID, performedAt: String, localDate: String,
    timezone: String, committedAt: String
  let workoutType: String, durationMin: Int, intensity: String?, estimatedKcal: Int?
  init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object([
      "kind", "provenance", "registration_id", "workout_id", "performed_at", "local_date",
      "time_zone", "committed_at", "workout_type", "duration_min", "intensity", "estimated_kcal",
    ])
    try trainingRequire(
      o.field("kind").text(max: 20) == "workout"
        && o.field("provenance").text(max: 40) == "conversation.workout.v1")
    registrationID = try o.field("registration_id").uuid()
    workoutID = try o.field("workout_id").uuid()
    performedAt = try o.field("performed_at").clock()
    committedAt = try o.field("committed_at").clock()
    localDate = try o.field("local_date").date()
    timezone = try o.field("time_zone").text(max: 100)
    workoutType = try o.field("workout_type").text(max: 200)
    durationMin = try o.field("duration_min").integer(max: 1440, min: 1)
    intensity = try o.nullableText("intensity", max: 20)
    estimatedKcal = try o.nullableInt("estimated_kcal", max: 10_000)
    try trainingRequire(intensity == nil || ["leve", "moderada", "alta"].contains(intensity!))
    try trainingRequire(try completionCivilDate(performedAt, zone: timezone) == localDate)
    try trainingRequire(
      ConversationProtocolInstant(performedAt)! <= ConversationProtocolInstant(committedAt)!)
  }
}

/// The old v1 initializer stays strict. Only a validated linked completion
/// receipt can construct the additive completed state, without rewriting it
/// into a fictitious abandoned/progress-v1 snapshot.
extension TrainingExecutionSession {
  init(completed raw: TrainingExecutionJSON, receipt: TrainingExecutionCompletionReceipt) throws {
    let o = try raw.object([
      "schema", "id", "owner_id", "auth_user_id", "epoch", "time_zone", "local_date", "started_at",
      "updated_at", "phase", "revision", "definition", "exercises",
    ])
    try trainingRequire(
      o.field("schema").text(max: 40) == "training.execution.v2"
        && o.field("phase").text(max: 20) == "completed" && receipt.kind == .completed)
    id = try o.field("id").uuid()
    ownerID = try o.field("owner_id").uuid()
    authUserID = try o.field("auth_user_id").uuid()
    epoch = try o.field("epoch").uuid()
    timezone = try o.field("time_zone").text(max: 100)
    localDate = try o.field("local_date").date()
    startedAt = try o.field("started_at").clock()
    updatedAt = try o.field("updated_at").clock()
    phase = .completed
    revision = try o.field("revision").integer(max: Int(Int32.max))
    definition = try .init(o.field("definition"))
    exercises = try o.field("exercises").array(max: 20, min: 1).map(TrainingExecutionExercise.init)
    try trainingRequire(
      exercises.count == definition.exercises.count
        && exercises.enumerated().allSatisfy { $0.offset == $0.element.index })
    let sets = exercises.flatMap(\.sets)
    try trainingRequire(Set(sets.map(\.id)).count == sets.count)
    try trainingRequire(try completionCivilDate(startedAt, zone: timezone) == localDate)
    try trainingRequire(
      ConversationProtocolInstant(startedAt)! <= ConversationProtocolInstant(updatedAt)!)
    try trainingRequire(
      receipt.ownerID == ownerID && receipt.authUserID == authUserID && receipt.epoch == epoch
        && receipt.sessionID == id
        && receipt.afterRevision == revision && receipt.at == updatedAt)
  }
}

struct TrainingExecutionCompletionIdentity: Sendable, Equatable {
  let binding: TrainingExecutionBinding, sessionID: UUID, completionID: UUID, inputHash: String
  init(operation: TrainingExecutionOperation) throws {
    try trainingRequire(operation.kind == "finish")
    binding = operation.binding
    sessionID = operation.sessionID
    completionID = operation.operationID
    inputHash = operation.inputHash
  }
  init(_ value: TrainingExecutionCompletionSnapshot) {
    binding = .init(value.scope)
    sessionID = value.sessionID
    completionID = value.completionID
    inputHash = value.inputHash
  }
  var cancelBody: Data {
    get throws {
      try TrainingExecutionJSON.object([
        "schema": .string("training.execution.finish-cancel.v1"),
        "session_id": .string(sessionID.uuidString.lowercased()),
        "completion_id": .string(completionID.uuidString.lowercased()),
        "expected_epoch": .string(binding.epoch.uuidString.lowercased()),
        "input_hash": .string(inputHash),
      ]).data()
    }
  }
}

struct TrainingExecutionCompletionSnapshot: Decodable, Sendable {
  enum Status: String, Sendable { case reserved, completed, cancelled }
  enum WorkoutState: String, Sendable { case present, removed }
  struct Decision: Sendable, Equatable { let status: String, field: String?, text: String }
  let status: Status, ownerID: UUID, authUserID: UUID, epoch: UUID, sessionID: UUID,
    completionID: UUID
  let inputHash: String, beforeRevision: Int, scope: TrainingExecutionScope
  let session: TrainingExecutionSession?, receipt: TrainingExecutionCompletionReceipt?,
    workout: TrainingExecutionCompletedWorkout?
  let workoutState: WorkoutState?, feedback: ConversationFeedbackPresentationV2Snapshot?,
    decision: Decision?
  fileprivate let sessionWire: TrainingExecutionJSON
  init(data: Data) throws { try self.init(TrainingExecutionJSON(data: data, limit: 2_097_152)) }
  init(from decoder: any Decoder) throws { try self.init(TrainingExecutionJSON(from: decoder)) }
  private init(_ raw: TrainingExecutionJSON) throws {
    try trainingRequire(raw.data().count <= 2_097_152)
    let o = try raw.object([
      "schema", "status", "owner_id", "auth_user_id", "epoch", "session_id", "completion_id",
      "input_hash", "before_revision", "scope", "session", "receipt", "workout", "workout_state",
      "feedback", "decision",
    ])
    try trainingRequire(o.field("schema").text(max: 60) == "training.execution-completion.v1")
    guard let status = Status(rawValue: try o.field("status").text(max: 20)) else {
      throw TrainingExecutionError.invalidResponse
    }
    self.status = status
    ownerID = try o.field("owner_id").uuid()
    authUserID = try o.field("auth_user_id").uuid()
    epoch = try o.field("epoch").uuid()
    sessionID = try o.field("session_id").uuid()
    completionID = try o.field("completion_id").uuid()
    inputHash = try o.field("input_hash").hash()
    beforeRevision = try o.field("before_revision").integer(max: 2_147_483_646)
    scope = try .init(o.field("scope"))
    try trainingRequire(
      scope.ownerID == ownerID && scope.authUserID == authUserID && scope.epoch == epoch)
    let r = try o.field("receipt")
    receipt = r.isNull ? nil : try .init(r)
    if let receipt {
      try trainingRequire(
        status != .reserved && receipt.kind.rawValue == status.rawValue
          && receipt.ownerID == ownerID
          && receipt.authUserID == authUserID && receipt.epoch == epoch
          && receipt.sessionID == sessionID && receipt.completionID == completionID
          && receipt.inputHash == inputHash && receipt.beforeRevision == beforeRevision)
      try trainingRequire(
        ConversationProtocolInstant(receipt.at)! <= ConversationProtocolInstant(scope.observedAt)!)
    } else {
      try trainingRequire(status == .reserved)
    }
    sessionWire = try o.field("session")
    switch status {
    case .reserved:
      let progress = try TrainingExecutionSession(sessionWire)
      try trainingRequire(progress.phase == .inProgress && progress.revision == beforeRevision)
      session = progress
    case .completed:
      guard let receipt else { throw TrainingExecutionError.invalidResponse }
      session = try .init(completed: sessionWire, receipt: receipt)
    case .cancelled:
      try trainingRequire(sessionWire.isNull)
      session = nil
    }
    if let session {
      try session.validate(scope: scope)
      try trainingRequire(session.id == sessionID)
    }
    let w = try o.field("workout")
    let state = try o.field("workout_state")
    if status == .completed {
      guard let receipt else { throw TrainingExecutionError.invalidResponse }
      let saved = try TrainingExecutionCompletedWorkout(w)
      try trainingRequire(
        saved.registrationID == completionID && saved.timezone == scope.timezone
          && saved.localDate == session?.localDate && saved.committedAt == receipt.at)
      guard let observed = WorkoutState(rawValue: try state.text(max: 20)) else {
        throw TrainingExecutionError.invalidResponse
      }
      workout = saved
      workoutState = observed
    } else {
      try trainingRequire(w.isNull && state.isNull)
      workout = nil
      workoutState = nil
    }
    let d = try o.field("decision")
    if !d.isNull {
      try trainingRequire(status == .cancelled)
      guard case .object(let fields) = d else { throw TrainingExecutionError.invalidResponse }
      let kind = try fields.field("status").text(max: 30)
      if kind == "needs_reply" {
        let closed = try d.object(["status", "question"])
        let q = try closed.field("question").object(["field", "text"])
        let field = try q.field("field").text(max: 30)
        try trainingRequire(["activity", "duration_min"].contains(field))
        decision = .init(status: kind, field: field, text: try q.field("text").text(max: 2_000))
      } else {
        let closed = try d.object(["status", "reason"])
        try trainingRequire(kind == "not_recorded")
        decision = .init(status: kind, field: nil, text: try closed.field("reason").text(max: 500))
      }
    } else {
      decision = nil
    }
    // Optional education is not a registration ACK. Invalid/unrelated optional
    // content is dropped without invalidating or repeating the official effect.
    let optional = try o.field("feedback")
    var presentation: ConversationFeedbackPresentationV2Snapshot?
    if status == .completed, let saved = workout, !optional.isNull,
      let value = try? JSONDecoder().decode(
        ConversationFeedbackPresentationV2Snapshot.self, from: optional.data()),
      value.original.registrationID == completionID.uuidString.lowercased(),
      value.original.kind == "workout",
      value.provenance.epoch == epoch.uuidString.lowercased(),
      value.provenance.commandID == completionID.uuidString.lowercased(),
      case .workout(let recorded) = value.recorded,
      recorded.logID == saved.workoutID.uuidString.lowercased(),
      recorded.workoutType == saved.workoutType,
      recorded.durationMin == Double(saved.durationMin), recorded.intensity == saved.intensity,
      recorded.estimatedKcal == saved.estimatedKcal.map(Double.init)
    {
      presentation = value
    }
    feedback = presentation
  }
  func validate(for operation: TrainingExecutionOperation) throws {
    try trainingRequire(operation.kind == "finish")
    try validate(identity: .init(operation: operation))
    try trainingRequire(beforeRevision == operation.expectedRevision)
  }
  func validate(identity: TrainingExecutionCompletionIdentity) throws {
    try trainingRequire(
      identity.binding.matches(scope) && identity.sessionID == sessionID
        && identity.completionID == completionID && identity.inputHash == inputHash)
  }
}

struct TrainingExecutionCurrentV2Snapshot: Decodable, Sendable {
  let scope: TrainingExecutionScope, session: TrainingExecutionSession,
    completion: TrainingExecutionCompletionSnapshot?
  init(data: Data) throws { try self.init(TrainingExecutionJSON(data: data, limit: 2_097_152)) }
  init(from decoder: any Decoder) throws { try self.init(TrainingExecutionJSON(from: decoder)) }
  fileprivate init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["schema", "scope", "session", "completion"])
    try trainingRequire(o.field("schema").text(max: 50) == "training.execution-state.v2")
    scope = try .init(o.field("scope"))
    let c = try o.field("completion")
    if c.isNull {
      completion = nil
      session = try .init(o.field("session"))
      try session.validate(scope: scope)
    } else {
      let value = try TrainingExecutionCompletionSnapshot(data: c.data())
      guard let current = value.session else { throw TrainingExecutionError.invalidResponse }
      try trainingRequire(
        value.status != .cancelled && value.scope == scope
          && value.sessionWire == o.field("session"))
      completion = value
      session = current
    }
  }
}

struct TrainingExecutionHistorySummary: Sendable {
  struct Completion: Sendable {
    let id: UUID, inputHash: String, status: TrainingExecutionCompletionSnapshot.Status
  }
  let base: TrainingExecutionSummary, phase: TrainingExecutionSession.Phase, dayClosed: Bool,
    completion: Completion?
  init(_ raw: TrainingExecutionJSON, scope: TrainingExecutionScope) throws {
    let keys: Set<String> = [
      "id", "revision", "local_date", "started_at", "updated_at", "plan_id", "day_index",
      "day_label", "total_exercises", "completed_exercises",
    ]
    let o = try raw.object(keys.union(["phase", "day_closed", "completion"]))
    base = try .init(.object(o.filter { keys.contains($0.key) }), scope: scope)
    guard let phase = TrainingExecutionSession.Phase(rawValue: try o.field("phase").text(max: 20))
    else { throw TrainingExecutionError.invalidResponse }
    self.phase = phase
    dayClosed = try o.field("day_closed").boolean()
    let c = try o.field("completion")
    if c.isNull {
      completion = nil
      try trainingRequire(phase != .completed)
    } else {
      let info = try c.object(["id", "input_hash", "status"])
      guard
        let status = TrainingExecutionCompletionSnapshot.Status(
          rawValue: try info.field("status").text(max: 20))
      else { throw TrainingExecutionError.invalidResponse }
      try trainingRequire(
        status != .cancelled && ((status == .completed) == (phase == .completed))
          && phase != .abandoned)
      completion = .init(
        id: try info.field("id").uuid(), inputHash: try info.field("input_hash").hash(),
        status: status)
    }
  }
}
struct TrainingExecutionHomeV2Snapshot: Decodable, Sendable {
  let scope: TrainingExecutionScope, plan: TrainingExecutionPlan?,
    sessions: [TrainingExecutionHistorySummary], nextCursor: TrainingExecutionCursor?
  init(data: Data) throws { try self.init(TrainingExecutionJSON(data: data)) }
  init(from decoder: any Decoder) throws { try self.init(TrainingExecutionJSON(from: decoder)) }
  private init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object(["schema", "scope", "plan", "sessions", "next_cursor"])
    try trainingRequire(o.field("schema").text(max: 50) == "training.execution-home.v2")
    scope = try .init(o.field("scope"))
    let p = try o.field("plan")
    plan = p.isNull ? nil : try .init(p, scope: scope)
    let readScope = scope
    sessions = try o.field("sessions").array(max: 20).map { try .init($0, scope: readScope) }
    try trainingRequire(Set(sessions.map(\.base.id)).count == sessions.count)
    for index in sessions.indices.dropFirst() {
      let a = sessions[index - 1].base
      let b = sessions[index].base
      try trainingRequire(
        ConversationProtocolInstant(a.updatedAt)! > ConversationProtocolInstant(b.updatedAt)!
          || (a.updatedAt == b.updatedAt && a.id.uuidString > b.id.uuidString))
    }
    let c = try o.field("next_cursor")
    nextCursor = c.isNull ? nil : try .init(c)
    if let cursor = nextCursor {
      try trainingRequire(
        sessions.count == 20 && cursor.ownerID == scope.ownerID && cursor.epoch == scope.epoch
          && cursor.timezone == scope.timezone
          && cursor.updatedAt == sessions.last?.base.updatedAt
          && cursor.sessionID == sessions.last?.base.id)
    }
  }
}

struct TrainingExecutionProgressV2Snapshot: Decodable, Sendable {
  enum Status: String, Sendable {
    case created, updated, replayed, pending
    case notApplied = "not_applied"
  }
  let status: Status, scope: TrainingExecutionScope, operationID: UUID, inputHash: String,
    receipt: TrainingExecutionReceipt?, current: TrainingExecutionCurrentV2Snapshot?
  init(data: Data) throws { try self.init(TrainingExecutionJSON(data: data, limit: 2_097_152)) }
  init(from decoder: any Decoder) throws { try self.init(TrainingExecutionJSON(from: decoder)) }
  private init(_ raw: TrainingExecutionJSON) throws {
    let o = try raw.object([
      "schema", "status", "scope", "operation_id", "input_hash", "receipt", "current",
    ])
    try trainingRequire(o.field("schema").text(max: 50) == "training.execution-mutation.v2")
    guard let status = Status(rawValue: try o.field("status").text(max: 20)) else {
      throw TrainingExecutionError.invalidResponse
    }
    self.status = status
    scope = try .init(o.field("scope"))
    operationID = try o.field("operation_id").uuid()
    inputHash = try o.field("input_hash").hash()
    let r = try o.field("receipt")
    receipt = r.isNull ? nil : try .init(r)
    let c = try o.field("current")
    current = c.isNull ? nil : try .init(c)
    if let current { try trainingRequire(current.scope == scope) }
    if status == .pending || status == .notApplied {
      try trainingRequire(receipt == nil)
      if status == .pending {
        try trainingRequire(
          current?.completion?.status == .reserved && current?.session.phase == .inProgress)
      }
    } else {
      guard let receipt, let current else { throw TrainingExecutionError.invalidResponse }
      try trainingRequire(
        receipt.ownerID == scope.ownerID && receipt.epoch == scope.epoch
          && receipt.operationID == operationID && receipt.inputHash == inputHash
          && receipt.sessionID == current.session.id
          && receipt.afterRevision <= current.session.revision
          && ConversationProtocolInstant(receipt.at)! >= ConversationProtocolInstant(
            current.session.startedAt)!
          && ConversationProtocolInstant(receipt.at)! <= ConversationProtocolInstant(
            current.session.updatedAt)!
      )
    }
  }
  func validate(for operation: TrainingExecutionOperation) throws {
    try trainingRequire(
      operation.kind != "finish" && operation.binding.matches(scope)
        && operation.operationID == operationID && operation.inputHash == inputHash)
    if let current { try trainingRequire(current.session.id == operation.sessionID) }
    if let receipt {
      try trainingRequire(
        receipt.kind == operation.kind && receipt.beforeRevision == operation.expectedRevision
          && receipt.afterRevision == (operation.expectedRevision.map { $0 + 1 } ?? 0))
      if status != .replayed {
        try trainingRequire(status == (operation.kind == "start" ? .created : .updated))
      }
    } else if status == .notApplied {
      let permanentlyFenced = current.map { $0.session.phase != .inProgress } ?? false
      // Compare original expected revision to current revision explicitly; a
      // cancellable reservation alone is never evidence of a permanent fence.
      let advanced =
        operation.expectedRevision.map { expected in
          current.map { expected < $0.session.revision } ?? false
        } ?? false
      var oldStart = false
      if operation.kind == "start" {
        guard case .object(let fields) = try TrainingExecutionJSON(data: operation.wireBody) else {
          throw TrainingExecutionError.invalidResponse
        }
        oldStart = try fields.field("expected_local_date").date() < scope.currentLocalDate
      }
      try trainingRequire(permanentlyFenced || advanced || oldStart)
    } else {
      try trainingRequire(status == .pending)
    }
  }
}

private func completionCivilDate(_ value: String, zone: String) throws -> String {
  guard let instant = ConversationProtocolInstant(value), let timezone = TimeZone(identifier: zone)
  else { throw TrainingExecutionError.invalidResponse }
  return NutritionCivilDate.string(
    Date(timeIntervalSince1970: Double(instant.seconds)), zone: timezone)
}
