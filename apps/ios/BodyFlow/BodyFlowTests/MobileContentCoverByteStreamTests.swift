import Foundation
import Testing

@testable import BodyFlow

@Suite("Mobile content cover byte stream", .serialized)
struct MobileContentCoverByteStreamTests {
    private static let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0x41, count: 40_000))

    private func makeStream(
        bearer: String = "bearer-test-value",
        timeout: TimeInterval = 30,
        handler: @escaping CoverURLProtocol.Handler
    ) async throws -> (MobileContentCoverByteStream, CoverLifecycleStub, ContentCoverTransportRequest) {
        await CoverURLProtocol.install(handler)
        let configuration = try MobileAPIConfiguration(originString: "https://staging.example.test")
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [CoverURLProtocol.self]
        let lifecycle = CoverLifecycleStub(bearer: bearer)
        let stream = MobileContentCoverByteStream(
            configuration: configuration,
            sessionLifecycle: lifecycle,
            session: URLSession(configuration: sessionConfiguration),
            timeout: timeout
        )
        let origin = try ContentCoverTrustedOrigin(validating: configuration.origin)
        let request = try ContentCoverRequestResolver(trustedOrigin: origin).resolve(
            try ContentCoverPath(validating: "/api/mobile/v1/content/covers/abc_DEF-123")
        )
        return (stream, lifecycle, request)
    }

    @Test("the cover request carries the bearer, the image accept list and no cookies or cache")
    func requestCarriesBearerAndStreamsBytes() async throws {
        let (stream, lifecycle, request) = try await makeStream { urlRequest in
            #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer bearer-test-value")
            #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "image/jpeg, image/png, image/webp")
            #expect(urlRequest.value(forHTTPHeaderField: "X-Request-Id")?.isEmpty == false)
            #expect(urlRequest.url?.absoluteString == "https://staging.example.test/api/mobile/v1/content/covers/abc_DEF-123")
            #expect(urlRequest.httpMethod == "GET")
            return .response(
                status: 200,
                headers: ["Content-Type": "image/png", "Cache-Control": "private, max-age=240", "Content-Length": String(Self.pngBytes.count)],
                body: Self.pngBytes
            )
        }

        let response = try await stream.stream(request)

        #expect(response.statusCode == 200)
        #expect(response.mimeType == "image/png")
        #expect(response.declaredLength == Int64(Self.pngBytes.count))
        #expect(response.cacheMaxAgeSeconds == 240)
        #expect(response.redirectLocation == nil)
        var received = Data()
        for try await chunk in response.chunks {
            received.append(chunk)
        }
        #expect(received == Self.pngBytes)
        let work = await lifecycle.work
        #expect(work.began.count == 1)
        #expect(work.finished == work.began)
    }

    @Test("a URL outside the trusted origin never gets a bearer")
    func foreignOriginFailsClosed() async throws {
        let (stream, lifecycle, _) = try await makeStream { _ in
            Issue.record("no request may leave for a foreign origin")
            return .response(status: 200, headers: [:], body: Data())
        }
        let foreign = try ContentCoverRequestResolver(
            trustedOrigin: try ContentCoverTrustedOrigin(validating: URL(string: "https://attacker.example.test")!)
        ).resolve(try ContentCoverPath(validating: "/api/mobile/v1/content/covers/abc_DEF-123"))

        await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try await stream.stream(foreign)
        }
        #expect(await lifecycle.work.began.isEmpty)
    }

    @Test("a redirect is refused and read as the proxy's opaque not-found")
    func redirectIsRefused() async throws {
        let (stream, lifecycle, request) = try await makeStream { _ in
            .redirect(to: URL(string: "https://staging.example.test/api/mobile/v1/content/covers/other")!)
        }

        await #expect(throws: BodyFlowCapabilityError.contentCoverNotFound) {
            try await stream.stream(request)
        }
        let work = await lifecycle.work
        #expect(work.finished == work.began)
    }

    @Test("a 404 passes through for the decoder to name, with the bytes still bounded by the loader")
    func notFoundPassesStatus() async throws {
        let (stream, _, request) = try await makeStream { _ in
            .response(status: 404, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        }
        let response = try await stream.stream(request)
        #expect(response.statusCode == 404)
        #expect(response.cacheMaxAgeSeconds == nil)
        for try await _ in response.chunks {}
    }

    @Test("ending the session closes every tracked cover's patient work exactly once")
    func cancelAllClosesPatientWorkOnce() async throws {
        let (stream, lifecycle, request) = try await makeStream { _ in
            .response(status: 200, headers: ["Content-Type": "image/png"], body: Self.pngBytes)
        }
        let response = try await stream.stream(request)

        await stream.cancelAll()

        // Whether the reader had already drained the buffered bytes or was
        // cancelled mid-way, the work is closed once and never twice.
        do {
            for try await _ in response.chunks {}
        } catch {}
        await stream.cancelAll()
        let work = await lifecycle.work
        #expect(work.began.count == 1)
        #expect(work.finished == work.began)
    }

    @Test("a proxy that never answers times out as offline and closes its patient work")
    func stalledProxyTimesOut() async throws {
        let (stream, lifecycle, request) = try await makeStream(timeout: 1) { _ in
            .stalled(status: 200, headers: ["Content-Type": "image/png"])
        }

        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await stream.stream(request)
        }
        let work = await lifecycle.work
        #expect(work.began.count == 1)
        #expect(work.finished == work.began)
    }

    @Test("Cache-Control parsing only trusts a plain max-age directive")
    func cacheControlParsing() {
        #expect(MobileContentCoverByteStream.maxAge(fromCacheControl: "private, max-age=300") == 300)
        #expect(MobileContentCoverByteStream.maxAge(fromCacheControl: "MAX-AGE=12") == 12)
        #expect(MobileContentCoverByteStream.maxAge(fromCacheControl: "private") == nil)
        #expect(MobileContentCoverByteStream.maxAge(fromCacheControl: "max-age=abc") == nil)
        #expect(MobileContentCoverByteStream.maxAge(fromCacheControl: "max-age=") == nil)
        #expect(MobileContentCoverByteStream.maxAge(fromCacheControl: nil) == nil)
    }

    @Test("a missing session keeps covers unavailable without a request")
    func missingSessionFailsClosed() async throws {
        let (stream, lifecycle, request) = try await makeStream(bearer: " ") { _ in
            Issue.record("no request may leave without a bearer")
            return .response(status: 200, headers: [:], body: Data())
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await stream.stream(request)
        }
        #expect(await lifecycle.work.began.isEmpty)
    }
}

private actor CoverLifecycleStub: SessionLifecycleProviding {
    struct Work: Sendable {
        var began: [UUID] = []
        var finished: [UUID] = []
    }

    private let bearer: String
    private(set) var work = Work()

    init(bearer: String) {
        self.bearer = bearer
    }

    func currentBearerToken() async -> String? { bearer }

    func leaseForRequest() async throws -> SessionLease {
        SessionLease(userID: "user-a", generation: 1, bearer: bearer)
    }

    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease { lease }

    func validate(_ lease: SessionLease) async throws {}

    func signOut() async -> RemoteRevocationOutcome { .confirmed }

    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) async throws -> UUID {
        let id = UUID()
        work.began.append(id)
        return id
    }

    func finishPatientWork(_ id: UUID) async {
        work.finished.append(id)
    }
}

private final class CoverURLProtocol: URLProtocol, @unchecked Sendable {
    enum Outcome {
        case response(status: Int, headers: [String: String], body: Data)
        case redirect(to: URL)
        case stalled(status: Int, headers: [String: String])
    }

    typealias Handler = @Sendable (URLRequest) -> Outcome

    private static let registry = CoverHandlerRegistry()
    private var loadingTask: Task<Void, Never>?

    static func install(_ handler: @escaping Handler) async {
        await registry.install(handler)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        loadingTask = Task {
            guard let handler = await Self.registry.current() else { return }
            let request = self.request
            switch handler(request) {
            case let .response(status, headers, body):
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            case let .redirect(location):
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                    headerFields: ["Location": location.absoluteString]
                )!
                var redirected = request
                redirected.url = location
                client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            case let .stalled(status, headers):
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data([0x89]))
                // Never finishes: the session's cancel must end it.
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }
}

private actor CoverHandlerRegistry {
    private var handler: CoverURLProtocol.Handler?

    func install(_ handler: @escaping CoverURLProtocol.Handler) {
        self.handler = handler
    }

    func current() -> CoverURLProtocol.Handler? {
        handler
    }
}
