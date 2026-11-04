import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Actual edit transport preserves immutable operation identity")
struct ConversationMealEditTransportTests {
  @Test func editHeadersCannotEscapeTheirExactClosedOperationRoutes() throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    let op = f.operation
    let base =
      "/api/mobile/v1/conversation/meal-commands/\(op.commandID.uuidString.lowercased())/edits/\(op.operationID.uuidString.lowercased())"
    let key = try IdempotencyKey(validating: op.idempotencyKey)
    let headers = MobileConversationRequestHeaders.mealEdit(
      epoch: op.epoch, ownerID: op.ownerID, inputHash: op.originalInputHash)
    for path in [
      base + "/reconcile", base + "/extra",
      base.replacingOccurrences(of: "/edits/", with: "/other/"),
    ] {
      #expect(throws: (any Error).self) {
        try MobileAPIRequest<ConversationMealEditReply>(
          method: .post, path: path, body: op.wireBody,
          idempotencyKey: key, conversation: headers, unauthorizedReplay: .never)
      }
    }
    #expect(throws: (any Error).self) {
      try MobileAPIRequest<ConversationMealEditReply>(
        method: .post, path: base, body: op.wireBody,
        idempotencyKey: key, conversation: headers)
    }
    #expect(throws: (any Error).self) {
      try MobileAPIRequest<ConversationMealEditReply>(
        method: .post, path: base, body: op.wireBody,
        idempotencyKey: IdempotencyKey(validating: "cmedit1:\(UUID().uuidString.lowercased())"),
        conversation: headers, unauthorizedReplay: .never)
    }
    let raw = try #require(JSONSerialization.jsonObject(with: op.wireBody) as? [String: Any])
    var injected = raw
    injected["owner_id"] = op.ownerID.uuidString.lowercased()
    #expect(throws: (any Error).self) {
      try MobileAPIRequest<ConversationMealEditReply>(
        method: .post, path: base,
        body: JSONSerialization.data(withJSONObject: injected), idempotencyKey: key,
        conversation: headers, unauthorizedReplay: .never)
    }
  }
  @Test func writeAndReadOnlyReconcileSendTheSameOriginalBytesAndPreconditions() async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    let session = try await f.session()
    let id = try await session.enqueue(operation: f.operation, server: f.context.observation)
    let ticket = try await session.prepareDispatch(id: id, server: f.context.observation)
    await f.http.stub.respond { request, _ in
      .init(
        status: 200, body: request.url?.path.hasSuffix("/reconcile") == true ? f.absent : f.saved)
    }
    let repo = try await MobileConversationMealEditRepository.scoped(
      transport: f.http.transport, lifecycle: f.http.lifecycle,
      lease: await f.http.lifecycle.leaseForRequest())
    #expect(try await repo.submit(ticket, context: f.context).matches(operation: f.operation))
    #expect(try await repo.reconcile(ticket, context: f.context).matches(operation: f.operation))
    let requests = await f.http.stub.requests
    #expect(requests.count == 2 && requests.allSatisfy { $0.httpMethod == "POST" })
    let base =
      "/api/mobile/v1/conversation/meal-commands/\(f.operation.commandID.uuidString.lowercased())/edits/\(f.operation.operationID.uuidString.lowercased())"
    #expect(requests.map { $0.url?.path } == [base, base + "/reconcile"])
    for request in requests {
      #expect(request.httpBody == f.operation.wireBody)
      #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == f.operation.idempotencyKey)
      #expect(
        request.value(forHTTPHeaderField: "X-Conversation-Owner")
          == f.operation.ownerID.uuidString.lowercased())
      #expect(
        request.value(forHTTPHeaderField: "X-Conversation-Epoch")
          == f.operation.epoch.uuidString.lowercased())
      #expect(
        request.value(forHTTPHeaderField: "X-Conversation-Input-Hash")
          == f.operation.originalInputHash)
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-initial")
    }
    #expect(UUID(uuidString: f.disk.lease.userID) != f.operation.ownerID)
    await session.invalidate()
  }

  @Test(arguments: [false, true])
  func neitherEditPOSTRefreshesOrPhysicallyReplaysA401(_ reconciliation: Bool) async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    let session = try await f.session()
    let id = try await session.enqueue(operation: f.operation, server: f.context.observation)
    let ticket = try await session.prepareDispatch(id: id, server: f.context.observation)
    await f.http.stub.respond { _, _ in .failure(401, "invalid_access_token") }
    let repo = try await MobileConversationMealEditRepository.scoped(
      transport: f.http.transport, lifecycle: f.http.lifecycle,
      lease: await f.http.lifecycle.leaseForRequest())
    await #expect(throws: (any Error).self) {
      if reconciliation {
        _ = try await repo.reconcile(ticket, context: f.context)
      } else {
        _ = try await repo.submit(ticket, context: f.context)
      }
    }
    #expect(await f.http.stub.requests.count == 1)
    #expect(await f.http.lifecycle.refreshCount == 0)
    #expect(
      try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).first?.state == .dispatchedUnknown
    )
    await session.invalidate()
  }

  @Test func revokedOrForeignContextDoesNotSendAnd202CannotBeAnEditACK() async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    let session = try await f.session()
    let id = try await session.enqueue(operation: f.operation, server: f.context.observation)
    let ticket = try await session.prepareDispatch(id: id, server: f.context.observation)
    let repo = try await MobileConversationMealEditRepository.scoped(
      transport: f.http.transport, lifecycle: f.http.lifecycle,
      lease: await f.http.lifecycle.leaseForRequest())
    await f.http.stub.respond { _, _ in .init(status: 202, body: f.saved) }
    await #expect(throws: (any Error).self) { try await repo.submit(ticket, context: f.context) }
    let before = await f.http.stub.requests.count
    let foreign = ConversationCommandContext(
      observation: .init(
        authUserID: f.context.authUserID,
        ownerID: UUID(), localSessionGeneration: f.context.sessionGeneration, epoch: f.context.epoch
      ),
      observedAt: f.context.observedAt)
    await #expect(throws: (any Error).self) { try await repo.reconcile(ticket, context: foreign) }
    _ = try f.authority.beginRefresh()
    await #expect(throws: (any Error).self) { try await repo.reconcile(ticket, context: f.context) }
    #expect(await f.http.stub.requests.count == before)
    await session.invalidate()
  }
}

struct EditControllerFixture: Sendable {
  let disk: EditOutboxFixture
  let http: ConversationHTTPFixture
  let keys = OutboxKeychainFake()
  let authority = ConversationOutboxObservationAuthority()
  let context: ConversationCommandContext
  let operation: ConversationMealEditOperation
  let preparedOperation: ConversationMealEditOperation
  let preparedSaved: Data
  let preparedAbsent: Data
  let group: ConversationMealGroupSnapshot
  let groupBody: Data
  let unavailableGroupBody: Data
  let saved: Data
  let absent: Data
  init() throws {
    disk = try .init()
    http = try .init()
    operation = try disk.operation()
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealEditPublicFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealEditPublicFixtures.json")
    #endif
    let fixtureData = try Data(contentsOf: url)
    #expect(
      ConversationMealCommand.digest(fixtureData)
        == "da84f8538ded15873383dd38e3611db493e9f079d14742ec8f1c623354618f63")
    let raw = try #require(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
    groupBody = try JSONSerialization.data(withJSONObject: #require(raw["group"]))
    unavailableGroupBody = try JSONSerialization.data(
      withJSONObject: #require(raw["unavailable_group"]))
    saved = try JSONSerialization.data(withJSONObject: #require(raw["saved"]))
    absent = try JSONSerialization.data(withJSONObject: #require(raw["absent"]))
    struct GroupEnvelope: Decodable { let data: ConversationMealGroupSnapshot }
    group = try JSONDecoder().decode(GroupEnvelope.self, from: groupBody).data
    preparedOperation = try .init(
      ownerID: group.ownerID, commandID: group.commandID,
      originalInputHash: group.originalInputHash, epoch: group.epoch,
      operationID: operation.operationID, expectedRevision: group.revision,
      expectedVersion: #require(group.current).expectedVersion, action: operation.action)
    // The codec fixture's input uses an independent placeholder CAS. These
    // controlled UNIT responses bind the actual-group-derived operation;
    // they are not new SQL/SDK fixture claims. Original wire goldens above stay exact.
    var savedUnit = try #require(raw["saved"] as? [String: Any])
    var savedData = try #require(savedUnit["data"] as? [String: Any])
    var receipt = try #require(savedData["receipt"] as? [String: Any])
    receipt["input_hash"] = preparedOperation.operationInputHash
    savedData["receipt"] = receipt
    savedUnit["data"] = savedData
    preparedSaved = try JSONSerialization.data(withJSONObject: savedUnit)
    var absentUnit = try #require(raw["absent"] as? [String: Any])
    var absentData = try #require(absentUnit["data"] as? [String: Any])
    absentData["operation_input_hash"] = preparedOperation.operationInputHash
    absentUnit["data"] = absentData
    preparedAbsent = try JSONSerialization.data(withJSONObject: absentUnit)
    let refresh = try authority.beginRefresh()
    context = .init(
      observation: try authority.accept(
        refreshID: refresh,
        authUserID: #require(UUID(uuidString: disk.lease.userID)), ownerID: disk.patient,
        localSessionGeneration: disk.lease.generation, epoch: disk.epoch),
      observedAt: group.admittedAt)
  }
  var vault: ConversationOutboxKeyVault {
    .init(service: ConversationMealEditOutboxSession.keychainService, security: keys)
  }
  func seedKey() async {
    await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: disk.owner.hash)
  }
  func session() async throws -> ConversationMealEditOutboxSession {
    await seedKey()
    return try await .open(
      lifecycle: http.lifecycle, store: disk.store, keyVault: vault, expectedLease: disk.lease)
  }
  func openController() async throws -> ConversationMealEditController {
    await seedKey()
    return try await .open(
      transport: http.transport, lifecycle: http.lifecycle,
      store: disk.store, keyVault: vault)
  }
  func prepare(_ controller: ConversationMealEditController) async throws
    -> ConversationMealEditPreparation
  {
    try await controller.prepare(
      commandID: preparedOperation.commandID,
      originalInputHash: preparedOperation.originalInputHash,
      expectedRevision: preparedOperation.expectedRevision,
      expectedVersion: preparedOperation.expectedVersion, action: preparedOperation.action,
      context: context, operationID: preparedOperation.operationID)
  }
}
