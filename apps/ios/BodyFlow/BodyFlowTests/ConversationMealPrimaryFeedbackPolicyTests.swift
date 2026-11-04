import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
#endif

@Suite("Six primary sections require unchanged current registration facts")
struct ConversationMealPrimaryFeedbackPolicyTests {
  @Test func unchangedOwnedFactsAllowOriginalSixSectionsWithoutRegeneratingThem() throws {
    let f = try Fixture()
    let group = try f.group()
    #expect(
      ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.saved.receipt, feedback: f.feedback, group: group, scope: f.scope))
    guard case .sections(let recorded, let sections) = f.feedback.presentation.content else {
      Issue.record("Six original sections required")
      return
    }
    #expect(
      sections.count == 6
        && recorded.items.first(where: { $0.foodName.contains("whey") })?.quantityG == 30)
    // Ordering and equivalent clock offsets do not change any occurrence.
    var raw = f.unchanged
    var current = try #require(raw["current"] as? [String: Any])
    var rows = try #require(current["items"] as? [[String: Any]])
    rows.reverse()
    for i in rows.indices {
      rows[i]["consumed_at"] = f.saved.receipt.consumedAt.replacingOccurrences(
        of: "Z", with: "+00:00")
    }
    current["items"] = rows
    raw["current"] = current
    #expect(
      ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.saved.receipt, feedback: f.feedback, group: try f.decode(raw), scope: f.scope))
  }
  @Test func actualEdited35gAndUnavailableDataAlwaysStayHistorical() throws {
    let f = try Fixture()
    let actual = try JSONDecoder().decode(GroupEnvelope.self, from: f.actual.groupEnvelope).data
    #expect(
      !ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.saved.receipt, feedback: f.feedback, group: actual, scope: f.scope))
    #expect(
      !ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.saved.receipt, feedback: f.feedback, group: nil, scope: f.scope))
    #expect(
      !ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.saved.receipt, feedback: nil, group: try f.group(), scope: f.scope))
  }
  @Test(arguments: [
    "lineage", "revision", "quantity", "calories", "protein-null", "source-null", "name",
    "missing-item", "meal", "clock", "timezone", "receipt", "epoch", "scope-generation",
    "scope-owner",
  ])
  func revisionZeroAloneCannotPromoteChangedOrForeignFacts(_ attack: String) throws {
    let f = try Fixture()
    var raw = f.unchanged
    var scope = f.scope
    var current = try #require(raw["current"] as? [String: Any])
    var rows = try #require(current["items"] as? [[String: Any]])
    switch attack {
    case "lineage": raw["lineage_compatible"] = false
    case "revision":
      raw["revision"] = 7
      raw["last_operation"] = f.edited["last_operation"]
    case "quantity": rows[0]["quantity_g"] = 207
    case "calories": rows[0]["kcal"] = 126.7
    case "protein-null": rows[0]["protein_g"] = NSNull()
    case "source-null": rows[0]["source"] = NSNull()
    case "name":
      rows[0]["food_name"] = "leite integral alterado"
      rows[0]["quantity_display"] = NSNull()
    case "missing-item": rows.removeLast()
    case "meal": rows[0]["meal_type"] = "jantar"
    case "clock": rows[0]["consumed_at"] = "2026-11-04T08:38:29.164555001Z"
    case "timezone": current["timezone"] = "America/Sao_Paulo"
    case "receipt":
      var original = try #require(raw["original_receipt"] as? [String: Any])
      original["registration_id"] = UUID().uuidString.lowercased()
      raw["original_receipt"] = original
    case "epoch": raw["epoch"] = UUID().uuidString.lowercased()
    case "scope-generation":
      scope = .init(ownerID: scope.ownerID, sessionGeneration: 8, epoch: scope.epoch)
    case "scope-owner":
      scope = .init(
        ownerID: f.actual.authUserID, sessionGeneration: scope.sessionGeneration, epoch: scope.epoch
      )
    default: Issue.record("Unknown attack")
    }
    current["items"] = rows
    raw["current"] = current
    #expect(
      !ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.saved.receipt, feedback: f.feedback, group: try f.decode(raw), scope: scope))
  }

  #if canImport(UIKit)
    @MainActor @Test func nativeResponseShowsSixSectionsDirectlyOnlyForUnchangedFacts() throws {
      let f = try Fixture()
      let row = FlowConversationSavedRow(
        command: f.actual.command, receipt: f.saved.receipt, feedback: f.feedback)
      let direct = SignUpRenderingProbe.host(
        FlowConversationSavedMealResponseView(
          row: row, group: try f.group(), scope: f.scope, refresh: {}
        ).environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 2400)
      let directNodes = direct.nodes()
      defer { direct.detach() }
      if case .sections(_, let sections) = f.feedback.presentation.content {
        for section in sections {
          #expect(
            directNodes.contains {
              $0.identifier == "conversation.feedback.section.\(section.key.rawValue)"
                && $0.label.utf16.elementsEqual(section.text.utf16)
            })
        }
      } else {
        Issue.record("Actual original six sections required")
      }
      #expect(!directNodes.contains { $0.identifier == "conversation.meal.original-history" })
      direct.detach()
      let edited = SignUpRenderingProbe.host(
        FlowConversationSavedMealResponseView(
          row: row, group: try f.decode(f.edited), scope: f.scope, refresh: {}
        ).environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 1800)
      defer { edited.detach() }
      let editedNodes = edited.nodes()
      #expect(editedNodes.contains { $0.identifier == "conversation.meal.original-history" })
      #expect(!editedNodes.contains { $0.identifier.hasPrefix("conversation.feedback.section.") })
      #expect(
        editedNodes.contains {
          $0.identifier.hasPrefix("conversation.meal.current-item.") && $0.label.contains("35 g")
            && $0.label.contains("123.2")
        })
    }
  #endif

  struct Fixture {
    let actual: FlowActualEditLifecycleFixture
    let saved: SavedConversationMealCommandResultSnapshot
    let feedback: ConversationFeedbackPresentationSnapshot.Bound
    let scope: ConversationFeedbackPresentationSnapshot.Scope
    let edited: [String: Any]
    let unchanged: [String: Any]
    init() throws {
      actual = try FlowActualEditLifecycleFixture()
      saved = try JSONDecoder().decode(SavedEnvelope.self, from: actual.savedEnvelope).data
      scope = .init(
        ownerID: actual.session.ownerID.uuidString.lowercased(), sessionGeneration: 7,
        epoch: actual.session.epoch.uuidString.lowercased())
      feedback = try #require(saved.boundFeedback(scope: scope))
      let envelope = try #require(
        JSONSerialization.jsonObject(with: actual.groupEnvelope) as? [String: Any])
      edited = try #require(envelope["data"] as? [String: Any])
      let savedRaw = try #require(
        JSONSerialization.jsonObject(with: actual.savedEnvelope) as? [String: Any])
      let packet = try #require(savedRaw["data"] as? [String: Any])
      let body = try #require(packet["feedback"] as? [String: Any])
      let recorded = try #require(body["recorded"] as? [String: Any])
      let foods = try #require(recorded["items"] as? [[String: Any]])
      var mock = edited
      var current = try #require(mock["current"] as? [String: Any])
      let existing = try #require(current["items"] as? [[String: Any]])
      let receipt = saved.receipt
      current["items"] = try foods.map { food -> [String: Any] in
        let name = try #require(food["food_name"] as? String)
        var row = food
        row["id"] = row.removeValue(forKey: "log_id")
        row["source"] = row.removeValue(forKey: "nutrition_source")
        row.removeValue(forKey: "quantity")
        row["quantity_display"] =
          existing.first(where: { $0["food_name"] as? String == name })?["quantity_display"]
          ?? NSNull()
        row["consumed_at"] = receipt.consumedAt
        row["meal_type"] = receipt.mealType.rawValue
        return row
      }
      current["timezone"] = saved.receipt.timezone
      mock["current"] = current
      mock["revision"] = 0
      mock["last_operation"] = NSNull()
      mock["lineage_compatible"] = true
      // Synthetic unchanged read derived ONLY from actual immutable original
      // facts/IDs. It is unit data, not a claim of a new SQL/current authority.
      unchanged = mock
    }
    func group() throws -> ConversationMealGroupSnapshot { try decode(unchanged) }
    func decode(_ raw: [String: Any]) throws -> ConversationMealGroupSnapshot {
      try .init(data: JSONSerialization.data(withJSONObject: raw))
    }
    private struct SavedEnvelope: Decodable { let data: SavedConversationMealCommandResultSnapshot }
  }
  private struct GroupEnvelope: Decodable { let data: ConversationMealGroupSnapshot }
}
