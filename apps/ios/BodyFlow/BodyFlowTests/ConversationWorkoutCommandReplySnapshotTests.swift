import Foundation
import Testing

@testable import BodyFlow

@Suite("Closed factual workout reply and real child binding")
struct ConversationWorkoutCommandReplySnapshotTests {
  @Test func actualSQLProjectionPreservesKnownAndUnknownEnergy() throws {
    let known = try saved(knownJSON)
    let unknown = try saved(unknownJSON)
    #expect(known.activity.durationMin == 30 && known.activity.estimatedKcal == 154)
    #expect(unknown.activity.durationMin == 30 && unknown.activity.estimatedKcal == nil)
    #expect(
      known.registration.workoutID.uuidString.lowercased() == "a1114546-c985-4893-94f1-fcda52a4030a"
    )
    #expect(known.registration.registrationID == known.commandID)
    #expect(known.feedback == nil && unknown.feedback == nil)
  }
  @Test(
    arguments: ["workout_type", "question"],
    ["bom", "nel", "ascii_blank", "control", "del", "utf16_limit", "utf16_over", "literal"])
  func textMatchesActualServerECMAScriptTrimWithoutChangingOriginalBytes(
    _ field: String, _ example: String
  ) throws {
    // Directed UNIT mutations of the unchanged actual PG-derived base packet.
    // Expected outcomes come from TS workoutText / ECMAScript trim, not Swift.
    let limit = field == "workout_type" ? 200 : 2000
    let text: String
    switch example {
    case "bom": text = "\u{FEFF}"
    case "nel": text = "\u{0085}"
    case "ascii_blank": text = " \t\r\n"
    case "control": text = "walk\u{001F}"
    case "del": text = "walk\u{007F}"
    case "utf16_limit": text = String(repeating: "😀", count: limit / 2)
    case "utf16_over": text = String(repeating: "😀", count: limit / 2 + 1)
    default: text = "  caminhada\t\r\n\u{FEFF}  "
    }
    var p = field == "workout_type" ? try object(knownJSON) : try state("needs_reply")
    try set(
      &p, field == "workout_type" ? "activity" : "question",
      field == "workout_type" ? "workout_type" : "text", text)
    if ["bom", "ascii_blank", "control", "del", "utf16_over"].contains(example) {
      #expect(throws: (any Error).self) { try decode(p) }
    } else if field == "workout_type" {
      #expect(try decodeSaved(p).activity.workoutType == text)
    } else {
      guard case .state(let value) = try decode(p) else {
        Issue.record("Expected typed question")
        return
      }
      #expect(value.question?.text == text)
    }
  }
  @Test func knownZeroRemainsKnownAndNoEnergyIsComputed() throws {
    var p = try object(knownJSON)
    try set(&p, "activity", "estimated_kcal", 0)
    #expect(try decodeSaved(p).activity.estimatedKcal == 0)
  }
  @Test func savedMatchesOnlyTheRealTypedChildAndAdmittedClock() throws {
    let p = try saved(knownJSON)
    #expect(
      p.matches(
        ownerID: p.ownerID, commandID: p.commandID, inputHash: p.inputHash,
        epoch: p.epoch, admittedAt: "2026-11-05T00:35:36.966052Z"))
    #expect(
      !p.matches(
        ownerID: UUID(), commandID: p.commandID, inputHash: p.inputHash,
        epoch: p.epoch, admittedAt: p.registration.performedAt))
    #expect(
      !p.matches(
        ownerID: p.ownerID, commandID: UUID(), inputHash: p.inputHash,
        epoch: p.epoch, admittedAt: p.registration.performedAt))
    #expect(
      !p.matches(
        ownerID: p.ownerID, commandID: p.commandID, inputHash: String(repeating: "f", count: 64),
        epoch: p.epoch, admittedAt: p.registration.performedAt))
    #expect(
      !p.matches(
        ownerID: p.ownerID, commandID: p.commandID, inputHash: p.inputHash,
        epoch: UUID(), admittedAt: p.registration.performedAt))
    #expect(
      !p.matches(
        ownerID: p.ownerID, commandID: p.commandID, inputHash: p.inputHash,
        epoch: p.epoch, admittedAt: "2026-11-05T00:35:36.966052001Z"))
  }
  @Test(arguments: [
    "schema", "extra", "owner", "command", "hash", "epoch", "registration", "workout", "log",
    "provenance", "effect", "duration", "intensity", "energy", "date", "zone", "clock", "nanoclock",
    "private", "missingFeedback",
  ])
  func principalFailureNeverDecodesSaved(_ attack: String) throws {
    var p = try object(knownJSON)
    switch attack {
    case "schema": p["schema"] = "conversation.workout-command-result.v2"
    case "extra": p["private_context"] = "private"
    case "owner": p["owner_id"] = "BAD"
    case "command": p["command_id"] = "bad"
    case "hash": p["input_hash"] = "bad"
    case "epoch": p["epoch"] = "bad"
    case "registration":
      try set(&p, "registration", "registration_id", UUID().uuidString.lowercased())
    case "workout": try set(&p, "registration", "workout_id", UUID().uuidString.lowercased())
    case "log": try set(&p, "activity", "log_id", "bad")
    case "provenance": try set(&p, "registration", "provenance", "legacy")
    case "effect": try set(&p, "registration", "effect_version", 2)
    case "duration": try set(&p, "activity", "duration_min", 0)
    case "intensity": try set(&p, "activity", "intensity", "high")
    case "energy": try set(&p, "activity", "estimated_kcal", -1)
    case "date": try set(&p, "registration", "local_date", "2026-11-04")
    case "zone": try set(&p, "registration", "time_zone", "not/a/zone")
    case "clock": try set(&p, "registration", "committed_at", "2026-11-04T00:00:00Z")
    case "nanoclock": try set(&p, "registration", "committed_at", "2026-11-05T00:35:36.966051999Z")
    case "private": try set(&p, "activity", "source_hash", String(repeating: "a", count: 64))
    case "missingFeedback": p.removeValue(forKey: "feedback")
    default: Issue.record("Unknown attack")
    }
    #expect(throws: (any Error).self) { try decode(p) }
  }
  @Test(arguments: ["null", "number", "raw", "malformedPresentation"])
  func optionalFeedbackFailurePreservesFactualSaved(_ kind: String) throws {
    var p = try object(knownJSON)
    switch kind {
    case "null": p["feedback"] = NSNull()
    case "number": p["feedback"] = 42
    case "raw": p["feedback"] = ["schema": "registration.feedback.v3"]
    default: p["feedback"] = ["schema": "conversation.feedback-presentation.v2"]
    }
    #expect(try decodeSaved(p).feedback == nil)
    #expect(
      try decodeSaved(p).registration.registrationID.uuidString.lowercased()
        == "3cc9561c-43c4-4250-a065-be0d5af2a640")
  }
  @Test func optionalPresentationRequiresSelectionAndExactWorkoutFacts() throws {
    // Controlled UNIT envelope around the existing unmodified wrapper fixture.
    // This is decoder/binding evidence, never an actual HTTP or SQL ACK claim.
    let wrapper = try object(workoutPresentationJSON)
    let source = try #require(wrapper["provenance"] as? [String: Any])
    let original = try #require(wrapper["original"] as? [String: Any])
    var activity = try #require(wrapper["recorded"] as? [String: Any])
    var p = try object(knownJSON)
    p["owner_id"] = "b7720000-0000-4000-8000-000000000102"
    p["command_id"] = source["command_id"]
    p["epoch"] = source["epoch"]
    p["registration"] = [
      "provenance": "conversation.workout.v1",
      "registration_id": original["registration_id"]!, "workout_id": activity["log_id"]!,
      "performed_at": "2026-11-05T17:00:00Z", "committed_at": "2026-11-05T17:00:01Z",
      "local_date": "2026-11-05", "time_zone": "UTC", "effect_version": 1,
    ]
    p["activity"] = activity
    p["feedback"] = wrapper
    guard case .saved(let unselected) = try decode(p) else {
      Issue.record("Missing saved")
      return
    }
    #expect(unselected.feedback == nil)
    guard case .saved(let selected) = try decode(p, selection: .v2) else {
      Issue.record("Missing saved")
      return
    }
    #expect(selected.feedback?.sections.count == 6)
    #expect(selected.feedback?.original.kind == "workout")
    activity["estimated_kcal"] = NSNull()
    p["activity"] = activity
    guard case .saved(let changed) = try decode(p, selection: .v2) else {
      Issue.record("Missing saved")
      return
    }
    #expect(changed.feedback == nil)
    #expect(changed.activity.estimatedKcal == nil)
  }
  @Test(arguments: ["absent", "pending", "not_recorded", "needs_reply"])
  func stateIsNeverSaved(_ status: String) throws {
    let p = try state(status)
    let reply = try decode(p)
    guard case .state(let s) = reply else {
      Issue.record("State became saved")
      return
    }
    #expect(s.status.rawValue == status)
    #expect(reply.acceptsHTTPStatus(status == "pending" ? 202 : 200))
    #expect(!reply.acceptsHTTPStatus(status == "pending" ? 200 : 202))
  }
  @Test(arguments: [
    "extra", "questionMissing", "questionWrongField", "questionExtra", "reasonOnAbsent",
  ])
  func stateShapeIsClosed(_ attack: String) throws {
    var p = try state(attack == "reasonOnAbsent" ? "absent" : "needs_reply")
    switch attack {
    case "extra": p["receipt"] = [:] as [String: String]
    case "questionMissing": p.removeValue(forKey: "question")
    case "questionWrongField": try set(&p, "question", "field", "meal_type")
    case "questionExtra": try set(&p, "question", "private", "private")
    case "reasonOnAbsent": p["reason"] = "unknown"
    default: Issue.record("Unknown attack")
    }
    #expect(throws: (any Error).self) { try decode(p) }
  }
  private func state(_ status: String) throws -> [String: Any] {
    let saved = try object(knownJSON)
    var result = saved.filter {
      ["owner_id", "command_id", "input_hash", "epoch"].contains($0.key)
    }
    result["schema"] = "conversation.workout-command-state.v1"
    result["status"] = status
    if status == "pending" { result["reason"] = "reconciliation_required" }
    if status == "not_recorded" { result["reason"] = "non_performed_or_conflicting_source" }
    if status == "needs_reply" {
      result["question"] = [
        "key": String(repeating: "a", count: 64), "field": "duration_min",
        "text": "Por quanto tempo?",
      ]
    }
    return result
  }
  private func decode(
    _ p: [String: Any], selection: ConversationFeedbackPresentationSelection? = nil
  ) throws -> ConversationWorkoutCommandReplySnapshot {
    try ConversationFeedbackPresentationSelection.decoder(selection: selection).decode(
      ConversationWorkoutCommandReplySnapshot.self, from: JSONSerialization.data(withJSONObject: p))
  }
  private func saved(_ json: String) throws -> SavedConversationWorkoutCommandResultSnapshot {
    try decodeSaved(object(json))
  }
  private func decodeSaved(_ p: [String: Any]) throws
    -> SavedConversationWorkoutCommandResultSnapshot
  {
    guard case .saved(let result) = try decode(p) else { throw TestFailure.value }
    return result
  }
  private func object(_ json: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
  }
  private func set(_ p: inout [String: Any], _ key: String, _ field: String, _ value: Any) throws {
    var child = try #require(p[key] as? [String: Any])
    child[field] = value
    p[key] = child
  }
  private enum TestFailure: Error { case value }
  // Exact public projection of real synthetic PG receipt pieces using service.ts:96–112.
  // PG fixture provenance: owned atomic core under rollback; not HTTP/provider/native E2E.
  private let workoutPresentationJSON =
    #"{"schema":"conversation.feedback-presentation.v2","mode":"historical","assistant":"Flow AI","original":{"schema":"registration.feedback.v3","registration_id":"139f0000-0000-4000-8000-000000000034","kind":"workout","local_date":"2026-11-05"},"status":"available","format":"sections","recorded":{"kind":"workout","log_id":"8943b5cf-f8c6-49ee-b0c3-3808b09bdb70","intensity":"moderada","duration_min":30,"workout_type":"caminhada","estimated_kcal":154},"sections":[{"key":"saved","text":"Atividade registrada."},{"key":"items","text":"caminhada · 30 min · moderada"},{"key":"summary","text":"Gasto estimado: 154 kcal."},{"key":"day","text":"No momento deste registro (2026-11-05):\nDia: 2026-11-05\nConsumido: 0 kcal. Meta indisponível.\nProteína: 0 g. Meta indisponível.\nSaldo alimentar indisponível.\nExercício registrado: 154 kcal. Esse gasto não aumenta a comida disponível."},{"key":"block","text":"Progresso consolidado no momento do registro:\nAs orientações de longo prazo estão pausadas."},{"key":"education","text":"O comentário educativo está indisponível; seu registro continua salvo."}],"current_policy":{"version":1,"observed_at":"2026-11-05T18:00:00Z","assessment":"complete","recording_allowed":true,"pause_weight_loss_guidance":false,"professional_assessment_recommended":false,"phase_selection_pending":false,"target_source":"official_only","hide":{"objective":false,"calories":false,"protein":false,"balance":false,"block":false,"budget":false}},"provenance":{"epoch":"b7720000-0000-4000-8000-000000000103","command_id":"139f0000-0000-4000-8000-000000000034","observed_at":"2026-11-05T18:00:00Z"}}"#
  private let knownJSON =
    #"{"owner_id":"139c0000-0000-4000-8000-000000000020","command_id":"3cc9561c-43c4-4250-a065-be0d5af2a640","input_hash":"a0b18222d3412d77e255cee02a69eb2c2541aebf4ee2b8714a7d4a7cb46be42a","epoch":"59334e5e-dc1c-408e-a268-b252eb02abe1","schema":"conversation.workout-command-result.v1","status":"saved","registration":{"provenance":"conversation.workout.v1","registration_id":"3cc9561c-43c4-4250-a065-be0d5af2a640","workout_id":"a1114546-c985-4893-94f1-fcda52a4030a","performed_at":"2026-11-05T00:35:36.966052Z","local_date":"2026-11-05","time_zone":"UTC","committed_at":"2026-11-05T00:35:37.012961Z","effect_version":1},"activity":{"kind":"workout","log_id":"a1114546-c985-4893-94f1-fcda52a4030a","intensity":"moderada","duration_min":30,"workout_type":"caminhada","estimated_kcal":154},"feedback":null}"#
  private let unknownJSON =
    #"{"owner_id":"139c0000-0000-4000-8000-000000000001","command_id":"139c0000-0000-4000-8000-000000000002","input_hash":"19cd4f402e1c7d9205f4e6c5d087f0777cd96854d28b43b50b8ef7aea94a70e4","epoch":"74660fd1-65a0-4f79-9255-96f64063127e","schema":"conversation.workout-command-result.v1","status":"saved","registration":{"provenance":"conversation.workout.v1","registration_id":"139c0000-0000-4000-8000-000000000002","workout_id":"6e1dd3b0-8610-4972-b35c-66a2abd53d17","performed_at":"2026-11-05T00:35:36.408754Z","local_date":"2026-11-05","time_zone":"UTC","committed_at":"2026-11-05T00:35:36.536072Z","effect_version":1},"activity":{"kind":"workout","log_id":"6e1dd3b0-8610-4972-b35c-66a2abd53d17","intensity":null,"duration_min":30,"workout_type":"caminhada","estimated_kcal":null},"feedback":null}"#
}
