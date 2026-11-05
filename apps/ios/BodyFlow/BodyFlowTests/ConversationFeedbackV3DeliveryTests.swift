import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
#endif

@Suite("Projected v3 factual delivery and unchanged current meals", .serialized)
struct ConversationFeedbackV3DeliveryTests {
  @Test("Root and linked primary sections require the actual unchanged group")
  func primaryRequiresEveryCurrentFact() throws {
    for row in try ConversationFeedbackPresentationV2Tests().fixtures(
      "ConversationFeedbackPresentationV2PrimaryFixtures")
    {
      let f = try V3PrimaryFixture(row)
      #expect(try f.shows(group: f.group))
      #expect(try !f.shows(group: nil))
      #expect(try !f.shows(group: f.group, generation: 8))
      for mutation in try #require(row["mutations"] as? [[String: Any]]) {
        #expect(try !f.shows(group: mutation["group"] as? [String: Any]))
      }
    }
  }
  @Test(
    "Only matching request and response selection exposes optional v3; saved ACK always survives")
  func exactHTTPSelectionRetainsSavedACK() async throws {
    let row = try #require(
      ConversationFeedbackPresentationV2Tests().fixtures(
        "ConversationFeedbackPresentationV2PrimaryFixtures"
      ).first)
    let f = try V3PrimaryFixture(row)
    let actual = try FlowActualEditLifecycleFixture()
    var envelope = try #require(
      JSONSerialization.jsonObject(with: actual.savedEnvelope) as? [String: Any])
    var packet = envelope["data"] as! [String: Any]
    packet["feedback"] = row["expected_wrapper"]
    envelope["data"] = packet
    let bytes = try JSONSerialization.data(withJSONObject: envelope)
    for requested in [false, true] {
      for echo in [nil, "2", "v2", "02", "2, 2"] as [String?] {
        let http = try ConversationHTTPFixture()
        await http.stub.respond { _, _ in
          var reply = ConversationHTTPReply(status: 200, body: bytes)
          if let echo { reply.headers[ConversationFeedbackPresentationSelection.header] = echo }
          return reply
        }
        let request = try MobileAPIRequest<ConversationMealCommandReply>(
          method: .get,
          path: "/api/mobile/v1/conversation/meal-commands/\(f.external["command_id"] as! String)",
          conversation: .reconciliation(
            epoch: UUID(uuidString: f.scope.epoch)!,
            ownerID: UUID(uuidString: f.scope.ownerID)!,
            inputHash: f.external["input_hash"] as! String),
          feedbackPresentation: requested ? .v2 : nil)
        let response = try await http.transport.executeHTTP(request)
        guard case .saved(let saved) = response.data else {
          Issue.record("Factual saved ACK lost")
          continue
        }
        #expect(saved.receipt.registrationID == f.presentation.original.registrationID)
        #expect((saved.feedback != nil) == (requested && echo == "2"))
        let sent = await http.stub.requests
        #expect(sent.count == 1 && sent[0].httpMethod == "GET")
        #expect(
          sent[0].value(forHTTPHeaderField: ConversationFeedbackPresentationSelection.header)
            == (requested ? "2" : nil))
        #expect(await http.lifecycle.refreshCount == 0)
      }
    }
  }
  @Test("Selection preserves old-server replies, original POST bytes and no-retry semantics")
  func oldServerAndImmutablePOSTCompatibility() async throws {
    let actual = try FlowActualEditLifecycleFixture()
    let compatible = try ConversationHTTPFixture()
    let bytes = actual.savedEnvelope
    await compatible.stub.respond { _, _ in .init(status: 200, body: bytes) }
    let old = try MobileAPIRequest<ConversationMealCommandReply>(
      method: .get,
      path:
        "/api/mobile/v1/conversation/meal-commands/\(actual.command.commandID.uuidString.lowercased())",
      conversation: .reconciliation(
        epoch: actual.session.epoch, ownerID: actual.session.ownerID,
        inputHash: actual.command.inputHash), feedbackPresentation: .v2)
    guard case .saved(let saved) = try await compatible.transport.executeHTTP(old).data else {
      Issue.record("Old server saved ACK lost")
      return
    }
    #expect(saved.feedback?.original.schema == "registration.feedback.v2")
    let http = try ConversationHTTPFixture()
    await http.stub.respond { _, _ in .failure(401, "expired") }
    let post = try MobileAPIRequest<ConversationHTTPValue>(
      method: .post,
      path: "/api/mobile/v1/conversation/meal-commands", body: actual.command.wireBody,
      idempotencyKey: IdempotencyKey(validating: actual.command.idempotencyKey),
      conversation: .submit(epoch: actual.session.epoch, ownerID: actual.session.ownerID),
      unauthorizedReplay: .never, feedbackPresentation: .v2)
    await #expect(throws: (any Error).self) { try await http.transport.executeHTTP(post) }
    let sent = await http.stub.requests
    #expect(sent.count == 1 && sent[0].httpBody == actual.command.wireBody)
    #expect(sent[0].value(forHTTPHeaderField: "Idempotency-Key") == actual.command.idempotencyKey)
    #expect(
      sent[0].value(forHTTPHeaderField: ConversationFeedbackPresentationSelection.header) == "2")
    #expect(await http.lifecycle.refreshCount == 0)
  }

  @Test(
    "Selected linked replies retain the genuine registration identity independently of feedback")
  func linkedReplyAndMalformedOptionalPreserveReceipt() throws {
    let actual = try ActualLinkedHTTPFixture()
    let rows = try ConversationFeedbackPresentationV2Tests().fixtures(
      "ConversationFeedbackPresentationV2PrimaryFixtures")
    for row in rows where (row["case"] as! String).hasPrefix("linked") {
      var envelope = try #require(
        JSONSerialization.jsonObject(with: actual.packet("saved_reply")) as? [String: Any])
      var reply = try #require(envelope["data"] as? [String: Any])
      reply["feedback"] = row["expected_wrapper"]
      let bytes = try JSONSerialization.data(withJSONObject: reply)
      let selected = try ConversationFeedbackPresentationV2Tests.selectedDecoder().decode(
        ConversationMealReplyResultSnapshot.self, from: bytes)
      #expect(try identity(selected) == actual.identity)
      #expect(selected.receipt?.registrationID != selected.replyID)
      #expect(selected.feedback != nil)
      #expect(
        selected.boundFeedback(
          scope: .init(
            ownerID: selected.ownerID.uuidString.lowercased(), sessionGeneration: 7,
            epoch: selected.epoch.uuidString.lowercased())) != nil)
      #expect(
        try JSONDecoder().decode(ConversationMealReplyResultSnapshot.self, from: bytes).feedback
          == nil)
      var broken = row["expected_wrapper"] as! [String: Any]
      broken["sections"] = []
      reply["feedback"] = broken
      let malformed = try ConversationFeedbackPresentationV2Tests.selectedDecoder().decode(
        ConversationMealReplyResultSnapshot.self,
        from: JSONSerialization.data(withJSONObject: reply))
      #expect(
        try malformed.status == .saved && identity(malformed) == actual.identity
          && malformed.feedback == nil)
      envelope["data"] = reply
    }
  }

  @Test(
    "Journal decoder preserves selected optional presentation while factual events stay byte-bound")
  func threadBridgeKeepsSelectionWithoutClaimingDelivery() throws {
    let extra = try object("ConversationFeedbackPresentationV2ThreadFixture")
    var root = try object("ConversationThreadPagePublicFixtures")
    var page = root["data"] as! [String: Any]
    var items = page["items"] as! [[String: Any]]
    let i = try #require(
      items.firstIndex { $0["event_id"] as? String == extra["event_id"] as? String })
    items[i]["feedback"] = extra["expected"]
    page["items"] = items
    root["data"] = page
    let bytes = try JSONSerialization.data(withJSONObject: page)
    let selected = try ConversationFeedbackPresentationV2Tests.selectedDecoder().decode(
      ConversationThreadPageSnapshot.self, from: bytes)
    let legacy = try JSONDecoder().decode(ConversationThreadPageSnapshot.self, from: bytes)
    #expect(
      selected.items.count == legacy.items.count && selected.threads.count == legacy.threads.count)
    guard case .fulfillment(let value) = selected.items[i].detail,
      case .fulfillment(let old) = legacy.items[i].detail
    else {
      Issue.record("Factual fulfillment lost")
      return
    }
    #expect(value.receipt.registrationID == old.receipt.registrationID)
    #expect(value.feedback != nil && old.feedback == nil)
    var invalid = extra["expected"] as! [String: Any]
    invalid["sections"] = []
    items[i]["feedback"] = invalid
    page["items"] = items
    let discarded = try ConversationFeedbackPresentationV2Tests.selectedDecoder().decode(
      ConversationThreadPageSnapshot.self, from: JSONSerialization.data(withJSONObject: page))
    guard case .fulfillment(let dropped) = discarded.items[i].detail else {
      Issue.record("ACK lost")
      return
    }
    #expect(
      dropped.feedback == nil && dropped.receipt.registrationID == value.receipt.registrationID)
  }

  @Test("A policy older than the proved effect discards only the new optional wrapper")
  func preEffectPolicyCannotBecomeDisplayAuthority() throws {
    let row = try #require(
      ConversationFeedbackPresentationV2Tests().fixtures(
        "ConversationFeedbackPresentationV2PrimaryFixtures"
      ).first)
    let actual = try FlowActualEditLifecycleFixture()
    var envelope = try #require(
      JSONSerialization.jsonObject(with: actual.savedEnvelope) as? [String: Any])
    var packet = envelope["data"] as! [String: Any]
    var wrapper = row["expected_wrapper"] as! [String: Any]
    var policy = wrapper["current_policy"] as! [String: Any]
    var provenance = wrapper["provenance"] as! [String: Any]
    policy["observed_at"] = packet["admitted_at"]
    provenance["observed_at"] = packet["admitted_at"]
    wrapper["current_policy"] = policy
    wrapper["provenance"] = provenance
    packet["feedback"] = wrapper
    let saved = try ConversationFeedbackPresentationV2Tests.selectedDecoder().decode(
      SavedConversationMealCommandResultSnapshot.self,
      from: JSONSerialization.data(withJSONObject: packet))
    #expect(saved.feedback == nil)
    #expect(
      saved.receipt.registrationID == (row["receipt"] as! [String: Any])["registration_id"]
        as? String)
    let extra = try object("ConversationFeedbackPresentationV2ThreadFixture")
    var page = try #require(
      object("ConversationThreadPagePublicFixtures")["data"] as? [String: Any])
    var items = page["items"] as! [[String: Any]]
    let i = try #require(
      items.firstIndex { $0["event_id"] as? String == extra["event_id"] as? String })
    wrapper = extra["expected"] as! [String: Any]
    policy = wrapper["current_policy"] as! [String: Any]
    provenance = wrapper["provenance"] as! [String: Any]
    let child = items[i]["child_binding"] as! [String: Any]
    policy["observed_at"] = child["admitted_at"]
    provenance["observed_at"] = child["admitted_at"]
    wrapper["current_policy"] = policy
    wrapper["provenance"] = provenance
    items[i]["feedback"] = wrapper
    page["items"] = items
    let history = try ConversationFeedbackPresentationV2Tests.selectedDecoder().decode(
      ConversationThreadPageSnapshot.self, from: JSONSerialization.data(withJSONObject: page))
    guard case .fulfillment(let event) = history.items[i].detail else {
      Issue.record("Factual event lost")
      return
    }
    #expect(event.feedback == nil)
  }

  @Test("A stale owned session cannot publish even a valid selected response")
  func lateSelectedResponseIsRefusedAfterOwnerChange() async throws {
    let row = try #require(
      ConversationFeedbackPresentationV2Tests().fixtures(
        "ConversationFeedbackPresentationV2PrimaryFixtures"
      ).first)
    let f = try V3PrimaryFixture(row)
    let actual = try FlowActualEditLifecycleFixture()
    var envelope = try #require(
      JSONSerialization.jsonObject(with: actual.savedEnvelope) as? [String: Any])
    var packet = envelope["data"] as! [String: Any]
    packet["feedback"] = row["expected_wrapper"]
    envelope["data"] = packet
    let bytes = try JSONSerialization.data(withJSONObject: envelope)
    let http = try ConversationHTTPFixture()
    let original = await http.lifecycle.leaseForRequest()
    let transport = http.transport.scoped(to: original)
    await http.stub.respond { _, _ in
      await http.lifecycle.replace(
        .init(
          userID: "90000000-0000-4000-8000-000000000002", generation: 8, bearer: "synthetic-next"))
      return .init(
        status: 200, body: bytes, headers: [ConversationFeedbackPresentationSelection.header: "2"])
    }
    let request = try MobileAPIRequest<ConversationMealCommandReply>(
      method: .get,
      path: "/api/mobile/v1/conversation/meal-commands/\(f.external["command_id"] as! String)",
      conversation: .reconciliation(
        epoch: UUID(uuidString: f.scope.epoch)!, ownerID: UUID(uuidString: f.scope.ownerID)!,
        inputHash: f.external["input_hash"] as! String), feedbackPresentation: .v2)
    await #expect(throws: (any Error).self) { try await transport.executeHTTP(request) }
    #expect(await http.stub.requests.count == 1)
    #expect(await http.lifecycle.refreshCount == 0)
  }

  #if canImport(UIKit)
    @MainActor
    @Test("Actual Flow root and linked content show projected six sections only while unchanged")
    func rendersRootAndLinkedPrimary() throws {
      for row in try ConversationFeedbackPresentationV2Tests().fixtures(
        "ConversationFeedbackPresentationV2PrimaryFixtures")
      {
        let f = try V3PrimaryFixture(row)
        let group = try JSONDecoder().decode(
          ConversationMealGroupSnapshot.self, from: JSONSerialization.data(withJSONObject: f.group))
        let view: AnyView
        if (row["case"] as! String).hasPrefix("linked") {
          let actual = try ActualLinkedHTTPFixture()
          view = AnyView(
            FlowConversationLinkedMealResponseView(
              row: .init(
                reference: actual.identity.reference,
                identity: actual.identity, feedback: f.bound), group: group, scope: f.scope,
              refresh: {}))
        } else {
          let actual = try FlowActualEditLifecycleFixture()
          let receipt = try JSONDecoder().decode(
            SavedConversationMealCommandResultSnapshot.Receipt.self,
            from: JSONSerialization.data(withJSONObject: #require(row["receipt"])))
          view = AnyView(
            FlowConversationSavedMealResponseView(
              row: .init(
                command: actual.command, receipt: receipt,
                feedback: f.bound), group: group, scope: f.scope, refresh: {}))
        }
        let host = SignUpRenderingProbe.host(view, width: 390, height: 6000)
        defer { host.detach() }
        let nodes = host.nodes()
        #expect(nodes.contains { $0.identifier == "conversation.meal.primary" })
        guard case .v3Sections(_, let sections) = f.presentation.content else {
          Issue.record("Missing sections")
          continue
        }
        for section in sections {
          let node = try #require(
            nodes.first { $0.identifier == "conversation.feedback.section.\(section.key.rawValue)" }
          )
          #expect(node.label.utf16.elementsEqual(section.text.utf16))
          #expect(node.frame.width > 0 && node.frame.height > 0)
        }
        #expect(!nodes.contains { $0.identifier == "conversation.meal.original-history" })
      }
    }
  #endif

  @Test("The new representation cannot escape into generic, session, group, media or edit requests")
  func closedRequestSelection() throws {
    #expect(throws: MobileAPIRequestError.invalidConversationHeaders) {
      try MobileAPIRequest<ConversationHTTPValue>(
        method: .get, path: "/api/mobile/v1/today", feedbackPresentation: .v2)
    }
    #expect(throws: MobileAPIRequestError.invalidConversationHeaders) {
      try MobileAPIRequest<ConversationHTTPValue>(
        method: .get, path: "/api/mobile/v1/conversation/session", conversation: .session,
        feedbackPresentation: .v2)
    }
    for allowed: MobileConversationRequestHeaders in [
      .submit(epoch: UUID(), ownerID: UUID()),
      .reconciliation(epoch: UUID(), ownerID: UUID(), inputHash: String(repeating: "a", count: 64)),
      .journal(epoch: UUID(), ownerID: UUID()), .threadJournal(epoch: UUID(), ownerID: UUID()),
    ] {
      #expect(allowed.supportsFeedbackPresentation)
    }
    #expect(
      !MobileConversationRequestHeaders.mealGroup(
        epoch: UUID(), ownerID: UUID(), inputHash: String(repeating: "a", count: 64)
      ).supportsFeedbackPresentation)
    #expect(
      !MobileConversationRequestHeaders.mealEdit(
        epoch: UUID(), ownerID: UUID(), inputHash: String(repeating: "a", count: 64)
      ).supportsFeedbackPresentation)
  }
  private func identity(_ reply: ConversationMealReplyResultSnapshot) throws
    -> ConversationMealLinkedIdentity
  {
    try .init(
      parentBinding: reply.parentBinding, childBinding: #require(reply.childBinding),
      parentDecisionHash: reply.parentDecisionHash, receipt: #require(reply.receipt))
  }
  private func object(_ name: String) throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/\(name).json")
    #endif
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }

}

struct V3PrimaryFixture {
  let row: [String: Any]
  let external: [String: Any]
  let group: [String: Any]
  let presentation: ConversationFeedbackPresentationSnapshot
  let scope: ConversationFeedbackPresentationSnapshot.Scope
  let bound: ConversationFeedbackPresentationSnapshot.Bound
  init(_ row: [String: Any]) throws {
    self.row = row
    external = try #require(row["external_binding"] as? [String: Any])
    group = try #require(row["group"] as? [String: Any])
    presentation = try ConversationFeedbackPresentationV2Tests.selectedDecoder().decode(
      ConversationFeedbackPresentationSnapshot.self,
      from: JSONSerialization.data(withJSONObject: #require(row["expected_wrapper"])))
    scope = .init(
      ownerID: external["owner_id"] as! String, sessionGeneration: 7,
      epoch: external["epoch"] as! String)
    guard case .v3Sections(.meal(let meal), _) = presentation.content else {
      throw V3FixtureError.value
    }
    bound = try #require(
      presentation.bound(
        to: .init(
          scope: scope,
          commandID: external["command_id"] as! String,
          registrationID: presentation.original.registrationID,
          localDate: presentation.original.localDate, mealKind: meal.mealKind,
          logIDs: meal.items.map(\.logID), admittedAt: external["admitted_at"] as! String),
        current: scope))
  }
  func shows(group raw: [String: Any]?, generation: UInt64 = 7) throws -> Bool {
    let decoder = JSONDecoder()
    let current = raw.flatMap {
      try? decoder.decode(
        ConversationMealGroupSnapshot.self, from: JSONSerialization.data(withJSONObject: $0))
    }
    let active = ConversationFeedbackPresentationSnapshot.Scope(
      ownerID: scope.ownerID, sessionGeneration: generation, epoch: scope.epoch)
    let receipt = try JSONSerialization.data(withJSONObject: #require(row["receipt"]))
    if external["parent_command_id"] != nil || (row["case"] as! String).hasPrefix("linked") {
      return ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: try decoder.decode(
          ConversationThreadPageSnapshot.LinkedReceipt.self, from: receipt), feedback: bound,
        group: current, scope: active)
    }
    return ConversationMealPrimaryFeedbackPolicy.showsPrimary(
      receipt: try decoder.decode(
        SavedConversationMealCommandResultSnapshot.Receipt.self, from: receipt), feedback: bound,
      group: current, scope: active)
  }
}
private enum V3FixtureError: Error { case value }
