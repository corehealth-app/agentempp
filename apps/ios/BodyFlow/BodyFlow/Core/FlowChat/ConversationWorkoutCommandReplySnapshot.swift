import Foundation

/// Closed factual projection from the authenticated workout command service.
/// Decoding and identity matching are not persistence proof or display authority.
struct SavedConversationWorkoutCommandResultSnapshot: Decodable, Sendable {
  struct Registration: Sendable {
    let registrationID: UUID
    let workoutID: UUID
    let performedAt: String
    let localDate: String
    let timeZone: String
    let committedAt: String
    let effectVersion: Int
  }
  struct Activity: Sendable {
    let logID: UUID
    let workoutType: String
    let durationMin: Int
    let intensity: String?
    let estimatedKcal: Int?
  }
  let ownerID: UUID
  let commandID: UUID
  let inputHash: String
  let epoch: UUID
  let registration: Registration
  let activity: Activity
  let feedback: ConversationFeedbackPresentationV2Snapshot?

  init(from decoder: any Decoder) throws {
    do {
      let raw = try PresentationValue(from: decoder)
      _ = try raw.object([
        "schema", "status", "owner_id", "command_id", "input_hash", "epoch",
        "registration", "activity", "feedback",
      ])
      try workoutReplyRequire(
        raw.member("schema").string() == "conversation.workout-command-result.v1")
      try workoutReplyRequire(raw.member("status").string() == "saved")
      ownerID = try workoutReplyUUID(raw.member("owner_id"))
      commandID = try workoutReplyUUID(raw.member("command_id"))
      inputHash = try workoutReplyHash(raw.member("input_hash"))
      epoch = try workoutReplyUUID(raw.member("epoch"))
      let record = try raw.member("registration")
      _ = try record.object([
        "provenance", "registration_id", "workout_id", "performed_at", "local_date",
        "time_zone", "committed_at", "effect_version",
      ])
      try workoutReplyRequire(record.member("provenance").string() == "conversation.workout.v1")
      let registrationID = try workoutReplyUUID(record.member("registration_id"))
      try workoutReplyRequire(registrationID == commandID)
      let workoutID = try workoutReplyUUID(record.member("workout_id"))
      let performedAt = try record.member("performed_at").string()
      let committedAt = try record.member("committed_at").string()
      guard let performed = ConversationProtocolInstant(performedAt),
        let committed = ConversationProtocolInstant(committedAt), performed <= committed
      else { throw WorkoutReplyInvalid.value }
      let localDate = try record.member("local_date").civilDate()
      let timeZone = try record.member("time_zone").string()
      guard let zone = TimeZone(identifier: timeZone) else { throw WorkoutReplyInvalid.value }
      var calendar = Calendar(identifier: .iso8601)
      calendar.timeZone = zone
      let day = calendar.dateComponents(
        [.year, .month, .day], from: Date(timeIntervalSince1970: Double(performed.seconds)))
      guard let year = day.year, let month = day.month, let date = day.day else {
        throw WorkoutReplyInvalid.value
      }
      try workoutReplyRequire(localDate == String(format: "%04d-%02d-%02d", year, month, date))
      let version = try workoutReplyInteger(record.member("effect_version"), min: 1, max: 1)
      registration = .init(
        registrationID: registrationID, workoutID: workoutID, performedAt: performedAt,
        localDate: localDate, timeZone: timeZone, committedAt: committedAt, effectVersion: version)
      let facts = try raw.member("activity")
      _ = try facts.object([
        "kind", "log_id", "workout_type", "duration_min", "intensity", "estimated_kcal",
      ])
      try workoutReplyRequire(facts.member("kind").string() == "workout")
      let logID = try workoutReplyUUID(facts.member("log_id"))
      try workoutReplyRequire(logID == workoutID)
      activity = .init(
        logID: logID, workoutType: try workoutReplyText(facts.member("workout_type"), limit: 200),
        durationMin: try workoutReplyInteger(facts.member("duration_min"), min: 1, max: 1440),
        intensity: try facts.member("intensity").nullable {
          try $0.oneOf(["leve", "moderada", "alta"])
        },
        estimatedKcal: try facts.member("estimated_kcal").nullable {
          try workoutReplyInteger($0, min: 0, max: 10_000)
        })
      if ConversationFeedbackPresentationSelection.selected(from: decoder) == .v2,
        let candidate = try? raw.member("feedback").decode(
          ConversationFeedbackPresentationV2Snapshot.self),
        Self.acceptsFeedback(
          candidate, commandID: commandID, epoch: epoch, registration: registration,
          activity: activity)
      {
        feedback = candidate
      } else {
        // Optional representation failure never turns a saved workout into a retry.
        feedback = nil
      }
    } catch {
      throw workoutReplyFailure(decoder)
    }
  }

  func matches(
    ownerID: UUID, commandID: UUID, inputHash: String, epoch: UUID, admittedAt: String
  ) -> Bool {
    guard self.ownerID == ownerID, self.commandID == commandID, self.inputHash == inputHash,
      self.epoch == epoch, let admitted = ConversationProtocolInstant(admittedAt),
      let performed = ConversationProtocolInstant(registration.performedAt)
    else { return false }
    return admitted == performed
  }

  private static func acceptsFeedback(
    _ value: ConversationFeedbackPresentationV2Snapshot, commandID: UUID, epoch: UUID,
    registration: Registration, activity: Activity
  ) -> Bool {
    guard value.original.kind == "workout",
      UUID(uuidString: value.original.registrationID) == registration.registrationID,
      value.original.localDate == registration.localDate,
      UUID(uuidString: value.provenance.commandID) == commandID,
      UUID(uuidString: value.provenance.epoch) == epoch,
      let observed = ConversationProtocolInstant(value.provenance.observedAt),
      let committed = ConversationProtocolInstant(registration.committedAt), committed <= observed,
      case .workout(let recorded) = value.recorded
    else { return false }
    return UUID(uuidString: recorded.logID) == activity.logID
      && recorded.workoutType.utf16.elementsEqual(activity.workoutType.utf16)
      && recorded.durationMin == Double(activity.durationMin)
      && recorded.intensity == activity.intensity
      && recorded.estimatedKcal == activity.estimatedKcal.map(Double.init)
  }
}

struct ConversationWorkoutCommandStateSnapshot: Decodable, Sendable {
  enum Status: String, Sendable {
    case absent, pending
    case notRecorded = "not_recorded"
    case needsReply = "needs_reply"
  }
  struct Question: Sendable {
    enum Field: String, Sendable {
      case activity
      case durationMin = "duration_min"
    }
    let key: String
    let field: Field
    let text: String
  }
  let status: Status
  let ownerID: UUID
  let commandID: UUID
  let inputHash: String
  let epoch: UUID
  let reason: String?
  let question: Question?

  init(from decoder: any Decoder) throws {
    do {
      let raw = try PresentationValue(from: decoder)
      guard let status = Status(rawValue: try raw.member("status").string()) else {
        throw WorkoutReplyInvalid.value
      }
      self.status = status
      let keys = ["schema", "status", "owner_id", "command_id", "input_hash", "epoch"]
      _ = try raw.object(
        keys + (status == .needsReply ? ["question"] : status == .absent ? [] : ["reason"]))
      try workoutReplyRequire(
        raw.member("schema").string() == "conversation.workout-command-state.v1")
      ownerID = try workoutReplyUUID(raw.member("owner_id"))
      commandID = try workoutReplyUUID(raw.member("command_id"))
      inputHash = try workoutReplyHash(raw.member("input_hash"))
      epoch = try workoutReplyUUID(raw.member("epoch"))
      if status == .needsReply {
        let q = try raw.member("question")
        _ = try q.object(["key", "field", "text"])
        guard let field = Question.Field(rawValue: try q.member("field").string()) else {
          throw WorkoutReplyInvalid.value
        }
        question = .init(
          key: try workoutReplyHash(q.member("key")), field: field,
          text: try workoutReplyText(q.member("text"), limit: 2000))
        reason = nil
      } else {
        question = nil
        if status == .absent {
          reason = nil
        } else {
          let code = try raw.member("reason").string()
          try workoutReplyRequire(
            code.range(of: "^[a-z_]{1,80}$", options: .regularExpression) != nil)
          reason = code
        }
      }
    } catch { throw workoutReplyFailure(decoder) }
  }
  func matches(
    ownerID: UUID, commandID: UUID, inputHash: String, epoch: UUID, admittedAt: String
  ) -> Bool {
    self.ownerID == ownerID && self.commandID == commandID && self.inputHash == inputHash
      && self.epoch == epoch && ConversationProtocolInstant(admittedAt) != nil
  }
}

enum ConversationWorkoutCommandReplySnapshot: Decodable, Sendable {
  case saved(SavedConversationWorkoutCommandResultSnapshot)
  case state(ConversationWorkoutCommandStateSnapshot)
  private enum CodingKeys: String, CodingKey { case schema }
  init(from decoder: any Decoder) throws {
    switch try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .schema) {
    case "conversation.workout-command-result.v1":
      self = .saved(try SavedConversationWorkoutCommandResultSnapshot(from: decoder))
    case "conversation.workout-command-state.v1":
      self = .state(try ConversationWorkoutCommandStateSnapshot(from: decoder))
    default: throw workoutReplyFailure(decoder)
    }
  }
  func matches(
    ownerID: UUID, commandID: UUID, inputHash: String, epoch: UUID, admittedAt: String
  ) -> Bool {
    switch self {
    case .saved(let value):
      value.matches(
        ownerID: ownerID, commandID: commandID, inputHash: inputHash, epoch: epoch,
        admittedAt: admittedAt)
    case .state(let value):
      value.matches(
        ownerID: ownerID, commandID: commandID, inputHash: inputHash, epoch: epoch,
        admittedAt: admittedAt)
    }
  }
  func acceptsHTTPStatus(_ code: Int) -> Bool {
    switch self {
    case .saved: code == 200
    case .state(let value): value.status == .pending ? code == 202 : code == 200
    }
  }
}

private enum WorkoutReplyInvalid: Error { case value }
private func workoutReplyRequire(_ value: Bool) throws {
  if !value { throw WorkoutReplyInvalid.value }
}
private func workoutReplyUUID(_ value: PresentationValue) throws -> UUID {
  let raw = try value.string()
  try workoutReplyRequire(
    raw.range(
      of: "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$",
      options: .regularExpression) != nil)
  guard let id = UUID(uuidString: raw) else { throw WorkoutReplyInvalid.value }
  return id
}
private func workoutReplyHash(_ value: PresentationValue) throws -> String {
  let raw = try value.string()
  try workoutReplyRequire(raw.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil)
  return raw
}
private func workoutReplyInteger(_ value: PresentationValue, min: Int, max: Int) throws -> Int {
  let amount = try value.amount(max: Double(max))
  try workoutReplyRequire(amount.rounded(.down) == amount && amount >= Double(min))
  return Int(amount)
}
private func workoutReplyText(_ value: PresentationValue, limit: Int) throws -> String {
  let raw = try value.string()
  try workoutReplyRequire(neutralText(raw, limit: limit))
  return raw
}
private func workoutReplyFailure(_ decoder: any Decoder) -> DecodingError {
  .dataCorrupted(
    .init(codingPath: decoder.codingPath, debugDescription: "Workout reply unavailable"))
}
