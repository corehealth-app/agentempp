import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
#endif

@Suite("Negotiated current-policy historical feedback v2", .serialized)
struct ConversationFeedbackPresentationV2Tests {
  @Test("The selected family admits all eighteen exact PT/EN policy projections")
  func acceptsSelectedProjections() throws {
    for row in try fixtures() {
      let payload = try #require(row["expected"] as? [String: Any])
      let value = try selectedDecoder().decode(
        ConversationFeedbackPresentationSnapshot.self,
        from: JSONSerialization.data(withJSONObject: payload))
      #expect(value.original.schema == "registration.feedback.v3")
      guard case .v3Sections(_, let sections) = value.content else {
        Issue.record("Expected six projected sections")
        continue
      }
      let expected = try #require(payload["sections"] as? [[String: String]])
      #expect(
        sections.map(\.key.rawValue) == ["saved", "items", "summary", "day", "block", "education"])
      for (actual, saved) in zip(sections, expected) {
        #expect(actual.text.utf16.elementsEqual(try #require(saved["text"]).utf16))
      }
    }
  }
  @Test("Wrapper2 remains unavailable without the explicit selected family")
  func selectionIsNotInferredFromThePayload() throws {
    for row in try fixtures() {
      let data = try JSONSerialization.data(withJSONObject: #require(row["expected"]))
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(ConversationFeedbackPresentationSnapshot.self, from: data)
      }
    }
    for echo in [nil, "v2", "02", "2, 2", "2; q=1", "2 "] as [String?] {
      #expect(ConversationFeedbackPresentationSelection.negotiated(request: .v2, echo: echo) == nil)
    }
    #expect(ConversationFeedbackPresentationSelection.negotiated(request: nil, echo: "2") == nil)
    #expect(ConversationFeedbackPresentationSelection.negotiated(request: .v2, echo: "2") == .v2)
  }

  @Test(
    "Every object, recorded discriminant and section boundary is closed",
    arguments: [
      "schema", "legacy-format", "extra-body", "private-policy", "recording-denied", "upper-epoch",
      "kind", "recorded-extra", "order", "section-extra", "section-empty", "section-long", "clock",
    ])
  func malformedProjectionIsRefused(_ attack: String) throws {
    var raw = try #require(fixtures()[0]["expected"] as? [String: Any])
    var original = raw["original"] as! [String: Any]
    var policy = raw["current_policy"] as! [String: Any]
    var provenance = raw["provenance"] as! [String: Any]
    var recorded = raw["recorded"] as! [String: Any]
    var sections = raw["sections"] as! [[String: Any]]
    switch attack {
    case "schema": raw["schema"] = "conversation.feedback-presentation.v3"
    case "legacy-format": raw["format"] = "legacy"
    case "extra-body": raw["canonical_body"] = ["private": true]
    case "private-policy": policy["private_risk"] = true
    case "recording-denied": policy["recording_allowed"] = false
    case "upper-epoch": provenance["epoch"] = (provenance["epoch"] as! String).uppercased()
    case "kind": original["kind"] = "workout"
    case "recorded-extra": recorded["owner_id"] = "foreign"
    case "order": sections.swapAt(0, 1)
    case "section-extra": sections[0]["authority"] = true
    case "section-empty": sections[0]["text"] = "  "
    case "section-long": sections[0]["text"] = String(repeating: "a", count: 64_001)
    default: provenance["observed_at"] = "2026-11-05T18:00:00.000000001Z"
    }
    raw["original"] = original
    raw["current_policy"] = policy
    raw["provenance"] = provenance
    raw["recorded"] = recorded
    raw["sections"] = sections
    #expect(throws: (any Error).self) {
      try selectedDecoder().decode(
        ConversationFeedbackPresentationSnapshot.self,
        from: JSONSerialization.data(withJSONObject: raw))
    }
  }

  @Test("Workout projects decode but never produce a meal binding")
  func workoutIsDecodeOnly() throws {
    for row in try fixtures() {
      let payload = try #require(row["expected"] as? [String: Any])
      let value = try selectedDecoder().decode(
        ConversationFeedbackPresentationSnapshot.self,
        from: JSONSerialization.data(withJSONObject: payload))
      guard value.original.kind == "workout" else { continue }
      let external = try #require(row["external_binding"] as? [String: Any])
      let scope = ConversationFeedbackPresentationSnapshot.Scope(
        ownerID: external["owner_id"] as! String,
        sessionGeneration: 7, epoch: external["epoch"] as! String)
      #expect(
        value.bound(
          to: .init(
            scope: scope, commandID: external["command_id"] as! String,
            registrationID: value.original.registrationID, localDate: value.original.localDate,
            mealKind: "cafe", logIDs: [value.original.registrationID],
            admittedAt: external["admitted_at"] as! String), current: scope) == nil)
    }
  }

  #if canImport(UIKit)
    @MainActor
    @Test("Real policy-projected PT/EN view displays all six literal sections")
    func rendersPolicyProjectedSixSections() throws {
      for row in try fixtures() {
        let payload = try #require(row["expected"] as? [String: Any])
        let value = try selectedDecoder().decode(
          ConversationFeedbackPresentationSnapshot.self,
          from: JSONSerialization.data(withJSONObject: payload))
        guard case .v3Sections(.meal(let meal), let sections) = value.content else { continue }
        let external = try #require(row["external_binding"] as? [String: Any])
        let scope = ConversationFeedbackPresentationSnapshot.Scope(
          ownerID: external["owner_id"] as! String,
          sessionGeneration: 7, epoch: external["epoch"] as! String)
        let bound = try #require(
          value.bound(
            to: .init(
              scope: scope,
              commandID: external["command_id"] as! String,
              registrationID: value.original.registrationID,
              localDate: value.original.localDate, mealKind: meal.mealKind,
              logIDs: meal.items.map(\.logID), admittedAt: external["admitted_at"] as! String),
            current: scope))
        let host = SignUpRenderingProbe.host(
          ConversationFeedbackPresentationView(feedback: bound), width: 390, height: 6000)
        defer { host.detach() }
        let nodes = host.nodes()
        for section in sections {
          let node = try #require(
            nodes.first { $0.identifier == "conversation.feedback.section.\(section.key.rawValue)" }
          )
          #expect(node.label.utf16.elementsEqual(section.text.utf16))
          #expect(node.frame.width > 0 && node.frame.height > 0)
        }
        #expect(host.geometry().isMounted)
      }
    }
  #endif

  static func selectedDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.userInfo[CodingUserInfoKey(rawValue: "conversation.feedback.presentation.selection")!] =
      "2"
    return decoder
  }
  func selectedDecoder() -> JSONDecoder { Self.selectedDecoder() }
  func fixtures(_ name: String = "ConversationFeedbackPresentationV2Fixtures") throws -> [[String:
    Any]]
  {
    #if SWIFT_PACKAGE
      let bundle = Bundle.module
    #else
      let bundle = Bundle(for: FeedbackPresentationV2Bundle.self)
    #endif
    let url = try #require(bundle.url(forResource: name, withExtension: "json"))
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    return try #require(root["fixtures"] as? [[String: Any]])
  }
}
private final class FeedbackPresentationV2Bundle {}
