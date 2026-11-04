import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Dormant authenticated durable meal-edit controller")
struct ConversationMealEditControllerTests {
  @Test(arguments: ["patient", "epoch", "logout"])
  func preparedPayloadIsWithheldWhenScopeChangesAfterItsStateOperation(_ change: String)
    async throws
  {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.seedKey()
    await f.http.stub.respond { _, _ in .init(status: 200, body: f.groupBody) }
    let gate = EditMutationGate()
    let life = EditGatedLifecycle(base: f.http.lifecycle, gate: gate)
    let controller = try await ConversationMealEditController.open(
      transport: f.http.transport,
      lifecycle: life, store: f.disk.store, keyVault: f.vault)
    let barrier = ConversationControllerBarrier()
    await gate.holdNextStateReturn(barrier)
    let pending = Task { try await f.prepare(controller) }
    #expect(await barrier.waitEnteredOrFinished())
    if change == "logout" {
      await f.http.lifecycle.replace(
        .init(
          userID: UUID().uuidString.lowercased(), generation: 8,
          bearer: "synthetic-replaced-session"))
    } else {
      let token = try f.authority.beginRefresh()
      _ = try f.authority.accept(
        refreshID: token, authUserID: f.context.authUserID,
        ownerID: change == "patient" ? UUID() : f.context.ownerID,
        localSessionGeneration: f.context.sessionGeneration,
        epoch: change == "epoch" ? UUID() : f.context.epoch)
    }
    await barrier.release()
    // No old payload may reach the caller, even though enqueue would also
    // reject its stale identity. This is the return boundary itself.
    await #expect(throws: (any Error).self) { try await pending.value }
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    #expect(await f.http.stub.requests.count == 1)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await controller.close()
  }
  @Test func sameAuthNewPatientCannotPublishSendDiscardOrRetagTheOriginalQueue() async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.http.stub.respond { _, _ in .init(status: 200, body: f.groupBody) }
    let controller = try await f.openController()
    let preparation = try await f.prepare(controller)
    let probe = await MainActor.run { EditControllerProbe() }
    let id = try await controller.enqueue(preparation: preparation, context: f.context) {
      probe.receive($0)
    }
    let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    let token = try f.authority.beginRefresh()
    let other = ConversationCommandContext(
      observation: try f.authority.accept(
        refreshID: token,
        authUserID: f.context.authUserID, ownerID: UUID(),
        localSessionGeneration: f.context.sessionGeneration, epoch: f.context.epoch),
      observedAt: f.context.observedAt)
    try await controller.publishSnapshot(context: other) { probe.receive($0) }
    #expect(await probe.snapshot?.entries.isEmpty == true)
    #expect(await probe.snapshot?.held.map(\.id) == [id])
    await #expect(throws: (any Error).self) {
      try await controller.send(id: id, context: other) { probe.receive($0) }
    }
    await #expect(throws: (any Error).self) {
      try await controller.discardUnsent(id: id, context: other) { probe.receive($0) }
    }
    await #expect(throws: (any Error).self) {
      try await controller.holdForLocalReset(id: id, context: other) { probe.receive($0) }
    }
    await #expect(throws: (any Error).self) {
      try await controller.enqueue(preparation: preparation, context: other) { probe.receive($0) }
    }
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == original)
    #expect(await f.http.stub.requests.count == 1)
    #expect(await probe.savedCount == 0)
    await controller.close()
  }
  @Test func actualHTTPUndoFixtureKeepsItsRealCASOperationHashAndReceiptUnchanged() async throws {
    let actual = try FlowActualEditLifecycleFixture()
    let disk = try EditOutboxFixture()
    defer { disk.remove() }
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "FlowMealEditLifecycleFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/FlowMealEditLifecycleFixtures.json")
    #endif
    let bytes = try Data(contentsOf: url)
    #expect(
      ConversationMealCommand.digest(bytes)
        == "f0037fb5da38db2ab3806d97f5d341f5ce82a5304f69c1e3618f2320dba6cc1b")
    let raw = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let undoBody = try JSONSerialization.data(withJSONObject: #require(raw["undo_ack"]))
    struct Group: Decodable { let data: ConversationMealGroupSnapshot }
    struct Undo: Decodable { let data: ConversationMealEditResultSnapshot }
    let group = try JSONDecoder().decode(Group.self, from: actual.groupEnvelope).data
    let undo = try JSONDecoder().decode(Undo.self, from: undoBody).data
    let target = try #require(group.lastOperation?.operationID)
    let version = try #require(group.current?.expectedVersion)
    let life = ConversationHTTPTestLifecycle()
    await life.replace(
      .init(userID: actual.authUserID, generation: 7, bearer: "synthetic-actual-fixture-account"))
    let lease = await life.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let keys = OutboxKeychainFake()
    await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    let http = try ConversationHTTPFixture(lifecycle: life)
    await http.stub.respond { request, _ in
      .init(status: 200, body: request.httpMethod == "GET" ? actual.groupEnvelope : undoBody)
    }
    let authority = ConversationOutboxObservationAuthority()
    let token = try authority.beginRefresh()
    let context = ConversationCommandContext(
      observation: try authority.accept(
        refreshID: token,
        authUserID: #require(UUID(uuidString: actual.authUserID)), ownerID: group.ownerID,
        localSessionGeneration: 7, epoch: group.epoch), observedAt: actual.session.observedAt)
    let controller = try await ConversationMealEditController.open(
      transport: http.transport,
      lifecycle: life, store: disk.store,
      keyVault: .init(service: ConversationMealEditOutboxSession.keychainService, security: keys))
    let preparation = try await controller.prepare(
      commandID: group.commandID,
      originalInputHash: group.originalInputHash, expectedRevision: group.revision,
      expectedVersion: version, action: .undoSave(targetOperationID: target), context: context,
      operationID: undo.receipt.operationID)
    #expect(
      preparation.operation.operationInputHash
        == "c108db45f4b005d83e4c42a363ca55e8cb969f48a09be5b1990f8f44ceade519")
    #expect(undo.matches(operation: preparation.operation))
    let probe = await MainActor.run { EditControllerProbe() }
    let id = try await controller.enqueue(preparation: preparation, context: context) {
      probe.receive($0)
    }
    try await controller.send(id: id, context: context) { probe.receive($0) }
    #expect(await probe.savedCount == 1)
    #expect(try disk.store.load(owner: owner, key: disk.key).isEmpty)
    let requests = await http.stub.requests
    #expect(requests.count == 2 && requests.last?.httpBody == preparation.operation.wireBody)
    #expect(
      requests.last?.value(forHTTPHeaderField: "X-Conversation-Owner")
        == group.ownerID.uuidString.lowercased())
    #expect(
      requests.last?.value(forHTTPHeaderField: "Authorization")
        == "Bearer synthetic-actual-fixture-account")
    #expect(UUID(uuidString: actual.authUserID) != group.ownerID)
    await controller.close()
  }
  @Test(arguments: ["version", "record", "disabled", "owner", "epoch", "unavailable", "outage"])
  func preparationCannotInventCurrentEligibilityOrReplaceTheCapturedCAS(_ attack: String)
    async throws
  {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    var response = f.groupBody
    var context = f.context
    var version = f.preparedOperation.expectedVersion
    var action = f.preparedOperation.action
    if attack == "version" { version = "v1:" + String(repeating: "b", count: 64) }
    if attack == "record" {
      action = .save(recordID: UUID(), items: [try .init(foodName: "Arroz cozido", quantityG: 200)])
    }
    if attack == "unavailable" { response = f.unavailableGroupBody }
    if attack == "disabled" {
      var envelope = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
      var group = try #require(envelope["data"] as? [String: Any])
      var actions = try #require(group["actions"] as? [String: Any])
      actions["save"] = ["allowed": false, "reason": "day_closed"]
      group["actions"] = actions
      envelope["data"] = group
      response = try JSONSerialization.data(withJSONObject: envelope)
    }
    if attack == "owner" || attack == "epoch" {
      context = .init(
        observation: .init(
          authUserID: f.context.authUserID,
          ownerID: attack == "owner" ? UUID() : f.context.ownerID,
          localSessionGeneration: f.context.sessionGeneration,
          epoch: attack == "epoch" ? UUID() : f.context.epoch), observedAt: f.context.observedAt)
    }
    let body = response
    await f.http.stub.respond { _, _ in
      if attack == "outage" { throw URLError(.notConnectedToInternet) }
      return .init(status: 200, body: body)
    }
    let controller = try await f.openController()
    await #expect(throws: (any Error).self) {
      try await controller.prepare(
        commandID: f.preparedOperation.commandID,
        originalInputHash: f.preparedOperation.originalInputHash, expectedRevision: 0,
        expectedVersion: version, action: action, context: context,
        operationID: f.preparedOperation.operationID)
    }
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    #expect(await f.http.stub.requests.count == 1)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await controller.close()
  }

  @Test func preparedCapabilityCannotBeCopiedToAnotherController() async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.http.stub.respond { _, _ in .init(status: 200, body: f.groupBody) }
    let first = try await f.openController()
    let prepared = try await f.prepare(first)
    let other = try await f.openController()
    let probe = await MainActor.run { EditControllerProbe() }
    await #expect(throws: (any Error).self) {
      try await other.enqueue(preparation: prepared, context: f.context) { probe.receive($0) }
    }
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    #expect(await f.http.stub.requests.count == 1)
    await first.close()
    await other.close()
  }

  @Test(arguments: ["stale_epoch", "version_conflict"])
  func permanentServerRefusalAndResetNeverTurnAbsenceIntoAnotherWrite(_ refusal: String)
    async throws
  {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.http.stub.respond { request, _ in
      request.httpMethod == "GET"
        ? .init(status: 200, body: f.groupBody)
        : .failure(409, "conversation_meal_edit_\(refusal)")
    }
    let controller = try await f.openController()
    let prepared = try await f.prepare(controller)
    let probe = await MainActor.run { EditControllerProbe() }
    let id = try await controller.enqueue(preparation: prepared, context: f.context) {
      probe.receive($0)
    }
    await #expect(throws: (any Error).self) {
      try await controller.send(id: id, context: f.context) { probe.receive($0) }
    }
    #expect(
      try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).first?.hold
        == (refusal == "stale_epoch" ? .staleEpoch : .serverChanged))
    await f.http.stub.respond { _, _ in .init(status: 200, body: f.preparedAbsent) }
    try await controller.reconcile(id: id, context: f.context) { probe.receive($0) }
    #expect(await !probe.absentCanResubmit)
    await #expect(throws: ConversationMealEditControllerError.reconciliationRequired) {
      try await controller.resubmit(id: id, context: f.context) { probe.receive($0) }
    }
    try await controller.holdForLocalReset(id: id, context: f.context) { probe.receive($0) }
    let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await controller.discardUnsent(id: id, context: f.context) { probe.receive($0) }
    }
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == original)
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).first?.hold == .reset)
    #expect(await probe.savedCount == 0)
    #expect(
      await f.http.stub.requests.filter {
        $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/reconcile") == false
      }.count == 1)
    await controller.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func logoutClosesRetainedControllerOwnedWorkAndKeepsUnknownCiphertext() async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    let barrier = ConversationControllerBarrier()
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      await barrier.enter()
      return .init(status: 200, body: f.preparedSaved)
    }
    let controller = try await f.openController()
    let prepared = try await f.prepare(controller)
    let probe = await MainActor.run { EditControllerProbe() }
    let id = try await controller.enqueue(preparation: prepared, context: f.context) {
      probe.receive($0)
    }
    let owned = await f.http.lifecycle.workIDs
    #expect(owned.count == 2)
    var finished = await f.http.lifecycle.finishedWorkEvents.makeAsyncIterator()
    let pending = Task {
      try await controller.send(id: id, context: f.context) { probe.receive($0) }
    }
    #expect(await barrier.waitEnteredOrFinished())
    let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    await f.http.lifecycle.replace(
      .init(
        userID: UUID().uuidString.lowercased(), generation: 8, bearer: "synthetic-other-account"))
    await barrier.release()
    await #expect(throws: (any Error).self) { try await pending.value }
    var completed: Set<UUID> = []
    while !owned.isSubset(of: completed) {
      completed.insert(try #require(await finished.next()))
    }
    await #expect(throws: (any Error).self) {
      try await controller.publishSnapshot(context: f.context) { probe.receive($0) }
    }
    #expect(await probe.savedCount == 0)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == original)
    #expect(await f.http.lifecycle.workCount == 0)
    #expect(await f.http.stub.requests.count == 2)
    await controller.close()
  }
  @Test func independentCodecPlaceholderCannotReplaceTheActualCurrentGroupCAS() async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.seedKey()
    await f.http.stub.respond { _, _ in .init(status: 200, body: f.groupBody) }
    let controller = try await ConversationMealEditController.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault)
    await #expect(throws: ConversationMealEditControllerError.changed) {
      try await controller.prepare(
        commandID: f.operation.commandID,
        originalInputHash: f.operation.originalInputHash,
        expectedRevision: f.operation.expectedRevision,
        expectedVersion: f.operation.expectedVersion, action: f.operation.action,
        context: f.context,
        operationID: f.operation.operationID)
    }
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await controller.close()
  }
  @Test func actualPreparationAndFactualACKDoNotDependOnAnotherCurrentGroupRead() async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.seedKey()
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      let before = try f.disk.store.load(owner: f.disk.owner, key: f.disk.key)
      #expect(
        before.first(where: { $0.id == .init(operation: f.preparedOperation) })?.state
          == .dispatchedUnknown)
      return .init(status: 200, body: f.preparedSaved)
    }
    let controller = try await ConversationMealEditController.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault)
    let prepared = try await controller.prepare(
      commandID: f.preparedOperation.commandID,
      originalInputHash: f.preparedOperation.originalInputHash,
      expectedRevision: f.preparedOperation.expectedRevision,
      expectedVersion: f.preparedOperation.expectedVersion, action: f.preparedOperation.action,
      context: f.context,
      operationID: f.preparedOperation.operationID)
    #expect(prepared.operation.wireBody == f.preparedOperation.wireBody)
    let probe = await MainActor.run { EditControllerProbe() }
    let id = try await controller.enqueue(preparation: prepared, context: f.context) {
      probe.receive($0)
    }
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).count == 1)
    try await controller.send(id: id, context: f.context) { probe.receive($0) }
    #expect(await probe.savedCount == 1)
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    #expect(await f.http.stub.requests.count == 2)  // One real group GET, one explicit edit POST.
    await #expect(throws: (any Error).self) {
      try await controller.enqueue(preparation: prepared, context: f.context) { probe.receive($0) }
    }
    #expect(await f.http.stub.requests.count == 2)
    await controller.close()
    #expect(await f.http.lifecycle.workCount == 0)
  }

  @Test(arguments: [false, true])
  func coldUnknownReconcilesWithOriginalBodyAndOnlyExplicitAbsentPermissionCanReplay(
    _ explicitReplay: Bool
  ) async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.seedKey()
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      throw URLError(.networkConnectionLost)
    }
    let first = try await ConversationMealEditController.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault)
    let prepared = try await first.prepare(
      commandID: f.preparedOperation.commandID,
      originalInputHash: f.preparedOperation.originalInputHash,
      expectedRevision: f.preparedOperation.expectedRevision,
      expectedVersion: f.preparedOperation.expectedVersion, action: f.preparedOperation.action,
      context: f.context,
      operationID: f.preparedOperation.operationID)
    let probe = await MainActor.run { EditControllerProbe() }
    let id = try await first.enqueue(preparation: prepared, context: f.context) {
      probe.receive($0)
    }
    await #expect(throws: (any Error).self) {
      try await first.send(id: id, context: f.context) { probe.receive($0) }
    }
    await first.close()
    let reopened = try await ConversationMealEditController.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault)
    let before = await f.http.stub.requests.count
    await #expect(throws: (any Error).self) {
      try await reopened.send(id: id, context: f.context) { probe.receive($0) }
    }
    #expect(await f.http.stub.requests.count == before)
    await f.http.stub.respond { request, _ in
      .init(
        status: 200,
        body: request.url?.path.hasSuffix("/reconcile") == true ? f.preparedAbsent : f.preparedSaved
      )
    }
    try await reopened.reconcile(id: id, context: f.context) { probe.receive($0) }
    #expect(await probe.absentCanResubmit)
    #expect(await f.http.stub.requests.count == before + 1)
    #expect(await probe.savedCount == 0)
    if explicitReplay {
      try await reopened.resubmit(id: id, context: f.context) { probe.receive($0) }
    } else {
      await f.http.stub.respond { _, _ in .init(status: 200, body: f.preparedSaved) }
      try await reopened.reconcile(id: id, context: f.context) { probe.receive($0) }
    }
    #expect(await probe.savedCount == 1)
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    let requests = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(
      requests.count == 3 && requests.allSatisfy { $0.httpBody == f.preparedOperation.wireBody })
    #expect(
      requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Idempotency-Key") == f.preparedOperation.idempotencyKey
      })
    #expect(
      requests.filter { $0.url?.path.hasSuffix("/reconcile") == false }.count
        == (explicitReplay ? 2 : 1))
    await #expect(throws: (any Error).self) {
      try await reopened.resubmit(id: id, context: f.context) { probe.receive($0) }
    }
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 3)
    await reopened.close()
  }

  @Test func storageUncertaintyRetainsTheSamePreparedOperationAcrossAnObservationRefresh()
    async throws
  {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.http.stub.respond { _, _ in .init(status: 200, body: f.groupBody) }
    let controller = try await f.openController()
    let prepared = try await f.prepare(controller)
    let probe = await MainActor.run { EditControllerProbe() }
    try FileManager.default.createDirectory(
      at: f.disk.store.root, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.disk.store.root.path)
    await #expect(throws: (any Error).self) {
      try await controller.enqueue(preparation: prepared, context: f.context) { probe.receive($0) }
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: f.disk.store.root.path)
    let token = try f.authority.beginRefresh()
    let renewed = ConversationCommandContext(
      observation: try f.authority.accept(
        refreshID: token,
        authUserID: f.context.authUserID, ownerID: f.context.ownerID,
        localSessionGeneration: f.context.sessionGeneration, epoch: f.context.epoch),
      observedAt: f.context.observedAt)
    let id = try await controller.enqueue(preparation: prepared, context: renewed) {
      probe.receive($0)
    }
    let same = try await controller.enqueue(preparation: prepared, context: renewed) {
      probe.receive($0)
    }
    #expect(id == same)
    let stored = try f.disk.store.load(owner: f.disk.owner, key: f.disk.key)
    #expect(stored.count == 1 && stored[0].operation.wireBody == prepared.operation.wireBody)
    #expect(stored[0].operation.operationID == prepared.operation.operationID)
    #expect(stored[0].operation.expectedVersion == f.group.current?.expectedVersion)
    // Preparation GET only; retry is not a new report/write.
    #expect(await f.http.stub.requests.count == 1)
    try await controller.discardUnsent(id: id, context: renewed) { probe.receive($0) }
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    await controller.close()
  }

  @Test func postRenamePatientRemapSuppressesPublicationAndCannotReenqueueTheClosedIntent()
    async throws
  {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.http.stub.respond { request, _ in
      .init(status: 200, body: request.httpMethod == "GET" ? f.groupBody : f.preparedSaved)
    }
    let controller = try await f.openController()
    let prepared = try await f.prepare(controller)
    let probe = await MainActor.run { EditControllerProbe() }
    let id = try await controller.enqueue(preparation: prepared, context: f.context) {
      probe.receive($0)
    }
    let barrier = ConversationControllerBarrier()
    await f.http.lifecycle.holdNextVisible(barrier)
    let pending = Task {
      try await controller.send(id: id, context: f.context) { probe.receive($0) }
    }
    #expect(await barrier.waitEnteredOrFinished())
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    let token = try f.authority.beginRefresh()
    _ = try f.authority.accept(
      refreshID: token, authUserID: f.context.authUserID,
      ownerID: UUID(), localSessionGeneration: f.context.sessionGeneration, epoch: f.context.epoch)
    await barrier.release()
    await #expect(throws: (any Error).self) { try await pending.value }
    #expect(await probe.savedCount == 0)
    let back = try f.authority.beginRefresh()
    let samePatientAgain = ConversationCommandContext(
      observation: try f.authority.accept(
        refreshID: back,
        authUserID: f.context.authUserID, ownerID: f.context.ownerID,
        localSessionGeneration: f.context.sessionGeneration, epoch: f.context.epoch),
      observedAt: f.context.observedAt)
    await #expect(throws: (any Error).self) {
      try await controller.enqueue(preparation: prepared, context: samePatientAgain) {
        probe.receive($0)
      }
    }
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    #expect(await f.http.stub.requests.count == 2)
    await controller.close()
  }

  @Test func sameOperationCannotStartAnOverlappingPhysicalReconciliation() async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    let barrier = ConversationControllerBarrier()
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      await barrier.enter()
      throw URLError(.networkConnectionLost)
    }
    let controller = try await f.openController()
    let prepared = try await f.prepare(controller)
    let probe = await MainActor.run { EditControllerProbe() }
    let id = try await controller.enqueue(preparation: prepared, context: f.context) {
      probe.receive($0)
    }
    let pending = Task {
      try await controller.send(id: id, context: f.context) { probe.receive($0) }
    }
    #expect(await barrier.waitEnteredOrFinished())
    await #expect(throws: ConversationMealEditControllerError.busy) {
      try await controller.reconcile(id: id, context: f.context) { probe.receive($0) }
    }
    #expect(await f.http.stub.requests.count == 2)
    await barrier.release()
    await #expect(throws: (any Error).self) { try await pending.value }
    await f.http.stub.respond { _, _ in .init(status: 200, body: f.preparedSaved) }
    try await controller.reconcile(id: id, context: f.context) { probe.receive($0) }
    #expect(await probe.savedCount == 1)
    #expect(await f.http.stub.requests.count == 3)
    await controller.close()
  }
}

@MainActor final class EditControllerProbe {
  var savedCount = 0
  var absentCanResubmit = false
  var snapshot: ConversationMealEditOutboxViewSnapshot?
  func receive(_ event: ConversationMealEditEvent) {
    switch event {
    case .saved: savedCount += 1
    case .absent(_, let canResubmit): absentCanResubmit = canResubmit
    case .snapshot(let value): snapshot = value
    default: break
    }
  }
}

@Suite("Edit mutations remain bound inside the actual local transaction")
struct ConversationMealEditAtomicContextTests {
  @Test(arguments: ["waiting", "discard", "reset"])
  func aPatientRemapAfterPreflightPreservesEveryOriginalCiphertextByte(_ transition: String)
    async throws
  {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    await f.seedKey()
    let gate = EditMutationGate()
    let lifecycle = EditGatedLifecycle(base: f.http.lifecycle, gate: gate)
    let session = try await ConversationMealEditOutboxSession.open(
      lifecycle: lifecycle,
      store: f.disk.store, keyVault: f.vault, expectedLease: f.disk.lease)
    let id = try await session.enqueue(operation: f.operation, server: f.context.observation)
    let ticket: ConversationMealEditOutboxTicket?
    if transition == "waiting" {
      ticket = try await session.prepareDispatch(id: id, server: f.context.observation)
    } else {
      ticket = nil
    }
    let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    let barrier = ConversationControllerBarrier()
    await gate.holdNextState(barrier)
    let pending = Task {
      switch transition {
      case "waiting":
        try await session.markWaiting(
          ticket: #require(ticket), hold: .serverChanged, server: f.context.observation)
      case "discard": try await session.discardUnsent(id: id, server: f.context.observation)
      default: try await session.holdForLocalReset(id: id, server: f.context.observation)
      }
    }
    #expect(await barrier.waitEnteredOrFinished())
    let refresh = try f.authority.beginRefresh()
    _ = try f.authority.accept(
      refreshID: refresh, authUserID: f.context.authUserID,
      ownerID: UUID(), localSessionGeneration: f.context.sessionGeneration, epoch: f.context.epoch)
    await barrier.release()
    await #expect(throws: (any Error).self) { try await pending.value }
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == original)
    #expect(
      try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).map(
        \.operation.operationInputHash) == [f.operation.operationInputHash])
    await session.invalidate()
  }
}

actor EditMutationGate {
  private var state: ConversationControllerBarrier?
  private var returningState: ConversationControllerBarrier?
  func holdNextState(_ barrier: ConversationControllerBarrier) { state = barrier }
  func holdNextStateReturn(_ barrier: ConversationControllerBarrier) { returningState = barrier }
  func beforeState() async {
    if let barrier = state {
      state = nil
      await barrier.enter()
    }
  }
  func afterState() async {
    if let barrier = returningState {
      returningState = nil
      await barrier.enter()
    }
  }
}

struct EditGatedLifecycle: SessionLifecycleProviding {
  let base: ConversationHTTPTestLifecycle
  let gate: EditMutationGate
  func currentBearerToken() async -> String? { await base.currentBearerToken() }
  func leaseForRequest() async throws -> SessionLease { await base.leaseForRequest() }
  func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
  func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
    try await base.refreshAfterUnauthorized(lease: lease)
  }
  func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
  func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws
    -> UUID
  { try await base.beginPatientWork(lease: lease, cancel: cancel) }
  func finishPatientWork(_ id: UUID) async { await base.finishPatientWork(id) }
  func performPatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @Sendable () throws -> Value
  ) async throws -> Value {
    await gate.beforeState()
    let result = try await base.performPatientStateOperation(lease: lease, operation: operation)
    await gate.afterState()
    return result
  }
  func performVisiblePatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @MainActor @Sendable () throws -> Value
  ) async throws -> Value {
    try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
  }
}
