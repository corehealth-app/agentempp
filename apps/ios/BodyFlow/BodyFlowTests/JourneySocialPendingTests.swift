import CryptoKit
import Foundation
import Security
import Testing

@testable import BodyFlow

@Suite("Social pending intent survives interruptions without another consent")
struct JourneySocialPendingTests {
  @Test func canonicalPayloadRestoresTheExactOriginalBodyAndLogin() throws {
    let p = try pendingSocial()
    let bytes = try p.storageData()
    let restored = try JSONDecoder().decode(JourneySocialPendingOperation.self, from: bytes)
    #expect(restored == p)
    #expect(restored.operation.wireBody == p.operation.wireBody)
    #expect(restored.operation.binding.loginID.uuidString.lowercased() == socialLogin)
    #expect(try restored.storageData() == bytes)
    let text = String(decoding: bytes, as: UTF8.self)
    #expect(
      !text.contains("unit-signature") && !text.contains("bearer") && !text.contains("password"))
    let sameOrigin = try JourneySocialPendingOperation(
      origin: URL(string: "https://SOCIAL.example.test:443")!, operation: p.operation)
    #expect(sameOrigin == p)
  }

  @Test(arguments: ["unknown", "missing", "version", "checksum", "owner", "body", "kind", "origin"])
  func corruptedProtectedDataDoesNotBecomeAnotherIntent(_ field: String) throws {
    let p = try pendingSocial()
    var raw = try JSONSerialization.jsonObject(with: p.storageData()) as! [String: Any]
    switch field {
    case "unknown": raw["access_token"] = "must-not-be-stored"
    case "missing": raw.removeValue(forKey: "login_id")
    case "version": raw["schema"] = "journey.social.pending.v2"
    case "checksum": raw["checksum"] = String(repeating: "0", count: 64)
    case "owner": raw["owner_id"] = socialPeer
    case "body":
      var command = raw["command"] as! [String: Any]
      command["nickname"] = "Changed without confirmation"
      raw["command"] = command
    case "kind": raw["kind"] = "moderate"
    default: raw["origin"] = "http://social.example.test/"
    }
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        JourneySocialPendingOperation.self, from: JSONSerialization.data(withJSONObject: raw))
    }
  }

  @Test(arguments: [
    "extra", "opted", "consent", "uuid", "revisionString", "revisionFraction", "revisionBool",
    "origin", "schema",
  ])
  func aValidChecksumStillRequiresAClosedTypedCommand(_ field: String) throws {
    var raw =
      try JSONSerialization.jsonObject(with: pendingSocial().storageData()) as! [String: Any]
    var command = raw["command"] as! [String: Any]
    switch field {
    case "extra": command["calories"] = 123
    case "opted": command["opted_in"] = false
    case "consent": command["consent_version"] = "other.v1"
    case "uuid": command["operation_id"] = "ABCDEF00-0000-4000-8000-000000000001"
    case "revisionString": command["expected_revision"] = "0"
    case "revisionFraction": command["expected_revision"] = 0.5
    case "revisionBool": command["expected_revision"] = false
    case "origin": raw["origin"] = "https://user:password@social.example.test/"
    default: raw["schema"] = "journey.social.pending.v2"
    }
    raw["command"] = command
    raw.removeValue(forKey: "checksum")
    let payload = try JSONSerialization.data(
      withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
    raw["checksum"] = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        JourneySocialPendingOperation.self, from: JSONSerialization.data(withJSONObject: raw))
    }
  }

  @Test func allPrivacyCommandsRoundTripWithoutInferringAnotherIntent() throws {
    let actions: [(JourneySocialOperation.Action, Int)] = [
      (.participation(nickname: nil, consentVersion: nil), 1),
      (.block(memberID: UUID(uuidString: socialPeer)!, blocked: true), 1),
      (.block(memberID: UUID(uuidString: socialPeer)!, blocked: false), 2),
      (.report(memberID: UUID(uuidString: socialPeer)!, reason: .spam), 2),
    ]
    for (action, revision) in actions {
      let op = try JourneySocialOperation(
        binding: socialBinding(), id: UUID(), expectedRevision: revision, action: action)
      let p = try JourneySocialPendingOperation(
        origin: URL(string: "https://social.example.test")!, operation: op)
      let restored = try JSONDecoder().decode(
        JourneySocialPendingOperation.self, from: p.storageData())
      #expect(restored == p && restored.operation.wireBody == op.wireBody)
    }
  }

  @Test func protectedStorageRestoresOnlyItsOriginAndAuthAccount() async throws {
    let security = SocialPendingMemorySecurity()
    let p = try pendingSocial()
    let first = try JourneySocialPendingStore(origin: p.origin, security: security)
    try await first.claim(p)
    let reopened = try JourneySocialPendingStore(origin: p.origin, security: security)
    #expect(try await reopened.load(authUserID: p.operation.binding.authUserID) == p)
    #expect(try await reopened.load(authUserID: UUID()) == nil)
    let other = try JourneySocialPendingStore(
      origin: URL(string: "https://other.example.test")!, security: security)
    #expect(try await other.load(authUserID: p.operation.binding.authUserID) == nil)
    await #expect(throws: (any Error).self) { try await other.claim(p) }
    let descriptors = await security.descriptors
    #expect(
      descriptors.allSatisfy {
        $0.accessibility == .whenUnlockedThisDeviceOnly && !$0.synchronizable
          && $0.accessGroup == nil
          && !$0.account.contains(socialAuth) && !$0.service.contains("Caminhante")
      })
  }

  @Test func onlyTheExactReceiptCanRetireItsPendingSlot() async throws {
    let security = SocialPendingMemorySecurity()
    let p = try pendingSocial()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    try await store.claim(p)
    try await store.claim(p)
    let next = try pendingSocial(id: UUID())
    await #expect(throws: JourneySocialPendingError.pendingOperation) {
      try await store.claim(next)
    }
    let saved = try socialDecode(
      JourneySocialMutationSnapshot.self,
      [
        "status": "applied",
        "receipt": ["operation_id": socialOperation, "revision": 1, "opted_in": true],
        "profile": socialProfile(),
      ])
    try await store.acknowledge(p, result: saved)
    try await store.claim(next)
    await #expect(throws: JourneySocialPendingError.pendingOperation) {
      try await store.acknowledge(p, result: saved)
    }
    #expect(try await store.load(authUserID: p.operation.binding.authUserID) == next)
  }

  @Test func newLoginMayRecoverAFenceWithoutResubmittingAnOldConsent() async throws {
    let security = SocialPendingMemorySecurity()
    let p = try pendingSocial()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    try await store.claim(p)
    let current = JourneySocialBinding(
      ownerID: p.operation.binding.ownerID, authUserID: p.operation.binding.authUserID,
      loginID: UUID())
    let proof = try socialDecode(JourneySocialResolutionSnapshot.self, socialResolution())
    try proof.validate(for: p, current: current)
    try await store.acknowledgeResolution(p, result: proof, current: current)
    #expect(try await store.load(authUserID: current.authUserID) == nil)
    #expect(await security.deletions == 1)
  }

  @Test(arguments: [
    "operation", "revision", "kind", "falseFence", "missingReceipt", "privateMember", "extra",
  ])
  func aMalformedResolutionNeverDiscardsTheOriginal(_ attack: String) async throws {
    let security = SocialPendingMemorySecurity()
    let p = try pendingSocial()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    try await store.claim(p)
    var raw = socialResolution()
    switch attack {
    case "operation": raw["operation_id"] = socialPeer
    case "revision": raw["expected_revision"] = 1
    case "kind": raw["kind"] = "block"
    case "falseFence":
      raw["receipt"] = ["operation_id": socialOperation, "revision": 1, "opted_in": true]
    case "missingReceipt": raw["status"] = "applied"
    case "privateMember":
      raw["profile"] = [
        "revision": 1, "opted_in": true, "nickname": "Caminhante", "member_id": socialLogin,
        "moderation": "active",
      ]
    default: raw["calories"] = 123
    }
    await #expect(throws: (any Error).self) {
      let proof = try socialDecode(JourneySocialResolutionSnapshot.self, raw)
      try await store.acknowledgeResolution(p, result: proof, current: p.operation.binding)
    }
    #expect(try await store.load(authUserID: p.operation.binding.authUserID) == p)
    #expect(await security.deletions == 0)
  }

  @Test func recoveryKeepsTheCurrentWithdrawalAndRejectsAnotherAccount() throws {
    let p = try pendingSocial()
    var raw = socialResolution()
    raw["status"] = "applied"
    raw["receipt"] = ["operation_id": socialOperation, "revision": 1, "opted_in": true]
    raw["profile"] = [
      "revision": 2, "opted_in": false, "nickname": NSNull(), "member_id": socialMember,
      "moderation": "active",
    ]
    let proof = try socialDecode(JourneySocialResolutionSnapshot.self, raw)
    try proof.validate(for: p, current: p.operation.binding)
    #expect(!proof.profile.optedIn && proof.profile.revision == 2)
    let foreign = JourneySocialBinding(ownerID: UUID(), authUserID: UUID(), loginID: UUID())
    #expect(throws: (any Error).self) { try proof.validate(for: p, current: foreign) }
  }

  @Test func corruptedStorageNeverDeletesOrOverwrites() async throws {
    let security = SocialPendingMemorySecurity()
    let p = try pendingSocial()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    try await store.claim(p)
    await security.corrupt()
    await #expect(throws: JourneySocialPendingError.storageUnavailable) {
      try await store.load(authUserID: p.operation.binding.authUserID)
    }
    await #expect(throws: JourneySocialPendingError.storageUnavailable) { try await store.claim(p) }
    #expect(await security.deletions == 0)
  }

  @Test func actorReentrancyCannotOverwriteAnUnresolvedClaim() async throws {
    let security = SocialPendingMemorySecurity()
    let p = try pendingSocial()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    let barrier = ConversationControllerBarrier()
    await security.holdNextRead(barrier)
    let task = Task {
      do {
        try await store.claim(p)
        await barrier.finish()
      } catch {
        await barrier.finish()
        throw error
      }
    }
    let entered = await barrier.waitEnteredOrFinished()
    if !entered {
      try await task.value
      Issue.record("Claim did not reach protected storage")
      return
    }
    await #expect(throws: JourneySocialPendingError.pendingOperation) { try await store.claim(p) }
    await barrier.release()
    try await task.value
    #expect(try await store.load(authUserID: p.operation.binding.authUserID) == p)
  }

  @Test func sessionClaimsBeforeSendingAndRetiresOnlyProvenOutcomes() async throws {
    let p = try pendingSocial()
    let security = SocialPendingMemorySecurity()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    let provider = SocialPendingProvider(binding: p.operation.binding, origin: p.origin)
    await provider.onSubmit { operation in
      #expect(operation == p.operation)
      #expect(try await store.load(authUserID: operation.binding.authUserID) == p)
      throw URLError(.networkConnectionLost)
    }
    let session = try JourneySocialPendingSession(provider: provider, store: store)
    await #expect(throws: (any Error).self) { try await session.submit(p.operation) }
    #expect(try await session.pending() == p)
    let different = try pendingSocial(id: UUID())
    await #expect(throws: JourneySocialPendingError.pendingOperation) {
      try await session.submit(different.operation)
    }
    #expect(await provider.submitCount == 1)
    #expect(await provider.recoveryCount == 0)
    await provider.onRecover { pending in
      #expect(pending == p)
      #expect(try await store.load(authUserID: pending.operation.binding.authUserID) == p)
      return try socialDecode(JourneySocialResolutionSnapshot.self, socialResolution())
    }
    #expect(try await session.recover(p).status == .fenced)
    #expect(try await session.pending() == nil)
    await provider.onSubmit { operation in try socialSaved(operation) }
    _ = try await session.submit(different.operation)
    #expect(try await session.pending() == nil)
    #expect(await provider.submitCount == 2)
    #expect(await security.deletions == 2)
  }

  @Test(arguments: ["read", "add"])
  func unavailableProtectedStoragePreventsPhysicalSubmission(_ failure: String) async throws {
    let p = try pendingSocial()
    let security = SocialPendingMemorySecurity()
    await security.deny(failure)
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    let provider = SocialPendingProvider(binding: p.operation.binding, origin: p.origin)
    await provider.onSubmit { operation in try socialSaved(operation) }
    let session = try JourneySocialPendingSession(provider: provider, store: store)
    await #expect(throws: JourneySocialPendingError.storageUnavailable) {
      try await session.submit(p.operation)
    }
    #expect(await provider.submitCount == 0)
    #expect(await security.deletions == 0)
  }

  @Test func failedLocalRetirementKeepsExactIntentForExplicitResolution() async throws {
    let p = try pendingSocial()
    let security = SocialPendingMemorySecurity()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    let provider = SocialPendingProvider(binding: p.operation.binding, origin: p.origin)
    await provider.onSubmit { operation in try socialSaved(operation) }
    await security.deny("delete")
    let session = try JourneySocialPendingSession(provider: provider, store: store)
    await #expect(throws: JourneySocialPendingError.storageUnavailable) {
      try await session.submit(p.operation)
    }
    #expect(try await session.pending() == p)
    await provider.onRecover { _ in
      var raw = socialResolution()
      raw["status"] = "applied"
      raw["receipt"] = ["operation_id": socialOperation, "revision": 1, "opted_in": true]
      raw["profile"] = socialProfile()
      return try socialDecode(JourneySocialResolutionSnapshot.self, raw)
    }
    await security.deny(nil)
    #expect(try await session.recover(p).status == .applied)
    #expect(try await session.pending() == nil)
    #expect(await provider.submitCount == 1)
  }

  @Test func newLoginResolvesWithoutReexecutingOldParticipation() async throws {
    let p = try pendingSocial()
    let security = SocialPendingMemorySecurity()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    try await store.claim(p)
    let current = JourneySocialBinding(
      ownerID: p.operation.binding.ownerID, authUserID: p.operation.binding.authUserID,
      loginID: UUID())
    let provider = SocialPendingProvider(binding: current, origin: p.origin)
    let session = try JourneySocialPendingSession(provider: provider, store: store)
    #expect(try await session.pending() == p)
    await #expect(throws: (any Error).self) { try await session.submit(p.operation) }
    #expect(await provider.submitCount == 0)
    await provider.onRecover { _ in
      try socialDecode(JourneySocialResolutionSnapshot.self, socialResolution())
    }
    _ = try await session.recover(p)
    #expect(try await session.pending() == nil)
  }

  @Test func foreignAccountCannotRecoverOrRetireAnotherPendingIntent() async throws {
    let p = try pendingSocial()
    let security = SocialPendingMemorySecurity()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    try await store.claim(p)
    let provider = SocialPendingProvider(
      binding: .init(ownerID: UUID(), authUserID: UUID(), loginID: UUID()), origin: p.origin)
    let session = try JourneySocialPendingSession(provider: provider, store: store)
    #expect(try await session.pending() == nil)
    await #expect(throws: (any Error).self) { try await session.recover(p) }
    #expect(await provider.recoveryCount == 0)
    #expect(try await store.load(authUserID: p.operation.binding.authUserID) == p)
  }

  @Test func accountDepartureAfterPhysicalWorkPreservesUnresolvedIntent() async throws {
    let p = try pendingSocial()
    let security = SocialPendingMemorySecurity()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    let provider = SocialPendingProvider(binding: p.operation.binding, origin: p.origin)
    await provider.onSubmit { operation in
      await provider.depart()
      return try socialSaved(operation)
    }
    let session = try JourneySocialPendingSession(provider: provider, store: store)
    await #expect(throws: SessionLifecycleError.sessionSuperseded) {
      try await session.submit(p.operation)
    }
    #expect(try await store.load(authUserID: p.operation.binding.authUserID) == p)
    #expect(await security.deletions == 0)
  }

  @Test func cancellationDuringProtectedClaimNeverDispatches() async throws {
    let p = try pendingSocial()
    let security = SocialPendingMemorySecurity()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    let provider = SocialPendingProvider(binding: p.operation.binding, origin: p.origin)
    let barrier = ConversationControllerBarrier()
    await security.holdNextRead(barrier)
    let session = try JourneySocialPendingSession(provider: provider, store: store)
    let task = Task {
      do {
        _ = try await session.submit(p.operation)
        await barrier.finish()
      } catch {
        await barrier.finish()
        throw error
      }
    }
    let entered = await barrier.waitEnteredOrFinished()
    if !entered {
      try await task.value
      Issue.record("Submission did not claim protected storage")
      return
    }
    task.cancel()
    await barrier.release()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await provider.submitCount == 0)
    #expect(try await store.load(authUserID: p.operation.binding.authUserID) == p)
  }

  @Test func sessionReentrancyCannotDispatchASecondIntent() async throws {
    let p = try pendingSocial()
    let security = SocialPendingMemorySecurity()
    let store = try JourneySocialPendingStore(origin: p.origin, security: security)
    let provider = SocialPendingProvider(binding: p.operation.binding, origin: p.origin)
    let barrier = ConversationControllerBarrier()
    await provider.onSubmit { operation in
      await barrier.enter()
      return try socialSaved(operation)
    }
    let session = try JourneySocialPendingSession(provider: provider, store: store)
    let task = Task {
      do {
        let result = try await session.submit(p.operation)
        await barrier.finish()
        return result
      } catch {
        await barrier.finish()
        throw error
      }
    }
    let entered = await barrier.waitEnteredOrFinished()
    if !entered {
      _ = try await task.value
      Issue.record("Submission did not reach provider")
      return
    }
    await #expect(throws: JourneySocialPendingError.pendingOperation) {
      try await session.submit(p.operation)
    }
    await barrier.release()
    _ = try await task.value
    #expect(await provider.submitCount == 1)
    #expect(try await session.pending() == nil)
  }

  @Test func liveRegistryUsesOneSerialOwnerPerCanonicalOrigin() async throws {
    let first = try await JourneySocialPendingStore.live(
      origin: URL(string: "https://SOCIAL-NATIVE.invalid:443")!)
    let second = try await JourneySocialPendingStore.live(
      origin: URL(string: "https://social-native.invalid/")!)
    #expect(first === second)
  }
}

func pendingSocial(id: UUID = UUID(uuidString: socialOperation)!) throws
  -> JourneySocialPendingOperation
{
  try .init(
    origin: URL(string: "https://social.example.test")!,
    operation: JourneySocialOperation(
      binding: socialBinding(), id: id, expectedRevision: 0,
      action: .participation(nickname: "Caminhante", consentVersion: "journey-social.v1")))
}
func socialResolution() -> [String: Any] {
  [
    "status": "fenced", "operation_id": socialOperation, "kind": "profile", "expected_revision": 0,
    "receipt": NSNull(),
    "profile": [
      "revision": 0, "opted_in": false, "nickname": NSNull(), "member_id": NSNull(),
      "moderation": "active",
    ],
  ]
}

private actor SocialPendingMemorySecurity: KeychainSecurityClient {
  private var values: [String: Data] = [:]
  private(set) var descriptors: [KeychainItemDescriptor] = []
  private(set) var deletions = 0
  private var nextReadBarrier: ConversationControllerBarrier?
  private var denied: String?
  func deny(_ operation: String?) { denied = operation }
  func holdNextRead(_ barrier: ConversationControllerBarrier) { nextReadBarrier = barrier }
  private func key(_ d: KeychainItemDescriptor) -> String { d.service + ":" + d.account }
  func read(_ d: KeychainItemDescriptor) async -> KeychainReadResult {
    descriptors.append(d)
    if denied == "read" { return .failure(errSecInteractionNotAllowed) }
    if let b = nextReadBarrier {
      nextReadBarrier = nil
      await b.enter()
    }
    return values[key(d)].map(KeychainReadResult.data) ?? .notFound
  }
  func add(_ d: KeychainItemDescriptor, data: Data) -> OSStatus {
    descriptors.append(d)
    if denied == "add" { return errSecInteractionNotAllowed }
    guard values[key(d)] == nil else { return errSecDuplicateItem }
    values[key(d)] = data
    return errSecSuccess
  }
  func update(_ d: KeychainItemDescriptor, data: Data) -> OSStatus { errSecUnimplemented }
  func delete(_ d: KeychainItemDescriptor) -> OSStatus {
    if denied == "delete" { return errSecInteractionNotAllowed }
    deletions += 1
    values.removeValue(forKey: key(d))
    return errSecSuccess
  }
  func corrupt() { for k in values.keys { values[k] = Data("corrupt pending state".utf8) } }
}

private func socialSaved(_ operation: JourneySocialOperation) throws
  -> JourneySocialMutationSnapshot
{
  try socialDecode(
    JourneySocialMutationSnapshot.self,
    [
      "status": "applied",
      "receipt": [
        "operation_id": operation.id.uuidString.lowercased(), "revision": 1, "opted_in": true,
      ],
      "profile": socialProfile(),
    ])
}

private actor SocialPendingProvider: JourneySocialProviding {
  nonisolated let binding: JourneySocialBinding
  nonisolated let origin: URL
  private var current = true
  private(set) var submitCount = 0
  private(set) var recoveryCount = 0
  private var submitHandler:
    (@Sendable (JourneySocialOperation) async throws -> JourneySocialMutationSnapshot)?
  private var recoveryHandler:
    (@Sendable (JourneySocialPendingOperation) async throws -> JourneySocialResolutionSnapshot)?
  init(binding: JourneySocialBinding, origin: URL) {
    self.binding = binding
    self.origin = origin
  }
  func validate() throws {
    try Task.checkCancellation()
    guard current else { throw SessionLifecycleError.sessionSuperseded }
  }
  func depart() { current = false }
  func onSubmit(
    _ body:
      @escaping @Sendable (JourneySocialOperation) async throws -> JourneySocialMutationSnapshot
  ) { submitHandler = body }
  func onRecover(
    _ body:
      @escaping @Sendable (JourneySocialPendingOperation) async throws ->
      JourneySocialResolutionSnapshot
  ) { recoveryHandler = body }
  func submit(_ operation: JourneySocialOperation) async throws -> JourneySocialMutationSnapshot {
    try validate()
    submitCount += 1
    guard let submitHandler else { throw JourneySocialInvalid.value }
    return try await submitHandler(operation)
  }
  func recover(_ pending: JourneySocialPendingOperation) async throws
    -> JourneySocialResolutionSnapshot
  {
    try validate()
    recoveryCount += 1
    guard let recoveryHandler else { throw JourneySocialInvalid.value }
    return try await recoveryHandler(pending)
  }
  func publish(_ action: @escaping @MainActor @Sendable () throws -> Void) async throws {
    try validate()
    try await action()
  }
  func profile() throws -> JourneySocialProfile { throw JourneySocialInvalid.value }
  func ranking(cursor: JourneySocialRankingCursor?, limit: Int) throws -> JourneySocialRankingPage {
    throw JourneySocialInvalid.value
  }
  func blocks(cursor: JourneySocialBlocksCursor?, limit: Int) throws -> JourneySocialBlocksPage {
    throw JourneySocialInvalid.value
  }
}
