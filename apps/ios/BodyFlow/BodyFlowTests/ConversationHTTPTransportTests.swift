import Foundation
import Testing
@testable import BodyFlow

@Suite("Conversation HTTP uses the existing authenticated transport", .serialized)
struct ConversationHTTPTransportTests {
    @Test func boundMediaPreservesOriginalOwnerBodyKeyAndNeverReplaysUnauthorizedMutation() async throws {
        let f = try ConversationHTTPFixture()
        await f.stub.respond { _, _ in .failure(401, "unauthorized") }
        let body = Data(#"{"kind":"meal_photo","mime_type":"image/jpeg","size_bytes":20}"#.utf8)
        let request = try MobileAPIRequest<ConversationHTTPValue>(method: .post, path: "/api/mobile/v1/media", body: body,
            idempotencyKey: IdempotencyKey(validating: "cmedia1:00000000-0000-4000-8000-000000000001:create"))
            .withConversationMediaOwner(f.ownerID)
        await #expect(throws: (any Error).self) { try await f.transport.executeHTTP(request) }
        let sent = await f.stub.requests
        #expect(sent.count == 1 && sent[0].httpBody == body)
        #expect(sent[0].value(forHTTPHeaderField: "X-Conversation-Owner") == f.ownerID.uuidString.lowercased())
        #expect(sent[0].value(forHTTPHeaderField: "Idempotency-Key") == "cmedia1:00000000-0000-4000-8000-000000000001:create")
        #expect(await f.lifecycle.refreshCount == 0)
    }

    @Test func mediaOwnerPreconditionCannotEscapeMediaRoutesOrRetagItself() throws {
        let owner = UUID(), other = UUID()
        let valid = try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/media/10000000-0000-4000-8000-000000000001").withConversationMediaOwner(owner)
        #expect(throws: MobileAPIRequestError.invalidConversationHeaders) { try valid.withConversationMediaOwner(other) }
        for path in ["/api/mobile/v1/me", "/api/mobile/v1/media/../me", "/api/mobile/v1/media/not-uuid", "/api/mobile/v1/media/10000000-0000-4000-8000-000000000001/private"] {
            #expect(throws: (any Error).self) { try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: path).withConversationMediaOwner(owner) }
        }
        #expect(throws: MobileAPIRequestError.invalidConversationHeaders) {
            try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/media/10000000-0000-4000-8000-000000000001", queryItems: [.init(name: "owner", value: other.uuidString)]).withConversationMediaOwner(owner)
        }
    }

    @Test func exactProtocolHeadersAndOriginalBodyAreSentOnce() async throws {
        let f = try ConversationHTTPFixture()
        await f.stub.respond { _, _ in .success() }
        let command = try ConversationMealCommand(source: .text("arroz200g"))
        let request = try MobileAPIRequest<ConversationHTTPValue>(method: .post, path: "/api/mobile/v1/conversation/meal-commands", body: command.wireBody,
            idempotencyKey: IdempotencyKey(validating: command.idempotencyKey), conversation: .submit(epoch: f.epoch, ownerID: f.ownerID), unauthorizedReplay: .never)
        let response = try await f.transport.executeHTTP(request)
        #expect(response.statusCode == 200 && response.data.value == "ok")
        let requests = await f.stub.requests
        #expect(requests.count == 1)
        #expect(requests[0].httpBody == command.wireBody)
        #expect(requests[0].value(forHTTPHeaderField: "Idempotency-Key") == command.idempotencyKey)
        #expect(requests[0].value(forHTTPHeaderField: "X-Conversation-Protocol") == "meal-command-v1")
        #expect(requests[0].value(forHTTPHeaderField: "X-Conversation-Epoch") == f.epoch.uuidString.lowercased())
        #expect(requests[0].value(forHTTPHeaderField: "X-Conversation-Input-Hash") == nil)
        #expect(requests[0].value(forHTTPHeaderField: "X-Conversation-Owner") == f.ownerID.uuidString.lowercased())
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-initial")
    }

    @Test func command401NeverRefreshesOrPhysicallyReplaysButLegacyBehaviorRemains() async throws {
        let f = try ConversationHTTPFixture()
        await f.stub.respond { _, attempt in attempt == 1 ? .failure(401, "invalid_access_token") : .success() }
        let command = try ConversationMealCommand(source: .text("meal"))
        let request = try MobileAPIRequest<ConversationHTTPValue>(method: .post, path: "/api/mobile/v1/conversation/meal-commands", body: command.wireBody,
            idempotencyKey: IdempotencyKey(validating: command.idempotencyKey), conversation: .submit(epoch: f.epoch, ownerID: f.ownerID), unauthorizedReplay: .never)
        await #expect(throws: MobileAPITransportError.unauthorized(code: "invalid_access_token", requestID: "conversation-error-0001")) { try await f.transport.executeHTTP(request) }
        #expect(await f.stub.requests.count == 1)
        #expect(await f.lifecycle.refreshCount == 0)
        let legacy = try ConversationHTTPFixture()
        await legacy.stub.respond { _, attempt in attempt == 1 ? .failure(401, "expired") : .success() }
        let old = try MobileAPIRequest<ConversationHTTPValue>(method: .post, path: "/api/mobile/v1/test", body: command.wireBody, idempotencyKey: IdempotencyKey(validating: command.idempotencyKey))
        _ = try await legacy.transport.execute(old)
        #expect(await legacy.stub.requests.count == 2)
        #expect(await legacy.lifecycle.refreshCount == 1)
        #expect(await legacy.stub.requests.allSatisfy { $0.httpBody == command.wireBody && $0.value(forHTTPHeaderField: "Idempotency-Key") == command.idempotencyKey })
    }

    @Test func statusAndReadonlyReconciliationHeadersArePreserved() async throws {
        let f = try ConversationHTTPFixture()
        await f.stub.respond { _, _ in .success(status: 202) }
        let command = try ConversationMealCommand(source: .text("meal"))
        let request = try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/conversation/meal-commands/\(command.commandID.uuidString.lowercased())",
            conversation: .reconciliation(epoch: f.epoch, ownerID: f.ownerID, inputHash: command.inputHash))
        let response = try await f.transport.executeHTTP(request)
        #expect(response.statusCode == 202)
        #expect(response.meta.requestID == "conversation-success-0001")
        let sent = try #require(await f.stub.requests.first)
        #expect(sent.httpMethod == "GET" && sent.httpBody == nil)
        #expect(sent.value(forHTTPHeaderField: "X-Conversation-Input-Hash") == command.inputHash)
        #expect(sent.value(forHTTPHeaderField: "Idempotency-Key") == nil)
    }

    @Test func newProtocolEnvelopeIsClosedWithoutChangingLegacyAdditiveReads() async throws {
        let f = try ConversationHTTPFixture()
        let body = Data(#"{"data":{"value":"ok"},"meta":{"api_version":"v1","request_id":"conversation-success-0001","private_extra":"synthetic"}}"#.utf8)
        await f.stub.respond { _, _ in .init(status: 200, body: body) }
        let closed = try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/conversation/session", conversation: .session)
        await #expect(throws: MobileAPITransportError.invalidResponse) { try await f.transport.executeHTTP(closed) }
        let legacy = try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/test")
        #expect(try await f.transport.execute(legacy).value == "ok")
    }

    @Test func typedHeadersCannotOverrideAuthOrOptIntoAnUnrelatedRouteOrReplay() throws {
        let f = try ConversationHTTPFixture()
        #expect(throws: MobileAPIRequestError.self) { try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/today", conversation: .session) }
        #expect(throws: MobileAPIRequestError.self) { try MobileAPIRequest<ConversationHTTPValue>(method: .post, path: "/api/mobile/v1/conversation/meal-commands", body: Data("{}".utf8), conversation: .submit(epoch: f.epoch, ownerID: f.ownerID), unauthorizedReplay: .never) }
        #expect(throws: MobileAPIRequestError.self) { try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/conversation/session", queryItems: [.init(name: "owner", value: "untrusted")], conversation: .session) }
        #expect(throws: MobileAPIRequestError.self) { try MobileAPIRequest<ConversationHTTPValue>(method: .post, path: "/api/mobile/v1/conversation/meal-commands", body: Data("{}".utf8), idempotencyKey: IdempotencyKey(validating: "cmsg1:\(UUID().uuidString.lowercased())"), conversation: .submit(epoch: f.epoch, ownerID: f.ownerID)) }
    }

    @Test func conversationGETNeverRedirectsWhileLegacySameOriginGETStillWorks() async throws {
        let f = try ConversationHTTPFixture()
        await f.stub.respond { request, attempt in
            if attempt == 1 {
                let target = try #require(URL(string: "/api/mobile/v1/test-final", relativeTo: request.url)?.absoluteURL)
                return .init(status: 302, body: Data(), headers: ["Location": target.absoluteString], redirectURL: target)
            }
            return .success()
        }
        let request = try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/conversation/session", conversation: .session)
        await #expect(throws: MobileAPITransportError.redirectNotAllowed) { try await f.transport.executeHTTP(request) }
        #expect(await f.stub.requests.count == 1)
        let legacy = try ConversationHTTPFixture()
        await legacy.stub.respond { request, attempt in
            if attempt == 1 {
                let target = try #require(URL(string: "/api/mobile/v1/test-final", relativeTo: request.url)?.absoluteURL)
                return .init(status: 302, body: Data(), headers: ["Location": target.absoluteString], redirectURL: target)
            }
            return .success()
        }
        let old = try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/test-start")
        #expect(try await legacy.transport.execute(old).value == "ok")
        #expect(await legacy.stub.requests.count == 2)
    }

    @Test func largerNewProtocolResponseDoesNotRaiseTheLegacyLimit() async throws {
        let f = try ConversationHTTPFixture()
        let body = try JSONSerialization.data(withJSONObject: ["data": ["value": String(repeating: "x", count: 100_000)], "meta": ["api_version": "v1", "request_id": "conversation-success-0001"]])
        await f.stub.respond { _, _ in .init(status: 200, body: body) }
        let request = try MobileAPIRequest<ConversationHTTPValue>(method: .get, path: "/api/mobile/v1/conversation/session", conversation: .session)
        #expect(try await f.transport.withResponseBodyLimit(262_144).executeHTTP(request).data.value.count == 100_000)
        await #expect(throws: MobileAPITransportError.responseTooLarge(limit: 65_536)) { try await f.transport.executeHTTP(request) }
    }
}

struct ConversationHTTPValue: Decodable, Sendable { let value: String }
extension ConversationHTTPTransportTests {
    private static var initializedSessionReply: ConversationHTTPReply {
        .init(status: 200, body: Data(#"{"data":{"schema":"conversation.session.v1","auth_user_id":"90000000-0000-4000-8000-000000000001","owner_id":"10000000-0000-4000-8000-000000000001","epoch":"50000000-0000-4000-8000-000000000001","observed_at":"2026-11-16T01:00:00.000001Z","meal_command_protocol":"conversation.command.v1"},"meta":{"api_version":"v1","request_id":"session-initialization-test"}}"#.utf8), headers: ["Content-Type":"application/json", "Cache-Control":"no-store", "X-Conversation-Protocol":"meal-command-v1"])
    }
    @Test func legacyMissingEpochUsesOneExplicitInitializationWithTheSameAuthLease() async throws {
        let f = try ConversationHTTPFixture(), lease = try await f.lifecycle.leaseForRequest()
        await f.stub.respond { request, attempt in
            if attempt == 1 { return .failure(409, "conversation_session_initialization_required") }
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/mobile/v1/conversation/session")
            #expect(request.httpBody == Data(#"{"schema":"conversation.session-initialization.v1"}"#.utf8))
            #expect(request.value(forHTTPHeaderField:"Idempotency-Key") == "conversation-session-initialize-v1")
            #expect(request.value(forHTTPHeaderField:"Authorization") == "Bearer synthetic-initial")
            return Self.initializedSessionReply
        }
        let repository = try await MobileConversationCommandRepository.scoped(transport:f.transport, lease:lease)
        let result = try await repository.session()
        #expect(result.ownerID == f.ownerID && result.epoch == f.epoch)
        let requests = await f.stub.requests
        #expect(requests.map(\.httpMethod) == ["GET","POST"])
        #expect(await f.lifecycle.refreshCount == 0)
    }
    @Test(arguments: [503,409]) func unrelatedSessionFailureNeverInitializes(_ status:Int) async throws {
        let f = try ConversationHTTPFixture(), lease = try await f.lifecycle.leaseForRequest()
        await f.stub.respond { _, _ in .failure(status,"conversation_command_unavailable") }
        let repository = try await MobileConversationCommandRepository.scoped(transport:f.transport,lease:lease)
        let expected: MobileAPITransportError = status == 409
            ? .conflict(code:"conversation_command_unavailable",requestID:"conversation-error-0001")
            : .server(status:status,code:"conversation_command_unavailable",requestID:"conversation-error-0001")
        await #expect(throws: expected) { try await repository.session() }
        #expect(await f.stub.requests.count == 1)
    }
    @Test func existingConversationSessionRemainsASingleRead() async throws {
        let f = try ConversationHTTPFixture(), lease = try await f.lifecycle.leaseForRequest()
        await f.stub.respond { _, _ in Self.initializedSessionReply }
        let repository = try await MobileConversationCommandRepository.scoped(transport:f.transport,lease:lease)
        #expect(try await repository.session().epoch == f.epoch)
        #expect(await f.stub.requests.map(\.httpMethod) == ["GET"])
    }
    @Test func unauthorizedInitializationIsNotRefreshedOrReplayed() async throws {
        let f = try ConversationHTTPFixture(), lease = try await f.lifecycle.leaseForRequest()
        await f.stub.respond { _, attempt in attempt == 1 ? .failure(409,"conversation_session_initialization_required") : .failure(401,"unauthorized") }
        let repository = try await MobileConversationCommandRepository.scoped(transport:f.transport,lease:lease)
        await #expect(throws: (any Error).self) { try await repository.session() }
        #expect(await f.stub.requests.map(\.httpMethod) == ["GET","POST"])
        #expect(await f.lifecycle.refreshCount == 0)
    }
    @Test func sessionInitializationRequestIsClosedAndRequiresExplicitNonReplay() throws {
        let body = Data(#"{"schema":"conversation.session-initialization.v1"}"#.utf8)
        let key = try IdempotencyKey(validating:"conversation-session-initialize-v1")
        #expect(throws: MobileAPIRequestError.self) { try MobileAPIRequest<ConversationSessionSnapshot>(method:.post,path:"/api/mobile/v1/conversation/session",body:body,idempotencyKey:key,conversation:.sessionInitialization) }
        #expect(throws: MobileAPIRequestError.self) { try MobileAPIRequest<ConversationSessionSnapshot>(method:.post,path:"/api/mobile/v1/conversation/session",queryItems:[.init(name:"owner",value:"foreign")],body:body,idempotencyKey:key,conversation:.sessionInitialization,unauthorizedReplay:.never) }
        #expect(throws: MobileAPIRequestError.self) { try MobileAPIRequest<ConversationSessionSnapshot>(method:.post,path:"/api/mobile/v1/conversation/session",body:Data("{}".utf8),idempotencyKey:key,conversation:.sessionInitialization,unauthorizedReplay:.never) }
        #expect(throws: MobileAPIRequestError.self) { try MobileAPIRequest<ConversationSessionSnapshot>(method:.post,path:"/api/mobile/v1/today",body:body,idempotencyKey:key,conversation:.sessionInitialization,unauthorizedReplay:.never) }
    }
    @Test func lostInitializationResponseIsNotAutomaticallyPostedAgain() async throws {
        let f = try ConversationHTTPFixture(), lease = try await f.lifecycle.leaseForRequest()
        await f.stub.respond { _, attempt in
            if attempt == 1 { return .failure(409,"conversation_session_initialization_required") }
            throw URLError(.networkConnectionLost)
        }
        let repository = try await MobileConversationCommandRepository.scoped(transport:f.transport,lease:lease)
        await #expect(throws: (any Error).self) { try await repository.session() }
        #expect(await f.stub.requests.map(\.httpMethod) == ["GET","POST"])
        await f.stub.respond { _, _ in Self.initializedSessionReply }
        #expect(try await repository.session().epoch == f.epoch)
        #expect(await f.stub.requests.map(\.httpMethod) == ["GET","POST","GET"])
    }
    @Test func accountSwitchBeforeInitializationCannotStartThePost() async throws {
        let f = try ConversationHTTPFixture(), lease = try await f.lifecycle.leaseForRequest()
        await f.stub.respond { _, _ in
            await f.lifecycle.replace(.init(userID:"90000000-0000-4000-8000-000000000099",generation:8,bearer:"synthetic-other-account"))
            return .failure(409,"conversation_session_initialization_required")
        }
        let repository = try await MobileConversationCommandRepository.scoped(transport:f.transport,lease:lease)
        await #expect(throws: (any Error).self) { try await repository.session() }
        #expect(await f.stub.requests.map(\.httpMethod) == ["GET"])
    }
    @Test func neutralConversationInitializesThenReadsItsOwnProtocolWithoutAFakeMeal() async throws {
        let f = try ConversationHTTPFixture(), lease = try await f.lifecycle.leaseForRequest()
        await f.stub.respond { request, attempt in
            if attempt == 1 { return .failure(409,"conversation_session_initialization_required") }
            if attempt == 2 { return Self.initializedSessionReply }
            #expect(request.url?.path == "/api/mobile/v1/conversation/intakes/session")
            return .init(status:200,body:Data(#"{"data":{"schema":"conversation.intake-session.v1","auth_user_id":"90000000-0000-4000-8000-000000000001","owner_id":"10000000-0000-4000-8000-000000000001","epoch":"50000000-0000-4000-8000-000000000001","observed_at":"2026-11-16T01:00:00.000002Z","intake_protocol":"conversation.intake.v1"},"meta":{"api_version":"v1","request_id":"neutral-session-initialization-test"}}"#.utf8),headers:["Content-Type":"application/json","X-Conversation-Protocol":"intake-v1"])
        }
        let repository = try await MobileConversationIntakeRepository.scoped(transport:f.transport,lease:lease)
        let result = try await repository.session()
        #expect(result.ownerID == f.ownerID && result.epoch == f.epoch)
        #expect(await f.stub.requests.map(\.httpMethod) == ["GET","POST","GET"])
    }
    @Test(arguments: ["owner","epoch","time"]) func neutralReopenCannotAdoptChangedInitializationScope(_ change:String) async throws {
        let f = try ConversationHTTPFixture(), lease = try await f.lifecycle.leaseForRequest()
        await f.stub.respond { _, attempt in
            if attempt == 1 { return .failure(409,"conversation_session_initialization_required") }
            if attempt == 2 { return Self.initializedSessionReply }
            var body = String(decoding:Self.initializedSessionReply.body,as:UTF8.self)
                .replacingOccurrences(of:"conversation.session.v1",with:"conversation.intake-session.v1")
                .replacingOccurrences(of:"meal_command_protocol",with:"intake_protocol")
                .replacingOccurrences(of:"conversation.command.v1",with:"conversation.intake.v1")
            switch change {
            case "owner": body = body.replacingOccurrences(of:"10000000-0000-4000-8000-000000000001",with:"10000000-0000-4000-8000-000000000099")
            case "epoch": body = body.replacingOccurrences(of:"50000000-0000-4000-8000-000000000001",with:"50000000-0000-4000-8000-000000000099")
            default: body = body.replacingOccurrences(of:"01:00:00.000001Z",with:"00:59:59.000001Z")
            }
            return .init(status:200,body:Data(body.utf8),headers:["Content-Type":"application/json","X-Conversation-Protocol":"intake-v1"])
        }
        let repository = try await MobileConversationIntakeRepository.scoped(transport:f.transport,lease:lease)
        await #expect(throws:MobileAPITransportError.invalidResponse) { try await repository.session() }
        #expect(await f.stub.requests.map(\.httpMethod) == ["GET","POST","GET"])
    }
}

struct ConversationHTTPFixture: Sendable {
    let stub: ConversationHTTPStub
    let lifecycle: ConversationHTTPTestLifecycle
    let transport: MobileAPITransport
    let ownerID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let epoch = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    init(lifecycle: ConversationHTTPTestLifecycle = .init(), timeout: Duration = .seconds(2)) throws {
        let value = try Self.makeTransport(lifecycle: lifecycle, timeout: timeout)
        stub = value.stub; transport = value.transport; self.lifecycle = lifecycle
    }
    static func makeTransport(lifecycle: any SessionLifecycleProviding, timeout: Duration = .seconds(2)) throws -> (stub: ConversationHTTPStub, transport: MobileAPITransport) {
        let host = "\(UUID().uuidString.lowercased()).conversation.invalid", stub = ConversationHTTPStub()
        let transport = MobileAPITransport(configuration: try MobileAPIConfiguration(originString: "https://\(host)"), sessionLifecycle: lifecycle,
            session: makeSession(host: host, stub: stub), clock: ContinuousClock(), timeout: timeout)
        return (stub, transport)
    }
    static func makeSession(host: String, stub: ConversationHTTPStub) -> URLSession {
        ConversationHTTPURLProtocol.install(stub, host: host)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConversationHTTPURLProtocol.self]
        return URLSession(configuration: config)
    }
}
struct ConversationHTTPReply: Sendable {
    let status: Int
    let body: Data
    var headers: [String: String] = ["Content-Type": "application/json"]
    var redirectURL: URL? = nil
    static func success(status: Int = 200) -> Self { .init(status: status, body: Data(#"{"data":{"value":"ok"},"meta":{"api_version":"v1","request_id":"conversation-success-0001"}}"#.utf8)) }
    static func failure(_ status: Int, _ code: String) -> Self { .init(status: status, body: Data("{\"error\":{\"code\":\"\(code)\",\"message\":\"Synthetic\",\"request_id\":\"conversation-error-0001\"}}".utf8)) }
}
actor ConversationHTTPStub {
    private(set) var requests: [URLRequest] = []
    private var handler: @Sendable (URLRequest, Int) async throws -> ConversationHTTPReply = { _, _ in throw URLError(.notConnectedToInternet) }
    func respond(_ handler: @escaping @Sendable (URLRequest, Int) async throws -> ConversationHTTPReply) { self.handler = handler }
    func reply(_ request: URLRequest) async throws -> ConversationHTTPReply {
        // URLSession may hand URLProtocol the body as a stream. Read the
        // actual received bytes at this synthetic server boundary; do not
        // infer them from the command fixture or weaken byte equality.
        var received = request
        if received.httpBody == nil, let stream = received.httpBodyStream {
            stream.open(); defer { stream.close() }
            var body = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            received.httpBody = body
        }
        requests.append(received)
        return try await handler(received, requests.count)
    }
}
actor ConversationHTTPTestLifecycle: SessionLifecycleProviding {
    private var lease = SessionLease(userID: "90000000-0000-4000-8000-000000000001", generation: 7, bearer: "synthetic-initial")
    private var work: [UUID: @Sendable () -> Void] = [:]
    private let finished = AsyncStream<UUID>.makeStream()
    private var nextVisibleBarrier: ConversationControllerBarrier?
    func holdNextVisible(_ barrier: ConversationControllerBarrier) { nextVisibleBarrier = barrier }
    private(set) var refreshCount = 0
    var workCount: Int { work.count }
    var workIDs: Set<UUID> { Set(work.keys) }
    var finishedWorkEvents: AsyncStream<UUID> { finished.stream }
    func leaseForRequest() -> SessionLease { lease }
    func currentBearerToken() -> String? { lease.bearer }
    func validate(_ value: SessionLease) throws { guard value.userID == lease.userID, value.generation == lease.generation else { throw SessionLifecycleError.sessionSuperseded } }
    func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease { try validate(lease); refreshCount += 1; self.lease = .init(userID: lease.userID, generation: lease.generation, bearer: "synthetic-rotated"); return self.lease }
    func replace(_ next: SessionLease) { lease = next; let callbacks = work.values; work.removeAll(); callbacks.forEach { $0() } }
    func signOut() -> RemoteRevocationOutcome { .confirmed }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) throws -> UUID { try validate(lease); let id = UUID(); work[id] = cancel; return id }
    func finishPatientWork(_ id: UUID) { work.removeValue(forKey: id); finished.continuation.yield(id) }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease, operation: @Sendable () throws -> Value) throws -> Value { try validate(lease); return try operation() }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease, operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try validate(lease)
        if let barrier = nextVisibleBarrier { nextVisibleBarrier = nil; await barrier.enter() }
        try validate(lease)
        return try await MainActor.run(body: operation)
    }
}
private final class ConversationHTTPRegistry: @unchecked Sendable {
    private let lock = NSLock(); private var stores: [String: ConversationHTTPStub] = [:]
    func install(_ store: ConversationHTTPStub, host: String) { lock.withLock { stores[host] = store } }
    func lookup(_ host: String?) -> ConversationHTTPStub? { lock.withLock { host.flatMap { stores[$0] } } }
}
private final class ConversationHTTPURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registry = ConversationHTTPRegistry()
    private let lock = NSLock(); private var stopped = false
    static func install(_ stub: ConversationHTTPStub, host: String) { registry.install(stub, host: host) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task {
            do {
                guard let store = Self.registry.lookup(request.url?.host) else { throw URLError(.dataNotAllowed) }
                let value = try await store.reply(request)
                guard !lock.withLock({ stopped }) else { return }
                guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: value.status, httpVersion: "HTTP/1.1", headerFields: value.headers) else { throw URLError(.badServerResponse) }
                if let redirectURL = value.redirectURL {
                    var redirected = request; redirected.url = redirectURL
                    client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
                    return
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: value.body); client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { lock.withLock { stopped = true } }
}
