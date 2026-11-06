import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Neutral intents share the existing encrypted fifty-row outbox")
struct ConversationNeutralIntakeOutboxStoreTests {
  @Test func firstNeutralAtomicallyUpgradesSameFileAndPreservesLegacyReportExactly() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let meal = try ConversationMealCommand(source: .text("PRIVATE old meal"))
    try f.store.update(owner: f.owner, key: f.key) {
      var row = ConversationOutboxEntry(
        command: meal, originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID)
      row.state = .dispatchedUnknown
      $0.append(row)
    }
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(try f.store.loadIntakes(owner: f.owner, key: f.key).isEmpty)
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    let intake = try FlowNeutralIntakeInput(
      intakeID: UUID(), source: .text("PRIVATE walked 30 min"))
    try f.store.updateIntakes(owner: f.owner, key: f.key) {
      $0.append(.init(input: intake, ownerID: f.server.ownerID, epoch: f.epoch))
    }
    let disk = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(disk.starts(with: Data("PCOBX005".utf8)))
    #expect(disk.range(of: intake.wireBody) == nil)
    let mealRow = try #require(f.store.load(owner: f.owner, key: f.key).first)
    #expect(
      mealRow.wireBody == meal.wireBody && mealRow.inputHash == meal.inputHash
        && mealRow.state == .dispatchedUnknown)
    let reopened = EncryptedConversationOutboxStore(directory: f.directory)
    #expect(
      try reopened.loadIntakes(owner: f.owner, key: f.key).first?.input.wireBody == intake.wireBody)
    try reopened.updateIntakes(owner: f.owner, key: f.key) { $0.removeAll() }
    try reopened.updateReplies(owner: f.owner, key: f.key) { _ in }
    #expect(
      try Data(contentsOf: f.store.fileURL(owner: f.owner)).starts(with: Data("PCOBX005".utf8)))
  }
  @Test func capacityAndIdentityCollisionRefuseWithoutReplacingCiphertext() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let id = UUID()
    try f.store.update(owner: f.owner, key: f.key) { rows in
      for n in 0..<49 {
        rows.append(
          .init(
            command: try ConversationMealCommand(
              commandID: n == 0 ? id : UUID(), source: .text("meal")), originalServerEpoch: f.epoch,
            originalPatientOwnerID: f.server.ownerID))
      }
    }
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.updateIntakes(owner: f.owner, key: f.key) {
        $0.append(
          .init(
            input: try FlowNeutralIntakeInput(intakeID: id, source: .text("walked")),
            ownerID: f.server.ownerID, epoch: f.epoch))
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    try f.store.updateIntakes(owner: f.owner, key: f.key) {
      $0.append(
        .init(
          input: try FlowNeutralIntakeInput(intakeID: UUID(), source: .text("walked")),
          ownerID: f.server.ownerID, epoch: f.epoch))
    }
    let full = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.queueFull) {
      try f.store.updateIntakes(owner: f.owner, key: f.key) {
        $0.append(
          .init(
            input: try FlowNeutralIntakeInput(intakeID: UUID(), source: .text("again")),
            ownerID: f.server.ownerID, epoch: f.epoch))
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == full)
    #expect(try f.store.load(owner: f.owner, key: f.key).count == 49)
  }
  @Test func allThreeKindsUseOneFiftyLimitAndEveryWriterPreservesOtherKinds() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let meal = try ConversationMealCommand(source: .text("old meal"))
    try f.store.update(owner: f.owner, key: f.key) {
      $0.append(
        .init(command: meal, originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID)
      )
    }
    let answer = try neutralReply()
    try f.store.updateReplies(owner: f.owner, key: f.key) { $0.append(.init(intent: answer)) }
    try f.store.updateIntakes(owner: f.owner, key: f.key) { rows in
      for _ in 0..<48 {
        rows.append(
          .init(
            input: try FlowNeutralIntakeInput(intakeID: UUID(), source: .text("walked")),
            ownerID: f.server.ownerID, epoch: f.epoch))
      }
    }
    let full = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.queueFull) {
      try f.store.update(owner: f.owner, key: f.key) {
        $0.append(
          .init(
            command: try ConversationMealCommand(source: .text("overflow")),
            originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID))
      }
    }
    #expect(throws: ConversationOutboxError.queueFull) {
      try f.store.updateReplies(owner: f.owner, key: f.key) {
        $0.append(.init(intent: try neutralReply()))
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == full)
    #expect(try f.store.load(owner: f.owner, key: f.key).first?.wireBody == meal.wireBody)
    #expect(
      try f.store.loadReplies(owner: f.owner, key: f.key).first?.intent.wireBody == answer.wireBody)
    #expect(try f.store.loadIntakes(owner: f.owner, key: f.key).count == 48)
  }
  @Test(arguments: [1, 2], ["queued", "dispatched-unknown"])
  func legacyUnboundOrUnknownReportsStayHeldThroughNeutralMigration(_ version: Int, _ state: String)
    throws
  {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    _ = try f.store.load(owner: f.owner, key: f.key)
    let meal = try ConversationMealCommand(source: .text("preserved legacy"))
    var row: [String: Any] = [
      "commandID": meal.commandID.uuidString, "wireBody": meal.wireBody.base64EncodedString(),
      "inputHash": meal.inputHash, "state": state, "hold": NSNull(),
    ]
    if version == 2 {
      row["originalServerEpoch"] = f.epoch.uuidString
      row["epochProvenance"] = "backend-observation"
    }
    let plain = try neutralData(["version": version, "owner": f.owner.hash, "entries": [row]])
    let box = try #require(
      AES.GCM.seal(
        plain, using: f.key,
        authenticating: Data(
          "performe.conversation.outbox\0version=\(version)\0owner=\(f.owner.hash)".utf8)
      ).combined)
    let bytes = Data((version == 1 ? "PCOBX001" : "PCOBX002").utf8) + box
    try bytes.write(to: f.store.fileURL(owner: f.owner))
    #expect(try f.store.loadIntakes(owner: f.owner, key: f.key).isEmpty)
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == bytes)
    try f.store.updateIntakes(owner: f.owner, key: f.key) {
      $0.append(
        .init(
          input: try FlowNeutralIntakeInput(intakeID: UUID(), source: .text("walked")),
          ownerID: f.server.ownerID, epoch: f.epoch))
    }
    let old = try #require(f.store.load(owner: f.owner, key: f.key).first)
    #expect(
      old.commandID == meal.commandID && old.wireBody == meal.wireBody
        && old.inputHash == meal.inputHash)
    #expect(old.originalPatientOwnerID == nil && old.ownerProvenance == .legacyUnbound)
    #expect(old.state == (state == "queued" ? .queued : .waitingReconciliation))
    #expect(old.hold == (version == 1 ? .originalEpochUnavailable : .originalOwnerUnavailable))
  }
  @Test func unknownCannotReturnToQueuedOrChangeIdentityAndWrongKeyPreservesBytes() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    try f.store.updateIntakes(owner: f.owner, key: f.key) {
      var row = ConversationNeutralIntakeOutboxEntry(
        input: try FlowNeutralIntakeInput(intakeID: UUID(), source: .text("walked")),
        ownerID: f.server.ownerID, epoch: f.epoch)
      row.state = .waitingReconciliation
      row.hold = .unknownOutcome
      $0.append(row)
    }
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.updateIntakes(owner: f.owner, key: f.key) {
        $0[0].state = .queued
        $0[0].hold = nil
      }
    }
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.loadIntakes(owner: f.owner, key: SymmetricKey(size: .bits256))
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    #expect(try f.store.loadIntakes(owner: f.owner, key: f.key).first?.hold == .unknownOutcome)
  }
}

private func neutralReply() throws -> ConversationMealReplyIntent {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
    "Fixtures/ConversationMealReplyPublicFixtures.json")
  let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  let saved = (root["saved"] as! [String: Any])["data"] as! [String: Any]
  let needs = (root["needs_reply"] as! [String: Any])["data"] as! [String: Any]
  let binding = try JSONDecoder().decode(
    ConversationThreadPageSnapshot.Binding.self, from: neutralData(saved["parent_binding"]!))
  let question = try JSONDecoder().decode(
    ConversationThreadPageSnapshot.Question.self, from: neutralData(needs["question"]!))
  return try .init(
    parentBinding: binding, parentDecisionHash: saved["parent_decision_hash"] as! String,
    question: question, replyID: UUID(), answer: .mealType(.almoco))
}
