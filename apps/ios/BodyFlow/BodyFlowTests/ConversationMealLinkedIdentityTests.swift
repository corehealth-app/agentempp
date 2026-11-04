import Foundation
import Testing

@testable import BodyFlow

@Suite("Genuine linked meal identity never becomes a v1 report")
struct ConversationMealLinkedIdentityTests {
  @Test func actualChildAndDistinctRegistrationBindFullCurrentGroup() throws {
    let f = try LinkedMealIdentityFixture()
    let identity = try f.identity()
    #expect(identity.commandID == f.child.commandID && identity.commandID != f.parent.commandID)
    #expect(identity.receipt.registrationID != identity.commandID)
    #expect(identity.inputHash == f.child.inputHash && identity.admittedAt == f.child.admittedAt)
    #expect(identity.parentBinding == f.parent && identity.childBinding == f.child)
    #expect(identity.matches(group: try f.group()))
    #expect(identity == (try f.identity()))
  }
  @Test(arguments: ["decision", "parent", "child", "hash", "epoch"])
  func sourceIdentityRequiresExactActualParentChildAndDecision(_ change: String) throws {
    let f = try LinkedMealIdentityFixture()
    var parent = try f.parentRaw
    var child = try f.childRaw
    var decision = f.decisionHash
    switch change {
    case "decision": decision = String(repeating: "a", count: 64)
    case "parent": parent["command_id"] = UUID().uuidString.lowercased()
    case "child": child["command_id"] = UUID().uuidString.lowercased()
    case "hash": child["input_hash"] = String(repeating: "b", count: 64)
    default: child["epoch"] = UUID().uuidString.lowercased()
    }
    let p = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Binding.self, from: linkedIdentityBytes(parent))
    let c = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Binding.self, from: linkedIdentityBytes(child))
    #expect(throws: (any Error).self) {
      try ConversationMealLinkedIdentity(
        parentBinding: p, childBinding: c, parentDecisionHash: decision, receipt: f.receipt)
    }
  }
  @Test(arguments: ["parent_input_hash", "parent_decision_hash", "effect_version", "admitted_at"])
  func validGroupWithDifferentOriginalLineageIsNotThisChild(_ field: String) throws {
    let f = try LinkedMealIdentityFixture()
    let identity = try f.identity()
    var raw = try f.groupRaw
    if field == "admitted_at" {
      for key in ["admitted_at"] {
        let clock = try #require(raw[key] as? String)
        let suffix = String(clock.dropLast().suffix(6))
        let incremented = String(format: "%06d", try #require(Int(suffix)) + 1)
        raw[key] = clock.replacingOccurrences(of: "." + suffix + "Z", with: "." + incremented + "Z")
      }
    } else {
      var receipt = try #require(raw["original_receipt"] as? [String: Any])
      receipt[field] =
        field == "effect_version"
        ? "cmeal1:" + String(repeating: "a", count: 64) : String(repeating: "a", count: 64)
      raw["original_receipt"] = receipt
    }
    let other = try f.group(raw)
    #expect(!identity.matches(group: other))
  }
  @Test func actualEditBindingsPermitOnlyAReadUntilTheOwnedGroupSuppliesItsReceipt() throws {
    let f = try LinkedMealIdentityFixture()
    let reference = try ConversationMealLinkedReadReference(
      parentBinding: f.parent, childBinding: f.child, parentDecisionHash: f.decisionHash)
    let complete = try reference.resolve(group: f.group())
    #expect(complete == (try f.identity()) && complete.reference == reference)
    let changed = try ConversationMealLinkedReadReference(
      parentBinding: f.parent, childBinding: f.child,
      parentDecisionHash: String(repeating: "a", count: 64))
    #expect(throws: (any Error).self) { try changed.resolve(group: f.group()) }
  }
  @Test(arguments: ["owner", "epoch", "child-protocol", "child-clock", "same-id", "decision"])
  func incompleteReadReferencesCannotRetagOwnershipProtocolOrAdmission(_ change: String) throws {
    let f = try LinkedMealIdentityFixture()
    var raw = try f.childRaw
    var decision = f.decisionHash
    switch change {
    case "owner": raw["owner_id"] = UUID().uuidString.lowercased()
    case "epoch": raw["epoch"] = UUID().uuidString.lowercased()
    case "child-protocol":
      raw["command_protocol"] = "conversation.command.v1"
      raw["kind"] = "meal.report"
    case "child-clock": raw["admitted_at"] = "2000-01-01T00:00:00.000000Z"
    case "same-id": raw["command_id"] = f.parent.commandID.uuidString.lowercased()
    default: decision = "not-a-decision-hash"
    }
    let child = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Binding.self, from: linkedIdentityBytes(raw))
    #expect(throws: (any Error).self) {
      try ConversationMealLinkedReadReference(
        parentBinding: f.parent, childBinding: child, parentDecisionHash: decision)
    }
  }
  @Test func equivalentGroupClockKeepsOriginalBindingsWithoutNormalizingThem() throws {
    let f = try LinkedMealIdentityFixture()
    let identity = try f.identity()
    var raw = try f.groupRaw
    for key in ["admitted_at", "registration_undo_expires_at"] {
      raw[key] = (raw[key] as? String)?.replacingOccurrences(of: "Z", with: "+00:00")
    }
    let group = try f.group(raw)
    #expect(group.admittedAt.hasSuffix("+00:00"))
    #expect(identity.matches(group: group))
    #expect(identity.admittedAt == f.child.admittedAt)
  }
}

struct LinkedMealIdentityFixture: Sendable {
  private let parentData: Data
  private let childData: Data
  var parentRaw: [String: Any] {
    get throws { try #require(JSONSerialization.jsonObject(with: parentData) as? [String: Any]) }
  }
  var childRaw: [String: Any] {
    get throws { try #require(JSONSerialization.jsonObject(with: childData) as? [String: Any]) }
  }
  let parent: ConversationThreadPageSnapshot.Binding
  let child: ConversationThreadPageSnapshot.Binding
  let receipt: ConversationThreadPageSnapshot.LinkedReceipt
  let decisionHash: String
  let groupData: Data
  var groupRaw: [String: Any] {
    get throws { try #require(JSONSerialization.jsonObject(with: groupData) as? [String: Any]) }
  }
  init() throws {
    let sdk = try linkedIdentityLoad("ConversationLinkedFeedbackSDKFixtures")
    let group = try linkedIdentityLoad("ConversationMealLinkedGroupPublicFixture")
    let root = try #require(JSONSerialization.jsonObject(with: sdk) as? [String: Any])
    parentData = try linkedIdentityBytes(#require(root["parentBinding"]))
    childData = try linkedIdentityBytes(#require(root["childBinding"]))
    parent = try JSONDecoder().decode(ConversationThreadPageSnapshot.Binding.self, from: parentData)
    child = try JSONDecoder().decode(ConversationThreadPageSnapshot.Binding.self, from: childData)
    receipt = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.LinkedReceipt.self,
      from: linkedIdentityBytes(#require(root["receipt"])))
    decisionHash = try #require(root["parentDecisionHash"] as? String)
    let rawGroup = try #require(JSONSerialization.jsonObject(with: group) as? [String: Any])
    groupData = try linkedIdentityBytes(#require(rawGroup["group"]))
  }
  func identity() throws -> ConversationMealLinkedIdentity {
    try .init(
      parentBinding: parent, childBinding: child, parentDecisionHash: decisionHash, receipt: receipt
    )
  }
  func group(_ raw: [String: Any]? = nil) throws -> ConversationMealGroupSnapshot {
    try .init(data: raw.map(linkedIdentityBytes) ?? groupData)
  }
}
private func linkedIdentityLoad(_ name: String) throws -> Data {
  #if SWIFT_PACKAGE
    let path = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
  #else
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
      "Fixtures/\(name).json")
  #endif
  return try Data(contentsOf: path)
}
private func linkedIdentityBytes(_ raw: Any) throws -> Data {
  try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
}
