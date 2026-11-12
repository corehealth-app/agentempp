import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Protected original media before remote upload")
struct ConversationMediaOriginalStoreTests {
  @Test func missingOrChangedTemporaryBytesAreRestoredButSymlinksAreRefused() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let original = try mediaOriginalUnit(f)
    let staging = MediaStagingStore(temporaryDirectory: f.directory)
    let staged = try original.restage(in: staging)
    try Data(repeating: 0, count: staged.sizeBytes).write(to: staged.fileURL)
    try original.ensureStaged(staged, in: staging)
    #expect(try Data(contentsOf: staged.fileURL) == Data("PRIVATE ORIGINAL BYTES".utf8))
    staging.purge()
    try original.ensureStaged(staged, in: staging)
    #expect(try Data(contentsOf: staged.fileURL) == Data("PRIVATE ORIGINAL BYTES".utf8))
    let foreign = f.directory.appendingPathComponent("foreign-original.mp3")
    let foreignBytes = Data("KEEP THIS FOREIGN FILE".utf8)
    try foreignBytes.write(to: foreign)
    try FileManager.default.removeItem(at: staged.fileURL)
    try FileManager.default.createSymbolicLink(at: staged.fileURL, withDestinationURL: foreign)
    #expect(throws: (any Error).self) { try original.ensureStaged(staged, in: staging) }
    #expect(try Data(contentsOf: foreign) == foreignBytes)
    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: staged.fileURL.path) == foreign.path
    )
  }
  @Test func discardingAnUnadmittedConcurrentCaptureCannotDeleteTheAdmittedOriginal() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let original = try f.store.prepareOriginal(mediaOriginalUnit(f), owner: f.owner, key: f.key)
    let before = try Data(contentsOf: f.store.originalFileURL(owner: f.owner))
    #expect(throws: ConversationOutboxError.commandNotFound) {
      try f.store.discardOriginal(intakeID: UUID(), owner: f.owner, key: f.key)
    }
    #expect(try Data(contentsOf: f.store.originalFileURL(owner: f.owner)) == before)
    #expect(try f.store.loadOriginal(owner: f.owner, key: f.key) == original)
  }

  @Test func staleOriginalSessionCannotBindOrDeleteAcrossAccountABAndLaterA() async throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let http = try ConversationHTTPFixture()
    let security = OutboxKeychainFake()
    let lease = await http.lifecycle.leaseForRequest()
    let vault = ConversationOutboxKeyVault(service: "original-session-unit", security: security)
    let session = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: http.lifecycle, store: f.store, keyVault: vault)
    let observation = ConversationOutboxServerObservation(
      authUserID: UUID(uuidString: lease.userID)!,
      ownerID: f.server.ownerID, localSessionGeneration: lease.generation, epoch: f.epoch)
    let context = ConversationCommandContext(
      observation: observation, observedAt: "2026-11-12T19:00:00Z")
    let staging = MediaStagingStore(temporaryDirectory: f.directory)
    let bytes = Data("PRIVATE ORIGINAL".utf8)
    let original = try ConversationMediaOriginal(
      staged: .init(
        fileURL: staging.stage(bytes, fileExtension: "mp3"),
        kind: .audioNote, mimeType: "audio/mpeg", sizeBytes: bytes.count, duration: 12,
        channel: .audioRecording),
      staging: staging, captureID: UUID(), intakeID: UUID(), context: context.identity,
      caption: nil, mealTypeHint: nil)
    _ = try await session.prepareOriginal(original, context: context)
    let owner = try ConversationOutboxOwner(lease: lease)
    let path = f.store.originalFileURL(owner: owner)
    let before = try Data(contentsOf: path)
    await http.lifecycle.replace(
      .init(userID: UUID().uuidString, generation: lease.generation + 1, bearer: "synthetic-B"))
    await #expect(throws: (any Error).self) {
      try await session.bindOriginalAsset(
        intakeID: original.intakeID, assetID: UUID(), context: context)
    }
    await #expect(throws: (any Error).self) {
      try await session.discardOriginal(intakeID: original.intakeID)
    }
    await http.lifecycle.replace(
      .init(userID: lease.userID, generation: lease.generation + 2, bearer: "synthetic-later-A"))
    await #expect(throws: (any Error).self) { try await session.loadOriginal(context: context) }
    #expect(try Data(contentsOf: path) == before)
    await session.invalidate()
  }

  @Test func nonNeutralPurposeAndForeignOrSymlinkBytesAreNotAdmitted() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let staging = MediaStagingStore(temporaryDirectory: f.directory)
    let bytes = Data("private bytes".utf8)
    let file = try staging.stage(Data("private bytes".utf8), fileExtension: "jpg")
    let identity = ConversationCommandContext.Identity(
      authUserID: UUID(uuidString: f.lease.userID)!, ownerID: f.server.ownerID,
      sessionGeneration: f.lease.generation, epoch: f.epoch)
    #expect(throws: (any Error).self) {
      try ConversationMediaOriginal(
        staged: .init(
          fileURL: file, kind: .mealPhoto, mimeType: "image/jpeg", sizeBytes: bytes.count,
          duration: nil, channel: .camera),
        staging: staging, captureID: UUID(), intakeID: UUID(), context: identity, caption: nil,
        mealTypeHint: nil)
    }
    let foreign = f.directory.appendingPathComponent("foreign.jpg")
    try bytes.write(to: foreign)
    #expect(throws: (any Error).self) {
      try ConversationMediaOriginal(
        staged: .init(
          fileURL: foreign, kind: .conversationPhoto, mimeType: "image/jpeg",
          sizeBytes: bytes.count, duration: nil, channel: .gallery),
        staging: staging, captureID: UUID(), intakeID: UUID(), context: identity, caption: nil,
        mealTypeHint: nil)
    }
    let link = try staging.makeFileURL(fileExtension: "jpg")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(throws: (any Error).self) {
      try ConversationMediaOriginal(
        staged: .init(
          fileURL: link, kind: .conversationPhoto, mimeType: "image/jpeg", sizeBytes: bytes.count,
          duration: nil, channel: .camera),
        staging: staging, captureID: UUID(), intakeID: UUID(), context: identity, caption: nil,
        mealTypeHint: nil)
    }
  }
  @Test func coldOriginalSurvivesTemporaryPurgeWithoutPlaintextOrLocalPaths() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let original = try mediaOriginalUnit(f)
    let saved = try f.store.prepareOriginal(original, owner: f.owner, key: f.key)
    MediaStagingStore(temporaryDirectory: f.directory).purge()
    let cold = EncryptedConversationOutboxStore(directory: f.directory)
    #expect(try cold.containsCiphertext(owner: f.owner))
    #expect(!FileManager.default.fileExists(atPath: cold.fileURL(owner: f.owner).path))
    let restored = try #require(try cold.loadOriginal(owner: f.owner, key: f.key))
    #expect(restored == saved)
    let staged = try restored.restage(in: .init(temporaryDirectory: f.directory))
    #expect(try Data(contentsOf: staged.fileURL) == Data("PRIVATE ORIGINAL BYTES".utf8))
    for file in try FileManager.default.contentsOfDirectory(
      at: cold.root, includingPropertiesForKeys: nil)
    {
      let bytes = try Data(contentsOf: file)
      #expect(bytes.range(of: Data("PRIVATE ORIGINAL".utf8)) == nil)
      #expect(bytes.range(of: Data(f.directory.path.utf8)) == nil)
      #expect(bytes.range(of: Data(f.lease.userID.utf8)) == nil)
    }
  }

  @Test func originalOnlyCiphertextRefusesMissingKeyWithoutCreatingAReplacement() async throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let http = try ConversationHTTPFixture()
    let owner = try ConversationOutboxOwner(lease: await http.lifecycle.leaseForRequest())
    _ = try f.store.prepareOriginal(mediaOriginalUnit(f), owner: owner, key: f.key)
    let ciphertext = try Data(contentsOf: f.store.originalFileURL(owner: owner))
    let security = OutboxKeychainFake()
    await #expect(throws: ConversationOutboxError.keyUnavailable) {
      try await ConversationNeutralIntakeOutboxSession.open(
        lifecycle: http.lifecycle, store: f.store,
        keyVault: .init(service: "missing-original-key", security: security))
    }
    #expect(await security.addCount == 0)
    #expect(try Data(contentsOf: f.store.originalFileURL(owner: owner)) == ciphertext)
  }

  @Test func wrongKeyCrossAccountAndModifiedCiphertextPreserveTheOriginal() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    _ = try f.store.prepareOriginal(mediaOriginalUnit(f), owner: f.owner, key: f.key)
    let path = f.store.originalFileURL(owner: f.owner)
    let ciphertext = try Data(contentsOf: path)
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.loadOriginal(owner: f.owner, key: SymmetricKey(size: .bits256))
    }
    let other = try ConversationOutboxOwner(
      lease: .init(userID: UUID().uuidString, generation: 9, bearer: "synthetic"))
    try ciphertext.write(to: f.store.originalFileURL(owner: other))
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.loadOriginal(owner: other, key: f.key)
    }
    var modified = ciphertext
    modified[modified.count - 1] ^= 1
    try modified.write(to: path)
    #expect(throws: ConversationOutboxError.integrityFailure) {
      try f.store.loadOriginal(owner: f.owner, key: f.key)
    }
    #expect(try Data(contentsOf: path) == modified)
  }

  @Test func originalReservesSharedCapacityAndCannotDispatchBeforeRetirement() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    try f.store.update(owner: f.owner, key: f.key) { rows in
      for _ in 0..<49 {
        rows.append(
          .init(
            command: try ConversationMealCommand(source: .text("old text")),
            originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID))
      }
    }
    let original = try f.store.prepareOriginal(mediaOriginalUnit(f), owner: f.owner, key: f.key)
    #expect(throws: ConversationOutboxError.queueFull) {
      try f.store.update(owner: f.owner, key: f.key) {
        $0.append(
          .init(
            command: try ConversationMealCommand(source: .text("overflow")),
            originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID))
      }
    }
    let bound = try f.store.bindOriginalAsset(
      intakeID: original.intakeID, assetID: UUID(), owner: f.owner, key: f.key)
    let input = try bound.input()
    try f.store.updateIntakes(owner: f.owner, key: f.key) {
      $0.append(.init(input: input, ownerID: bound.ownerID, epoch: bound.epoch))
    }
    #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try f.store.updateIntakes(owner: f.owner, key: f.key) { $0[0].state = .dispatchedUnknown }
    }
    // Exact crash window: main queue persisted, capture retirement not yet written.
    #expect(
      try EncryptedConversationOutboxStore(directory: f.directory).loadOriginal(
        owner: f.owner, key: f.key) == nil)
    #expect(
      try f.store.loadIntakes(owner: f.owner, key: f.key).first?.input.wireBody == input.wireBody)
    try f.store.updateIntakes(owner: f.owner, key: f.key) { $0[0].state = .dispatchedUnknown }
    #expect(try f.store.load(owner: f.owner, key: f.key).count == 49)
    #expect(try f.store.loadIntakes(owner: f.owner, key: f.key).count == 1)
  }

  @Test func crashAfterCancellationMarkerCannotResurrectQueuedMediaOrOverwriteIt() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let original = try f.store.prepareOriginal(mediaOriginalUnit(f), owner: f.owner, key: f.key)
    let bound = try f.store.bindOriginalAsset(
      intakeID: original.intakeID, assetID: UUID(), owner: f.owner, key: f.key)
    let input = try bound.input()
    try f.store.updateIntakes(owner: f.owner, key: f.key) {
      $0.append(.init(input: input, ownerID: bound.ownerID, epoch: bound.epoch))
    }
    // Controlled crash fixture: the durable cancellation exists but the old
    // queue write has not executed. This is not a fabricated server receipt.
    let marker: [String: Any] = [
      "version": 1, "owner": f.owner.hash,
      "retired": [
        "intakeID": input.intakeID.uuidString, "ownerID": bound.ownerID.uuidString,
        "epoch": bound.epoch.uuidString, "inputHash": input.inputHash, "cancelled": true,
      ],
    ]
    let plaintext = try JSONSerialization.data(withJSONObject: marker)
    let box = try AES.GCM.seal(
      plaintext, using: f.key,
      authenticating: Data("performe.conversation.original\0version=1\0owner=\(f.owner.hash)".utf8))
    let path = f.store.originalFileURL(owner: f.owner)
    try (Data("PCOMG001".utf8) + #require(box.combined)).write(to: path)
    #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try f.store.updateIntakes(owner: f.owner, key: f.key) { $0[0].state = .dispatchedUnknown }
    }
    #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try f.store.prepareOriginal(mediaOriginalUnit(f), owner: f.owner, key: f.key)
    }
    #expect(try f.store.loadOriginal(owner: f.owner, key: f.key) == nil)
    #expect(try f.store.loadIntakes(owner: f.owner, key: f.key).isEmpty)
  }

  @Test func realFailedWritePreservesOldQueueAndDoesNotAdmitAnOriginal() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    try f.store.update(owner: f.owner, key: f.key) {
      $0.append(
        .init(
          command: try ConversationMealCommand(source: .text("existing")),
          originalServerEpoch: f.epoch, originalPatientOwnerID: f.server.ownerID))
    }
    let ciphertext = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    let original = try mediaOriginalUnit(f)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.store.root.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: f.store.root.path)
    }
    #expect(throws: ConversationOutboxError.storageUnavailable) {
      try f.store.prepareOriginal(original, owner: f.owner, key: f.key)
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == ciphertext)
    #expect(!FileManager.default.fileExists(atPath: f.store.originalFileURL(owner: f.owner).path))
  }

  @Test func sameOriginalReplaysButDifferentBytesOrBoundAssetCannotReplaceIt() throws {
    let f = try OutboxDiskFixture()
    defer { f.remove() }
    let original = try mediaOriginalUnit(f)
    _ = try f.store.prepareOriginal(original, owner: f.owner, key: f.key)
    let asset = UUID()
    let bound = try f.store.bindOriginalAsset(
      intakeID: original.intakeID, assetID: asset, owner: f.owner, key: f.key)
    #expect(try f.store.prepareOriginal(original, owner: f.owner, key: f.key) == bound)
    #expect(throws: ConversationOutboxError.invalidTransition) {
      try f.store.bindOriginalAsset(
        intakeID: original.intakeID, assetID: UUID(), owner: f.owner, key: f.key)
    }
    let changed = try mediaOriginalUnit(
      f, captureID: original.captureID, intakeID: original.intakeID, bytes: Data("different".utf8))
    #expect(throws: ConversationOutboxError.invalidTransition) {
      try f.store.prepareOriginal(changed, owner: f.owner, key: f.key)
    }
    #expect(try f.store.loadOriginal(owner: f.owner, key: f.key) == bound)
    try f.store.discardOriginal(intakeID: original.intakeID, owner: f.owner, key: f.key)
    #expect(try f.store.loadOriginal(owner: f.owner, key: f.key) == nil)
  }
}

func mediaOriginalUnit(
  _ f: OutboxDiskFixture, captureID: UUID = UUID(), intakeID: UUID = UUID(),
  bytes: Data = Data("PRIVATE ORIGINAL BYTES".utf8)
) throws -> ConversationMediaOriginal {
  let staging = MediaStagingStore(temporaryDirectory: f.directory)
  let file = try staging.stage(bytes, fileExtension: "mp3")
  return try .init(
    staged: .init(
      fileURL: file, kind: .audioNote, mimeType: "audio/mpeg", sizeBytes: bytes.count,
      duration: 12, channel: .audioRecording), staging: staging, captureID: captureID,
    intakeID: intakeID,
    context: .init(
      authUserID: UUID(uuidString: f.lease.userID)!, ownerID: f.server.ownerID,
      sessionGeneration: f.lease.generation, epoch: f.epoch), caption: "PRIVATE ORIGINAL caption",
    mealTypeHint: .cafe)
}
