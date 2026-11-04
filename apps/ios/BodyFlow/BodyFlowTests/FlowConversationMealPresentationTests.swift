import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
#endif

@Suite("Flow separates current meal facts from the immutable registration")
@MainActor
struct FlowConversationMealPresentationTests {
  @Test(arguments: ["cached", "in-flight-empty", "same-revision-other-operation"])
  func aKnownJournalEditRejectsOlderAndConflictingGroupReads(_ ordering: String) async throws {
    let f = try ConversationMealPrimaryFeedbackPolicyTests.Fixture()
    let actual = f.actual
    let disk = try OutboxDiskFixture()
    defer { disk.remove() }
    let lifecycle = ConversationHTTPTestLifecycle()
    await lifecycle.replace(
      .init(userID: actual.authUserID, generation: 7, bearer: "synthetic-journal-current"))
    let http = try ConversationHTTPFixture(lifecycle: lifecycle)
    let owner = try ConversationOutboxOwner(lease: await lifecycle.leaseForRequest())
    let keys = OutboxKeychainFake()
    await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    try disk.store.update(owner: owner, key: disk.key) {
      $0.append(
        .init(
          command: actual.command, originalServerEpoch: actual.session.epoch,
          originalPatientOwnerID: actual.session.ownerID))
    }
    let unchangedBody = try JSONSerialization.data(withJSONObject: [
      "data": f.unchanged, "meta": ["api_version": "v1", "request_id": "unit-unchanged-read"],
    ])
    let savedEnvelope = try #require(
      JSONSerialization.jsonObject(with: actual.savedEnvelope) as? [String: Any])
    let saved = try #require(savedEnvelope["data"] as? [String: Any])
    let groupEnvelope = try #require(
      JSONSerialization.jsonObject(with: actual.groupEnvelope) as? [String: Any])
    let edited = try #require(groupEnvelope["data"] as? [String: Any])
    let edit = try #require(edited["last_operation"] as? [String: Any])
    let editAck =
      [
        "schema": "conversation.meal-edit-result.v1", "status": "saved",
        "owner_id": actual.session.ownerID.uuidString.lowercased(),
        "command_id": actual.command.commandID.uuidString.lowercased(),
        "input_hash": actual.command.inputHash,
        "epoch": actual.session.epoch.uuidString.lowercased(), "receipt": edit,
      ] as [String: Any]
    let commandID = actual.command.commandID.uuidString.lowercased()
    let journal =
      [
        "schema": "conversation.journal-page.v1", "auth_user_id": actual.authUserID,
        "owner_id": actual.session.ownerID.uuidString.lowercased(),
        "epoch": actual.session.epoch.uuidString.lowercased(),
        "observed_at": try #require(edited["observed_at"]),
        "items": [
          [
            "event_id": "edit/\(commandID)/\(try #require(edit["operation_id"] as? String))",
            "at": try #require(edit["applied_at"]), "kind": "edit", "result": editAck,
          ],
          [
            "event_id": "command/\(commandID)", "at": try #require(saved["admitted_at"]),
            "kind": "command",
            "original_command": try JSONSerialization.jsonObject(with: actual.command.wireBody),
            "result": saved, "terminal_receipt": NSNull(),
          ],
        ], "has_more": false, "next_cursor": NSNull(),
      ] as [String: Any]
    let journalBody = try JSONSerialization.data(withJSONObject: [
      "data": journal, "meta": ["api_version": "v1", "request_id": "unit-known-edit-journal"],
    ])
    var conflicting = edited
    var conflictingEffect = edit
    conflictingEffect["operation_id"] = UUID().uuidString.lowercased()
    conflicting["last_operation"] = conflictingEffect
    let contradictoryBody = try JSONSerialization.data(withJSONObject: [
      "data": conflicting, "meta": ["api_version": "v1", "request_id": "unit-conflicting-read"],
    ])
    var emptyJournal = journal
    emptyJournal["items"] = []
    let emptyJournalBody = try JSONSerialization.data(withJSONObject: [
      "data": emptyJournal,
      "meta": ["api_version": "v1", "request_id": "unit-empty-history-reset"],
    ])
    let phase = FlowMealProjectionPhase()
    let barrier = ConversationControllerBarrier()
    await http.stub.respond { request, _ in
      let path = request.url?.path ?? ""
      if path.hasSuffix("/session") { return .init(status: 200, body: actual.sessionEnvelope) }
      if path.hasSuffix("/journal") {
        if await phase.takeEmptyJournal() { return .init(status: 200, body: emptyJournalBody) }
        await phase.markEdited()
        return .init(status: 200, body: journalBody)
      }
      if path.hasSuffix("/meal") {
        let old = !(await phase.edited)
        if old, ordering == "in-flight-empty" { await barrier.enter() }
        if await phase.takeStaleRead() {
          return .init(
            status: 200,
            body: ordering == "same-revision-other-operation" ? contradictoryBody : unchangedBody)
        }
        return .init(status: 200, body: old ? unchangedBody : actual.groupEnvelope)
      }
      return .init(status: 200, body: actual.savedEnvelope)
    }
    let model = try await FlowConversationModel.open(
      transport: http.transport, lifecycle: lifecycle, store: disk.store,
      keyVault: .init(service: "synthetic", security: keys))
    await model.sendQueued(commandID: actual.command.commandID)
    let initialRead = Task { await model.loadCurrentGroup(commandID: actual.command.commandID) }
    if ordering == "in-flight-empty" {
      #expect(await barrier.waitEnteredOrFinished())
      #expect(model.currentGroup(commandID: actual.command.commandID) == nil)
    } else {
      await initialRead.value
      #expect(model.currentGroup(commandID: actual.command.commandID)?.revision == 0)
    }
    await model.loadHistory()
    #expect(model.knownEditRevision(commandID: actual.command.commandID) == 7)
    #expect(model.currentGroup(commandID: actual.command.commandID) == nil)
    if ordering == "in-flight-empty" {
      await barrier.release()
      await initialRead.value
      #expect(model.currentGroup(commandID: actual.command.commandID) == nil)
    }
    // A newly started GET can also return stale/conflicting server facts;
    // cancellation of the old request alone cannot protect publication.
    await phase.returnStaleOnce()
    await model.loadCurrentGroup(commandID: actual.command.commandID)
    #expect(model.currentGroup(commandID: actual.command.commandID) == nil)
    await model.loadCurrentGroup(commandID: actual.command.commandID)
    let current = try #require(model.currentGroup(commandID: actual.command.commandID))
    #expect(current.current?.items.first(where: { $0.foodName.contains("whey") })?.quantityG == 35)
    // A fresh first page may omit this older edit. It cannot erase a fact
    // already learned within the same patient/epoch identity.
    await phase.returnEmptyJournalOnce()
    await model.loadHistory()
    #expect(model.knownEditRevision(commandID: actual.command.commandID) == 7)
    await phase.returnStaleOnce()
    await model.loadCurrentGroup(commandID: actual.command.commandID)
    #expect(model.currentGroup(commandID: actual.command.commandID) == nil)
    await model.loadCurrentGroup(commandID: actual.command.commandID)
    #expect(model.currentGroup(commandID: actual.command.commandID)?.revision == 7)
    let otherPatient = UUID()
    let sessionObject = try #require(
      JSONSerialization.jsonObject(with: actual.sessionEnvelope) as? [String: Any])
    var sessionData = try #require(sessionObject["data"] as? [String: Any])
    sessionData["owner_id"] = otherPatient.uuidString.lowercased()
    let otherSession = try JSONSerialization.data(withJSONObject: [
      "data": sessionData, "meta": ["api_version": "v1", "request_id": "unit-other-patient"],
    ])
    await http.stub.respond { _, _ in .init(status: 200, body: otherSession) }
    await model.refresh()
    #expect(model.acceptedIdentity?.ownerID == otherPatient)
    #expect(model.knownEditRevision(commandID: actual.command.commandID) == 0)
    #expect(model.currentGroup(commandID: actual.command.commandID) == nil)
    #expect(await http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }

  #if canImport(UIKit)
    @Test func actualCurrentAndHistoricalComponentsExpose35gAndOriginalSixSectionsSeparately()
      throws
    {
      let fixture = try FlowActualEditLifecycleFixture()
      struct GroupEnvelope: Decodable { let data: ConversationMealGroupSnapshot }
      struct SavedEnvelope: Decodable { let data: SavedConversationMealCommandResultSnapshot }
      let group = try JSONDecoder().decode(GroupEnvelope.self, from: fixture.groupEnvelope).data
      let saved = try JSONDecoder().decode(SavedEnvelope.self, from: fixture.savedEnvelope).data
      let feedback = try #require(
        saved.boundFeedback(
          scope: .init(
            ownerID: fixture.session.ownerID.uuidString.lowercased(), sessionGeneration: 7,
            epoch: fixture.session.epoch.uuidString.lowercased())))
      let host = SignUpRenderingProbe.host(
        VStack(alignment: .leading) {
          FlowConversationMealGroupView(group: group)
          Text("Original historical registration")
          ConversationFeedbackPresentationView(feedback: feedback)
        }.environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 3200)
      defer { host.detach() }
      let nodes = host.nodes()
      let diagnostic = Comment(rawValue: nodes.map(\.description).joined(separator: "\n"))
      #expect(
        nodes.contains {
          $0.identifier == "conversation.meal.current-title" && $0.label == "Current meal"
        })
      let whey = try #require(group.current?.items.first(where: { $0.foodName.contains("whey") }))
      let node = try #require(
        nodes.first {
          $0.identifier == "conversation.meal.current-item.\(whey.id.uuidString.lowercased())"
            && $0.isElement
        }, diagnostic)
      #expect(node.label.contains("35 g") && node.label.contains("123.2"))
      #expect(node.frame.width > 0 && node.frame.height > 0)
      #expect(
        nodes.contains {
          $0.identifier == "conversation.feedback.historical"
            && $0.label.contains(saved.receipt.localDate)
        })
      if case .sections(let recorded, let sections) = feedback.presentation.content {
        #expect(recorded.items.first(where: { $0.foodName.contains("whey") })?.quantityG == 30)
        for section in sections {
          #expect(
            nodes.contains {
              $0.identifier == "conversation.feedback.section.\(section.key.rawValue)"
                && $0.label.utf16.elementsEqual(section.text.utf16)
            })
        }
      } else {
        Issue.record("Actual six historical sections required")
      }
    }
  #endif

  @Test func actualLifecycleShowsCurrent35gAlongsideHistorical30gWithoutChangingOriginalReceipt()
    async throws
  {
    let f = try FlowActualEditLifecycleFixture()
    let disk = try OutboxDiskFixture()
    defer { disk.remove() }
    let lifecycle = ConversationHTTPTestLifecycle()
    await lifecycle.replace(
      .init(userID: f.authUserID, generation: 7, bearer: "synthetic-lifecycle"))
    let http = try ConversationHTTPFixture(lifecycle: lifecycle)
    let owner = try ConversationOutboxOwner(lease: await lifecycle.leaseForRequest())
    let keys = OutboxKeychainFake()
    await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    try disk.store.update(owner: owner, key: disk.key) {
      $0.append(
        .init(
          command: f.command, originalServerEpoch: f.session.epoch,
          originalPatientOwnerID: f.session.ownerID))
    }
    await http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true {
        return .init(status: 200, body: f.sessionEnvelope)
      }
      if request.url?.path.hasSuffix("/meal") == true {
        return .init(status: 200, body: f.groupEnvelope)
      }
      return .init(status: 200, body: f.savedEnvelope)
    }
    let model = try await FlowConversationModel.open(
      transport: http.transport, lifecycle: lifecycle, store: disk.store,
      keyVault: .init(service: "synthetic", security: keys))
    await model.sendQueued(commandID: f.command.commandID)
    let original = try #require(model.savedRows.first)
    let originalFeedback = try #require(original.feedback)
    guard case .sections(let recorded, let sections) = originalFeedback.presentation.content else {
      Issue.record("Actual original six sections required")
      await model.close()
      return
    }
    #expect(
      sections.count == 6
        && recorded.items.first(where: { $0.foodName.contains("whey") })?.quantityG == 30)
    await model.loadCurrentGroup(commandID: original.id)
    let current = try #require(model.currentGroup(commandID: original.id))
    #expect(
      current.revision == 7
        && current.current?.items.first(where: { $0.foodName.contains("whey") })?.quantityG == 35)
    #expect(current.current?.items.first(where: { $0.foodName.contains("whey") })?.kcal == 123.2)
    #expect(model.savedRows.first?.feedback == originalFeedback)
    #expect(model.savedRows.first?.receipt == original.receipt)
    await http.stub.respond { _, _ in .failure(503, "conversation_meal_edit_unavailable") }
    await model.loadCurrentGroup(commandID: original.id)
    #expect(
      model.currentGroup(commandID: original.id) == nil
        && model.groupUnavailable(commandID: original.id))
    #expect(
      model.savedRows.first?.receipt == original.receipt
        && model.savedRows.first?.feedback == originalFeedback)
    #expect(try disk.store.load(owner: owner, key: disk.key).isEmpty)
    #expect(await http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }
}

struct FlowActualEditLifecycleFixture: Sendable {
  let authUserID: String
  let command: ConversationMealCommand
  let session: ConversationSessionSnapshot
  let sessionEnvelope: Data
  let savedEnvelope: Data
  let groupEnvelope: Data
  init() throws {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "FlowMealEditLifecycleFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/FlowMealEditLifecycleFixtures.json")
    #endif
    let data = try Data(contentsOf: url)
    #expect(
      ConversationMealCommand.digest(data)
        == "f0037fb5da38db2ab3806d97f5d341f5ce82a5304f69c1e3618f2320dba6cc1b")
    let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    authUserID = try #require(raw["auth_user_id"] as? String)
    command = try ConversationMealCommand(
      wireBody: JSONSerialization.data(
        withJSONObject: #require(raw["original_command"]),
        options: [.sortedKeys, .withoutEscapingSlashes]))
    sessionEnvelope = try JSONSerialization.data(withJSONObject: #require(raw["session"]))
    savedEnvelope = try JSONSerialization.data(withJSONObject: #require(raw["original_saved"]))
    // Actual QA artifact has group DATA only. This synthetic HTTP envelope
    // supplies only ordinary metadata; facts, IDs and hashes stay exact.
    groupEnvelope = try JSONSerialization.data(withJSONObject: [
      "data": #require(raw["current_after_save"]),
      "meta": ["api_version": "v1", "request_id": "native-current-group-fixture"],
    ])
    session = try JSONDecoder().decode(Envelope.self, from: sessionEnvelope).data
  }
  private struct Envelope: Decodable { let data: ConversationSessionSnapshot }
}

private actor FlowMealProjectionPhase {
  private(set) var edited = false
  private var staleNext = false
  private var emptyJournalNext = false
  func markEdited() { edited = true }
  func returnStaleOnce() { staleNext = true }
  func returnEmptyJournalOnce() { emptyJournalNext = true }
  func takeEmptyJournal() -> Bool {
    defer { emptyJournalNext = false }
    return emptyJournalNext
  }
  func takeStaleRead() -> Bool {
    defer { staleNext = false }
    return staleNext
  }
}
