import Auth
import Foundation
import Testing

@testable import BodyFlow

@Suite("Supabase Auth Isolation", .serialized)
struct SupabaseAuthServiceTests {
    @Test("discarding SDK storage never retains values and removal is idempotent")
    func discardingStorageNeverRetains() throws {
        let storage = DiscardingSupabaseAuthStorage()
        try storage.store(key: "fixture-key", value: Data("secret-value".utf8))

        #expect(try storage.retrieve(key: "fixture-key") == nil)
        try storage.remove(key: "fixture-key")
        try storage.remove(key: "fixture-key")
        #expect(!String(describing: storage).contains("fixture-key"))
        #expect(!String(reflecting: storage).contains("secret-value"))
    }

    @Test("safe fetch accepts approved HTTPS requests without caching")
    func safeFetchAcceptsApprovedOrigin() async throws {
        let harness = try await AuthFetchHarness()
        await harness.stub.respond(with: .success(Data("{}".utf8)))
        var request = URLRequest(url: URL(string: "https://project.example.test/auth/v1/token")!)
        request.cachePolicy = .useProtocolCachePolicy

        let (_, response) = try await harness.fetch(request)
        let captured = try #require(await harness.stub.requests().first)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(captured.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test("safe fetch disables cookies and URL credential storage")
    func safeFetchDisablesParallelCredentialState() throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral

        _ = SupabaseAuthFetch(
            configuration: try configuration(),
            sessionConfiguration: sessionConfiguration
        )

        #expect(sessionConfiguration.httpShouldSetCookies == false)
        #expect(sessionConfiguration.httpCookieStorage == nil)
        #expect(sessionConfiguration.urlCredentialStorage == nil)
    }

    @Test("safe fetch rejects same-origin URLs outside the Auth namespace")
    func safeFetchRejectsOtherSameOriginPath() async throws {
        let harness = try await AuthFetchHarness()
        let request = URLRequest(url: URL(string: "https://project.example.test/rest/v1/private")!)

        await #expect(throws: SupabaseAuthNetworkError.originNotAllowed) {
            _ = try await harness.fetch(request)
        }
        #expect(await harness.stub.requests().isEmpty)
    }

    @Test("safe fetch rejects another origin before sending")
    func safeFetchRejectsOtherOrigin() async throws {
        let harness = try await AuthFetchHarness()
        let request = URLRequest(url: URL(string: "https://other.example.test/auth/v1/token")!)

        await #expect(throws: SupabaseAuthNetworkError.originNotAllowed) {
            _ = try await harness.fetch(request)
        }
        #expect(await harness.stub.requests().isEmpty)
    }

    @Test("safe fetch blocks cross-origin redirects before a credentialed second request")
    func safeFetchBlocksCrossOriginRedirect() async throws {
        let harness = try await AuthFetchHarness()
        await harness.stub.respond(with: .redirect(
            to: URL(string: "https://other.example.test/auth/v1/token")!
        ))
        var request = URLRequest(url: URL(string: "https://project.example.test/auth/v1/token")!)
        request.setValue("Bearer synthetic", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("password=synthetic".utf8)

        await #expect(throws: SupabaseAuthNetworkError.redirectNotAllowed) {
            _ = try await harness.fetch(request)
        }
        let requests = await harness.stub.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.host == "project.example.test")
    }

    @Test("safe fetch propagates cancellation and suppresses late success")
    func safeFetchPropagatesCancellation() async throws {
        let harness = try await AuthFetchHarness()
        await harness.stub.respond(with: .success(Data("{}".utf8), delay: .seconds(5)))
        let request = URLRequest(url: URL(string: "https://project.example.test/auth/v1/token")!)
        let task = Task { try await harness.fetch(request) }
        try await harness.stub.waitForRequests(1)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("sign-in uses one short-lived password grant and maps its session")
    func signInUsesExactlyOnePasswordGrant() async throws {
        let recorder = AuthRequestRecorder(response: sessionResponse())
        let remote = try SupabaseAuthRemoteClient(
            configuration: configuration(),
            fetch: { request in try await recorder.fetch(request) }
        )

        let record = try await remote.signIn(
            email: "member@fixture.invalid",
            password: "password-do-not-retain"
        )
        let requests = await recorder.requests

        #expect(requests.count == 1)
        #expect(requests[0].url?.path == "/auth/v1/token")
        #expect(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "grant_type", value: "password")])
        #expect(!String(data: requests[0].httpBody ?? Data(), encoding: .utf8)!.contains("refresh_token"))
        #expect(record.publicSession.email == "member@fixture.invalid")
        #expect(record.accessToken == syntheticAccessToken())

        try await Task.sleep(for: .milliseconds(20))
        #expect(await recorder.requests.count == 1)
    }

    @Test("AuthClient deallocates by a finite deadline without late or refresh requests")
    func authClientDeallocatesWithoutLateRequests() async throws {
        let recorder = AuthRequestRecorder(response: sessionResponse())
        let weakClient = WeakAuthClientReference()
        let remote = try SupabaseAuthRemoteClient(
            configuration: configuration(),
            fetch: { request in try await recorder.fetch(request) },
            clientObserver: { client in weakClient.capture(client) }
        )

        _ = try await remote.signIn(
            email: "member@fixture.invalid",
            password: "password-synthetic"
        )
        #expect(weakClient.wasCaptured)

        try await waitForAuthClientDeallocation(weakClient, timeout: .seconds(3))
        let completedRequests = await recorder.requests
        #expect(completedRequests.count == 1)
        #expect(!completedRequests.contains { request in
            String(data: request.httpBody ?? Data(), encoding: .utf8)?
                .contains("grant_type=refresh_token") == true
        })

        try await Task.sleep(for: .milliseconds(150))
        #expect(await recorder.requests.count == completedRequests.count)
        #expect(weakClient.isReleased)
    }

    @Test("sign-up without a session requires confirmation")
    func signUpRequiresConfirmation() async throws {
        let recorder = AuthRequestRecorder(response: userResponse())
        let remote = try SupabaseAuthRemoteClient(
            configuration: configuration(),
            fetch: { request in try await recorder.fetch(request) }
        )

        let result = try await remote.signUp(
            email: "member@fixture.invalid",
            password: "password-synthetic"
        )

        #expect(result == .confirmationRequired(email: "member@fixture.invalid"))
        #expect(await recorder.requests.count == 1)
    }

    @Test("sign-up with a session maps an authenticated record")
    func signUpCanAuthenticate() async throws {
        let recorder = AuthRequestRecorder(response: sessionResponse())
        let remote = try SupabaseAuthRemoteClient(
            configuration: configuration(),
            fetch: { request in try await recorder.fetch(request) }
        )

        let result = try await remote.signUp(
            email: "member@fixture.invalid",
            password: "password-synthetic"
        )

        guard case .authenticated(let record) = result else {
            Issue.record("Expected authenticated record")
            return
        }
        #expect(record.userID == "00000000-0000-4000-8000-000000000001")
    }

    @Test("password recovery performs one request and returns no session")
    func passwordRecoveryUsesOneRequest() async throws {
        let recorder = AuthRequestRecorder(response: Data("{}".utf8))
        let remote = try SupabaseAuthRemoteClient(
            configuration: configuration(),
            fetch: { request in try await recorder.fetch(request) }
        )

        try await remote.requestPasswordRecovery(email: "member@fixture.invalid")

        let requests = await recorder.requests
        #expect(requests.count == 1)
        #expect(requests[0].url?.path == "/auth/v1/recover")
    }

    @Test("remote cancellation is propagated and does not trigger another request")
    func remoteCancellationIsPropagated() async throws {
        let recorder = AuthRequestRecorder(response: sessionResponse(), delay: .seconds(5))
        let remote = try SupabaseAuthRemoteClient(
            configuration: configuration(),
            fetch: { request in try await recorder.fetch(request) }
        )
        let task = Task {
            try await remote.signIn(
                email: "member@fixture.invalid",
                password: "password-synthetic"
            )
        }
        try await recorder.waitForRequests(1)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        let requestsAtCancellation = await recorder.requests.count
        try await Task.sleep(for: .milliseconds(150))
        #expect(await recorder.requests.count == requestsAtCancellation)
    }

    @Test("direct refresh posts only the refresh token to the locked Auth endpoint")
    func directRefreshUsesOriginLockedGrant() async throws {
        let recorder = AuthRequestRecorder(response: sessionResponse())
        let remote = SupabaseAuthRemoteClient(
            configuration: try configuration(),
            fetch: recorder.fetch
        )

        let refreshed = try await remote.refresh(record: authenticationRecord())
        let requests = await recorder.requests

        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.absoluteString ==
            "https://project.example.test/auth/v1/token?grant_type=refresh_token")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") ==
            "Bearer sb_publishable_synthetic")
        #expect(requests[0].httpBody == Data(#"{"refresh_token":"refresh-synthetic"}"#.utf8))
        #expect(refreshed.userID == authenticationRecord().userID)
    }

    @Test("local logout uses the captured bearer and never requests global scope")
    func directLogoutUsesLocalScope() async throws {
        let recorder = AuthRequestRecorder(response: Data(), status: 204)
        let remote = SupabaseAuthRemoteClient(
            configuration: try configuration(),
            fetch: recorder.fetch
        )

        let outcome = await remote.revokeCurrentSession(
            accessToken: syntheticAccessToken()
        )
        let requests = await recorder.requests

        #expect(outcome == .confirmed)
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.absoluteString ==
            "https://project.example.test/auth/v1/logout?scope=local")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") ==
            "Bearer \(syntheticAccessToken())")
        #expect(requests[0].httpBody == nil)
    }

    @Test("non-204 local logout remains explicitly unconfirmed", arguments: [
        401, 403, 429, 500,
    ])
    func directLogoutClassifiesUnconfirmed(_ status: Int) async throws {
        let recorder = AuthRequestRecorder(response: Data(), status: status)
        let remote = SupabaseAuthRemoteClient(
            configuration: try configuration(),
            fetch: recorder.fetch
        )

        #expect(await remote.revokeCurrentSession(
            accessToken: syntheticAccessToken()
        ) == .unconfirmed)
        #expect(await recorder.requests.count == 1)
    }

    @Test("direct refresh classifies terminal and transient statuses", arguments: [
        RefreshStatusCase(status: 400, error: .invalidGrant),
        RefreshStatusCase(status: 403, error: .forbidden),
        RefreshStatusCase(status: 429, error: .rateLimited),
        RefreshStatusCase(status: 503, error: .server),
    ])
    func directRefreshClassifiesStatus(_ errorCase: RefreshStatusCase) async throws {
        let recorder = AuthRequestRecorder(response: Data("{}".utf8), status: errorCase.status)
        let remote = SupabaseAuthRemoteClient(
            configuration: try configuration(),
            fetch: recorder.fetch
        )

        await #expect(throws: errorCase.error) {
            _ = try await remote.refresh(record: authenticationRecord())
        }
        #expect(await recorder.requests.count == 1)
    }

    @Test("direct refresh maps the locked fetch timeout without retry")
    func directRefreshMapsTimeout() async throws {
        let remote = SupabaseAuthRemoteClient(
            configuration: try configuration(),
            fetch: { _ in throw SupabaseAuthNetworkError.timeout }
        )

        await #expect(throws: SupabaseAuthRemoteError.timeout) {
            _ = try await remote.refresh(record: authenticationRecord())
        }
    }

    @Test("authentication adapter accepts honest remote outcomes and throws only before local invalidation")
    func signOutAdapterMapsLifecycleOutcome() async throws {
        for outcome in [RemoteRevocationOutcome.confirmed, .unconfirmed] {
            let lifecycle = LifecycleOutcomeStub(outcome: outcome)
            let service = SupabaseAuthenticationService(
                remote: SupabaseAuthRemoteStub(),
                lifecycle: lifecycle
            )
            try await service.signOut()
            #expect(await lifecycle.signOutCount == 1)
        }

        let failed = LifecycleOutcomeStub(outcome: .localInvalidationFailed)
        let service = SupabaseAuthenticationService(
            remote: SupabaseAuthRemoteStub(),
            lifecycle: failed
        )
        await #expect(throws: AuthenticationError.storageUnavailable) {
            try await service.signOut()
        }
    }

    @Test("remote errors reveal no password, email, token, or response body")
    func remoteErrorsAreRedacted() async throws {
        let body = Data(#"{"error":"token-do-not-print","email":"member@fixture.invalid"}"#.utf8)
        let recorder = AuthRequestRecorder(response: body, status: 400)
        let remote = try SupabaseAuthRemoteClient(
            configuration: configuration(),
            fetch: { request in try await recorder.fetch(request) }
        )

        do {
            _ = try await remote.signIn(
                email: "member@fixture.invalid",
                password: "password-do-not-print"
            )
            Issue.record("Expected failure")
        } catch {
            let value = String(reflecting: error)
            #expect(!value.contains("password-do-not-print"))
            #expect(!value.contains("member@fixture.invalid"))
            #expect(!value.contains("token-do-not-print"))
        }
    }

    @Test("remote maps explicit invalid credentials without exposing the response")
    func remoteMapsInvalidCredentials() async throws {
        let body = Data(#"{"error_code":"invalid_credentials","msg":"invalid fixture"}"#.utf8)
        let recorder = AuthRequestRecorder(response: body, status: 400)
        let remote = try SupabaseAuthRemoteClient(
            configuration: configuration(),
            fetch: { request in try await recorder.fetch(request) }
        )

        await #expect(throws: SupabaseAuthRemoteError.invalidCredentials) {
            _ = try await remote.signIn(
                email: "member@fixture.invalid",
                password: "password-synthetic"
            )
        }
    }

    @Test("remote rejects an unconfirmed user and a bearer bound to another subject", arguments: [
        sessionResponse(emailConfirmed: false),
        sessionResponse(emailConfirmed: false, accountConfirmed: true),
        sessionResponse(tokenSubject: "00000000-0000-4000-8000-000000000099"),
    ])
    func remoteRejectsInvalidIdentityBinding(_ response: Data) async throws {
        let recorder = AuthRequestRecorder(response: response)
        let remote = try SupabaseAuthRemoteClient(
            configuration: configuration(),
            fetch: { request in try await recorder.fetch(request) }
        )

        await #expect(throws: SupabaseAuthRemoteError.invalidResponse) {
            _ = try await remote.signIn(
                email: "member@fixture.invalid",
                password: "password-synthetic"
            )
        }
    }

    @Test("service sign-in validates input and persists before returning")
    func serviceSignInPersists() async throws {
        let secureStore = InMemorySecureStore()
        let sessionStore = AuthenticationSessionStore(secureStore: secureStore)
        let record = authenticationRecord()
        let remote = SupabaseAuthRemoteStub(signInResult: .success(record))
        let service = SupabaseAuthenticationService(
            remote: remote,
            sessionStore: sessionStore
        )

        await #expect(throws: AuthenticationError.invalidInput) {
            _ = try await service.signIn(email: "invalid", password: "password")
        }
        let session = try await service.signIn(
            email: "member@fixture.invalid",
            password: "password-do-not-retain"
        )

        #expect(session == record.publicSession)
        #expect(await sessionStore.state == .authenticated(record.publicSession))
        #expect(await remote.signInCount == 1)
        #expect(!String(reflecting: service).contains("password-do-not-retain"))
    }

    @Test("service restore is local and sign-out clears only app-owned storage")
    func serviceRestoreAndSignOutAreLocal() async throws {
        let secureStore = InMemorySecureStore()
        let sessionStore = AuthenticationSessionStore(secureStore: secureStore)
        let record = authenticationRecord()
        try await sessionStore.replace(with: record)
        let remote = SupabaseAuthRemoteStub()
        let service = SupabaseAuthenticationService(remote: remote, sessionStore: sessionStore)

        #expect(try await service.restoreSession() == record.publicSession)
        try await service.signOut()

        #expect(await sessionStore.state == .signedOut)
        #expect(await remote.totalRequestCount == 0)
    }

    @Test("service sign-up preserves confirmation and authenticated outcomes")
    func serviceSignUpOutcomes() async throws {
        let confirmationRemote = SupabaseAuthRemoteStub(
            signUpResult: .success(.confirmationRequired(email: "member@fixture.invalid"))
        )
        let confirmationStore = AuthenticationSessionStore(secureStore: InMemorySecureStore())
        let confirmationService = SupabaseAuthenticationService(
            remote: confirmationRemote,
            sessionStore: confirmationStore
        )
        #expect(
            try await confirmationService.signUp(
                email: "member@fixture.invalid",
                password: "password-synthetic"
            ) == .confirmationRequired(email: "member@fixture.invalid")
        )
        #expect(await confirmationStore.state == .notHydrated)

        let record = authenticationRecord()
        let authenticatedRemote = SupabaseAuthRemoteStub(
            signUpResult: .success(.authenticated(record))
        )
        let authenticatedStore = AuthenticationSessionStore(secureStore: InMemorySecureStore())
        let authenticatedService = SupabaseAuthenticationService(
            remote: authenticatedRemote,
            sessionStore: authenticatedStore
        )
        #expect(
            try await authenticatedService.signUp(
                email: "member@fixture.invalid",
                password: "password-synthetic"
            ) == .authenticated(record.publicSession)
        )
        #expect(await authenticatedStore.state == .authenticated(record.publicSession))
    }

    @Test("service maps remote, storage, and development confirmation failures")
    func serviceMapsFailures() async throws {
        let remote = SupabaseAuthRemoteStub(
            signInResult: .failure(SupabaseAuthRemoteError.invalidCredentials)
        )
        let service = SupabaseAuthenticationService(
            remote: remote,
            sessionStore: AuthenticationSessionStore(secureStore: InMemorySecureStore())
        )

        await #expect(throws: AuthenticationError.invalidCredentials) {
            _ = try await service.signIn(
                email: "member@fixture.invalid",
                password: "password-synthetic"
            )
        }
        await #expect(throws: AuthenticationError.operationUnavailable) {
            _ = try await service.confirmEmailForDevelopment()
        }
    }

    @Test("service restore distinguishes lifecycle availability from storage")
    func serviceRestoreMapsLifecycleFailures() async throws {
        let transient = SupabaseAuthenticationService(
            remote: SupabaseAuthRemoteStub(),
            lifecycle: RestoreFailureLifecycle(error: .refreshFailed)
        )
        await #expect(throws: AuthenticationError.serviceUnavailable) {
            _ = try await transient.restoreSession()
        }

        let storage = SupabaseAuthenticationService(
            remote: SupabaseAuthRemoteStub(),
            lifecycle: RestoreFailureLifecycle(error: .localInvalidationFailed)
        )
        await #expect(throws: AuthenticationError.storageUnavailable) {
            _ = try await storage.restoreSession()
        }
    }

    @Test("service recovery validates input and delegates exactly once")
    func serviceRecoveryDelegatesOnce() async throws {
        let remote = SupabaseAuthRemoteStub()
        let service = SupabaseAuthenticationService(
            remote: remote,
            sessionStore: AuthenticationSessionStore(secureStore: InMemorySecureStore())
        )

        await #expect(throws: AuthenticationError.invalidInput) {
            try await service.requestPasswordRecovery(email: "invalid")
        }
        try await service.requestPasswordRecovery(email: "member@fixture.invalid")
        #expect(await remote.recoveryCount == 1)
    }
}

private func configuration() throws -> SupabaseAuthConfiguration {
    try SupabaseAuthConfiguration(
        originString: "https://project.example.test",
        key: "sb_publishable_synthetic"
    )
}

struct RefreshStatusCase: Sendable {
    let status: Int
    let error: SupabaseAuthRemoteError
}

private actor LifecycleOutcomeStub: SessionLifecycleProviding {
    let outcome: RemoteRevocationOutcome
    private(set) var signOutCount = 0

    init(outcome: RemoteRevocationOutcome) { self.outcome = outcome }
    func currentBearerToken() -> String? { nil }
    func leaseForRequest() throws -> SessionLease {
        throw SessionLifecycleError.missingSession
    }
    func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease {
        throw SessionLifecycleError.missingSession
    }
    func validate(_ lease: SessionLease) throws {
        throw SessionLifecycleError.missingSession
    }
    func signOut() -> RemoteRevocationOutcome {
        signOutCount += 1
        return outcome
    }
    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) throws -> UUID {
        throw SessionLifecycleError.missingSession
    }
    func finishPatientWork(_ id: UUID) {}
}

private struct RestoreFailureLifecycle: SessionLifecycleProviding {
    let error: SessionLifecycleError

    func restorePublicSession() async throws -> AuthSession? { throw error }
    func currentBearerToken() async -> String? { nil }
    func leaseForRequest() async throws -> SessionLease { throw error }
    func refreshAfterUnauthorized(lease: SessionLease) async throws
        -> SessionLease { throw error }
    func validate(_ lease: SessionLease) async throws { throw error }
    func signOut() async -> RemoteRevocationOutcome { .unconfirmed }
    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) async throws -> UUID { throw error }
    func finishPatientWork(_ id: UUID) async {}
}

private func sessionResponse(
    emailConfirmed: Bool = true,
    accountConfirmed: Bool = false,
    tokenSubject: String = "00000000-0000-4000-8000-000000000001"
) -> Data {
    let emailConfirmation = emailConfirmed
        ? #", "email_confirmed_at":"2026-08-23T12:00:00Z""#
        : ""
    let accountConfirmation = accountConfirmed
        ? #", "confirmed_at":"2026-08-23T12:00:00Z","phone_confirmed_at":"2026-08-23T12:00:00Z""#
        : ""
    return Data(#"{"access_token":"\#(syntheticAccessToken(subject: tokenSubject))","token_type":"bearer","expires_in":3600,"expires_at":4000000000,"refresh_token":"refresh-synthetic","user":{"id":"00000000-0000-4000-8000-000000000001","aud":"authenticated","role":"authenticated","email":"member@fixture.invalid"\#(emailConfirmation)\#(accountConfirmation),"app_metadata":{"provider":"email","providers":["email"]},"user_metadata":{},"identities":[],"created_at":"2026-08-23T12:00:00Z","updated_at":"2026-08-23T12:00:00Z","is_anonymous":false}}"#.utf8)
}

private func syntheticAccessToken(
    subject: String = "00000000-0000-4000-8000-000000000001"
) -> String {
    let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8).authBase64URL
    let payload = Data(#"{"sub":"\#(subject)"}"#.utf8).authBase64URL
    return "\(header).\(payload).synthetic"
}

private extension Data {
    var authBase64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private func userResponse() -> Data {
    Data(#"{"id":"00000000-0000-4000-8000-000000000001","aud":"authenticated","role":"authenticated","email":"member@fixture.invalid","confirmation_sent_at":"2026-08-23T12:00:00Z","app_metadata":{"provider":"email","providers":["email"]},"user_metadata":{},"identities":[],"created_at":"2026-08-23T12:00:00Z","updated_at":"2026-08-23T12:00:00Z","is_anonymous":false}"#.utf8)
}

private func authenticationRecord() -> AuthenticationSessionRecord {
    AuthenticationSessionRecord(
        userID: "00000000-0000-4000-8000-000000000001",
        email: "member@fixture.invalid",
        isEmailConfirmed: true,
        isOnboardingCompleted: false,
        accessToken: syntheticAccessToken(),
        refreshToken: "refresh-synthetic",
        expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
    )
}

private actor SupabaseAuthRemoteStub: SupabaseAuthRemoteOperating {
    private let signInResult: Result<AuthenticationSessionRecord, Error>
    private let signUpResult: Result<SupabaseRemoteSignUpResult, Error>
    private(set) var signInCount = 0
    private(set) var signUpCount = 0
    private(set) var recoveryCount = 0

    var totalRequestCount: Int { signInCount + signUpCount + recoveryCount }

    init(
        signInResult: Result<AuthenticationSessionRecord, Error> = .failure(
            SupabaseAuthRemoteError.requestFailed
        ),
        signUpResult: Result<SupabaseRemoteSignUpResult, Error> = .failure(
            SupabaseAuthRemoteError.requestFailed
        )
    ) {
        self.signInResult = signInResult
        self.signUpResult = signUpResult
    }

    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        signInCount += 1
        return try signInResult.get()
    }

    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        signUpCount += 1
        return try signUpResult.get()
    }

    func requestPasswordRecovery(email: String) throws {
        recoveryCount += 1
    }
}

private actor AuthRequestRecorder {
    private(set) var requests: [URLRequest] = []
    let response: Data
    let status: Int
    let delay: Duration

    init(response: Data, status: Int = 200, delay: Duration = .zero) {
        self.response = response
        self.status = status
        self.delay = delay
    }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        try await Task.sleep(for: delay)
        try Task.checkCancellation()
        return (
            response,
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }

    func waitForRequests(
        _ count: Int,
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(10)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while requests.count < count {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw AuthTestWaitError.requestsNotObserved(count: count, timeout: timeout)
            }
            try await clock.sleep(for: pollInterval)
        }
    }
}

private struct AuthFetchHarness: Sendable {
    let stub: AuthFetchStubStore
    let fetch: SupabaseAuthFetch

    init() async throws {
        let stub = AuthFetchStubStore()
        await AuthFetchURLProtocol.install(store: stub)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [AuthFetchURLProtocol.self]
        self.stub = stub
        fetch = SupabaseAuthFetch(
            configuration: try configuration(),
            sessionConfiguration: sessionConfiguration,
            timeout: 2
        )
    }
}

private struct AuthFetchStub: Sendable {
    let status: Int
    let body: Data
    let delay: Duration
    let redirectURL: URL?

    static func success(_ body: Data, delay: Duration = .zero) -> Self {
        Self(status: 200, body: body, delay: delay, redirectURL: nil)
    }

    static func redirect(to url: URL) -> Self {
        Self(status: 302, body: Data(), delay: .zero, redirectURL: url)
    }
}

private actor AuthFetchStubStore {
    private var captured: [URLRequest] = []
    private var stub = AuthFetchStub.success(Data())

    func respond(with stub: AuthFetchStub) { self.stub = stub }
    func requests() -> [URLRequest] { captured }
    func response(for request: URLRequest) -> AuthFetchStub {
        captured.append(request)
        return stub
    }
    func waitForRequests(
        _ count: Int,
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(10)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while captured.count < count {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw AuthTestWaitError.requestsNotObserved(count: count, timeout: timeout)
            }
            try await clock.sleep(for: pollInterval)
        }
    }
}

private final class WeakAuthClientReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var client: AuthClient?
    private var captured = false

    var wasCaptured: Bool { lock.withLock { captured } }
    var isReleased: Bool { lock.withLock { captured && client == nil } }

    func capture(_ client: AuthClient) {
        lock.withLock {
            self.client = client
            captured = true
        }
    }
}

private enum AuthTestWaitError: Error, CustomStringConvertible {
    case clientNotReleased(timeout: Duration)
    case requestsNotObserved(count: Int, timeout: Duration)

    var description: String {
        switch self {
        case .clientNotReleased(let timeout):
            "AuthClient did not deallocate within the finite deadline \(timeout)"
        case .requestsNotObserved(let count, let timeout):
            "Expected \(count) auth request(s) within the finite deadline \(timeout)"
        }
    }
}

private func waitForAuthClientDeallocation(
    _ reference: WeakAuthClientReference,
    timeout: Duration,
    pollInterval: Duration = .milliseconds(10)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !reference.isReleased {
        try Task.checkCancellation()
        guard clock.now < deadline else {
            throw AuthTestWaitError.clientNotReleased(timeout: timeout)
        }
        try await clock.sleep(for: pollInterval)
    }
}

private final class AuthFetchURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registry = AuthFetchStubRegistry()
    private var loadingTask: Task<Void, Never>?

    static func install(store: AuthFetchStubStore) async { await registry.install(store) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "https" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        loadingTask = Task {
            guard let store = await Self.registry.current() else { return }
            let stub = await store.response(for: request)
            do {
                try await Task.sleep(for: stub.delay)
                try Task.checkCancellation()
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: stub.status,
                    httpVersion: "HTTP/1.1",
                    headerFields: stub.redirectURL.map { ["Location": $0.absoluteString] }
                )!
                if let redirectURL = stub.redirectURL {
                    var redirected = request
                    redirected.url = redirectURL
                    client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
                    return
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: stub.body)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            }
        }
    }

    override func stopLoading() { loadingTask?.cancel() }
}

private actor AuthFetchStubRegistry {
    private var store: AuthFetchStubStore?
    func install(_ store: AuthFetchStubStore) { self.store = store }
    func current() -> AuthFetchStubStore? { store }
}
