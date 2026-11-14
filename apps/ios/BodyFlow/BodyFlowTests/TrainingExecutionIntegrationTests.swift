import CryptoKit
import Foundation
import Security
import Testing

@testable import BodyFlow

@Suite("Native execution saves and recovers original training facts")
@MainActor
struct TrainingExecutionIntegrationTests {
  @Test func repositoryUsesDomainOwnerAndCannotFollowAReplacedLogin() async throws {
    let h = try await TrainingNativeHarness.make()
    let home = try await h.repository.home(cursor: nil)
    #expect(home.scope.ownerID != home.scope.authUserID)
    let sent = try #require(await h.http.stub.requests.last)
    #expect(
      sent.value(forHTTPHeaderField: "X-Training-Owner") == "13700000-0000-4000-8000-000000000002")
    let n = await h.http.stub.requests.count
    await h.http.lifecycle.replace(
      .init(
        userID: home.scope.authUserID.uuidString.lowercased(), generation: 8, bearer: "replacement")
    )
    await #expect(throws: (any Error).self) { try await h.repository.home(cursor: nil) }
    #expect(await h.http.stub.requests.count == n)
  }

  @Test func actualSeriesSurvivesNewModelWithoutSeedingThePrescription() async throws {
    let h = try await TrainingNativeHarness.make()
    let model = h.model()
    await model.load()
    #expect(model.home?.plan?.days[0].exercises[0].recommendedSets == 3)
    #expect(await model.start(dayIndex: 0))
    #expect(model.session?.exercises.allSatisfy { $0.sets.isEmpty } == true)
    let set = try TrainingExecutionSet(
      id: UUID(), index: 0, repetitions: 8, loadKg: 15.5, durationSeconds: nil, completed: true)
    #expect(await model.saveSet(exercise: 0, set: set))
    let id = try #require(model.session?.id)
    await model.close()
    let reopened = h.model()
    await reopened.load()
    await reopened.select(id)
    #expect(reopened.session?.exercises[0].sets.first?.repetitions == 8)
    #expect(reopened.session?.exercises[0].sets.first?.loadKg == 15.5)
    #expect(reopened.session?.exercises[1].sets.isEmpty == true)
    #expect(reopened.pending == nil)
  }

  @Test func lostReplyPersistsBeforeSendAndReplaysSameOperationAfterReopening() async throws {
    let h = try await TrainingNativeHarness.make()
    let first = h.model()
    await first.load()
    #expect(await first.start(dayIndex: 0))
    await h.server.loseNextReply()
    let set = try TrainingExecutionSet(
      id: UUID(), index: 0, repetitions: 8, loadKg: 0, durationSeconds: nil, completed: true)
    #expect(!(await first.saveSet(exercise: 0, set: set)))
    let pending = try #require(first.pending)
    #expect(try await h.store.load(authUserID: h.repository.authUserID) == pending)
    await first.close()
    let reopened = h.model()
    await reopened.load()
    #expect(reopened.pending == pending)
    #expect(await reopened.retryPending())
    #expect(reopened.session?.exercises[0].sets.count == 1)
    #expect(reopened.session?.exercises[0].sets.first?.loadKg == 0)
    #expect(reopened.pending == nil)
    let posts = await h.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 3)
    #expect(posts[1].httpBody == posts[2].httpBody)
    #expect(
      posts[1].value(forHTTPHeaderField: "Idempotency-Key")
        == posts[2].value(forHTTPHeaderField: "Idempotency-Key"))
  }

  @Test func concurrentRevisionIsShownInsteadOfOverwritingAnotherClient() async throws {
    let h = try await TrainingNativeHarness.make()
    let model = h.model()
    await model.load()
    #expect(await model.start(dayIndex: 0))
    try await h.server.advanceRevision()
    let before = await h.http.stub.requests.filter { $0.httpMethod == "POST" }.count
    let set = try TrainingExecutionSet(
      id: UUID(), index: 0, repetitions: 8, loadKg: 15.5, durationSeconds: nil, completed: true)
    #expect(!(await model.saveSet(exercise: 0, set: set)))
    #expect(model.session?.revision == 1)
    #expect(model.failure == .changed)
    #expect(model.pending == nil)
    #expect(await h.http.stub.requests.filter { $0.httpMethod == "POST" }.count == before)
  }

  @Test func latePublicationCannotExposeClosedOwner() async throws {
    let h = try await TrainingNativeHarness.make()
    let model = h.model()
    let barrier = ConversationControllerBarrier()
    await h.server.holdNextHome(barrier)
    let work = Task { await model.load() }
    #expect(await barrier.waitEnteredOrFinished())
    model.invalidateSynchronously()
    await barrier.release()
    await work.value
    await model.close()
    #expect(model.isClosed && model.home == nil && model.session == nil && model.pending == nil)
  }

  @Test func pendingFromOldEpochCannotBeTransplantedToNewScope() async throws {
    let h = try await TrainingNativeHarness.make()
    let model = h.model()
    await model.load()
    #expect(await model.start(dayIndex: 0))
    await h.server.loseNextReply()
    let set = try TrainingExecutionSet(
      id: UUID(), index: 0, repetitions: 8, loadKg: nil, durationSeconds: nil, completed: true)
    #expect(!(await model.saveSet(exercise: 0, set: set)))
    let pending = try #require(model.pending)
    try await h.server.changeEpoch()
    let before = await h.http.stub.requests.filter { $0.httpMethod == "POST" }.count
    #expect(!(await model.retryPending()))
    #expect(model.failure == .changed)
    #expect(try await h.store.load(authUserID: h.repository.authUserID) == pending)
    #expect(await h.http.stub.requests.filter { $0.httpMethod == "POST" }.count == before)
  }

  @Test func serverRejectionRetiresOnlyProvenUnappliedCommandButAmbiguousFailureStaysPending()
    async throws
  {
    for code in ["training_execution_revision_conflict", "training_execution_scope_changed"] {
      let h = try await TrainingNativeHarness.make()
      let model = h.model()
      await model.load()
      #expect(await model.start(dayIndex: 0))
      await h.server.rejectNextWrite(code)
      let set = try TrainingExecutionSet(
        id: UUID(), index: 0, repetitions: 8, loadKg: nil, durationSeconds: nil, completed: true)
      #expect(!(await model.saveSet(exercise: 0, set: set)))
      #expect((model.pending == nil) == (code == "training_execution_revision_conflict"))
      #expect(
        (try await h.store.load(authUserID: h.repository.authUserID) == nil)
          == (code == "training_execution_revision_conflict"))
    }
  }
}

@MainActor
struct TrainingNativeHarness {
  let http: ConversationHTTPFixture
  let server: TrainingNativeServer
  let repository: MobileTrainingExecutionRepository
  let store: TrainingExecutionPendingStore
  static func make() async throws -> Self {
    let f = try TrainingExecutionFixture()
    let home = try TrainingExecutionHomeSnapshot(data: f.data("home"))
    let http = try ConversationHTTPFixture()
    await http.lifecycle.replace(
      .init(
        userID: home.scope.authUserID.uuidString.lowercased(), generation: 7,
        bearer: "synthetic-training-138"))
    let server = try TrainingNativeServer(fixture: f)
    await http.stub.respond { request, _ in try await server.reply(request) }
    let repository = try await MobileTrainingExecutionRepository.scoped(
      transport: http.transport, lifecycle: http.lifecycle,
      lease: await http.lifecycle.leaseForRequest())
    let store = try TrainingExecutionPendingStore(
      origin: #require(http.transport.configuredOrigin), security: TrainingNativeSecurity())
    return .init(http: http, server: server, repository: repository, store: store)
  }
  func model() -> TrainingExecutionModel { .init(provider: repository, store: store) }
}

actor TrainingNativeServer {
  // External HTTP substitute only. Native repository, protocol decoders,
  // operation/hash, session lifecycle, model and pending store are real.
  private var homeBytes: Data, state: Data?, receipts: [String: Data] = [:]
  private var created: Data, updated: Data
  private var pages: [Data] = []
  private var beforeSendFailure = false
  private var lose = false, rejection: String?, barrier: ConversationControllerBarrier?
  init(fixture: TrainingExecutionFixture) throws {
    homeBytes = try fixture.data("home")
    created = try fixture.data("created")
    updated = try fixture.data("updated")
  }
  func loseNextReply() { lose = true }
  func failBeforeNextWrite() { beforeSendFailure = true }
  func rejectNextWrite(_ code: String) { rejection = code }
  func holdNextHome(_ value: ConversationControllerBarrier) { barrier = value }
  func advanceRevision() throws {
    var s = try object(state!)
    s["revision"] = (s["revision"] as! Int) + 1
    state = try data(s)
  }
  func abandonFromAnotherClient() throws {
    var s = try object(state!)
    s["revision"] = (s["revision"] as! Int) + 1
    s["phase"] = "abandoned"
    s["updated_at"] = "2026-11-14T20:00:02.000000Z"
    state = try data(s)
  }
  func makeTwoResumePages(staleDuplicate: Bool = false) throws {
    var h = try object(homeBytes)
    let scope = h["scope"] as! [String: Any]
    let plan = h["plan"] as! [String: Any]
    let rows: [[String: Any]] = (1...21).reversed().map { i in
      [
        "id": String(format: "13800000-0000-4000-8000-%012d", i), "revision": 0,
        "local_date": "2026-11-14",
        "started_at": "2026-11-14T20:00:00.000000Z", "updated_at": "2026-11-14T20:00:00.000000Z",
        "plan_id": plan["plan_id"]!, "day_index": 0, "day_label": "Treino sintético",
        "total_exercises": 2, "completed_exercises": 0,
      ]
    }
    var firstRows = Array(rows.prefix(20))
    if staleDuplicate { firstRows[0]["revision"] = 1 }
    h["sessions"] = firstRows
    h["next_cursor"] = [
      "owner_id": scope["owner_id"]!, "epoch": scope["epoch"]!,
      "time_zone": scope["time_zone"]!, "updated_at": "2026-11-14T20:00:00.000000Z",
      "session_id": rows[19]["id"]!,
    ]
    let first = try data(h)
    h["sessions"] = staleDuplicate ? [rows[0]] : [rows[20]]
    h["next_cursor"] = NSNull()
    pages = [first, try data(h)]
  }
  func changeEpoch() throws {
    var h = try object(homeBytes)
    var scope = h["scope"] as! [String: Any]
    var plan = h["plan"] as! [String: Any]
    scope["epoch"] = "13800000-0000-4000-8000-000000000099"
    plan["epoch"] = scope["epoch"]
    h["scope"] = scope
    h["plan"] = plan
    homeBytes = try data(h)
  }
  func reply(_ request: URLRequest) async throws -> ConversationHTTPReply {
    if request.url?.path == "/api/mobile/v1/me" {
      let h = try object(homeBytes)
      let scope = h["scope"] as! [String: Any]
      return try envelope(["id": scope["owner_id"]!])
    }
    if request.httpMethod == "POST" {
      if beforeSendFailure {
        beforeSendFailure = false
        throw URLError(.notConnectedToInternet)
      }
      if let code = rejection {
        rejection = nil
        if code == "training_execution_revision_conflict" { try advanceRevision() }
        return .failure(409, code)
      }
      let command = try object(request.httpBody!)
      let op = command["operation_id"] as! String
      if let old = receipts[op] {
        var r = try object(old)
        r["status"] = "replayed"
        r["session"] = try object(state!)
        r["audit"] = NSNull()
        return try envelope(r)
      }
      let start = command["schema"] as? String == "training.execution.start.v1"
      var result = try object(start ? created : updated)
      var s = start ? result["session"] as! [String: Any] : try object(state!)
      s["id"] = command["session_id"]
      let before = start ? nil : s["revision"] as? Int
      if !start {
        s["revision"] = before! + 1
        s["updated_at"] = "2026-11-14T20:00:01.000000Z"
        let action = command["action"] as! [String: Any]
        if action["kind"] as? String == "save_set" {
          var ex = s["exercises"] as! [[String: Any]]
          let i = action["exercise_index"] as! Int
          ex[i]["sets"] = [action["set"]!]
          s["exercises"] = ex
        }
      }
      state = try data(s)
      var receipt = result["receipt"] as! [String: Any]
      receipt["session_id"] = command["session_id"]
      receipt["operation_id"] = op
      receipt["input_hash"] = SHA256.hash(
        data: try JSONSerialization.data(
          withJSONObject: command, options: [.sortedKeys, .withoutEscapingSlashes])
      ).map { String(format: "%02x", $0) }.joined()
      receipt["before_revision"] = before.map { $0 as Any } ?? NSNull()
      receipt["after_revision"] = s["revision"]
      result["receipt"] = receipt
      result["session"] = s
      receipts[op] = try data(result)
      if lose {
        lose = false
        throw URLError(.networkConnectionLost)
      }
      return try envelope(result)
    }
    if request.url?.path == "/api/mobile/v1/training/execution" {
      if let held = barrier {
        barrier = nil
        await held.enter()
        await held.finish()
      }
      if !pages.isEmpty {
        let index = request.url?.query == nil ? 0 : 1
        return try envelope(object(pages[index]))
      }
      var h = try object(homeBytes)
      if let state {
        let s = try object(state)
        let def = s["definition"] as! [String: Any]
        h["sessions"] = [
          [
            "id": s["id"]!, "revision": s["revision"]!, "local_date": s["local_date"]!,
            "started_at": s["started_at"]!, "updated_at": s["updated_at"]!,
            "plan_id": def["plan_id"]!, "day_index": def["day_index"]!,
            "day_label": def["day_label"]!, "total_exercises": 2, "completed_exercises": 0,
          ]
        ]
        if s["phase"] as? String != "in_progress" { h["sessions"] = [] as [[String: Any]] }
        var scope = h["scope"] as! [String: Any]
        var plan = h["plan"] as! [String: Any]
        scope["observed_at"] = "2026-11-14T20:00:02.000000Z"
        plan["observed_at"] = scope["observed_at"]
        h["scope"] = scope
        h["plan"] = plan
      }
      return try envelope(h)
    }
    guard let state else { return .failure(404, "training_execution_not_found") }
    var scope = try object(homeBytes)["scope"] as! [String: Any]
    scope["observed_at"] = "2026-11-14T20:00:02.000000Z"
    return try envelope([
      "schema": "training.execution-read.v1", "scope": scope, "session": object(state),
    ])
  }
  private func object(_ bytes: Data) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
  }
  private func data(_ raw: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: raw)
  }
  private func envelope(_ raw: [String: Any]) throws -> ConversationHTTPReply {
    .init(
      status: 200,
      body: try data([
        "data": raw, "meta": ["api_version": "v1", "request_id": "training-native-138"],
      ]),
      headers: [
        "Content-Type": "application/json", "X-Training-Execution": "1",
        "Cache-Control": "no-store",
      ])
  }
}
private actor TrainingNativeSecurity: KeychainSecurityClient {
  private var values: [String: Data] = [:]
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

extension TrainingExecutionIntegrationTests {
  @Test func unacceptedStartRecoversAfter404WithoutInventingAnExecutedSession() async throws {
    let h = try await TrainingNativeHarness.make()
    let first = h.model()
    await first.load()
    await h.server.failBeforeNextWrite()
    #expect(!(await first.start(dayIndex: 0)))
    let pending = try #require(first.pending)
    #expect(first.session == nil)
    await first.close()
    let next = h.model()
    await next.load()
    #expect(next.session == nil && next.pending == pending)
    #expect(await next.retryPending())
    #expect(next.session?.id == pending.sessionID)
    #expect(next.session?.exercises.allSatisfy { $0.sets.isEmpty } == true)
  }
  @Test func retryAfterAnotherClientAbandonsKeepsTheCurrentTerminalState() async throws {
    let h = try await TrainingNativeHarness.make()
    let model = h.model()
    await model.load()
    #expect(await model.start(dayIndex: 0))
    await h.server.loseNextReply()
    let set = try TrainingExecutionSet(
      id: UUID(), index: 0, repetitions: 8, loadKg: 15.5, durationSeconds: nil, completed: true)
    #expect(!(await model.saveSet(exercise: 0, set: set)))
    try await h.server.abandonFromAnotherClient()
    #expect(await model.retryPending())
    #expect(
      model.pending == nil && model.session?.phase == .abandoned && model.session?.revision == 2)
    #expect(!model.canEdit)
  }
}

extension TrainingExecutionIntegrationTests {
  @Test func resumePaginationKeepsAllOwnedSessionsWithoutTruncatingAtTwenty() async throws {
    let h = try await TrainingNativeHarness.make()
    let model = h.model()
    try await h.server.makeTwoResumePages()
    await model.load()
    #expect(model.resumableSessions.count == 20 && model.nextCursor != nil)
    await model.loadMore()
    #expect(model.resumableSessions.count == 21 && model.nextCursor == nil)
    #expect(Set(model.resumableSessions.map(\.id)).count == 21)
    let last = try #require(await h.http.stub.requests.last?.url)
    #expect(
      URLComponents(url: last, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) == [
        "cursor"
      ])
  }
  @Test func aConfirmedFreshEpochWithdrawsTheOldSelectedSessionWithoutTransplantingIt() async throws
  {
    let h = try await TrainingNativeHarness.make()
    let model = h.model()
    await model.load()
    #expect(await model.start(dayIndex: 0))
    let old = try #require(model.session?.id)
    try await h.server.changeEpoch()
    await model.load()
    #expect(
      model.session == nil
        && model.home?.scope.epoch.uuidString.lowercased() == "13800000-0000-4000-8000-000000000099"
    )
    #expect(model.failure == .changed && model.pending == nil)
    let urls = await h.http.stub.requests.suffix(1).map { $0.url?.path }
    #expect(!urls.contains("/api/mobile/v1/training/execution/" + old.uuidString.lowercased()))
  }
}

extension TrainingExecutionIntegrationTests {
  @Test func rejectedPaginationPublishesNoPartialScopeOrRows() async throws {
    let h = try await TrainingNativeHarness.make()
    let model = h.model()
    try await h.server.makeTwoResumePages(staleDuplicate: true)
    await model.load()
    let before = try #require(model.home)
    let rows = model.resumableSessions
    let cursor = model.nextCursor
    await model.loadMore()
    #expect(model.failure == .changed)
    #expect(model.home == before && model.resumableSessions == rows && model.nextCursor == cursor)
  }
}
