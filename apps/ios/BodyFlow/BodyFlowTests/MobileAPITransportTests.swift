import Foundation
import Testing

@testable import BodyFlow

@Suite("Mobile API Transport", .serialized)
struct MobileAPITransportTests {
    @Test("same-origin request obtains and sends the current bearer")
    func sendsCurrentBearer() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success())

        let payload: TransportPayload = try await harness.transport.execute(.getToday())
        let requests = await harness.stub.requests()

        #expect(payload == TransportPayload(value: "ok"))
        #expect(requests.count == 1)
        #expect(requests[0].url?.host == "staging.example.test")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer session-alpha")
    }

    @Test("missing token fails closed before network activity")
    func rejectsMissingToken() async throws {
        let harness = try await TransportHarness(tokens: [])

        await #expect(throws: MobileAPITransportError.missingSession) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
        #expect(await harness.stub.requests().isEmpty)
    }

    @Test("token is fetched again for consecutive requests")
    func fetchesRotatedToken() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha", "session-beta"])
        await harness.stub.respond(with: .success())

        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let authorization = await harness.stub.requests().map {
            $0.value(forHTTPHeaderField: "Authorization")
        }

        #expect(authorization == ["Bearer session-alpha", "Bearer session-beta"])
    }

    @Test("a cross-origin request cannot be constructed")
    func cannotConstructCrossOriginRequest() {
        #expect(throws: MobileAPIRequestError.self) {
            try MobileAPIRequest<TransportPayload>(
                method: .get,
                path: "https://other.example.test/api/mobile/v1/today"
            )
        }
    }

    @Test("same-origin API redirect follows without losing authorization")
    func followsApprovedRedirect() async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha"],
            maximumRetryCount: 0
        )
        await harness.stub.respond { request, call in
            if call == 1 {
                return .redirect(
                    from: request.url!,
                    to: URL(string: "https://staging.example.test/api/mobile/v1/profile")!
                )
            }
            return .success()
        }

        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let requests = await harness.stub.requests()

        #expect(requests.count == 2)
        #expect(requests[1].url?.path == "/api/mobile/v1/profile")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer session-alpha")
    }

    @Test("same-origin redirect cannot rewrite a mutation")
    func blocksMutationRedirect() async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha"],
            maximumRetryCount: 0
        )
        await harness.stub.respond { request, _ in
            .redirect(
                from: request.url!,
                to: URL(string: "https://staging.example.test/api/mobile/v1/profile")!
            )
        }
        let request = try MobileAPIRequest<TransportPayload>(
            method: .post,
            path: "/api/mobile/v1/content/item/read",
            body: Data("{\"event\":\"opened\"}".utf8),
            idempotencyKey: try IdempotencyKey(validating: "mobile-redirect-0001")
        )

        await #expect(throws: MobileAPITransportError.redirectNotAllowed) {
            let _: TransportPayload = try await harness.transport.execute(request)
        }
        #expect(await harness.stub.requests().count == 1)
    }

    @Test("cross-origin redirect is blocked before a second request")
    func blocksCrossOriginRedirect() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond { request, _ in
            .redirect(
                from: request.url!,
                to: URL(string: "https://other.example.test/api/mobile/v1/today")!
            )
        }

        await #expect(throws: MobileAPITransportError.redirectNotAllowed) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
        #expect(await harness.stub.requests().count == 1)
    }

    @Test("explicit timeout maps to a typed error without retry")
    func mapsTimeout() async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha"],
            timeout: .milliseconds(30)
        )
        await harness.stub.respond(with: .success(delay: .seconds(1)))

        await #expect(throws: MobileAPITransportError.timeout) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
        #expect(await harness.stub.requests().count == 1)
    }

    @Test("task cancellation remains CancellationError")
    func preservesCancellation() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success(delay: .seconds(1)))
        let transport = harness.transport
        let request = try MobileAPIRequest<TransportPayload>.getToday()
        let task = Task { try await transport.execute(request) }
        await harness.stub.waitForRequests(1)

        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("late protocol success cannot replace cancellation")
    func suppressesLateSuccess() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success(delay: .milliseconds(150), ignoresCancellation: true))
        let transport = harness.transport
        let request = try MobileAPIRequest<TransportPayload>.getToday()
        let task = Task { try await transport.execute(request) }
        await harness.stub.waitForRequests(1)

        task.cancel()
        try? await Task.sleep(for: .milliseconds(250))

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("response body limit is enforced before decoding")
    func rejectsOversizedBody() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"], bodyLimit: 32)
        await harness.stub.respond(with: .init(
            status: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(repeating: 0x61, count: 33)
        ))

        await #expect(throws: MobileAPITransportError.responseTooLarge(limit: 32)) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("default body limit rejects the first byte above 64 KiB")
    func rejectsBodyAboveDefaultLimit() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .init(
            status: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(repeating: 0x61, count: 65_537)
        ))

        await #expect(throws: MobileAPITransportError.responseTooLarge(limit: 65_536)) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("oversized declared content length fails before decode")
    func rejectsOversizedDeclaredContentLength() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .init(
            status: 200,
            headers: [
                "Content-Type": "application/json",
                "Content-Length": "65537",
            ],
            body: Data("not-json".utf8)
        ))

        await #expect(throws: MobileAPITransportError.responseTooLarge(limit: 65_536)) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("invalid JSON maps to a typed decode error")
    func mapsInvalidJSON() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .init(status: 200, body: Data("not-json".utf8)))

        await #expect(throws: MobileAPITransportError.decodingFailure) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("success data and metadata envelope decodes")
    func decodesSuccessEnvelope() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success(requestID: "request-success-0001"))

        let payload: TransportPayload = try await harness.transport.execute(.getToday())

        #expect(payload.value == "ok")
    }

    @Test("success envelope with another API version fails closed")
    func rejectsIncompatibleAPIVersion() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .init(
            status: 200,
            body: Data(
                "{\"data\":{\"value\":\"ok\"},\"meta\":{\"api_version\":\"v2\",\"request_id\":\"request-version-0001\"}}".utf8
            )
        ))

        await #expect(throws: MobileAPITransportError.invalidResponse) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test(
        "error envelope maps stable HTTP categories",
        arguments: [
            ErrorCase(status: 401, code: "invalid_access_token", category: .unauthorized),
            ErrorCase(status: 403, code: "patient_account_inactive", category: .forbidden),
            ErrorCase(status: 409, code: "idempotency_key_conflict", category: .conflict),
            ErrorCase(status: 422, code: "validation_failed", category: .validation),
            ErrorCase(status: 429, code: "rate_limited", category: .rateLimited),
            ErrorCase(status: 503, code: "internal_error", category: .server),
        ]
    )
    func mapsErrorEnvelope(_ errorCase: ErrorCase) async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha"],
            maximumRetryCount: 0
        )
        await harness.stub.respond(with: .failure(
            status: errorCase.status,
            code: errorCase.code,
            requestID: "request-error-0001"
        ))

        do {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
            Issue.record("Expected a typed transport error")
        } catch let error as MobileAPITransportError {
            #expect(error.category == errorCase.category)
        }
    }

    @Test("request ID is safe and attached to every attempt")
    func attachesRequestID() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success())

        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let requestID = try #require(
            await harness.stub.requests().first?.value(forHTTPHeaderField: "X-Request-Id")
        )

        #expect((8...128).contains(requestID.count))
        #expect(requestID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._:-".contains($0)) })
    }

    @Test("mutation receives JSON and one stable idempotency key")
    func attachesMutationHeaders() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success())
        let key = try IdempotencyKey(validating: "mobile-mutation-0001")
        let request = try MobileAPIRequest<TransportPayload>(
            method: .post,
            path: "/api/mobile/v1/content/item/read",
            body: Data("{\"event\":\"opened\"}".utf8),
            idempotencyKey: key
        )

        let _: TransportPayload = try await harness.transport.execute(request)
        let captured = try #require(await harness.stub.requests().first)

        #expect(captured.value(forHTTPHeaderField: "Idempotency-Key") == key.value)
        #expect(captured.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(captured.httpMethod == "POST")
    }

    @Test("safe read retries one transient server failure")
    func retriesSafeRead() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha", "session-alpha"])
        await harness.stub.respond { _, call in
            call == 1 ? .failure(status: 503, code: "internal_error") : .success()
        }

        let _: TransportPayload = try await harness.transport.execute(.getToday())

        #expect(await harness.stub.requests().count == 2)
    }

    @Test("mutation retry preserves the logical idempotency key")
    func preservesKeyAcrossRetry() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha", "session-alpha"])
        await harness.stub.respond { _, call in
            call == 1 ? .failure(status: 503, code: "internal_error") : .success()
        }
        let key = try IdempotencyKey(validating: "mobile-mutation-retry-0001")
        let request = try MobileAPIRequest<TransportPayload>(
            method: .patch,
            path: "/api/mobile/v1/me",
            body: Data("{}".utf8),
            idempotencyKey: key
        )

        let _: TransportPayload = try await harness.transport.execute(request)
        let keys = await harness.stub.requests().map {
            $0.value(forHTTPHeaderField: "Idempotency-Key")
        }

        #expect(keys == [key.value, key.value])
    }

    @Test("validation and decode failures are never retried")
    func doesNotRetryUnsafeFailures() async throws {
        let validationHarness = try await TransportHarness(tokens: ["session-alpha"])
        await validationHarness.stub.respond(with: .failure(status: 422, code: "validation_failed"))
        await #expect(throws: MobileAPITransportError.self) {
            let _: TransportPayload = try await validationHarness.transport.execute(.getToday())
        }
        #expect(await validationHarness.stub.requests().count == 1)

        let decodeHarness = try await TransportHarness(tokens: ["session-alpha"])
        await decodeHarness.stub.respond(with: .init(status: 200, body: Data("private body".utf8)))
        await #expect(throws: MobileAPITransportError.decodingFailure) {
            let _: TransportPayload = try await decodeHarness.transport.execute(.getToday())
        }
        #expect(await decodeHarness.stub.requests().count == 1)
    }

    @Test("diagnostic descriptions redact bearer body and signed URL shaped input")
    func diagnosticDescriptionsAreRedacted() {
        let sensitive = [
            "Bearer session-alpha",
            "person@example.invalid",
            "{\"name\":\"Private Person\"}",
            "https://storage.example.test/object?token=signed-value",
        ]
        let descriptions = [
            MobileAPITransportError.decodingFailure.description,
            MobileAPITransportError.http(
                status: 400,
                code: sensitive.joined(separator: " "),
                requestID: "unsafe request id \(sensitive[0])"
            ).description,
        ]

        for description in descriptions {
            for value in sensitive {
                #expect(!description.contains(value))
            }
        }
    }

    @Test("private patient requests bypass URL cache")
    func disablesPrivateCaching() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success())

        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let request = try #require(await harness.stub.requests().first)

        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }
}

private struct TransportPayload: Codable, Equatable, Sendable {
    let value: String
}

private extension MobileAPIRequest where Response == TransportPayload {
    static func getToday() throws -> Self {
        try MobileAPIRequest(method: .get, path: "/api/mobile/v1/today")
    }
}

struct ErrorCase: Sendable {
    let status: Int
    let code: String
    let category: TransportErrorCategory
}

enum TransportErrorCategory: Sendable {
    case unauthorized
    case forbidden
    case conflict
    case validation
    case rateLimited
    case server
    case other
}

private extension MobileAPITransportError {
    var category: TransportErrorCategory {
        switch self {
        case .unauthorized: .unauthorized
        case .forbidden: .forbidden
        case .conflict: .conflict
        case .validation: .validation
        case .rateLimited: .rateLimited
        case .server: .server
        default: .other
        }
    }
}

private struct TransportHarness: Sendable {
    let stub: TransportStubStore
    let transport: MobileAPITransport

    init(
        tokens: [String],
        timeout: Duration = .seconds(2),
        bodyLimit: Int = 64 * 1_024,
        maximumRetryCount: Int = 1
    ) async throws {
        let stub = TransportStubStore()
        let protocolClass = StubURLProtocol.self
        await protocolClass.install(store: stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        let tokenProvider = RotatingTokenProvider(tokens: tokens)

        self.stub = stub
        self.transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(
                originString: "https://staging.example.test"
            ),
            sessionTokenProvider: tokenProvider,
            session: session,
            clock: ContinuousClock(),
            timeout: timeout,
            responseBodyLimit: bodyLimit,
            maximumRetryCount: maximumRetryCount
        )
    }
}

private actor RotatingTokenProvider: SessionTokenProviding {
    private var tokens: [String]

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func currentBearerToken() -> String? {
        guard !tokens.isEmpty else { return nil }
        return tokens.removeFirst()
    }
}

private struct StubResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data
    let delay: Duration
    let ignoresCancellation: Bool
    let redirectURL: URL?

    init(
        status: Int,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: Data = Data(),
        delay: Duration = .zero,
        ignoresCancellation: Bool = false,
        redirectURL: URL? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
        self.delay = delay
        self.ignoresCancellation = ignoresCancellation
        self.redirectURL = redirectURL
    }

    static func success(
        requestID: String = "request-success-0001",
        delay: Duration = .zero,
        ignoresCancellation: Bool = false
    ) -> StubResponse {
        let body = Data(
            "{\"data\":{\"value\":\"ok\"},\"meta\":{\"api_version\":\"v1\",\"request_id\":\"\(requestID)\"}}".utf8
        )
        return StubResponse(
            status: 200,
            body: body,
            delay: delay,
            ignoresCancellation: ignoresCancellation
        )
    }

    static func failure(
        status: Int,
        code: String,
        requestID: String = "request-error-0001"
    ) -> StubResponse {
        StubResponse(
            status: status,
            body: Data(
                "{\"error\":{\"code\":\"\(code)\",\"message\":\"Synthetic failure\",\"request_id\":\"\(requestID)\",\"details\":{}}}".utf8
            )
        )
    }

    static func redirect(from: URL, to: URL) -> StubResponse {
        StubResponse(
            status: 302,
            headers: ["Location": to.absoluteString],
            redirectURL: to
        )
    }
}

private actor TransportStubStore {
    typealias Handler = @Sendable (URLRequest, Int) async throws -> StubResponse

    private var capturedRequests: [URLRequest] = []
    private var handler: Handler = { _, _ in .success() }

    func respond(with response: StubResponse) {
        handler = { _, _ in response }
    }

    func respond(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func response(for request: URLRequest) async throws -> StubResponse {
        capturedRequests.append(request)
        return try await handler(request, capturedRequests.count)
    }

    func requests() -> [URLRequest] {
        capturedRequests
    }

    func waitForRequests(_ count: Int) async {
        while capturedRequests.count < count {
            await Task.yield()
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registry = StubRegistry()
    private var loadingContext: StubLoadingContext?

    static func install(store: TransportStubStore) async {
        await registry.install(store)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let context = StubLoadingContext(
            protocolInstance: self,
            request: request,
            registry: Self.registry
        )
        loadingContext = context
        context.start()
    }

    override func stopLoading() {
        loadingContext?.cancel()
    }
}

private final class StubLoadingContext: @unchecked Sendable {
    private let protocolInstance: StubURLProtocol
    private let request: URLRequest
    private let registry: StubRegistry
    private let lock = NSLock()
    private var cancelled = false

    init(
        protocolInstance: StubURLProtocol,
        request: URLRequest,
        registry: StubRegistry
    ) {
        self.protocolInstance = protocolInstance
        self.request = request
        self.registry = registry
    }

    func start() {
        Task { await run() }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    private func run() async {
        guard let store = await registry.current() else { return }
        do {
            let stub = try await store.response(for: request)
            try? await Task.sleep(for: stub.delay)
            guard stub.ignoresCancellation || !isCancelled else {
                throw CancellationError()
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.status,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            if let redirectURL = stub.redirectURL {
                var redirected = request
                redirected.url = redirectURL
                protocolInstance.client?.urlProtocol(
                    protocolInstance,
                    wasRedirectedTo: redirected,
                    redirectResponse: response
                )
                return
            }
            protocolInstance.client?.urlProtocol(
                protocolInstance,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            protocolInstance.client?.urlProtocol(protocolInstance, didLoad: stub.body)
            protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
        } catch is CancellationError {
            protocolInstance.client?.urlProtocol(
                protocolInstance,
                didFailWithError: URLError(.cancelled)
            )
        } catch {
            protocolInstance.client?.urlProtocol(
                protocolInstance,
                didFailWithError: error
            )
        }
    }

    private var isCancelled: Bool {
        lock.withLock { cancelled }
    }
}

private actor StubRegistry {
    private var store: TransportStubStore?

    func install(_ store: TransportStubStore) {
        self.store = store
    }

    func current() -> TransportStubStore? {
        store
    }
}
