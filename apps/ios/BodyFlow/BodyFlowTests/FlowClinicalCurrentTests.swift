import Foundation
import Testing

@testable import BodyFlow

@Suite("Current clinical Flow wire and original owner")
struct FlowClinicalCurrentTests {
  @Test func wirePolicyIsOptionalOnlyForLegacyAndNeverAcceptsNullOrUnknownVersion() throws {
    let policy = try Self.policy(restricted: true)
    let history = FlowHistoryResponse(conversationID: "flow", messages: [], clinicalPolicy: policy)
    let bytes = try JSONEncoder().encode(history)
    #expect(
      try JSONDecoder().decode(FlowHistoryResponse.self, from: bytes).clinicalPolicy == policy)
    var raw = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    raw["clinical_policy"] = NSNull()
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        FlowHistoryResponse.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    raw["clinical_policy"] = ["version": 2]
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        FlowHistoryResponse.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    let reply = FlowSendResponse(
      conversationID: "flow", message: Self.reply(), clinicalPolicy: policy)
    var post = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(reply)) as? [String: Any])
    post["clinical_policy"] = NSNull()
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        FlowSendResponse.self, from: JSONSerialization.data(withJSONObject: post))
    }
    #expect(FlowHistoryResponse(conversationID: "flow", messages: []).clinicalPolicy == nil)
  }
  @Test func currentRepositoryNegotiatesBothMethodsAndRejectsMissingPolicyWithoutDowngrade()
    async throws
  {
    let life = FlowClinicalLifecycle()
    let transport = FlowClinicalTransport(policy: try Self.policy(restricted: true))
    let root = MobileFlowChatRepository(
      transport: transport, sessionLifecycle: life, clinicalRepresentation: .currentV1)
    let repo = try await root.scoped(for: "auth-A")
    _ = try await repo.history(limit: 20)
    _ = try await repo.send(
      text: "QA", idempotencyKey: IdempotencyKey(validating: "flow-current-qa"))
    #expect(await transport.queries.count == 2)
    for query in await transport.queries {
      #expect(query.contains(URLQueryItem(name: "clinical_policy", value: "current_clinical_v1")))
    }
    await transport.omitPolicy()
    await #expect(throws: MobileAPITransportError.invalidResponse) {
      try await repo.history(limit: 20)
    }
    await #expect(throws: MobileAPITransportError.invalidResponse) {
      try await repo.send(text: "QA", idempotencyKey: IdempotencyKey(validating: "flow-current-qa"))
    }
  }
  @Test func oldScopeCannotBecomeBOrAWithANewGeneration() async throws {
    let life = FlowClinicalLifecycle()
    let transport = FlowClinicalTransport(policy: try Self.policy(restricted: false))
    let root = MobileFlowChatRepository(
      transport: transport, sessionLifecycle: life, clinicalRepresentation: .currentV1)
    let old = try await root.scoped(for: "auth-A")
    for user in ["auth-B", "auth-A"] {
      await life.replace(user)
      await #expect(throws: (any Error).self) { try await old.history(limit: 20) }
      await #expect(throws: (any Error).self) { try await old.scoped(for: "auth-A") }
    }
    #expect(await transport.queries.isEmpty)
    #expect(await life.leases == 1)
  }
  @Test @MainActor func emptyNewHistoryMasksAllRetainedACKCopiesAndNeverRepostsAcceptedTurn()
    async throws
  {
    let healthy = try Self.policy(restricted: false)
    let restricted = try Self.policy(restricted: true, at: "2026-10-27T13:00:00Z")
    let provider = FlowClinicalSequenceProvider(
      response: .init(
        conversationID: "flow", message: Self.reply(),
        draft: .init(id: "draft", domain: .nutrition), clinicalPolicy: healthy),
      history: .init(conversationID: "flow", messages: [], clinicalPolicy: healthy))
    let model = FlowChatModel(
      userID: "auth-A", provider: provider, keyProvider: RandomIdempotencyKeyProvider())
    model.composer = "QA"
    await model.send()
    #expect(model.messages.first?.content.contains("1800") == true)
    #expect(model.turnDraft != nil && model.outbox.first?.state == .accepted)
    await provider.setHistory(
      .init(conversationID: "flow", messages: [], clinicalPolicy: restricted))
    model.composer = "Próximo texto"
    await model.load()
    #expect(model.clinicalPolicy?.hide.calories == true)
    #expect(model.messages.map(\.id) == ["reply"])
    #expect(model.messages.first?.content.contains("1800") == false)
    #expect(model.outbox.first?.serverReply == model.messages.first)
    #expect(model.outbox.first?.state == .accepted && model.turnDraft == nil)
    #expect(model.composer == "Próximo texto")
    await model.retry()
    #expect(await provider.sends == 1)
  }
  @Test @MainActor
  func officialProjectedMessageSurvivesLaterEmptyGETWhileOldPolicyCannotRestoreContent()
    async throws
  {
    let healthy = try Self.policy(restricted: false)
    let restricted = try Self.policy(restricted: true, at: "2026-10-27T13:00:00Z")
    let provider = FlowClinicalSequenceProvider(
      response: .init(conversationID: "flow", message: Self.reply(), clinicalPolicy: healthy),
      history: .init(conversationID: "flow", messages: [], clinicalPolicy: healthy))
    let model = FlowChatModel(
      userID: "auth-A", provider: provider, keyProvider: RandomIdempotencyKeyProvider())
    model.composer = "QA"
    await model.send()
    let projected = Self.reply(content: "Consumido: 1000 kcal. XP: 150.")
    await provider.setHistory(
      .init(conversationID: "flow", messages: [projected], clinicalPolicy: restricted))
    await model.load()
    #expect(model.messages == [projected])
    await provider.setHistory(
      .init(conversationID: "flow", messages: [], clinicalPolicy: restricted))
    await model.load()
    #expect(model.messages == [projected])
    await provider.setHistory(
      .init(conversationID: "flow", messages: [Self.reply()], clinicalPolicy: healthy))
    await model.load()
    #expect(model.clinicalPolicy == restricted)
    #expect(model.messages.first?.content.contains("1800") == false)
    #expect(await provider.sends == 1)
  }
  @Test @MainActor func modelScopesOnceAndInvalidationPermanentlyClosesOldOwner() async throws {
    let p = FlowClinicalSequenceProvider(
      response: .init(conversationID: "flow", message: Self.reply()),
      history: .init(conversationID: "flow", messages: []))
    let model = FlowChatModel(
      userID: "auth-A", provider: p, keyProvider: RandomIdempotencyKeyProvider())
    await model.load()
    model.composer = "QA"
    await model.send()
    await model.load()
    #expect(await p.scopes == ["auth-A"])
    model.invalidate()
    model.composer = "Old owner must not send"
    await model.send()
    await model.load()
    #expect(await p.sends == 1)
    #expect(model.messages.isEmpty && model.outbox.isEmpty)
  }
  @Test @MainActor func missingOrOlderPolicyHidesCachedGuidanceEvenWhenCurrentPolicyWasHealthy()
    async throws
  {
    let current = try Self.policy(restricted: false, at: "2026-10-27T13:00:00Z")
    let older = try Self.policy(restricted: false)
    for invalid in [nil, older] as [CurrentClinicalPolicy?] {
      let p = FlowClinicalSequenceProvider(
        response: .init(conversationID: "flow", message: Self.reply(), clinicalPolicy: current),
        history: .init(conversationID: "flow", messages: [], clinicalPolicy: current))
      let model = FlowChatModel(
        userID: "auth-A", provider: p, keyProvider: RandomIdempotencyKeyProvider())
      model.composer = "QA"
      await model.send()
      #expect(model.messages.first?.content.contains("1800") == true)
      await p.setHistory(.init(conversationID: "flow", messages: [], clinicalPolicy: invalid))
      await model.load()
      #expect(model.clinicalPolicy == current)
      #expect(model.messages.first?.content.contains("1800") == false)
      #expect(model.outbox.first?.serverReply == model.messages.first)
      #expect(model.outbox.first?.state == .accepted)
      #expect(await p.sends == 1)
    }
  }
  @Test @MainActor func olderPOSTKeepsAcceptanceButCannotPublishItsGuidanceOrDraft() async throws {
    let current = try Self.policy(restricted: false, at: "2026-10-27T13:00:00Z")
    let older = try Self.policy(restricted: false)
    let p = FlowClinicalSequenceProvider(
      response: .init(
        conversationID: "flow", message: Self.reply(),
        draft: .init(id: "draft", domain: .nutrition), clinicalPolicy: older),
      history: .init(conversationID: "flow", messages: [], clinicalPolicy: current))
    let model = FlowChatModel(
      userID: "auth-A", provider: p, keyProvider: RandomIdempotencyKeyProvider())
    await model.load()
    await p.setHistory(.init(conversationID: "flow", messages: [], clinicalPolicy: older))
    model.composer = "QA"
    await model.send()
    #expect(model.messages.first?.content.contains("1800") == false)
    #expect(model.turnDraft == nil && model.outbox.first?.state == .accepted)
    #expect(model.clinicalPolicy == current)
    await model.retry()
    #expect(await p.sends == 1)
  }
  @Test @MainActor func unconfirmedAnchorIsAlsoMaskedWithoutLosingItsRetryIdentity() async throws {
    let healthy = try Self.policy(restricted: false)
    let restricted = try Self.policy(restricted: true, at: "2026-10-27T13:00:00Z")
    let p = FlowClinicalSequenceProvider(
      response: .init(conversationID: "flow", message: Self.reply(), clinicalPolicy: healthy),
      history: .init(conversationID: "flow", messages: [], clinicalPolicy: healthy))
    let model = FlowChatModel(
      userID: "auth-A", provider: p, keyProvider: RandomIdempotencyKeyProvider())
    await p.failNextSend()
    model.composer = "Pending A"
    await model.send()
    let pendingID = try #require(model.outbox.first?.id)
    model.composer = "Accepted B"
    await model.send()
    #expect(model.outbox.first?.followingReply?.content.contains("1800") == true)
    await p.setHistory(.init(conversationID: "flow", messages: [], clinicalPolicy: restricted))
    await model.load()
    let anchor = try #require(model.outbox.first?.followingReply)
    #expect(!anchor.content.contains("1800") && anchor.id == "reply")
    #expect(model.outbox.first?.id == pendingID && model.outbox.first?.state == .unconfirmed)
    #expect(model.outbox.last?.state == .accepted)
    let originalKey = try #require(await p.keys.first)
    await model.retry(outboxID: pendingID)
    #expect(await p.keys.last == originalKey)
  }
  @Test @MainActor func presentationMetadataStaysWithinRetainedHistoryAndACKWindow() async throws {
    let healthy = try Self.policy(restricted: false)
    let p = FlowClinicalSequenceProvider(
      response: .init(conversationID: "flow", message: Self.reply(), clinicalPolicy: healthy),
      history: .init(conversationID: "flow", messages: [], clinicalPolicy: healthy))
    let model = FlowChatModel(
      userID: "auth-A", provider: p, keyProvider: RandomIdempotencyKeyProvider())
    for index in 0..<55 {
      let reply = FlowMessage(
        id: "reply-\(index)", conversationID: "flow", role: .assistant, content: "XP",
        state: .completed, requestID: "request-\(index)",
        createdAt: Date(timeIntervalSince1970: Double(index)))
      await p.setResponse(.init(conversationID: "flow", message: reply, clinicalPolicy: healthy))
      model.composer = "QA \(index)"
      await model.send()
    }
    let metadata = try #require(
      Mirror(reflecting: model).children.first(where: {
        $0.label == "_presentationByID" || $0.label == "presentationByID"
      })?.value as? [String: CurrentClinicalPolicy])
    #expect(model.messages.count == 50 && model.outbox.count == 50)
    #expect(metadata.count == 50 && metadata["reply-0"] == nil)
  }
  @Test(arguments: [false, true]) func lateReplyCannotSurviveAnAccountRoundTrip(isPost: Bool)
    async throws
  {
    let life = FlowClinicalLifecycle()
    let transport = FlowClinicalTransport(policy: try Self.policy(restricted: false))
    let root = MobileFlowChatRepository(
      transport: transport, sessionLifecycle: life, clinicalRepresentation: .currentV1)
    let scoped = try await root.scoped(for: "auth-A")
    await transport.holdNext()
    let request = Task {
      if isPost {
        _ = try await scoped.send(
          text: "QA", idempotencyKey: IdempotencyKey(validating: "late-original-owner"))
      } else {
        _ = try await scoped.history(limit: 50)
      }
    }
    await transport.waitForRequest()
    await life.replace("auth-B")
    await life.replace("auth-A")
    await transport.release()
    await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await request.value }
    #expect(await transport.queries.count == 1)
    #expect(await life.leases == 1)
  }
  @Test func currentRepositoryRefusesUnboundTransportBeforeDispatch() async throws {
    let transport = FlowClinicalTransport(policy: try Self.policy(restricted: false))
    let repo = MobileFlowChatRepository(transport: transport, clinicalRepresentation: .currentV1)
    await #expect(throws: SessionLifecycleError.sessionSuperseded) {
      try await repo.scoped(for: "auth-A")
    }
    await #expect(throws: SessionLifecycleError.sessionSuperseded) {
      try await repo.history(limit: 50)
    }
    await #expect(throws: SessionLifecycleError.sessionSuperseded) {
      try await repo.send(text: "QA", idempotencyKey: IdempotencyKey(validating: "unbound-current"))
    }
    #expect(await transport.queries.isEmpty)
  }
  @Test @MainActor func clinicalMutationDuringPOSTPreservesACKAndComposerUntilFreshGET()
    async throws
  {
    let healthy = try Self.policy(restricted: false)
    let restricted = try Self.policy(restricted: true, at: "2026-10-27T13:00:00Z")
    let p = FlowClinicalSequenceProvider(
      response: .init(
        conversationID: "flow", message: Self.reply(),
        draft: .init(id: "draft", domain: .nutrition), clinicalPolicy: healthy),
      history: .init(conversationID: "flow", messages: [], clinicalPolicy: healthy))
    let model = FlowChatModel(
      userID: "auth-A", provider: p, keyProvider: RandomIdempotencyKeyProvider())
    await model.load()
    await p.holdNextSend()
    model.composer = "Sending A"
    let send = Task { await model.send() }
    await p.waitForSends(1)
    model.composer = "Next C"
    model.suspendClinicalPresentationUntilRefresh()
    await p.setHistoryError(URLError(.notConnectedToInternet))
    await p.releaseSend()
    await send.value
    #expect(model.outbox.first?.state == .accepted && model.turnDraft == nil)
    #expect(model.messages.first?.content.contains("1800") == false)
    #expect(model.outbox.first?.serverReply == model.messages.first && model.composer == "Next C")
    let official = Self.reply(content: "Consumido: 1000 kcal. XP: 150.")
    await p.setHistoryError(nil)
    await p.setHistory(
      .init(conversationID: "flow", messages: [official], clinicalPolicy: restricted))
    await model.retry()
    #expect(model.messages == [official] && model.composer == "Next C")
    #expect(model.outbox.first?.state == .accepted && model.turnDraft == nil)
    #expect(await p.sends == 1)
  }
  static func policy(restricted: Bool, at: String = "2026-10-27T12:00:00Z") throws
    -> CurrentClinicalPolicy
  {
    let object: [String: Any] = [
      "version": 1, "observed_at": at, "assessment": "complete", "recording_allowed": true,
      "pause_weight_loss_guidance": restricted, "professional_assessment_recommended": restricted,
      "phase_selection_pending": false,
      "target_source": restricted ? "unavailable" : "assigned_phase",
      "hide": [
        "objective": restricted, "calories": restricted, "protein": restricted,
        "balance": restricted, "block": restricted,
      ],
    ]
    return try JSONDecoder().decode(
      CurrentClinicalPolicy.self, from: JSONSerialization.data(withJSONObject: object))
  }
  static func reply(content: String = "Meta calórica: 1800 kcal.") -> FlowMessage {
    .init(
      id: "reply", conversationID: "flow", role: .assistant, content: content, state: .completed,
      requestID: "request", createdAt: Date(timeIntervalSince1970: 1000))
  }
}
private actor FlowClinicalTransport: MobileAPIExecuting {
  var policy: CurrentClinicalPolicy?
  var queries: [[URLQueryItem]] = []
  private var hold = false
  private var held: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  init(policy: CurrentClinicalPolicy?) { self.policy = policy }
  func omitPolicy() { policy = nil }
  func execute<Response: Decodable & Sendable>(_ request: MobileAPIRequest<Response>) async throws
    -> Response
  {
    queries.append(request.queryItems)
    started?.resume()
    started = nil
    if hold { await withCheckedContinuation { held = $0 } }
    let bytes =
      request.method == .get
      ? try JSONEncoder().encode(
        FlowHistoryResponse(conversationID: "flow", messages: [], clinicalPolicy: policy))
      : try JSONEncoder().encode(
        FlowSendResponse(
          conversationID: "flow", message: FlowClinicalCurrentTests.reply(), clinicalPolicy: policy)
      )
    return try JSONDecoder().decode(Response.self, from: bytes)
  }
  func holdNext() { hold = true }
  func waitForRequest() async {
    if queries.isEmpty { await withCheckedContinuation { started = $0 } }
  }
  func release() {
    hold = false
    held?.resume()
    held = nil
  }
}
private actor FlowClinicalSequenceProvider: FlowChatProviding {
  var response: FlowSendResponse
  var currentHistory: FlowHistoryResponse
  var scopes: [String] = []
  var sends = 0
  var keys: [String] = []
  var shouldFail = false
  var historyError: URLError?
  private var holdSend = false
  private var heldSend: CheckedContinuation<Void, Never>?
  private var sendWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  init(response: FlowSendResponse, history: FlowHistoryResponse) {
    self.response = response
    currentHistory = history
  }
  func scoped(for userID: String) async throws -> any FlowChatProviding {
    scopes.append(userID)
    return self
  }
  func history(limit: Int) async throws -> FlowHistoryResponse {
    if let historyError { throw historyError }
    return currentHistory
  }
  func send(text: String, idempotencyKey: IdempotencyKey) async throws -> FlowSendResponse {
    sends += 1
    keys.append(idempotencyKey.value)
    let ready = sendWaiters.filter { $0.0 <= sends }
    sendWaiters.removeAll { $0.0 <= sends }
    for waiter in ready { waiter.1.resume() }
    if shouldFail {
      shouldFail = false
      throw URLError(.timedOut)
    }
    let acknowledged = response
    if holdSend { await withCheckedContinuation { heldSend = $0 } }
    return acknowledged
  }
  func setHistory(_ value: FlowHistoryResponse) { currentHistory = value }
  func setResponse(_ value: FlowSendResponse) { response = value }
  func failNextSend() { shouldFail = true }
  func setHistoryError(_ value: URLError?) { historyError = value }
  func holdNextSend() { holdSend = true }
  func waitForSends(_ count: Int) async {
    if sends < count { await withCheckedContinuation { sendWaiters.append((count, $0)) } }
  }
  func releaseSend() {
    holdSend = false
    heldSend?.resume()
    heldSend = nil
  }
}
private actor FlowClinicalLifecycle: SessionLifecycleProviding {
  var user = "auth-A", generation: UInt64 = 1, leases = 0
  func currentBearerToken() async -> String? { "synthetic" }
  func leaseForRequest() async throws -> SessionLease {
    leases += 1
    return .init(userID: user, generation: generation, bearer: "synthetic")
  }
  func validate(_ lease: SessionLease) async throws {
    guard lease.userID == user && lease.generation == generation else {
      throw SessionLifecycleError.sessionSuperseded
    }
  }
  func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
    try await validate(lease)
    return lease
  }
  func signOut() async -> RemoteRevocationOutcome {
    generation += 1
    return .confirmed
  }
  func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws
    -> UUID
  {
    try await validate(lease)
    return UUID()
  }
  func finishPatientWork(_ id: UUID) async {}
  func replace(_ value: String) {
    user = value
    generation += 1
  }
}
