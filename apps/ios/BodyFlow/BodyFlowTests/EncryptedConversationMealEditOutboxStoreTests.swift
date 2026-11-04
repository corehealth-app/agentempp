import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Encrypted immutable meal-edit queue")
struct EncryptedConversationMealEditOutboxStoreTests {
  @Test func restartPreservesExactOriginalBindingBodyAndUnknownWithoutPlaintext() throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let op = try f.operation(name: "PRIVATE MILK whey 😀 e\u{301}")
    try f.store.update(owner: f.owner, key: f.key) { $0.append(.init(operation: op)) }
    try f.store.update(owner: f.owner, key: f.key) { $0[0].state = .dispatchedUnknown }
    let value = try EncryptedConversationMealEditOutboxStore(directory: f.directory).load(
      owner: f.owner, key: f.key)
    #expect(value.count == 1 && value[0].state == .dispatchedUnknown)
    #expect(
      value[0].operation.wireBody == op.wireBody
        && value[0].operation.operationInputHash == op.operationInputHash)
    #expect(value[0].operation.ownerID == op.ownerID && value[0].operation.epoch == op.epoch)
    for file in try FileManager.default.contentsOfDirectory(
      at: f.store.root, includingPropertiesForKeys: nil)
    {
      let data = try Data(contentsOf: file)
      #expect(data.range(of: Data("PRIVATE MILK".utf8)) == nil)
      #expect(data.range(of: Data(f.lease.userID.utf8)) == nil)
      #expect(!file.lastPathComponent.contains(f.lease.userID))
    }
  }
  @Test func wrongAuthKeyAndTamperPreserveCiphertext() throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    try f.store.update(owner: f.owner, key: f.key) {
      $0.append(.init(operation: try f.operation()))
    }
    let path = f.store.fileURL(owner: f.owner)
    let original = try Data(contentsOf: path)
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.load(owner: f.owner, key: SymmetricKey(size: .bits256))
    }
    let other = try ConversationOutboxOwner(
      lease: .init(userID: UUID().uuidString, generation: 0, bearer: "synthetic"))
    try original.write(to: f.store.fileURL(owner: other))
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.load(owner: other, key: f.key)
    }
    var changed = original
    changed[changed.count - 1] ^= 1
    try changed.write(to: path)
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.load(owner: f.owner, key: f.key)
    }
    #expect(try Data(contentsOf: path) == changed)
  }
  @Test func reportCiphertextCannotBeReadOrOverwrittenAsEditCiphertext() throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let report = EncryptedConversationOutboxStore(directory: f.directory)
    try report.update(owner: f.owner, key: f.key) {
      $0.append(
        .init(
          command: try ConversationMealCommand(source: .text("PRIVATE REPORT")),
          originalServerEpoch: f.epoch, originalPatientOwnerID: f.patient))
    }
    let reportURL = report.fileURL(owner: f.owner)
    let data = try Data(contentsOf: reportURL)
    #expect(report.root != f.store.root)
    _ = try f.store.containsCiphertext(owner: f.owner)
    try data.write(to: f.store.fileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.load(owner: f.owner, key: f.key)
    }
    #expect(try Data(contentsOf: reportURL) == data)
  }
  @Test func fullQueueRefusesNewIntentWithoutEvictionOrPartialWrite() throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    try f.store.update(owner: f.owner, key: f.key) { entries in
      for _ in 0..<50 { entries.append(.init(operation: try f.operation(operationID: UUID()))) }
    }
    let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.queueFull) {
      try f.store.update(owner: f.owner, key: f.key) {
        $0.append(.init(operation: try f.operation(operationID: UUID())))
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
    #expect(try f.store.load(owner: f.owner, key: f.key).count == 50)
  }
  @Test func duplicateIdentityRejectedButOperationUUIDMayRepeatAcrossCommands() throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let a = try f.operation()
    let b = try f.operation(commandID: UUID())
    try f.store.update(owner: f.owner, key: f.key) {
      $0.append(.init(operation: a))
      $0.append(.init(operation: b))
    }
    #expect(try f.store.load(owner: f.owner, key: f.key).map(\.id).count == 2)
    #expect(a.operationID == b.operationID)
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.update(owner: f.owner, key: f.key) { $0.append(.init(operation: a)) }
    }
  }
  @Test func immutableIntentAndMonotonicHoldsCannotBeRebased() throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    let op = try f.operation()
    try f.store.update(owner: f.owner, key: f.key) { $0.append(.init(operation: op)) }
    try f.store.update(owner: f.owner, key: f.key) {
      $0[0].state = .waitingReconciliation
      $0[0].hold = .staleEpoch
    }
    let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.update(owner: f.owner, key: f.key) {
        $0[0].state = .queued
        $0[0].hold = nil
      }
    }
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.update(owner: f.owner, key: f.key) { $0[0].hold = .unknownOutcome }
    }
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.update(owner: f.owner, key: f.key) { entries in
        entries[0] = .init(operation: try f.operation(name: "changed same OP"))
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
  }
  @Test func realAtomicFailurePreservesPreviousQueue() throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    try f.store.update(owner: f.owner, key: f.key) {
      $0.append(.init(operation: try f.operation()))
    }
    let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.store.root.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: f.store.root.path)
    }
    #expect(throws: ConversationOutboxError.storageUnavailable) {
      try f.store.update(owner: f.owner, key: f.key) {
        $0.append(.init(operation: try f.operation(operationID: UUID())))
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
  }
  @Test func authenticatedButInconsistentHashOrUnknownEnvelopeIsRefused() throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    try f.store.update(owner: f.owner, key: f.key) {
      $0.append(.init(operation: try f.operation()))
    }
    let url = f.store.fileURL(owner: f.owner)
    let original = try Data(contentsOf: url)
    let aad = Data("performe.conversation.meal-edit.outbox\0version=1\0owner=\(f.owner.hash)".utf8)
    let plain = try AES.GCM.open(
      AES.GCM.SealedBox(combined: original.dropFirst(8)), using: f.key, authenticating: aad)
    let base = try #require(JSONSerialization.jsonObject(with: plain) as? [String: Any])
    for attack in ["hash", "extra", "version"] {
      var value = base
      if attack == "extra" {
        value["unknown"] = "private"
      } else if attack == "version" {
        value["version"] = 2
      } else {
        var entries = try #require(value["entries"] as? [[String: Any]])
        entries[0]["operationInputHash"] = String(repeating: "f", count: 64)
        value["entries"] = entries
      }
      let changed = try JSONSerialization.data(withJSONObject: value)
      let sealed = try #require(AES.GCM.seal(changed, using: f.key, authenticating: aad).combined)
      let forged = Data("PCEDX001".utf8) + sealed
      try forged.write(to: url)
      #expect(throws: ConversationOutboxError.integrityFailure) {
        try f.store.load(owner: f.owner, key: f.key)
      }
      #expect(try Data(contentsOf: url) == forged)
    }
  }
  @Test func concurrentStoreInstancesRetainEveryDistinctIntent() async throws {
    let f = try EditOutboxFixture()
    defer { f.remove() }
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<20 {
        group.addTask {
          let store = EncryptedConversationMealEditOutboxStore(directory: f.directory)
          try store.update(owner: f.owner, key: f.key) {
            $0.append(.init(operation: try f.operation(operationID: UUID())))
          }
        }
      }
      try await group.waitForAll()
    }
    let values = try f.store.load(owner: f.owner, key: f.key)
    #expect(values.count == 20 && Set(values.map(\.id)).count == 20)
  }
}

struct EditOutboxFixture: Sendable {
  let directory: URL
  let store: EncryptedConversationMealEditOutboxStore
  let key = SymmetricKey(size: .bits256)
  let lease = SessionLease(
    userID: "90000000-0000-4000-8000-000000000001", generation: 7,
    bearer: "synthetic-never-persisted")
  let owner: ConversationOutboxOwner
  let patient = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
  let epoch = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
  var server: ConversationOutboxServerObservation {
    .init(
      authUserID: UUID(uuidString: lease.userID)!, ownerID: patient,
      localSessionGeneration: lease.generation, epoch: epoch)
  }
  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "edit-outbox-test-\(UUID())", isDirectory: true)
    store = .init(directory: directory)
    owner = try .init(lease: lease)
  }
  func operation(
    operationID: UUID = UUID(uuidString: "10000000-0000-4000-8000-000000000080")!,
    commandID: UUID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
    name: String = "Arroz cozido"
  ) throws -> ConversationMealEditOperation {
    try .init(
      ownerID: patient, commandID: commandID,
      originalInputHash: "d74050d7026b612f959ea907f0cb4dd79280539fe8e463f543f2e4ed5fc9ecf6",
      epoch: epoch, operationID: operationID, expectedRevision: 0,
      expectedVersion: "v1:" + String(repeating: "a", count: 64),
      action: .save(
        recordID: UUID(uuidString: "10000000-0000-4000-8000-000000000005")!,
        items: [.init(foodName: name, quantityG: 200, quantityBasis: .stated)]))
  }
  func remove() { try? FileManager.default.removeItem(at: directory) }
}
