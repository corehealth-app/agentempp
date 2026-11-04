import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
#endif

@Suite("Actual public HTTP child edit capture preserves its genuine lineage")
@MainActor
struct ConversationMealLinkedActualHTTPTests {
  @Test func actualOwnedReadsKeepDistinctRegistrationAndOriginalFeedbackAcrossRealRevisions()
    async throws
  {
    let f = try ActualLinkedHTTPFixture()
    #expect(f.identity.receipt.registrationID != f.identity.commandID)
    #expect(f.identity.inputHash != f.identity.parentBinding.inputHash)
    let life = ConversationHTTPTestLifecycle()
    await life.replace(
      .init(
        userID: f.session.authUserID.uuidString.lowercased(), generation: 7,
        bearer: "synthetic-public-golden"))
    let http = try ConversationHTTPFixture(lifecycle: life)
    let context = try f.context()
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: http.transport, lifecycle: life, lease: await life.leaseForRequest())
    let scope = ConversationFeedbackPresentationSnapshot.Scope(
      ownerID: f.session.ownerID.uuidString.lowercased(), sessionGeneration: 7,
      epoch: f.session.epoch.uuidString.lowercased())
    let feedback = try #require(f.reply.boundFeedback(scope: scope))
    for key in ["group_before_save", "group_before_undo", "group_after_undo"] {
      let body = try f.packet(key)
      await http.stub.respond { _, _ in .init(status: 200, body: body) }
      let group = try await repo.group(linked: f.identity, context: context)
      #expect(f.identity.matches(group: group))
      #expect(
        ConversationMealPrimaryFeedbackPolicy.showsPrimary(
          receipt: f.identity.receipt, feedback: feedback, group: group, scope: scope)
          == (key == "group_before_save"))
    }
    #expect(
      await http.stub.requests.allSatisfy {
        $0.httpMethod == "GET"
          && $0.url?.path.contains(f.identity.commandID.uuidString.lowercased()) == true
      })
  }

  @Test func actualLostSaveReconcilesItsOriginalHashThenUndoUsesTheActualNewCAS() async throws {
    let f = try ActualLinkedHTTPFixture()
    let disk = try EditOutboxFixture()
    defer { disk.remove() }
    let life = ConversationHTTPTestLifecycle()
    await life.replace(
      .init(
        userID: f.session.authUserID.uuidString.lowercased(), generation: 7,
        bearer: "synthetic-public-golden"))
    let lease = await life.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let keys = OutboxKeychainFake()
    await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    let http = try ConversationHTTPFixture(lifecycle: life)
    let phase = ActualLinkedHTTPPhase()
    let group0 = try f.packet("group_before_save")
    let group1 = try f.packet("group_before_undo")
    let group2 = try f.packet("group_after_undo")
    let saved = try f.packet("save_reconcile_ack")
    let undone = try f.packet("undo_save_ack")
    await http.stub.respond { request, _ in
      if request.httpMethod == "GET" {
        let stage = await phase.value
        return .init(status: 200, body: stage == 0 ? group0 : stage == 1 ? group1 : group2)
      }
      if request.url?.path.hasSuffix("/reconcile") == true {
        return .init(status: 200, body: saved)
      }
      if request.url?.path.hasSuffix(f.save.operationID.uuidString.lowercased()) == true {
        await phase.set(1)
        throw URLError(.networkConnectionLost)
      }
      guard request.url?.path.hasSuffix(f.undo.operationID.uuidString.lowercased()) == true else {
        throw URLError(.badURL)
      }
      await phase.set(2)
      return .init(status: 200, body: undone)
    }
    let controller = try await ConversationMealEditController.open(
      transport: http.transport, lifecycle: life, store: disk.store,
      keyVault: .init(service: ConversationMealEditOutboxSession.keychainService, security: keys))
    let context = try f.context()
    let save = try await controller.prepare(
      linked: f.identity, expectedRevision: f.save.expectedRevision,
      expectedVersion: f.save.expectedVersion,
      action: f.save.action, context: context, operationID: f.save.operationID)
    #expect(save.operation.operationInputHash == f.save.operationInputHash)
    let probe = EditControllerProbe()
    let saveID = try await controller.enqueue(preparation: save, context: context) {
      probe.receive($0)
    }
    await #expect(throws: (any Error).self) {
      try await controller.send(id: saveID, context: context) { probe.receive($0) }
    }
    #expect(
      try disk.store.load(owner: owner, key: disk.key).first?.operation.wireBody
        == save.operation.wireBody)
    try await controller.reconcile(id: saveID, context: context) { probe.receive($0) }
    #expect(try disk.store.load(owner: owner, key: disk.key).isEmpty && probe.savedCount == 1)
    let undo = try await controller.prepare(
      linked: f.identity, expectedRevision: f.undo.expectedRevision,
      expectedVersion: f.undo.expectedVersion,
      action: f.undo.action, context: context, operationID: f.undo.operationID)
    #expect(undo.operation.operationInputHash == f.undo.operationInputHash)
    #expect(
      undo.operation.expectedVersion != save.operation.expectedVersion
        && undo.operation.expectedRevision == 1)
    let undoID = try await controller.enqueue(preparation: undo, context: context) {
      probe.receive($0)
    }
    try await controller.send(id: undoID, context: context) { probe.receive($0) }
    #expect(try disk.store.load(owner: owner, key: disk.key).isEmpty && probe.savedCount == 2)
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: http.transport, lifecycle: life, lease: lease)
    let group = try await repo.group(linked: f.identity, context: context)
    #expect(group.revision == 2 && group.lastOperation?.kind == .saveUndone)
    let mutations = await http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(mutations.count == 3)
    #expect(
      mutations[0].httpBody == save.operation.wireBody
        && mutations[1].httpBody == save.operation.wireBody)
    #expect(mutations[2].httpBody == undo.operation.wireBody)
    #expect(
      mutations.allSatisfy {
        $0.value(forHTTPHeaderField: "X-Conversation-Input-Hash") == f.identity.inputHash
      })
    await controller.close()
  }

  #if canImport(UIKit)
    @Test(arguments: [false, true])
    func actualNativeCardShowsSixOriginalSectionsOrCurrentCorrectedFacts(_ edited: Bool) throws {
      let f = try ActualLinkedHTTPFixture()
      let group = try f.group(edited ? "group_before_undo" : "group_before_save")
      let scope = ConversationFeedbackPresentationSnapshot.Scope(
        ownerID: f.identity.ownerID.uuidString.lowercased(), sessionGeneration: 7,
        epoch: f.identity.epoch.uuidString.lowercased())
      let feedback = try #require(f.reply.boundFeedback(scope: scope))
      let row = FlowConversationLinkedMealRow(
        reference: f.identity.reference, identity: f.identity, feedback: feedback)
      let actions = FlowConversationMealEditActions(
        editItem: { _ in }, undoSave: { _ in }, undoRegistration: { _ in }, isWorking: false)
      let host = SignUpRenderingProbe.host(
        FlowConversationLinkedMealResponseView(
          row: row, group: group, scope: scope, editing: actions, refresh: {}
        )
        .environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 2800)
      defer { host.detach() }
      let nodes = host.nodes()
      let diagnostic = Comment(rawValue: nodes.map(\.description).joined(separator: "\n"))
      #expect(
        nodes.contains { $0.identifier == "conversation.meal.original-history" } == edited,
        diagnostic)
      #expect(nodes.contains { $0.identifier.hasPrefix("conversation.meal.edit.") }, diagnostic)
      if edited {
        let item = try #require(group.current?.items.first)
        #expect(
          nodes.contains {
            $0.identifier == "conversation.meal.current-item.\(item.id.uuidString.lowercased())"
              && $0.label.contains("150 g")
          }, diagnostic)
        #expect(nodes.contains { $0.identifier == "conversation.meal.undo-save" }, diagnostic)
      } else {
        guard case .sections(_, let sections) = feedback.presentation.content else {
          Issue.record("Six actual literal sections required")
          return
        }
        for section in sections {
          #expect(
            nodes.contains {
              $0.identifier == "conversation.feedback.section.\(section.key.rawValue)"
                && $0.label.utf16.elementsEqual(section.text.utf16)
            }, diagnostic)
        }
      }
    }
  #endif
}

/// Exact public local compiled HTTP R3 capture, with controlled backend origin;
/// it does not claim provider/onboarding qualification or a native network run.
struct ActualLinkedHTTPFixture: Sendable {
  let data: Data
  let session: ConversationSessionSnapshot
  let reply: ConversationMealReplyResultSnapshot
  let identity: ConversationMealLinkedIdentity
  let save: ConversationMealEditOperation
  let undo: ConversationMealEditOperation
  init() throws {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(
          forResource: "ConversationLinkedActualHTTPFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationLinkedActualHTTPFixtures.json")
    #endif
    data = try Data(contentsOf: url)
    #expect(
      data.count == 40394
        && ConversationMealCommand.digest(data)
          == "0c7613c8a258e7ff5085802c1a27bcc675747f1cf2db57e26e474ab884f9753a"
    )
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    func decode<T: Decodable>(_ type: T.Type, _ key: String) throws -> T {
      let observation = try #require(root[key] as? [String: Any])
      let packet = try #require(observation["packet"] as? [String: Any])
      return try JSONDecoder().decode(
        type, from: JSONSerialization.data(withJSONObject: #require(packet["data"])))
    }
    session = try decode(ConversationSessionSnapshot.self, "session_after_seed")
    reply = try decode(ConversationMealReplyResultSnapshot.self, "saved_reply")
    identity = try .init(
      parentBinding: reply.parentBinding, childBinding: #require(reply.childBinding),
      parentDecisionHash: reply.parentDecisionHash, receipt: #require(reply.receipt))
    let actualIdentity = identity
    func operation(_ key: String) throws -> ConversationMealEditOperation {
      let observation = try #require(root[key] as? [String: Any])
      let intent = try #require(observation["intent"] as? [String: Any])
      let path = try #require(intent["path"] as? String)
      let id = try #require(UUID(uuidString: String(path.split(separator: "/").last!)))
      let body = try #require(intent["body_utf8"] as? String)
      return try .init(
        ownerID: actualIdentity.ownerID, commandID: actualIdentity.commandID,
        originalInputHash: actualIdentity.inputHash,
        epoch: actualIdentity.epoch, operationID: id, wireBody: Data(body.utf8))
    }
    save = try operation("save_input_and_lost_body")
    undo = try operation("undo_save_ack")
  }
  func packet(_ key: String) throws -> Data {
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let observation = try #require(root[key] as? [String: Any])
    return try JSONSerialization.data(withJSONObject: #require(observation["packet"]))
  }
  func group(_ key: String) throws -> ConversationMealGroupSnapshot {
    struct Envelope: Decodable { let data: ConversationMealGroupSnapshot }
    return try JSONDecoder().decode(Envelope.self, from: packet(key)).data
  }
  func context() throws -> ConversationCommandContext {
    .init(
      observation: .init(
        authUserID: session.authUserID, ownerID: session.ownerID, localSessionGeneration: 7,
        epoch: session.epoch), observedAt: session.observedAt)
  }
}
private actor ActualLinkedHTTPPhase {
  private(set) var value = 0
  func set(_ value: Int) { self.value = value }
}
