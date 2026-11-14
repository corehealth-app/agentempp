import Foundation
import Security
import Testing
@testable import BodyFlow

@Suite("Training keeps one protected original pending operation")
struct TrainingExecutionPendingStoreTests {
  @Test func restoreKeepsOriginalIdentityAndDoesNotAdoptAnotherAccount() async throws {
    let f = try TrainingExecutionFixture(), security = TrainingPendingMemorySecurity()
    let home = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let op = try TrainingExecutionOperation(binding: .init(home.scope), wireBody: f.command("start"))
    let first = try TrainingExecutionPendingStore(origin: URL(string: "https://staging.example.test")!, security: security)
    try await first.claim(op)
    let reopened = try TrainingExecutionPendingStore(origin: URL(string: "https://staging.example.test")!, security: security)
    #expect(try await reopened.load(authUserID: home.scope.authUserID) == op)
    #expect(try await reopened.load(authUserID: UUID()) == nil)
    let otherOrigin = try TrainingExecutionPendingStore(origin: URL(string: "https://different.example.test")!, security: security)
    #expect(try await otherOrigin.load(authUserID: home.scope.authUserID) == nil)
    let descriptors = await security.descriptors
    #expect(descriptors.allSatisfy { $0.accessibility == .whenUnlockedThisDeviceOnly && !$0.synchronizable && $0.accessGroup == nil })
    #expect(descriptors.allSatisfy { !$0.account.contains(home.scope.authUserID.uuidString.lowercased()) })
  }

  @Test func collisionAndStaleAcknowledgementNeverDiscardNewerPendingWork() async throws {
    let f = try TrainingExecutionFixture(), security = TrainingPendingMemorySecurity()
    let home = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let start = try TrainingExecutionOperation(binding: .init(home.scope), wireBody: f.command("start"))
    let save = try TrainingExecutionOperation(binding: .init(home.scope), wireBody: f.command("save"))
    let store = try TrainingExecutionPendingStore(origin: URL(string: "https://staging.example.test")!, security: security)
    try await store.claim(start); try await store.claim(start)
    await #expect(throws: TrainingExecutionError.pendingOperation) { try await store.claim(save) }
    #expect(try await store.load(authUserID: home.scope.authUserID) == start)
    let receipt = try TrainingExecutionMutationSnapshot(data: f.data("created"))
    try await store.acknowledge(start, result: receipt)
    try await store.claim(save)
    await #expect(throws: TrainingExecutionError.pendingOperation) { try await store.acknowledge(start, result: receipt) }
    #expect(try await store.load(authUserID: home.scope.authUserID) == save)
    try await store.acknowledge(save, result: .init(data: f.data("replay")))
    #expect(try await store.load(authUserID: home.scope.authUserID) == nil)
  }

  @Test func unreadableOrCorruptStorageFailsClosedWithoutRemovingAnything() async throws {
    let f = try TrainingExecutionFixture(), security = TrainingPendingMemorySecurity()
    let home = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let op = try TrainingExecutionOperation(binding: .init(home.scope), wireBody: f.command("start"))
    let store = try TrainingExecutionPendingStore(origin: URL(string: "https://staging.example.test")!, security: security)
    try await store.claim(op)
    await security.corrupt()
    await #expect(throws: TrainingExecutionError.storageUnavailable) { try await store.load(authUserID: home.scope.authUserID) }
    await #expect(throws: TrainingExecutionError.storageUnavailable) { try await store.claim(op) }
    #expect(await security.deletions == 0)
  }
}

private actor TrainingPendingMemorySecurity: KeychainSecurityClient {
  private var values: [String: Data] = [:]
  private(set) var descriptors: [KeychainItemDescriptor] = []
  private(set) var deletions = 0
  private var nextReadBarrier: ConversationControllerBarrier?
  func holdNextRead(_ barrier: ConversationControllerBarrier) { nextReadBarrier = barrier }
  private func key(_ d: KeychainItemDescriptor) -> String { d.service + ":" + d.account }
  func read(_ d: KeychainItemDescriptor) async -> KeychainReadResult {
    descriptors.append(d)
    if let barrier = nextReadBarrier { nextReadBarrier = nil; await barrier.enter() }
    return values[key(d)].map(KeychainReadResult.data) ?? .notFound
  }
  func add(_ d: KeychainItemDescriptor, data: Data) -> OSStatus {
    descriptors.append(d)
    guard values[key(d)] == nil else { return errSecDuplicateItem }
    values[key(d)] = data; return errSecSuccess
  }
  func update(_ d: KeychainItemDescriptor, data: Data) -> OSStatus { errSecUnimplemented }
  func delete(_ d: KeychainItemDescriptor) -> OSStatus { deletions += 1; values.removeValue(forKey: key(d)); return errSecSuccess }
  func corrupt() { for k in values.keys { values[k] = Data("bad protected state".utf8) } }
}


extension TrainingExecutionPendingStoreTests {
  @Test func actorReentrancyCannotOverwriteAnInFlightClaim() async throws {
    let f = try TrainingExecutionFixture(), security = TrainingPendingMemorySecurity()
    let home = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let op = try TrainingExecutionOperation(binding: .init(home.scope), wireBody: f.command("start"))
    let store = try TrainingExecutionPendingStore(origin: URL(string: "https://staging.example.test")!, security: security)
    let barrier = ConversationControllerBarrier()
    await security.holdNextRead(barrier)
    let first = Task {
      do { try await store.claim(op); await barrier.finish() }
      catch { await barrier.finish(); throw error }
    }
    let entered = await barrier.waitEnteredOrFinished()
    if !entered { try await first.value; Issue.record("The first claim did not reach protected storage"); return }
    await #expect(throws: TrainingExecutionError.pendingOperation) { try await store.claim(op) }
    await barrier.release(); try await first.value
    #expect(try await store.load(authUserID: home.scope.authUserID) == op)
    #expect(await security.deletions == 0)
  }

  @Test func liveRegistryReusesTheSameSerialOwnerForAnOrigin() async throws {
    let a = try await TrainingExecutionPendingStore.live(origin: URL(string: "https://native-training.invalid")!)
    let b = try await TrainingExecutionPendingStore.live(origin: URL(string: "https://native-training.invalid/")!)
    #expect(a === b)
  }
}
