import Foundation
import Testing

@testable import BodyFlow

@Suite("Negotiated neutral media binds the original attachment to the factual child")
struct FlowMediaIntakeContractsTests {
  @Test(arguments: ["meal_photo", "audio_workout"])
  func actualSQLMediaReceiptAcknowledgesOnlyTheOriginalTicket(_ label: String) throws {
    let unit = try mediaIntakeUnit(label)
    let ticket = try mediaIntakeTicket(unit)
    let reply = try mediaIntakeDecode(unit["response"]!)
    #expect(reply.matches(ticket))
    switch (label, reply.factualAcknowledgement(for: ticket)) {
    case ("meal_photo", .meal(let saved)?):
      #expect(saved.receipt.registrationID == "b56ae1d2-466d-4f18-b4f2-37c8ef60a69f")
    case ("audio_workout", .workout(let saved)?):
      #expect(saved.activity.durationMin == 30 && saved.activity.estimatedKcal == nil)
    default: Issue.record("A genuine bound receipt is required")
    }
    let foreign = FlowNeutralIntakeTicket(
      input: ticket.input, ownerID: UUID(), epoch: ticket.epoch,
      ownerHash: ticket.ownerHash, sessionGeneration: ticket.sessionGeneration)
    #expect(!reply.matches(foreign) && reply.factualAcknowledgement(for: foreign) == nil)
  }
  @Test(arguments: ["audio_note_not_performed", "gym_photo_not_performed"])
  func actualNonPerformedMediaDoesNotBecomeARegistration(_ label: String) throws {
    let unit = try mediaIntakeUnit(label)
    let ticket = try mediaIntakeTicket(unit)
    let reply = try mediaIntakeDecode(unit["response"]!)
    #expect(reply.matches(ticket))
    #expect(reply.factualAcknowledgement(for: ticket) == nil)
  }
  @Test(arguments: ["meal_photo", "audio_workout"])
  func mediaResultRequiresExplicitDecoderNegotiation(_ label: String) throws {
    let packet = try mediaIntakeUnit(label)["response"]!
    for selection in [nil, "2", "true"] as [String?] {
      #expect(throws: (any Error).self) { try mediaIntakeDecode(packet, selection: selection) }
    }
  }
  @Test func legacyMediaEnvelopeCannotBeUpgradedIntoAnAcknowledgement() throws {
    let unit = try mediaIntakeUnit("meal_photo")
    let ticket = try mediaIntakeTicket(unit)
    var p = unit["response"] as! [String: Any]
    var s = p["selection"] as! [String: Any]
    p["schema"] = "conversation.intake-result.v1"
    s.removeValue(forKey: "media_projection")
    p["selection"] = s
    let legacy = try mediaIntakeDecode(p, selection: nil)
    #expect(legacy.factualAcknowledgement(for: ticket) == nil)
    #expect(try mediaIntakeDecode(p).factualAcknowledgement(for: ticket) == nil)
  }
  @Test(arguments: [
    "projection", "originSchema", "parentID", "inputHash", "sourceHash", "epoch", "decisionHash",
    "claim", "childHash", "owner", "kind", "processedClock", "updatedClock", "futureClock",
    "processingHash", "privateURL", "version",
  ])
  func changedOrPrivateProjectionIsRefused(_ attack: String) throws {
    var p = try mediaIntakeUnit("meal_photo")["response"] as! [String: Any]
    var s = p["selection"] as! [String: Any]
    var projection = s["media_projection"] as! [String: Any]
    var origin = projection["origin"] as! [String: Any]
    var media = projection["media"] as! [String: Any]
    switch attack {
    case "projection": projection["schema"] = "unapproved"
    case "originSchema": origin["schema"] = "unapproved"
    case "parentID": origin["intake_id"] = UUID().uuidString.lowercased()
    case "inputHash": origin["input_hash"] = String(repeating: "f", count: 64)
    case "sourceHash": origin["source_hash"] = String(repeating: "f", count: 64)
    case "epoch": origin["epoch"] = UUID().uuidString.lowercased()
    case "decisionHash": origin["decision_hash"] = String(repeating: "f", count: 64)
    case "claim": origin["claim_id"] = "not-a-uuid"
    case "childHash": projection["child_input_hash"] = String(repeating: "f", count: 64)
    case "owner": media["owner_id"] = UUID().uuidString.lowercased()
    case "kind": media["kind"] = "gym_photo"
    case "processedClock": media["processed_at"] = "invalid"
    case "updatedClock": media["updated_at"] = "invalid"
    case "futureClock": media["processed_at"] = "2099-01-01T00:00:00Z"
    case "processingHash": media["processing_hash"] = "invalid"
    case "privateURL": media["signed_url"] = "https://unit.invalid/private"
    default: p["schema"] = "conversation.intake-result.v1"
    }
    projection["origin"] = origin
    projection["media"] = media
    s["media_projection"] = projection
    p["selection"] = s
    #expect(throws: (any Error).self) { try mediaIntakeDecode(p) }
  }
  @Test func validDifferentAssetCannotMatchTheOriginalTicket() throws {
    let unit = try mediaIntakeUnit("meal_photo")
    let ticket = try mediaIntakeTicket(unit)
    var p = unit["response"] as! [String: Any]
    var s = p["selection"] as! [String: Any]
    var projection = s["media_projection"] as! [String: Any]
    var media = projection["media"] as! [String: Any]
    media["asset_id"] = UUID().uuidString.lowercased()
    projection["media"] = media
    s["media_projection"] = projection
    p["selection"] = s
    let reply = try mediaIntakeDecode(p)
    #expect(!reply.matches(ticket))
    #expect(reply.factualAcknowledgement(for: ticket) == nil)
  }
  @Test func negotiatedMediaEnvelopeCannotOmitItsProjectionOrUseTerminalV2Shape() throws {
    let unit = try mediaIntakeUnit("meal_photo")
    var p = unit["response"] as! [String: Any]
    var s = p["selection"] as! [String: Any]
    s.removeValue(forKey: "media_projection")
    p["selection"] = s
    #expect(throws: (any Error).self) { try mediaIntakeDecode(p) }
    let selected = unit["response"] as! [String: Any]
    let selection = selected["selection"] as! [String: Any]
    let terminal: [String: Any] = [
      "schema": "conversation.intake-result.v2", "status": "not_recorded",
      "intake": unit["binding"]!, "source_hash": selection["source_hash"]!,
      "decision_hash": selection["decision_hash"]!, "reason": "not_performed",
    ]
    #expect(throws: (any Error).self) { try mediaIntakeDecode(terminal) }
    let legacy = try neutralMealUnit()["response"] as! [String: Any]
    #expect(try mediaIntakeDecode(legacy).status == .selected)
  }
}
func mediaIntakeUnit(_ label: String) throws -> [String: Any] {
  let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
    "Fixtures/ConversationIntakeMediaFixtures.json")
  let root = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
  return (root["cases"] as! [[String: Any]]).first { $0["label"] as? String == label }!
}
func mediaIntakeTicket(_ unit: [String: Any], generation: UInt64 = 7) throws
  -> FlowNeutralIntakeTicket
{
  let b = unit["binding"] as! [String: Any]
  return .init(
    input: try FlowNeutralIntakeInput(wireBody: neutralData(unit["input"]!)),
    ownerID: UUID(uuidString: b["owner_id"] as! String)!,
    epoch: UUID(uuidString: b["epoch"] as! String)!,
    ownerHash: "synthetic-media", sessionGeneration: generation)
}
func mediaIntakeDecode(_ packet: Any, selection: String? = "1") throws
  -> FlowNeutralIntakeResponseSnapshot
{
  let decoder = JSONDecoder()
  if let selection {
    decoder.userInfo[
      CodingUserInfoKey(rawValue: "conversation.intake.media-provenance.selection")!] = selection
  }
  return try decoder.decode(FlowNeutralIntakeResponseSnapshot.self, from: neutralData(packet))
}
