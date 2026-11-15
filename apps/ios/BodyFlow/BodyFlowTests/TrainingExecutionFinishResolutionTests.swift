import Foundation
import Security
import Testing

@testable import BodyFlow

@Suite("Finish recovery binds the original operation without borrowing another receipt")
struct TrainingExecutionFinishResolutionTests {
  @Test func allActualSQLProofsRemainDistinctAndBindTheOriginalCommand() throws {
    let f = try FinishResolutionFixture()
    for label in f.cases.keys.sorted() {
      let value = try f.value(label)
      let operation = try f.operation(label)
      try value.validate(for: operation, mode: f.mode(label))
      if label == "terminal_other_completed" {
        #expect(value.status == .fenced && value.completion == nil)
        #expect(value.current?.completion?.completionID != operation.operationID)
      }
      if label == "withdrawn_old_epoch" {
        #expect(value.status == .withdrawn && value.current == nil)
        #expect(value.scope.epoch != operation.binding.epoch)
      }
      if label == "own_cancelled_other_completed" {
        #expect(
          value.completion?.status == .cancelled && value.current?.session.phase == .completed)
      }
    }
  }
  @Test(arguments: ["operation", "hash", "revision", "reason", "mode", "source", "marker", "clock"])
  func corruptedProofCannotRetireAPendingFinish(_ attack: String) throws {
    let f = try FinishResolutionFixture()
    var root = try f.payload("withdrawn_other_completed")
    switch attack {
    case "operation": root["operation_id"] = UUID().uuidString.lowercased()
    case "hash": root["input_hash"] = String(repeating: "f", count: 64)
    case "revision": root["before_revision"] = 99
    case "reason": root["reason"] = "terminal"
    case "mode": root["mode"] = "observe"
    case "source": root["source"] = "never accepted"
    case "marker": root["withdrawal"] = NSNull()
    default:
      var marker = try #require(root["withdrawal"] as? [String: Any])
      marker["at"] = "2099-01-01T00:00:00.000000Z"
      root["withdrawal"] = marker
    }
    #expect(throws: (any Error).self) {
      try TrainingExecutionFinishResolutionSnapshot(
        data: JSONSerialization.data(withJSONObject: root)
      )
      .validate(for: f.operation("withdrawn_other_completed"), mode: .withdraw)
    }
  }
}
struct FinishResolutionFixture {
  let cases: [String: [String: Any]]
  init() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/TrainingFinishResolutionControlledFixture.json")
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    cases = try #require(root["cases"] as? [String: [String: Any]])
  }
  func payload(_ label: String) throws -> [String: Any] {
    try #require(cases[label]?["payload"] as? [String: Any])
  }
  func value(_ label: String) throws -> TrainingExecutionFinishResolutionSnapshot {
    try .init(data: JSONSerialization.data(withJSONObject: payload(label)))
  }
  func mode(_ label: String) throws -> TrainingExecutionFinishResolutionMode {
    let raw = try #require(cases[label]?["mode"] as? String)
    return try #require(TrainingExecutionFinishResolutionMode(rawValue: raw))
  }
  func operation(_ label: String) throws -> TrainingExecutionOperation {
    let root = try payload(label)
    let scope = try TrainingExecutionScope(
      TrainingExecutionJSON(data: JSONSerialization.data(withJSONObject: #require(root["scope"]))))
    let command = try #require(cases[label]?["command"] as? [String: Any])
    let rawEpoch = try #require(command["expected_epoch"] as? String)
    let epoch = try #require(UUID(uuidString: rawEpoch))
    return try .init(
      binding: .init(
        ownerID: scope.ownerID, authUserID: scope.authUserID, epoch: epoch, timezone: scope.timezone
      ),
      wireBody: JSONSerialization.data(withJSONObject: command))
  }
}

@MainActor
@Suite("Visible recovery retires exact finish fences and keeps independent current state")
struct TrainingExecutionFinishResolutionModelTests {
  @Test(arguments: ["terminal_other_completed", "withdrawn_old_epoch", "fenced_old_epoch"])
  func readonlyRecoveryResolvesOnlyTheExactFutureFence(_ label: String) async throws {
    let h = try await ResolutionModelHarness.make(label)
    await h.model.load()
    #expect(h.model.pending == h.operation)
    _ = await h.model.retryPending()
    #expect(h.model.pending == nil)
    #expect(h.model.failure == (label == "withdrawn_old_epoch" ? .finishWithdrawn : .finishFenced))
    #expect(try await h.store.load(authUserID: h.operation.binding.authUserID) == nil)
    if label == "terminal_other_completed" {
      #expect(h.model.session?.phase == .completed)
      #expect(h.model.completion?.completionID != h.operation.operationID)
    } else {
      #expect(h.model.session == nil && h.model.completion == nil)
    }
    #expect(
      await h.http.stub.requests.filter { $0.url?.path.hasSuffix("/completions") == true }.isEmpty)
  }
  @Test func explicitWithdrawalOfAnUnacceptedOldEpochCommandNeverRegistersAWorkout() async throws {
    let h = try await ResolutionModelHarness.make("withdrawn_old_epoch", mode: .withdraw)
    await h.model.load()
    #expect(await h.model.cancelPendingCompletion())
    #expect(h.model.pending == nil && h.model.completion == nil)
    #expect(
      await h.http.stub.requests.contains {
        $0.value(forHTTPHeaderField: "Idempotency-Key")
          == h.operation.finishResolutionKey(.withdraw)
      })
    #expect(await h.http.lifecycle.refreshCount == 0)
  }
  @Test func anotherReservationAndAnUnproved404KeepTheSameDurableOperation() async throws {
    for label in ["other_reserved", "terminal_other_completed"] {
      let h = try await ResolutionModelHarness.make(
        label, failResolution: label == "terminal_other_completed")
      await h.model.load()
      #expect(!(await h.model.retryPending()))
      #expect(h.model.pending == h.operation)
      #expect(try await h.store.load(authUserID: h.operation.binding.authUserID) == h.operation)
      #expect(
        await h.http.stub.requests.filter { $0.url?.path.hasSuffix("/completions") == true }.isEmpty
      )
    }
  }
  @Test func cancellingOwnReceiptDisplaysTheOtherActualCompletedExecution() async throws {
    let h = try await ResolutionModelHarness.make("own_cancelled_other_completed", mode: .withdraw)
    await h.model.load()
    #expect(await h.model.cancelPendingCompletion())
    #expect(h.model.pending == nil && h.model.session?.phase == .completed)
    #expect(h.model.completion?.status == .completed)
    #expect(h.model.completion?.completionID != h.operation.operationID)
  }
}

@MainActor struct ResolutionModelHarness {
  let http: ConversationHTTPFixture, store: TrainingExecutionPendingStore
  let operation: TrainingExecutionOperation, model: TrainingExecutionModel
  static func make(
    _ label: String, mode: TrainingExecutionFinishResolutionMode = .observe,
    failResolution: Bool = false, loseFinishReply: Bool = false
  ) async throws -> Self {
    let fixture = try FinishResolutionFixture()
    let operation = try fixture.operation(label)
    let captured = try JSONSerialization.data(withJSONObject: fixture.payload(label))
    let http = try ConversationHTTPFixture()
    await http.lifecycle.replace(
      .init(
        userID: operation.binding.authUserID.uuidString.lowercased(), generation: 7,
        bearer: "synthetic-resolution-143"))
    await http.stub.respond { request, _ in
      let path = try #require(request.url?.path)
      var payload = try #require(JSONSerialization.jsonObject(with: captured) as? [String: Any])
      var status = 200
      let scope = try #require(payload["scope"] as? [String: Any])
      if path == "/api/mobile/v1/me" {
        payload = ["id": operation.binding.ownerID.uuidString.lowercased()]
      } else if path == "/api/mobile/v1/training/execution-v2" {
        payload = [
          "schema": "training.execution-home.v2", "scope": scope, "plan": NSNull(), "sessions": [],
          "next_cursor": NSNull(),
        ]
      } else if request.httpMethod == "POST" {
        if loseFinishReply && path.hasSuffix("/completions") {
          guard request.httpBody == operation.wireBody,
            request.value(forHTTPHeaderField: "Idempotency-Key") == operation.idempotencyKey
          else { throw TrainingExecutionError.invalidResponse }
          throw URLError(.networkConnectionLost)
        }
        guard !path.hasSuffix("/completions"),
          request.httpBody == (try operation.finishResolutionBody(mode)),
          request.value(forHTTPHeaderField: "Idempotency-Key")
            == operation.finishResolutionKey(mode)
        else { throw TrainingExecutionError.invalidResponse }
        if failResolution {
          status = 404
          payload = [:]
        } else {
          payload["mode"] = mode.rawValue
        }
      } else {
        if let current = payload["current"] as? [String: Any] {
          payload = current
        } else {
          status = 404
          payload = [:]
        }
      }
      let packet: [String: Any] =
        status == 404
        ? ["error": ["code": "training_execution_not_found", "message": "Not found"]]
        : ["data": payload, "meta": ["api_version": "v1", "request_id": "resolution-143"]]
      return .init(
        status: status, body: try JSONSerialization.data(withJSONObject: packet),
        headers: [
          "Content-Type": "application/json", "X-Training-Execution": "2",
          "X-Training-Completion": "1", "Cache-Control": "no-store",
        ])
    }
    let repo = try await MobileTrainingExecutionCompletionRepository.scoped(
      transport: http.transport, lifecycle: http.lifecycle,
      lease: await http.lifecycle.leaseForRequest())
    let store = try TrainingExecutionPendingStore(
      origin: #require(http.transport.configuredOrigin), security: ResolutionSecurity())
    try await store.claim(operation)
    return .init(
      http: http, store: store, operation: operation, model: .init(provider: repo, store: store))
  }
}
private actor ResolutionSecurity: KeychainSecurityClient {
  var values: [String: Data] = [:]
  func read(_ d: KeychainItemDescriptor) -> KeychainReadResult {
    values[d.account].map(KeychainReadResult.data) ?? .notFound
  }
  func add(_ d: KeychainItemDescriptor, data: Data) -> OSStatus {
    guard values[d.account] == nil else { return errSecDuplicateItem }
    values[d.account] = data
    return errSecSuccess
  }
  func update(_ d: KeychainItemDescriptor, data: Data) -> OSStatus { errSecUnimplemented }
  func delete(_ d: KeychainItemDescriptor) -> OSStatus {
    values[d.account] = nil
    return errSecSuccess
  }
}

extension TrainingExecutionFinishResolutionTests {
  @Test func readyPendingAndAnotherReceiptCannotRetireTheKeychainSlot() async throws {
    let f = try FinishResolutionFixture()
    for label in ["ready", "other_reserved", "own_completed"] {
      let operation = try f.operation(label)
      let store = try TrainingExecutionPendingStore(
        origin: URL(string: "https://resolution.invalid")!, security: ResolutionSecurity())
      try await store.claim(operation)
      await #expect(throws: (any Error).self) {
        try await store.retireFinish(operation, resolution: f.value(label))
      }
      #expect(try await store.load(authUserID: operation.binding.authUserID) == operation)
    }
    let operation = try f.operation("terminal_other_completed")
    let proof = try f.value("terminal_other_completed")
    let store = try TrainingExecutionPendingStore(
      origin: URL(string: "https://resolution.invalid")!, security: ResolutionSecurity())
    let other = try f.operation("own_completed")
    try await store.claim(other)
    await #expect(throws: (any Error).self) {
      try await store.retireFinish(operation, resolution: proof)
    }
    #expect(try await store.load(authUserID: other.binding.authUserID) == other)
  }
  @Test func resolutionHasItsOwnClosedBodyPathKeyAndStrict200Protocol() throws {
    let operation = try FinishResolutionFixture().operation("ready")
    let capability = MobileTrainingExecutionRequestHeaders.finishResolution(operation, .observe)
    let path = "/api/mobile/v1/training/execution-v2/" + operation.sessionID.uuidString.lowercased()
    try capability.validate(
      method: .post, path: path, query: [], body: operation.finishResolutionBody(.observe),
      key: IdempotencyKey(validating: operation.finishResolutionKey(.observe)), replay: .never)
    #expect(throws: (any Error).self) {
      try capability.validate(
        method: .post, path: path, query: [], body: operation.finishResolutionBody(.withdraw),
        key: IdempotencyKey(validating: operation.finishResolutionKey(.observe)), replay: .never)
    }
    #expect(throws: (any Error).self) {
      try capability.validate(
        method: .post, path: "/api/mobile/v1/training/execution-v2/completions", query: [],
        body: operation.wireBody,
        key: IdempotencyKey(validating: operation.idempotencyKey), replay: .never)
    }
    let response = HTTPURLResponse(
      url: URL(string: "https://example.invalid" + path)!, statusCode: 202, httpVersion: nil,
      headerFields: [
        "X-Training-Execution": "2", "X-Training-Completion": "1", "Cache-Control": "no-store",
      ])!
    #expect(throws: (any Error).self) { try capability.validateResponseProtocol(response) }
  }
}
extension TrainingExecutionFinishResolutionModelTests {
  @Test func replacingTheLoginNeverResolvesOrClearsTheOriginalAccountSlot() async throws {
    let h = try await ResolutionModelHarness.make("terminal_other_completed")
    await h.model.load()
    let before = await h.http.stub.requests.count
    await h.http.lifecycle.replace(
      .init(
        userID: h.operation.binding.authUserID.uuidString.lowercased(), generation: 8,
        bearer: "replacement-login"))
    #expect(!(await h.model.retryPending()))
    #expect(await h.http.stub.requests.count == before)
    #expect(try await h.store.load(authUserID: h.operation.binding.authUserID) == h.operation)
  }
}

extension TrainingExecutionFinishResolutionModelTests {
  @Test func aReadyObservationPermitsOnlyOneIdenticalRetryAndALostPostReplyKeepsTheSlot()
    async throws
  {
    let h = try await ResolutionModelHarness.make("ready", loseFinishReply: true)
    await h.model.load()
    #expect(!(await h.model.retryPending()))
    #expect(h.model.pending == h.operation)
    #expect(try await h.store.load(authUserID: h.operation.binding.authUserID) == h.operation)
    let requests = await h.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(requests.count == 2)
    #expect(requests.first?.httpBody == (try h.operation.finishResolutionBody(.observe)))
    #expect(requests.last?.httpBody == h.operation.wireBody)
    #expect(
      requests.last?.value(forHTTPHeaderField: "Idempotency-Key") == h.operation.idempotencyKey)
    #expect(await h.http.lifecycle.refreshCount == 0)
  }
}
