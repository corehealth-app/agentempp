import Foundation
import Security
import Testing

@testable import BodyFlow

@MainActor @Suite("Visible training completion owns one durable operation")
struct TrainingExecutionCompletionModelTests {
  @Test func finishUsesActualReportAndColdHistoryRetainsPerformedFacts() async throws {
    let h = try await CompletionModelHarness.make()
    let model = h.model()
    await model.load()
    await model.select(h.operation.sessionID)
    #expect(model.supportsCompletion && model.canEdit)
    #expect(await model.finish(report: h.report))
    #expect(model.session?.phase == .completed && model.completion?.workout?.durationMin == 30)
    #expect(model.pending == nil && !model.canEdit)
    #expect(model.session?.exercises[1].sets.isEmpty == true)
    await model.close()
    let cold = h.model()
    await cold.load()
    #expect(cold.resumableSessions.first?.historyPhase == .completed)
    await cold.select(h.operation.sessionID)
    #expect(cold.completion?.feedback?.sections.count == 6)
    #expect(cold.session?.exercises[0].sets.first?.loadKg == 15.5)
    #expect(await h.server.finishPosts == 1)
  }
  @Test func lostFinishReplySurvivesReopenAndReadonlyRecoveryDoesNotRepeatThePost() async throws {
    let h = try await CompletionModelHarness.make()
    let first = h.model()
    await first.load()
    await first.select(h.operation.sessionID)
    await h.server.setMode(.loseReply)
    #expect(!(await first.finish(report: h.report)))
    #expect(first.pending == h.operation)
    #expect(try await h.store.load(authUserID: h.repository.authUserID) == h.operation)
    await first.close()
    let cold = h.model()
    await cold.load()
    #expect(cold.session?.phase == .completed && cold.pending == h.operation)
    #expect(await cold.retryPending())
    #expect(cold.pending == nil && cold.completion?.status == .completed)
    #expect(await h.server.finishPosts == 1)
  }
  @Test func reservationBlocksSeriesAndLateCompletedCancellationKeepsTheActualWorkout() async throws
  {
    let h = try await CompletionModelHarness.make()
    let model = h.model()
    await model.load()
    await model.select(h.operation.sessionID)
    await h.server.setMode(.reserve)
    #expect(!(await model.finish(report: h.report)))
    #expect(model.pending == h.operation && !model.canEdit && model.completion?.status == .reserved)
    let before = await h.http.stub.requests.count
    #expect(!(await model.markExercise(0, completed: true)))
    #expect(await h.http.stub.requests.count == before)
    #expect(await model.cancelPendingCompletion())
    #expect(model.completion?.status == .completed && model.session?.phase == .completed)
    #expect(model.completion?.workout != nil && model.pending == nil)
    #expect(await h.server.finishPosts == 1)
  }
  @Test func oldProgressACKRetiresOnlyItselfAndKeepsTheLaterCompletedCurrentState() async throws {
    let h = try await CompletionModelHarness.make()
    let f = try TrainingCompletionFixture()
    try await h.store.claim(f.operation("save"))
    await h.server.setState(.completed)
    let model = h.model()
    await model.load()
    #expect(model.session?.phase == .completed && model.pending?.kind == "save_set")
    #expect(await model.retryPending())
    #expect(
      model.pending == nil && model.session?.revision == 2 && model.completion?.status == .completed
    )
    #expect(await h.server.finishPosts == 0)
  }
  @Test func closedDayDoesNotSubmitOrInventACompletedWorkout() async throws {
    let h = try await CompletionModelHarness.make()
    let model = h.model()
    await model.load()
    await model.select(h.operation.sessionID)
    await h.server.setMode(.closedDay)
    #expect(!(await model.finish(report: h.report)))
    #expect(model.pending == nil && model.completion == nil && model.failure == .changed)
    #expect(await h.server.finishPosts == 0)
  }
}

@MainActor struct CompletionModelHarness {
  let http: ConversationHTTPFixture, server: CompletionModelServer,
    repository: MobileTrainingExecutionCompletionRepository, store: TrainingExecutionPendingStore
  let operation: TrainingExecutionOperation, report: String
  static func make() async throws -> Self {
    let f = try TrainingCompletionFixture()
    let op = try f.finish()
    let http = try ConversationHTTPFixture()
    await http.lifecycle.replace(
      .init(
        userID: op.binding.authUserID.uuidString.lowercased(), generation: 7,
        bearer: "synthetic-visible-completion-142"))
    let server = CompletionModelServer(fixture: f)
    await http.stub.respond { request, _ in try await server.reply(request) }
    let repository = try await MobileTrainingExecutionCompletionRepository.scoped(
      transport: http.transport, lifecycle: http.lifecycle,
      lease: await http.lifecycle.leaseForRequest())
    let store = try TrainingExecutionPendingStore(
      origin: #require(http.transport.configuredOrigin), security: CompletionModelSecurity())
    return .init(
      http: http, server: server, repository: repository, store: store, operation: op,
      report: "Fiz full body por 30 min com intensidade moderada.")
  }
  func model() -> TrainingExecutionModel {
    let id = operation.operationID
    return .init(provider: repository, store: store, makeCompletionID: { id })
  }
}
actor CompletionModelServer {
  // Only external HTTP/Auth boundary is substituted. Public packets were
  // captured from the real R141 local handlers/service/SQL. No domain math here.
  enum State { case progress, reserved, completed }
  enum Mode { case normal, loseReply, reserve, closedDay, cancelBeforeEffect }
  let fixture: TrainingCompletionFixture
  var state: State = .progress, mode: Mode = .normal
  private(set) var finishPosts = 0
  init(fixture: TrainingCompletionFixture) { self.fixture = fixture }
  func setMode(_ value: Mode) { mode = value }
  func setState(_ value: State) { state = value }
  func reply(_ request: URLRequest) throws -> ConversationHTTPReply {
    let path = request.url!.path
    if path == "/api/mobile/v1/me" {
      return try envelope(["id": fixture.finish().binding.ownerID.uuidString.lowercased()])
    }
    var value: [String: Any]
    var status = 200
    if path == "/api/mobile/v1/training/execution-v2" {
      value = try fixture.object(state == .completed ? "home_completed" : "home")
      if mode == .closedDay {
        var scope = value["scope"] as! [String: Any]
        scope["recording_allowed"] = false
        value["scope"] = scope
      }
    } else if request.httpMethod == "POST", let bytes = request.httpBody,
      let wrapper = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
      wrapper["schema"] as? String == "training.execution.finish-resolution.v1",
      let command = wrapper["command"] as? [String: Any],
      let mode = wrapper["mode"] as? String
    {
      let operation = try TrainingExecutionOperation(
        binding: fixture.finish().binding,
        wireBody: JSONSerialization.data(withJSONObject: command))
      let knownFinish = try fixture.finish()
      let knownCancel = try fixture.operation("cancelFinish")
      let known = operation == knownFinish || operation == knownCancel
      if !known { return try envelope(fixture.object("progress_replay_completed")) }
      if mode == "withdraw" { state = modeForCancellation() }
      let own = try fixture.object(
        mode == "withdraw" && self.mode == .cancelBeforeEffect
          ? "cancelled_before_effect"
          : (state == .reserved ? "reserved_completion" : "completed_completion"))
      let current: [String: Any]
      if mode == "withdraw" && self.mode == .cancelBeforeEffect {
        current = try fixture.object("cancelled_current")
      } else if state == .reserved {
        current = [
          "schema": "training.execution-state.v2", "scope": own["scope"]!,
          "session": own["session"]!, "completion": own,
        ]
      } else {
        current = try fixture.object("state_completed")
      }
      value = [
        "schema": "training.execution-finish-resolution.v1", "mode": mode,
        "status": "available", "reason": NSNull(), "scope": current["scope"]!,
        "session_id": operation.sessionID.uuidString.lowercased(),
        "operation_id": operation.operationID.uuidString.lowercased(),
        "input_hash": operation.inputHash, "before_revision": operation.expectedRevision!,
        "expected_epoch": operation.binding.epoch.uuidString.lowercased(), "current": current,
        "completion": own, "withdrawal": NSNull(),
      ]
    } else if path.hasSuffix("/cancel") {
      state = mode == .cancelBeforeEffect ? .progress : .completed
      value = try fixture.object(
        mode == .cancelBeforeEffect ? "cancelled_before_effect" : "completion_after_cancel")
    } else if request.httpMethod == "POST" && path.hasSuffix("/completions") {
      let received = try TrainingExecutionOperation(
        binding: fixture.finish().binding, wireBody: #require(request.httpBody))
      guard received == (try fixture.finish()),
        request.value(forHTTPHeaderField: "Idempotency-Key") == received.idempotencyKey
      else { throw TrainingExecutionError.invalidResponse }
      finishPosts += 1
      state = mode == .reserve ? .reserved : .completed
      if mode == .loseReply {
        mode = .normal
        throw URLError(.networkConnectionLost)
      }
      value = try fixture.object(
        state == .reserved ? "reserved_completion" : "completed_completion")
      status = state == .reserved ? 202 : 200
    } else if path.contains("/completions/") {
      value = try fixture.object(
        state == .reserved ? "reserved_completion" : "completed_completion")
      status = state == .reserved ? 202 : 200
    } else if request.httpMethod == "POST" {
      value = try fixture.object("progress_replay_completed")
    } else {
      value = try fixture.object(
        mode == .cancelBeforeEffect
          ? "cancelled_current" : (state == .completed ? "state_completed" : "state_progress"))
    }
    return try envelope(value, status: status)
  }
  private func modeForCancellation() -> State {
    mode == .cancelBeforeEffect ? .progress : .completed
  }
  private func envelope(_ data: [String: Any], status: Int = 200) throws -> ConversationHTTPReply {
    .init(
      status: status,
      body: try JSONSerialization.data(withJSONObject: [
        "data": data, "meta": ["api_version": "v1", "request_id": "training-visible-native-142"],
      ]),
      headers: [
        "Content-Type": "application/json", "X-Training-Execution": "2",
        "X-Training-Completion": "1", "Cache-Control": "no-store",
      ])
  }
}
private actor CompletionModelSecurity: KeychainSecurityClient {
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

extension TrainingExecutionCompletionModelTests {
  @Test func explicitV2SessionCompositionIsInertUntilOpenedAndWithdrawsOnClose() async throws {
    let h = try await CompletionModelHarness.make()
    let before = await h.http.stub.requests.count
    let source = TrainingExecutionSessionSource(
      transport: h.http.transport, lifecycle: h.http.lifecycle, pendingStore: h.store,
      completionEnabled: true)
    #expect(await h.http.stub.requests.count == before)
    let model = try await source.open(
      expectedUserID: h.repository.authUserID.uuidString.lowercased())
    #expect(model.supportsCompletion)
    await model.load()
    await model.select(h.operation.sessionID)
    #expect(model.canEdit && model.completion == nil)
    model.invalidateSynchronously()
    let count = await h.http.stub.requests.count
    #expect(!(await model.finish(report: h.report)))
    #expect(
      await h.http.stub.requests.count == count && model.session == nil && model.completion == nil)
    await model.close()
  }
}

extension TrainingExecutionCompletionModelTests {
  @Test func preEffectCancellationClearsOnlyItsReceiptAndRetainsTheRealUncompletedSession()
    async throws
  {
    let h = try await CompletionModelHarness.make()
    let f = try TrainingCompletionFixture()
    let held = try f.operation("cancelFinish")
    try await h.store.claim(held)
    await h.server.setMode(.cancelBeforeEffect)
    let model = h.model()
    await model.load()
    #expect(model.pending == held && model.session?.id == held.sessionID)
    #expect(await model.cancelPendingCompletion())
    #expect(
      model.pending == nil && model.completion?.status == .cancelled
        && model.completion?.workout == nil)
    #expect(model.session?.phase == .inProgress && model.session?.revision == 0)
    #expect(model.session?.exercises.allSatisfy { $0.sets.isEmpty } == true)
    #expect(try await h.store.load(authUserID: h.repository.authUserID) == nil)
    #expect(await h.server.finishPosts == 0)
  }
  @Test func malformedResolutionNeverBorrowsAnotherCompletionToAcknowledgeAnUnknownLocalFinish()
    async throws
  {
    let h = try await CompletionModelHarness.make()
    let f = try TrainingCompletionFixture()
    let raw = try TrainingExecutionJSON(data: f.finish().wireBody)
    guard case .object(var fields) = raw else { throw TrainingExecutionError.invalidResponse }
    fields["operation_id"] = .string("14200000-0000-4000-8000-000000000099")
    let unknown = try TrainingExecutionOperation(
      binding: h.operation.binding, wireBody: TrainingExecutionJSON.object(fields).data())
    try await h.store.claim(unknown)
    await h.server.setState(.completed)
    let model = h.model()
    await model.load()
    #expect(model.completion?.completionID == h.operation.operationID)
    #expect(!(await model.retryPending()))
    #expect(model.pending == unknown && model.session?.phase == .completed)
    #expect(try await h.store.load(authUserID: h.repository.authUserID) == unknown)
    #expect(await h.server.finishPosts == 0)
  }
}
