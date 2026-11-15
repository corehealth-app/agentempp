import Foundation
import Testing

@testable import BodyFlow

@MainActor @Suite("Completion transport preserves the original login and wire operation")
struct TrainingExecutionCompletionTransportTests {
  @Test func lostFinishReplyUsesTheSameKeyAndReadRecoveryNeverPostsAnotherWorkout() async throws {
    let h = try await CompletionTransportHarness.make()
    let operation = try TrainingCompletionFixture().finish()
    await h.server.setMode(.lost)
    await #expect(throws: (any Error).self) { try await h.repository.finish(operation) }
    let saved = try await h.repository.completion(.init(operation: operation))
    #expect(saved.status == .completed)
    let posts = await h.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 1 && posts[0].httpBody == operation.wireBody)
    #expect(posts[0].value(forHTTPHeaderField: "Idempotency-Key") == operation.idempotencyKey)
    #expect(await h.http.lifecycle.refreshCount == 0)
  }
  @Test func progressReceiptCanReturnCurrentCompletionAndForeignScopeNeverPublishes() async throws {
    let h = try await CompletionTransportHarness.make()
    let f = try TrainingCompletionFixture()
    let home = try await h.repository.home(cursor: nil)
    let current = try await h.repository.current(
      try f.finish().sessionID, binding: .init(home.scope))
    #expect(current.session.phase == .completed)
    let ack = try await h.repository.progress(f.operation("save"))
    #expect(ack.receipt?.afterRevision == 1 && ack.current?.session.revision == 2)
    await h.server.setMode(.foreign)
    await #expect(throws: (any Error).self) { try await h.repository.finish(f.finish()) }
  }
  @Test func reservedStatusMustMatch202AndNeverPretendToBeAnAcknowledgement() async throws {
    let h = try await CompletionTransportHarness.make()
    let operation = try TrainingCompletionFixture().finish()
    await h.server.setMode(.reserved)
    let pending = try await h.repository.finish(operation)
    #expect(pending.status == .reserved && pending.receipt == nil)
    await h.server.setMode(.wrongStatus)
    await #expect(throws: (any Error).self) { try await h.repository.finish(operation) }
  }
  @Test(arguments: [CompletionTransportServer.Mode.unauthorized, .redirect])
  func originalLoginNeverRefreshesOrFollowsCompletionRedirect(
    _ mode: CompletionTransportServer.Mode
  ) async throws {
    let h = try await CompletionTransportHarness.make()
    let operation = try TrainingCompletionFixture().finish()
    await h.server.setMode(mode)
    let before = await h.http.stub.requests.count
    await #expect(throws: (any Error).self) { try await h.repository.finish(operation) }
    #expect(await h.http.stub.requests.count == before + 1)
    #expect(await h.http.lifecycle.refreshCount == 0)
    let count = await h.http.stub.requests.count
    await h.http.lifecycle.replace(
      .init(
        userID: operation.binding.authUserID.uuidString.lowercased(), generation: 8,
        bearer: "synthetic-new-login"))
    await #expect(throws: (any Error).self) {
      try await h.repository.completion(.init(operation: operation))
    }
    #expect(await h.http.stub.requests.count == count)
  }
}

@MainActor struct CompletionTransportHarness {
  let http: ConversationHTTPFixture, server: CompletionTransportServer,
    repository: MobileTrainingExecutionCompletionRepository
  static func make() async throws -> Self {
    let f = try TrainingCompletionFixture()
    let op = try f.finish()
    let http = try ConversationHTTPFixture()
    await http.lifecycle.replace(
      .init(
        userID: op.binding.authUserID.uuidString.lowercased(), generation: 7,
        bearer: "synthetic-completion-141"))
    let server = CompletionTransportServer(fixture: f)
    await http.stub.respond { request, _ in try await server.reply(request) }
    let repository = try await MobileTrainingExecutionCompletionRepository.scoped(
      transport: http.transport, lifecycle: http.lifecycle,
      lease: await http.lifecycle.leaseForRequest())
    return .init(http: http, server: server, repository: repository)
  }
}
actor CompletionTransportServer {
  enum Mode: Sendable { case normal, lost, foreign, unauthorized, redirect, reserved, wrongStatus }
  let fixture: TrainingCompletionFixture
  var mode: Mode = .normal
  init(fixture: TrainingCompletionFixture) { self.fixture = fixture }
  func setMode(_ value: Mode) { mode = value }
  func reply(_ request: URLRequest) throws -> ConversationHTTPReply {
    let path = request.url!.path
    if path == "/api/mobile/v1/me" {
      return try envelope(["id": fixture.finish().binding.ownerID.uuidString.lowercased()])
    }
    if mode == .unauthorized { return .failure(401, "unauthorized") }
    if mode == .redirect {
      let target = URL(string: "https://never-follow.invalid/api/mobile/v1/workouts")!
      return .init(
        status: 302, body: Data(), headers: ["Location": target.absoluteString], redirectURL: target
      )
    }
    if mode == .lost {
      mode = .normal
      throw URLError(.networkConnectionLost)
    }
    var value: [String: Any]
    if path == "/api/mobile/v1/training/execution-v2" {
      value = try fixture.object("home_completed")
    } else if request.httpMethod == "POST" && !path.hasSuffix("/completions")
      && !path.hasSuffix("/cancel")
    {
      value = try fixture.object("progress_replay_completed")
    } else if path.contains("/completions/") || path.hasSuffix("/completions") {
      value = try fixture.object("completed_completion")
    } else {
      value = try fixture.object("state_completed")
    }
    if mode == .reserved || mode == .wrongStatus {
      value = try fixture.object("reserved_completion")
    }
    if mode == .foreign { value["owner_id"] = UUID().uuidString.lowercased() }
    return try envelope(value)
  }
  private func envelope(_ data: [String: Any]) throws -> ConversationHTTPReply {
    .init(
      status: mode == .reserved ? 202 : 200,
      body: try JSONSerialization.data(withJSONObject: [
        "data": data,
        "meta": ["api_version": "v1", "request_id": "training-completion-native-141"],
      ]),
      headers: [
        "Content-Type": "application/json", "X-Training-Execution": "2",
        "X-Training-Completion": "1", "Cache-Control": "no-store",
      ])
  }
}
