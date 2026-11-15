import Foundation

enum TrainingExecutionFinishResolutionMode: String, Sendable { case observe, withdraw }
extension TrainingExecutionOperation {
  func finishResolutionBody(_ mode: TrainingExecutionFinishResolutionMode) throws -> Data {
    try trainingRequire(kind == "finish")
    return try TrainingExecutionJSON.object([
      "schema": .string("training.execution.finish-resolution.v1"), "mode": .string(mode.rawValue),
      "command": TrainingExecutionJSON(data: wireBody),
    ]).data()
  }
  func finishResolutionKey(_ mode: TrainingExecutionFinishResolutionMode) -> String {
    "tresolve1:\(mode.rawValue):\(operationID.uuidString.lowercased())"
  }
}

/// A permanent future fence or an explicit withdrawal is not a workout receipt.
/// The original operation, its own completion and the current execution remain
/// independently bound. Generic absence/network failure never constructs this.
struct TrainingExecutionFinishResolutionSnapshot: Decodable, Sendable {
  enum Status: String, Sendable { case available, withdrawn, fenced, ready, pending }
  let status: Status, mode: TrainingExecutionFinishResolutionMode, reason: String?
  let scope: TrainingExecutionScope, sessionID: UUID, operationID: UUID, expectedEpoch: UUID
  let inputHash: String, beforeRevision: Int
  let current: TrainingExecutionCurrentV2Snapshot?, completion: TrainingExecutionCompletionSnapshot?
  init(data: Data) throws { try self.init(TrainingExecutionJSON(data: data, limit: 2_097_152)) }
  init(from decoder: any Decoder) throws { try self.init(TrainingExecutionJSON(from: decoder)) }
  private init(_ raw: TrainingExecutionJSON) throws {
    try trainingRequire(raw.data().count <= 2_097_152)
    let o = try raw.object([
      "schema", "mode", "status", "reason", "scope", "session_id", "operation_id", "input_hash",
      "before_revision", "expected_epoch", "current", "completion", "withdrawal",
    ])
    try trainingRequire(
      o.field("schema").text(max: 60) == "training.execution-finish-resolution.v1")
    guard let status = Status(rawValue: try o.field("status").text(max: 20)),
      let mode = TrainingExecutionFinishResolutionMode(rawValue: try o.field("mode").text(max: 20))
    else { throw TrainingExecutionError.invalidResponse }
    self.status = status
    self.mode = mode
    reason = try o.nullableText("reason", max: 50)
    scope = try .init(o.field("scope"))
    sessionID = try o.field("session_id").uuid()
    operationID = try o.field("operation_id").uuid()
    expectedEpoch = try o.field("expected_epoch").uuid()
    inputHash = try o.field("input_hash").hash()
    beforeRevision = try o.field("before_revision").integer(max: 2_147_483_646)
    let c = try o.field("current")
    let own = try o.field("completion")
    let marker = try o.field("withdrawal")
    current = c.isNull ? nil : try .init(data: c.data())
    completion = own.isNull ? nil : try .init(data: own.data())
    if let current {
      try trainingRequire(current.scope == scope && current.session.id == sessionID)
    }
    if status == .available {
      guard let completion else { throw TrainingExecutionError.invalidResponse }
      try trainingRequire(
        marker.isNull && reason == nil && completion.sessionID == sessionID
          && completion.completionID == operationID && completion.inputHash == inputHash
          && completion.beforeRevision == beforeRevision && completion.epoch == expectedEpoch
          && completion.scope.ownerID == scope.ownerID
          && completion.scope.authUserID == scope.authUserID
          && completion.scope.epoch == scope.epoch && completion.scope.timezone == scope.timezone
          && ConversationProtocolInstant(completion.scope.observedAt)!
            <= ConversationProtocolInstant(scope.observedAt)!
      )
      if completion.status != .cancelled {
        try trainingRequire(
          current?.completion?.completionID == operationID
            && current?.completion?.status == completion.status
            && current?.session == completion.session)
      }
    } else if status == .withdrawn {
      try trainingRequire(completion == nil && reason == nil)
      let m = try marker.object([
        "schema", "owner_id", "auth_user_id", "session_id", "operation_id",
        "epoch", "before_revision", "input_hash", "at",
      ])
      try trainingRequire(
        m.field("schema").text(max: 60) == "training.execution-finish-withdrawal.v1"
          && m.field("owner_id").uuid() == scope.ownerID
          && m.field("auth_user_id").uuid() == scope.authUserID
          && m.field("session_id").uuid() == sessionID
          && m.field("operation_id").uuid() == operationID
          && m.field("epoch").uuid() == expectedEpoch && m.field("input_hash").hash() == inputHash
          && m.field("before_revision").integer(max: 2_147_483_646) == beforeRevision)
      let at = try m.field("at").clock()
      try trainingRequire(
        ConversationProtocolInstant(at)! <= ConversationProtocolInstant(scope.observedAt)!)
      if scope.epoch != expectedEpoch { try trainingRequire(current == nil) }
    } else {
      try trainingRequire(completion == nil && marker.isNull)
      let derived: (Status, String?)
      if scope.epoch != expectedEpoch {
        try trainingRequire(current == nil)
        derived = (.fenced, "epoch_changed")
      } else if let current, current.session.phase != .inProgress {
        derived = (.fenced, "terminal")
      } else if let current, current.session.revision > beforeRevision {
        derived = (.fenced, "revision_advanced")
      } else if let current, current.session.localDate < scope.currentLocalDate {
        derived = (.fenced, "date_passed")
      } else if current?.completion?.status == .reserved {
        derived = (.pending, "other_reservation")
      } else if current == nil {
        derived = (.pending, "session_unavailable")
      } else if !scope.recordingAllowed || scope.openLocalDate != current?.session.localDate {
        derived = (.pending, "recording_unavailable")
      } else if current?.session.revision != beforeRevision {
        derived = (.pending, "revision_unavailable")
      } else {
        derived = (.ready, nil)
      }
      try trainingRequire(status == derived.0 && reason == derived.1)
    }
    if mode == .withdraw {
      try trainingRequire(
        status == .withdrawn || (status == .available && completion?.status != .reserved))
    }
  }
  func validate(
    for operation: TrainingExecutionOperation, mode: TrainingExecutionFinishResolutionMode
  ) throws {
    try trainingRequire(
      operation.kind == "finish" && self.mode == mode
        && operation.operationID == operationID && operation.sessionID == sessionID
        && operation.inputHash == inputHash && operation.expectedRevision == beforeRevision
        && operation.binding.epoch == expectedEpoch && operation.binding.ownerID == scope.ownerID
        && operation.binding.authUserID == scope.authUserID)
    if status == .available { try completion?.validate(for: operation) }
    if status != .withdrawn && reason != "epoch_changed" {
      try trainingRequire(operation.binding.matches(scope))
    }
  }
}
