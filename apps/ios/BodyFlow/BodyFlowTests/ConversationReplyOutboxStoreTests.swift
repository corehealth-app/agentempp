import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Reports and linked replies share one protected fifty-intent queue")
struct ConversationReplyOutboxStoreTests {
  @Test func v3ReadsStayByteExactAndFirstReplyMigratesAtomicallyWithoutChangingReports() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let report = try ConversationMealCommand(source: .text("PRIVATE original report 😀"))
    try f.store.update(owner: f.owner, key: f.key) {
      var row = ConversationOutboxEntry(
        command: report, originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID)
      row.state = .dispatchedUnknown
      $0.append(row)
    }
    let old = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(old.starts(with: Data("PCOBX003".utf8)))
    #expect(try f.store.loadReplies(owner: f.owner, key: f.key).isEmpty)
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == old)
    let intent = try reply()
    try f.store.updateReplies(owner: f.owner, key: f.key) { $0.append(.init(intent: intent)) }
    let migrated = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(migrated.starts(with: Data("PCOBX004".utf8)))
    let reports = try f.store.load(owner: f.owner, key: f.key)
    #expect(
      reports.count == 1 && reports[0].wireBody == report.wireBody
        && reports[0].inputHash == report.inputHash)
    #expect(reports[0].state == .dispatchedUnknown && reports[0].originalServerEpoch == f.epoch)
    let reopened = EncryptedConversationOutboxStore(directory: f.directory)
    let answers = try reopened.loadReplies(owner: f.owner, key: f.key)
    #expect(
      answers.count == 1 && answers[0].intent.wireBody == intent.wireBody
        && answers[0].intent.replyInputHash == intent.replyInputHash)
    #expect(answers[0].intent.replyID == intent.replyID)
    try f.store.update(owner: f.owner, key: f.key) {
      $0[0].state = .waitingReconciliation
      $0[0].hold = .unknownOutcome
    }
    #expect(
      try reopened.loadReplies(owner: f.owner, key: f.key)[0].intent.wireBody == intent.wireBody)
    for path in try FileManager.default.contentsOfDirectory(
      at: f.store.root, includingPropertiesForKeys: nil)
    {
      let bytes = try Data(contentsOf: path)
      #expect(bytes.range(of: Data("PRIVATE original report".utf8)) == nil)
      #expect(bytes.range(of: intent.wireBody) == nil)
      #expect(!path.lastPathComponent.contains(f.lease.userID))
    }
  }

  @Test(arguments: [1, 2], ["queued", "dispatched-unknown"])
  func legacyMissingBindingsRemainHeldThroughFirstReplyTransaction(_ version: Int, _ state: String)
    throws
  {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    _ = try f.store.load(owner: f.owner, key: f.key)
    let report = try ConversationMealCommand(source: .text("preserved legacy original"))
    var row: [String: Any] = [
      "commandID": report.commandID.uuidString, "wireBody": report.wireBody.base64EncodedString(),
      "inputHash": report.inputHash, "state": state, "hold": NSNull(),
    ]
    if version == 2 {
      row["originalServerEpoch"] = f.epoch.uuidString
      row["epochProvenance"] = "backend-observation"
    }
    let plain = try JSONSerialization.data(withJSONObject: [
      "version": version, "owner": f.owner.hash, "entries": [row],
    ])
    let sealed = try #require(
      AES.GCM.seal(
        plain, using: f.key,
        authenticating: Data(
          "performe.conversation.outbox\0version=\(version)\0owner=\(f.owner.hash)".utf8)
      ).combined)
    let old = Data((version == 1 ? "PCOBX001" : "PCOBX002").utf8) + sealed
    try old.write(to: f.store.fileURL(owner: f.owner))
    #expect(try f.store.loadReplies(owner: f.owner, key: f.key).isEmpty)
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == old)
    try f.store.updateReplies(owner: f.owner, key: f.key) { $0.append(.init(intent: try reply())) }
    let restored = try #require(f.store.load(owner: f.owner, key: f.key).first)
    #expect(
      restored.commandID == report.commandID && restored.wireBody == report.wireBody
        && restored.inputHash == report.inputHash)
    #expect(restored.originalPatientOwnerID == nil && restored.ownerProvenance == .legacyUnbound)
    #expect(restored.originalServerEpoch == (version == 1 ? nil : f.epoch))
    #expect(restored.state == (state == "queued" ? .queued : .waitingReconciliation))
    #expect(restored.hold == (version == 1 ? .originalEpochUnavailable : .originalOwnerUnavailable))
    #expect(
      try Data(contentsOf: f.store.fileURL(owner: f.owner)).starts(with: Data("PCOBX004".utf8)))
  }
  @Test func reportAndReplyCannotShareAnIdentityAndNoCiphertextIsReplaced() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let report = try ConversationMealCommand(source: .text("original report"))
    try f.store.update(owner: f.owner, key: f.key) {
      $0.append(
        .init(
          command: report, originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID))
    }
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.updateReplies(owner: f.owner, key: f.key) {
        $0.append(.init(intent: try reply(id: report.commandID)))
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
  }
  @Test func combinedCapacityIsFiftyInBothDirectionsWithoutEvictionOrPartialWrite() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    try f.store.update(owner: f.owner, key: f.key) { rows in
      for _ in 0..<49 {
        rows.append(
          .init(
            command: try ConversationMealCommand(source: .text("report")),
            originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID))
      }
    }
    try f.store.updateReplies(owner: f.owner, key: f.key) { $0.append(.init(intent: try reply())) }
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
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
        $0.append(.init(intent: try reply()))
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    #expect(try f.store.load(owner: f.owner, key: f.key).count == 49)
    #expect(try f.store.loadReplies(owner: f.owner, key: f.key).count == 1)
  }

  @Test func twoKindsOfConcurrentTransactionsNeverDropTheOtherKindsOriginalBytes() async throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let original = try reply()
    try f.store.updateReplies(owner: f.owner, key: f.key) { $0.append(.init(intent: original)) }
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<12 {
        group.addTask {
          let store = EncryptedConversationOutboxStore(directory: f.directory)
          if index.isMultiple(of: 2) {
            try store.update(owner: f.owner, key: f.key) {
              $0.append(
                .init(
                  command: try ConversationMealCommand(source: .text("independent report")),
                  originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID))
            }
          } else {
            try store.updateReplies(owner: f.owner, key: f.key) {
              $0.append(.init(intent: try reply()))
            }
          }
        }
      }
      try await group.waitForAll()
    }
    #expect(try f.store.load(owner: f.owner, key: f.key).count == 6)
    let answers = try f.store.loadReplies(owner: f.owner, key: f.key)
    #expect(answers.count == 7 && Set(answers.map { $0.intent.replyID }).count == 7)
    #expect(answers.first?.intent.wireBody == original.wireBody)
    #expect(answers.dropFirst().allSatisfy { $0.intent.replyInputHash == original.replyInputHash })
  }

  @Test func v4WrongKeyAccountTamperingAndRealRenameFailurePreserveCiphertext() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    try f.store.updateReplies(owner: f.owner, key: f.key) { $0.append(.init(intent: try reply())) }
    let path = f.store.fileURL(owner: f.owner)
    let original = try Data(contentsOf: path)
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.loadReplies(owner: f.owner, key: SymmetricKey(size: .bits256))
    }
    let other = try ConversationOutboxOwner(
      lease: .init(userID: UUID().uuidString.lowercased(), generation: 8, bearer: "synthetic"))
    try original.write(to: f.store.fileURL(owner: other))
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.loadReplies(owner: other, key: f.key)
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.store.root.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: f.store.root.path)
    }
    #expect(throws: ConversationOutboxError.storageUnavailable) {
      try f.store.updateReplies(owner: f.owner, key: f.key) {
        $0.append(.init(intent: try reply()))
      }
    }
    #expect(try Data(contentsOf: path) == original)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: f.store.root.path)
    var damaged = original
    damaged[damaged.count - 1] ^= 1
    try damaged.write(to: path)
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.loadReplies(owner: f.owner, key: f.key)
    }
    #expect(try Data(contentsOf: path) == damaged)
  }

  @Test func identityAndDispatchStateCannotBeReplacedUnderAnExistingReplyID() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let original = try reply()
    try f.store.updateReplies(owner: f.owner, key: f.key) { $0.append(.init(intent: original)) }
    try f.store.updateReplies(owner: f.owner, key: f.key) { $0[0].state = .dispatchedUnknown }
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.updateReplies(owner: f.owner, key: f.key) { $0[0] = .init(intent: original) }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    #expect(try f.store.loadReplies(owner: f.owner, key: f.key)[0].state == .dispatchedUnknown)
  }

  private func reply(id: UUID = UUID()) throws -> ConversationMealReplyIntent {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealReplyPublicFixtures", withExtension: "json")
      )
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealReplyPublicFixtures.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let saved = try #require((root["saved"] as? [String: Any])?["data"] as? [String: Any])
    let needs = try #require((root["needs_reply"] as? [String: Any])?["data"] as? [String: Any])
    let parent = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Binding.self,
      from: JSONSerialization.data(withJSONObject: #require(saved["parent_binding"])))
    let question = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Question.self,
      from: JSONSerialization.data(withJSONObject: #require(needs["question"])))
    let decision = try #require(saved["parent_decision_hash"] as? String)
    return try .init(
      parentBinding: parent, parentDecisionHash: decision, question: question, replyID: id,
      answer: .mealType(.almoco))
  }
}
