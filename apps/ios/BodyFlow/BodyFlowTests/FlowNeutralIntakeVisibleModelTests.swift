import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@MainActor @Suite("Actual Flow composition sends neutral text without retagging old meals")
struct FlowNeutralIntakeVisibleModelTests {
  @Test func actualComposerModeSavesOneGenuineTypedMealAndInvalidatesOfficialReadsOnce()
    async throws
  {
    let f = try await neutralVisibleFixture()
    defer { f.disk.remove() }
    let model = try await FlowConversationModel.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "leite integral 206 g"
    neutral.mealTypeHint = .cafe
    #expect(neutral.canSubmit)
    await neutral.submit()
    #expect(neutral.composer.isEmpty)
    #expect(neutral.savedRows.count == 1)
    #expect(model.savedEffectRevision == 1)
    #expect(model.pendingRows.isEmpty)
    let requests = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(requests.count == 1 && requests[0].url?.path == "/api/mobile/v1/conversation/intakes")
    let receivedBody = try #require(requests[0].httpBody)
    let raw = try #require(JSONSerialization.jsonObject(with: receivedBody) as? [String: Any])
    #expect(raw["kind"] == nil && raw["intake_protocol"] as? String == "conversation.intake.v1")
    #expect((raw["source"] as? [String: Any])?["text"] as? String == "leite integral 206 g")
    #expect(
      requests[0].value(forHTTPHeaderField: "Idempotency-Key") == "cintake1:"
        + (raw["intake_id"] as! String))
    await model.close()
  }
  @Test func lostResponseKeepsOriginalInputAndExplicitGetPublishesSavedWithoutAnotherPost()
    async throws
  {
    let f = try await neutralVisibleFixture(loseFirstPost: true)
    defer { f.disk.remove() }
    let model = try await FlowConversationModel.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "leite integral 206 g"
    neutral.mealTypeHint = .cafe
    await neutral.submit()
    #expect(neutral.savedRows.isEmpty)
    let id = try #require(neutral.pendingRows.first?.input.intakeID)
    await neutral.reconcile(intakeID: id)
    #expect(neutral.savedRows.count == 1 && model.savedEffectRevision == 1)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }
  @Test(arguments: ["workout_known_unit", "workout_unknown_unit"])
  func actualNeutralControllerPublishesTypedWorkoutWithoutMealBindingOrEnergyFallback(
    _ variant: String
  ) async throws {
    let f = try await neutralVisibleFixture(variant: variant)
    defer { f.disk.remove() }
    let model = try await FlowConversationModel.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "Fiz 30 minutos de caminhada."
    await neutral.submit()
    let row = try #require(neutral.savedRows.first)
    guard case .workout(let saved) = row.acknowledgement else {
      Issue.record("Workout must stay typed")
      return
    }
    #expect(saved.activity.estimatedKcal == (variant == "workout_known_unit" ? 154 : nil))
    #expect(model.savedEffectRevision == 1 && model.savedRows.isEmpty)
    await model.close()
  }
  @Test func oldQueuedMealStaysByteExactWhileNewComposerUsesOnlyNeutralEndpoint() async throws {
    let f = try await neutralVisibleFixture()
    defer { f.disk.remove() }
    let lease = try await f.http.lifecycle.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let key = try await f.vault.key(owner: owner, mayCreate: true)
    let old = try ConversationMealCommand(source: .text("original old queued meal"))
    let t = try neutralRuntimeTicket()
    try f.disk.store.update(owner: owner, key: key) {
      $0.append(
        .init(command: old, originalServerEpoch: t.epoch, originalPatientOwnerID: t.ownerID))
    }
    let model = try await FlowConversationModel.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "leite integral 206 g"
    neutral.mealTypeHint = .cafe
    await neutral.submit()
    let remaining = try #require(f.disk.store.load(owner: owner, key: key).first)
    #expect(
      remaining.commandID == old.commandID && remaining.wireBody == old.wireBody
        && remaining.inputHash == old.inputHash && remaining.state == .queued)
    #expect(
      await f.http.stub.requests.filter {
        $0.httpMethod == "POST" && $0.url?.path.contains("meal-commands") == true
      }.isEmpty)
    await model.close()
  }
  @Test(arguments: ["pt", "en"])
  func workoutPresentationHasItsOwnFactBindingAndKeepsSixCurrentPolicySections(_ language: String)
    throws
  {
    let (saved, scope) = try neutralWorkoutPresentationUnit(language: language)
    let bound = try #require(
      ConversationFeedbackPresentationSnapshot.boundWorkout(saved, scope: scope))
    guard case .v3Sections(let recorded, let sections) = bound.presentation.content,
      case .workout = recorded
    else {
      Issue.record("Workout must not acquire meal binding")
      return
    }
    #expect(
      sections.map(\.key.rawValue) == ["saved", "items", "summary", "day", "block", "education"])
    #expect(
      ConversationFeedbackPresentationSnapshot.boundWorkout(
        saved,
        scope: .init(
          ownerID: UUID().uuidString.lowercased(), sessionGeneration: scope.sessionGeneration,
          epoch: scope.epoch)) == nil)
    #expect(
      ConversationFeedbackPresentationSnapshot.boundWorkout(
        saved,
        scope: .init(
          ownerID: scope.ownerID, sessionGeneration: scope.sessionGeneration,
          epoch: UUID().uuidString.lowercased())) == nil)
  }
  @Test(arguments: [
    "outer_not_recorded_unit", "meal_not_recorded_unit", "workout_not_recorded_unit",
  ])
  func provenNotRecordedClosesOnlyItsNeutralRowWithoutFactualInvalidation(_ variant: String)
    async throws
  {
    let f = try await neutralVisibleFixture(variant: variant)
    defer { f.disk.remove() }
    let lease = try await f.http.lifecycle.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let key = try await f.vault.key(owner: owner, mayCreate: true)
    let old = try ConversationMealCommand(source: .text("preserve queued literal"))
    let t = try neutralRuntimeTicket()
    try f.disk.store.update(owner: owner, key: key) {
      $0.append(
        .init(command: old, originalServerEpoch: t.epoch, originalPatientOwnerID: t.ownerID))
    }
    let model = try await FlowConversationModel.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "Mensagem de teste sem registro"
    await neutral.submit()
    #expect(try f.disk.store.loadIntakes(owner: owner, key: key).isEmpty)
    #expect(
      neutral.terminalRows.count == 1
        && neutral.terminalRows.first?.response.deliveryState == .notRecorded)
    #expect(
      neutral.pendingRows.isEmpty && neutral.savedRows.isEmpty && model.savedEffectRevision == 0)
    #expect(try f.disk.store.load(owner: owner, key: key).first?.wireBody == old.wireBody)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }
  @Test(arguments: ["clarification_unit", "workout_needs_reply_unit"])
  func unansweredQuestionsStayProtectedWithoutSavedOrContinuation(_ variant: String) async throws {
    let f = try await neutralVisibleFixture(variant: variant)
    defer { f.disk.remove() }
    let lease = try await f.http.lifecycle.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let key = try await f.vault.key(owner: owner, mayCreate: true)
    let model = try await FlowConversationModel.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "Fiz atividade"
    await neutral.submit()
    let pending = try #require(neutral.pendingRows.first)
    try #require(neutral.state(intakeID: pending.input.intakeID))
    await neutral.reconcile(intakeID: pending.input.intakeID)
    let response = try #require(neutral.state(intakeID: pending.input.intakeID))
    #expect(
      neutral.terminalRows.isEmpty && neutral.savedRows.isEmpty && model.savedEffectRevision == 0)
    #expect(!neutral.canContinue(intakeID: pending.input.intakeID))
    #expect(
      try f.disk.store.loadIntakes(owner: owner, key: key).first?.input.wireBody
        == pending.input.wireBody)
    if variant == "clarification_unit" {
      #expect(response.question?.text == "O que você já consumiu ou realizou?")
    } else {
      guard case .workout(.state(let state)) = response.result else {
        Issue.record("Typed question required")
        return
      }
      #expect(state.question?.text == "Quantos minutos você realizou?")
    }
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }
  @Test func bundledSelectionIsExplicitAndKeepsOldSelectionLiteral() {
    #expect(FlowConversationRuntimeSelection.load("neutral_intake_v1") == .neutralIntakeV1)
    #expect(FlowConversationRuntimeSelection.load("meal_command_v1") == .mealCommandV1)
    #expect(FlowConversationRuntimeSelection.load(nil) == .legacy)
  }
}
struct NeutralVisibleFixture {
  let http: ConversationHTTPFixture
  let disk: OutboxDiskFixture
  let vault: ConversationOutboxKeyVault
  let server: NeutralVisibleUnitServer
}
func neutralVisibleFixture(loseFirstPost: Bool = false, variant: String = "meal_unit") async throws
  -> NeutralVisibleFixture
{
  let http = try ConversationHTTPFixture()
  let disk = try OutboxDiskFixture()
  let lease = try await http.lifecycle.leaseForRequest()
  let server = try NeutralVisibleUnitServer(
    auth: lease.userID, loseFirstPost: loseFirstPost, variant: variant)
  await http.stub.respond { request, _ in try await server.reply(request) }
  return .init(
    http: http, disk: disk,
    vault: .init(service: "neutral-visible-unit", security: OutboxKeychainFake()), server: server)
}
/// Controlled UNIT server around the unchanged actual typed projector packet.
/// Rebinding neutral metadata here proves client routing, not persisted HTTP/PG.
actor NeutralVisibleUnitServer {
  let auth: String
  var loseFirstPost: Bool
  var original: Data?
  let base: Data
  let session: Data
  init(auth: String, loseFirstPost: Bool, variant: String) throws {
    self.auth = auth
    self.loseFirstPost = loseFirstPost
    let controlled =
      variant.contains("not_recorded") || variant == "clarification_unit"
      || variant == "workout_needs_reply_unit"
    let basis =
      controlled ? (variant.hasPrefix("workout") ? "workout_known_unit" : "meal_unit") : variant
    let unit = try neutralFixture()[basis] as! [String: Any]
    let binding = unit["binding"] as! [String: Any]
    if variant == "clarification_unit" {
      self.base = try neutralData(neutralUncertainUnit("clarification"))
    } else if variant == "workout_needs_reply_unit" {
      var packet = unit["response"] as! [String: Any]
      var selection = packet["selection"] as! [String: Any]
      var child = selection["command"] as! [String: Any]
      packet["result"] = [
        "schema": "conversation.workout-command-state.v1", "status": "needs_reply",
        "owner_id": child["owner_id"]!, "command_id": child["command_id"]!,
        "input_hash": child["input_hash"]!, "epoch": child["epoch"]!,
        "question": [
          "key": String(repeating: "a", count: 64), "field": "duration_min",
          "text": "Quantos minutos você realizou?",
        ],
      ]
      self.base = try neutralData(packet)
    } else {
      self.base = try neutralData(
        variant.contains("not_recorded")
          ? neutralNotRecordedUnit(variant: variant) : unit["response"]!)
    }
    self.session = try neutralData([
      "schema": "conversation.intake-session.v1", "auth_user_id": auth,
      "owner_id": binding["owner_id"]!, "epoch": binding["epoch"]!,
      "observed_at": basis == "meal_unit" ? "2026-11-03T12:00:00Z" : "2026-11-05T12:00:00Z",
      "intake_protocol": "conversation.intake.v1",
    ])
  }
  func reply(_ request: URLRequest) throws -> ConversationHTTPReply {
    let path = request.url!.path
    if path == "/api/mobile/v1/conversation/session" {
      var p = try JSONSerialization.jsonObject(with: session) as! [String: Any]
      p["schema"] = "conversation.session.v1"
      p.removeValue(forKey: "intake_protocol")
      p["meal_command_protocol"] = "conversation.command.v1"
      var r = try neutralHTTP(p)
      r.headers["X-Conversation-Protocol"] = "meal-command-v1"
      return r
    }
    if path == "/api/mobile/v1/conversation/intakes/session" {
      return try neutralHTTP(JSONSerialization.jsonObject(with: session))
    }
    if request.httpMethod == "POST" {
      original = request.httpBody
      if loseFirstPost {
        loseFirstPost = false
        throw URLError(.networkConnectionLost)
      }
    }
    guard let original,
      let input = try JSONSerialization.jsonObject(with: original) as? [String: Any]
    else { throw URLError(.badServerResponse) }
    var p = try JSONSerialization.jsonObject(with: base) as! [String: Any]
    var binding = p["intake"] as! [String: Any]
    binding["intake_id"] = input["intake_id"]
    binding["input_hash"] = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
    p["intake"] = binding
    return try neutralHTTP(p)
  }
}

/// Current-policy wrapper is unchanged from the pinned pure prepare/render
/// fixture. Outer ACK scope/clocks are explicitly UNIT, never HTTP/PG proof.
func neutralWorkoutPresentationUnit(language: String = "pt") throws -> (
  SavedConversationWorkoutCommandResultSnapshot, ConversationFeedbackPresentationSnapshot.Scope
) {
  let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
    "Fixtures/ConversationFeedbackPresentationV2Fixtures.json")
  let root = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
  let example = try #require(
    (root["fixtures"] as! [[String: Any]]).first {
      $0["case"] as? String
        == (language == "en" ? "pure-unit-unknown_workout-en" : "pg-original-known_workout-pt")
    })
  let wrapper = example["expected"] as! [String: Any]
  let binding = example["external_binding"] as! [String: Any]
  let provenance = wrapper["provenance"] as! [String: Any]
  let facts = wrapper["recorded"] as! [String: Any]
  let identity = wrapper["original"] as! [String: Any]
  let unit = try neutralFixture()["workout_known_unit"] as! [String: Any]
  let response = unit["response"] as! [String: Any]
  var packet = response["result"] as! [String: Any]
  var registration = packet["registration"] as! [String: Any]
  packet["owner_id"] = binding["owner_id"]
  packet["command_id"] = provenance["command_id"]
  packet["epoch"] = provenance["epoch"]
  registration["registration_id"] = identity["registration_id"]
  registration["workout_id"] = facts["log_id"]
  registration["performed_at"] = binding["admitted_at"]
  registration["committed_at"] = provenance["observed_at"]
  registration["local_date"] = identity["local_date"]
  registration["time_zone"] = "UTC"
  packet["registration"] = registration
  packet["activity"] = facts
  packet["feedback"] = wrapper
  let saved = try ConversationFeedbackPresentationSelection.decoder(selection: .v2).decode(
    SavedConversationWorkoutCommandResultSnapshot.self, from: neutralData(packet))
  return (
    saved,
    .init(
      ownerID: binding["owner_id"] as! String, sessionGeneration: 7,
      epoch: provenance["epoch"] as! String)
  )
}

/// Counterfactual closed state UNIT around unchanged real typed binding pieces.
/// This is not a SQL or publicHTTP terminal response.
func neutralNotRecordedUnit(variant: String) throws -> [String: Any] {
  let basis = variant.hasPrefix("workout") ? "workout_known_unit" : "meal_unit"
  let unit = try neutralFixture()[basis] as! [String: Any]
  var packet = unit["response"] as! [String: Any]
  let selection = packet["selection"] as! [String: Any]
  let child = selection["command"] as! [String: Any]
  if variant.hasPrefix("outer") {
    return [
      "schema": "conversation.intake-result.v1", "status": "not_recorded",
      "intake": packet["intake"]!, "source_hash": selection["source_hash"]!,
      "decision_hash": selection["decision_hash"]!, "reason": "not_consumed",
    ]
  }
  var state: [String: Any] = [
    "schema": basis == "meal_unit"
      ? "conversation.meal-command-state.v1" : "conversation.workout-command-state.v1",
    "status": "not_recorded", "owner_id": child["owner_id"]!, "command_id": child["command_id"]!,
    "input_hash": child["input_hash"]!, "epoch": child["epoch"]!, "reason": "not_consumed",
  ]
  if basis == "meal_unit" { state["food_indexes"] = [] as [Int] }
  packet["result"] = state
  return packet
}
