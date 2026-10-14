#if DEBUG
import Foundation
import Observation
import SwiftUI

/// Requires an explicit DEBUG UI-test choice. Normal launches never select this fixture.
enum C11RootNavigationSelection: String, Sendable {
    case sourceOn = "on"
    case sourceOff = "off"
    case getUnauthorizedThenSuccess = "get-401-200"

    static func resolve(arguments: [String]) -> Self? {
        guard arguments.contains("--ui-testing") else { return nil }
        let choices: [(Self, String)] = [
            (.sourceOn, "--ui-testing-c11-root-source-on"),
            (.sourceOff, "--ui-testing-c11-root-source-off"),
            (.getUnauthorizedThenSuccess, "--ui-testing-c11-root-get-401-200")
        ]
        let selected = choices.filter { arguments.contains($0.1) }
        guard selected.count == 1 else { return nil }
        return selected[0].0
    }

    var suppliesMealRecordSource: Bool {
        switch self {
        case .sourceOn, .getUnauthorizedThenSuccess: true
        case .sourceOff: false
        }
    }
}

/// Synthetic app-process dependencies; Root executes the only initial auth restore.
/// This is a harness bootstrap, not a new authentication implementation.
@MainActor
struct C11RootNavigationFixture {
    let selection: C11RootNavigationSelection
    let configuration: AppLaunchConfiguration
    let dependencies: AppDependencies
    let probe: C11RootNavigationProbe

    static func make(selection: C11RootNavigationSelection) throws -> Self {
        let configuration = AppLaunchConfiguration(mode: .releaseUnavailable,
            shouldResetDemoState: false, startsWithCompletedFixture: true,
            preloadsSyntheticOnboardingValues: false, authBehavior: .succeed(after: nil))
        let probe = C11RootNavigationProbe()
        let record = try C11RootNavigationFacts.record()
        let secure = try C11RootNavigationSecureStore(record: record)
        let store = AuthenticationSessionStore(secureStore: secure,
            now: { Date(timeIntervalSince1970: 1000) })
        let remote = C11RootNavigationRemote(probe: probe, selection: selection)
        let lifecycle = SessionLifecycleCoordinator(store: store, remote: remote,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        let bindingProbe = C11RootNavigationLifecycleProbe(base: lifecycle, probe: probe)
        let server = C11RootNavigationServer(probe: probe, selection: selection)
        C11RootNavigationURLProtocol.install(server)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [C11RootNavigationURLProtocol.self]
        let transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://c11-ui.fixture.invalid"),
            sessionLifecycle: lifecycle, session: URLSession(configuration: sessionConfiguration),
            clock: ContinuousClock(), timeout: .seconds(5))
        // Only this explicitly selected synthetic harness can supply a source.
        let source = AppDependencies.makeMealRecordBindingSource(enabled: selection.suppliesMealRecordSource,
            mode: configuration.mode, client: transport, lifecycle: bindingProbe)
        let scaffold = AppDependencies.scaffold()
        let unavailable = UnavailableBodyFlowCapabilities()
        let reads = C11RootNavigationReads()
        let authentication = SupabaseAuthenticationService(remote: remote, lifecycle: lifecycle)
        let dependencies = AppDependencies(apiClient: transport, authentication: authentication,
            onboarding: C11RootNavigationOnboarding(), coachPersona: scaffold.coachPersona,
            secureStore: secure, telemetry: DisabledTelemetryClient(), today: reads, history: reads,
            plan: unavailable, progress: unavailable, mealDetection: unavailable,
            registration: unavailable, hydration: unavailable, weight: unavailable,
            routine: unavailable, me: unavailable,
            publishedContentSessions: UnavailablePublishedContentSessionFactory(),
            coachExperienceSessions: UnavailableCoachExperienceSessionFactory(),
            contentCoverSessions: UnavailableContentCoverSessionFactory(),
            timeProvider: C11RootNavigationTime(), idempotencyKeyProvider: RandomIdempotencyKeyProvider(),
            patientTimeZoneStore: PatientTimeZoneStore(seed: PatientTimeZoneContext(documentedIANAIdentifier: nil)),
            flowChat: scaffold.flowChat, mealRecordBindingSource: source)
        return Self(selection: selection, configuration: configuration, dependencies: dependencies, probe: probe)
    }
}

/// Read-only diagnostic values from actual source/transport/remote calls, never tokens.
@MainActor
@Observable
final class C11RootNavigationProbe {
    private(set) var gets = 0
    private(set) var binds = 0
    private(set) var refreshes = 0
    private(set) var blocked = 0
    private(set) var sameLogicalRequest = false
    private(set) var bearerChanged = false
    func recordGET() { gets += 1 }
    func recordBind() { binds += 1 }
    func recordRefresh() { refreshes += 1 }
    func recordBlocked() { blocked += 1 }
    func recordReplayComparison(sameLogical: Bool, bearerChanged: Bool) {
        sameLogicalRequest = sameLogical
        self.bearerChanged = bearerChanged
    }
}

@MainActor
struct C11RootNavigationDiagnosticView: View {
    let selection: C11RootNavigationSelection
    let probe: C11RootNavigationProbe
    private var diagnostic: String {
        let counts = "C11 \(selection.rawValue): get=\(probe.gets) bind=\(probe.binds) refresh=\(probe.refreshes) blocked=\(probe.blocked)"
        guard selection == .getUnauthorizedThenSuccess else { return counts }
        return counts + " sameLogical=\(probe.sameLogicalRequest ? 1 : 0) bearerChanged=\(probe.bearerChanged ? 1 : 0)"
    }
    var body: some View {
        Text(diagnostic)
            .font(.system(size: 9, design: .monospaced))
            .padding(2)
            .background(.black.opacity(0.85))
            .foregroundStyle(.white)
            .accessibilityIdentifier("c11.fixture.status")
            .allowsHitTesting(false)
    }
}

private enum C11RootNavigationFacts {
    static let userID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let recordID = "11111111-1111-4111-8111-111111111111"
    static let date = Date(timeIntervalSince1970: 1791903600)
    static let meta = MobileResponseMetadata(apiVersion: "v1", requestID: "c11-ui-get-200")
    static func record() throws -> AuthenticationSessionRecord {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: ["sub": userID, "fixture": "c11-root-navigation"])
        func part(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let synthetic = "\(part(header)).\(part(payload)).synthetic-signature"
        return AuthenticationSessionRecord(userID: userID, email: "c11-root@example.invalid",
            isEmailConfirmed: true, isOnboardingCompleted: true, accessToken: synthetic,
            refreshToken: "synthetic-c11-root-refresh", expiresAt: Date(timeIntervalSince1970: 2000))
    }
    /// This valid synthetic replacement is returned ONLY by the new refresh scenario.
    /// Public session facts stay identical; token values never enter diagnostics.
    static func refreshedRecord(from original: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord {
        guard original.userID == userID else { throw SupabaseAuthRemoteError.requestFailed }
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: ["sub": userID, "fixture": "c11-root-navigation-refreshed"])
        func part(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let synthetic = "\(part(header)).\(part(payload)).synthetic-signature"
        return AuthenticationSessionRecord(userID: original.userID, email: original.email,
            isEmailConfirmed: original.isEmailConfirmed, isOnboardingCompleted: original.isOnboardingCompleted,
            accessToken: synthetic, refreshToken: "synthetic-c11-root-refreshed", expiresAt: Date(timeIntervalSince1970: 3000))
    }
    static var row: HistoryMealLogRow {
        HistoryMealLogRow(id: recordID, mealType: "almoco", foodName: "Synthetic C11 confirmed food",
            quantityG: 50, kcal: 100, proteinG: 1, carbsG: 2, fatG: 3, consumedAt: APITimestamp(value: date))
    }
    static func detail() -> MealRecordResponse {
        let item = MealRecordItemSnapshot(id: recordID, foodName: "Synthetic C11 confirmed food",
            quantityG: 50, kcal: 100, proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact",
            consumedAt: APITimestamp(value: date), mealType: "almoco")
        return MealRecordResponse(data: MealRecordSnapshot(recordID: recordID, scope: .item,
            expectedVersion: "opaque-c11-ui-version", itemIDs: [recordID], items: [item], editable: true,
            dayClosed: false, localDate: "2026-10-13", timezone: "America/Sao_Paulo", editBlockReason: nil), meta: meta)
    }
}

/// Same JSONEncoder/schema/storageKey as AuthenticationSessionStore.replace; no async init race.
private final class C11RootNavigationSecureStore: SecureStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    init(record: AuthenticationSessionRecord) throws {
        values = [AuthenticationSessionStore.storageKey: try JSONEncoder().encode(record)]
    }
    func data(forKey key: String) -> Data? { lock.withLock { values[key] } }
    func store(_ data: Data, forKey key: String) { lock.withLock { values[key] = data } }
    func removeData(forKey key: String) { lock.withLock { _ = values.removeValue(forKey: key) } }
}

private actor C11RootNavigationRemote: SupabaseAuthRemoteOperating {
    let probe: C11RootNavigationProbe
    let selection: C11RootNavigationSelection
    init(probe: C11RootNavigationProbe, selection: C11RootNavigationSelection) {
        self.probe = probe
        self.selection = selection
    }
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws { throw SupabaseAuthRemoteError.requestFailed }
    func refresh(record: AuthenticationSessionRecord) async throws -> AuthenticationSessionRecord {
        await probe.recordRefresh()
        guard selection == .getUnauthorizedThenSuccess else { throw SupabaseAuthRemoteError.requestFailed }
        return try C11RootNavigationFacts.refreshedRecord(from: record)
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .unconfirmed }
}

private struct C11RootNavigationReads: TodayProviding, HistoryProviding {
    func today() -> TodayResponse { DemoBodyFlowFixtures.loadedToday }
    func history(_ query: HistoryQuery) -> HistoryResponse {
        HistoryResponse(data: HistorySnapshot(meals: [C11RootNavigationFacts.row], workouts: [],
            pagination: HistoryPaginationMetadata(limit: 30, before: nil)), meta: C11RootNavigationFacts.meta)
    }
}
private actor C11RootNavigationOnboarding: OnboardingRepository {
    func loadDraft(for userID: String) -> OnboardingDraft? { nil }
    func loadState(for userID: String) -> OnboardingServerState {
        OnboardingServerState(locale: "pt-BR", completion: .init(completed: true,
            completedAt: "2026-10-13T00:00:00.000Z"), requirements: .unavailable,
            acceptedActions: [], draft: nil)
    }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) {}
    func complete(_ draft: OnboardingDraft, for userID: String) {}
    func clear(for userID: String) {}
}
private struct C11RootNavigationTime: TimeProviding { var now: Date { C11RootNavigationFacts.date } }

/// A status-bearing HTTP response from the strictly synthetic protocol, never a real endpoint.
private struct C11RootNavigationHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

/// Only an exact synthetic GET is allowed. Unknown requests never reach internet.
private actor C11RootNavigationServer {
    let probe: C11RootNavigationProbe
    let selection: C11RootNavigationSelection
    private var attemptedGETs = 0
    private var firstLogicalRequest: LogicalRequest?
    private var firstAuthorization: String?

    /// Contains safe request metadata only. Authorization is NEVER placed here.
    private struct LogicalRequest: Equatable {
        let method: String?
        let url: URL?
        let bodyIsAbsent: Bool
        let requestID: String?
        let idempotencyKey: String?
        init(_ request: URLRequest) {
            method = request.httpMethod
            url = request.url
            bodyIsAbsent = request.httpBody == nil && request.httpBodyStream == nil
            requestID = request.value(forHTTPHeaderField: "X-Request-Id")
            idempotencyKey = request.value(forHTTPHeaderField: "Idempotency-Key")
        }
        var isValidRead: Bool {
            bodyIsAbsent && requestID?.isEmpty == false && idempotencyKey == nil
        }
    }

    init(probe: C11RootNavigationProbe, selection: C11RootNavigationSelection) {
        self.probe = probe
        self.selection = selection
    }

    func respond(to request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.url?.absoluteString == "https://c11-ui.fixture.invalid/api/mobile/v1/meal-records/11111111-1111-4111-8111-111111111111" else {
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
        attemptedGETs += 1
        await probe.recordGET()
        guard selection == .getUnauthorizedThenSuccess else {
            return C11RootNavigationHTTPResponse(statusCode: 200,
                data: try JSONEncoder().encode(C11RootNavigationFacts.detail()))
        }
        switch attemptedGETs {
        case 1:
            firstLogicalRequest = LogicalRequest(request)
            firstAuthorization = request.value(forHTTPHeaderField: "Authorization")
            let error = ["error": ["code": "expired_token", "message": "Synthetic fixture unauthorized",
                                     "request_id": "c11-ui-unauthorized"]]
            return C11RootNavigationHTTPResponse(statusCode: 401,
                data: try JSONSerialization.data(withJSONObject: error))
        case 2:
            let second = LogicalRequest(request)
            let currentAuthorization = request.value(forHTTPHeaderField: "Authorization")
            let sameLogical = firstLogicalRequest == second && second.isValidRead
            let changed = firstAuthorization?.hasPrefix("Bearer ") == true
                && currentAuthorization?.hasPrefix("Bearer ") == true
                && firstAuthorization != currentAuthorization
            firstAuthorization = nil
            await probe.recordReplayComparison(sameLogical: sameLogical, bearerChanged: changed)
            return C11RootNavigationHTTPResponse(statusCode: 200,
                data: try JSONEncoder().encode(C11RootNavigationFacts.detail()))
        default:
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
    }
}

/// Counts only source.bind captures; all authority/visible state operations delegate to the REAL base.
private actor C11RootNavigationLifecycleProbe: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    let probe: C11RootNavigationProbe
    init(base: SessionLifecycleCoordinator, probe: C11RootNavigationProbe) { self.base = base; self.probe = probe }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease {
        await probe.recordBind()
        return try await base.leaseForRequest()
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
        try await base.refreshAfterUnauthorized(lease: lease)
    }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        try await base.beginPatientWork(lease: lease, cancel: cancel)
    }
    func finishPatientWork(_ id: UUID) async { await base.finishPatientWork(id) }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

// URLProtocol itself is not transferred into an async closure. Only the narrow
// immutable-handle loading context below crosses that boundary.
private final class C11RootNavigationURLProtocol: URLProtocol {
    private static let registry = C11RootNavigationProtocolRegistry()
    private let lock = NSLock()
    private var loadingContext: C11RootNavigationLoadingContext?
    private var stopped = false

    static func install(_ server: C11RootNavigationServer) { registry.install(server) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let context = C11RootNavigationLoadingContext(protocolInstance: self, request: request,
            server: Self.registry.current, client: client)
        let admission: (accepted: Bool, cancelImmediately: Bool) = lock.withLock {
            guard loadingContext == nil else { return (false, false) }
            loadingContext = context
            return (true, stopped)
        }
        guard admission.accepted else { return }
        if admission.cancelImmediately { context.cancel() }
        context.start()
    }

    override func stopLoading() {
        let current = lock.withLock {
            stopped = true
            return loadingContext
        }
        current?.cancel()
    }

    fileprivate func release(_ context: C11RootNavigationLoadingContext) {
        lock.withLock {
            if loadingContext === context { loadingContext = nil }
        }
    }
}

/// The known loading-context pattern, with one immutable request/server/client
/// and serialized terminal delivery. No mutable URLProtocol properties are read
/// by the task. Its own start/cancel/finish state is protected by this lock.
private final class C11RootNavigationLoadingContext: @unchecked Sendable {
    private let protocolInstance: C11RootNavigationURLProtocol
    private let request: URLRequest
    private let server: C11RootNavigationServer?
    private let client: (any URLProtocolClient)?
    // Client delivery may synchronously call stopLoading: allow that reentry.
    private let lock = NSRecursiveLock()
    private var started = false
    private var cancelled = false
    private var terminalDelivered = false
    private var finished = false
    private var task: Task<Void, Never>?

    init(protocolInstance: C11RootNavigationURLProtocol, request: URLRequest,
         server: C11RootNavigationServer?, client: (any URLProtocolClient)?) {
        self.protocolInstance = protocolInstance
        self.request = request
        self.server = server
        self.client = client
    }

    func start() {
        let admitted = lock.withLock {
            guard !started, !cancelled, !finished else { return false }
            started = true
            return true
        }
        guard admitted else {
            finish()
            return
        }
        // The sendable context is the sole async capture; not the URLProtocol.
        let work = Task { await run() }
        let cancelNow = lock.withLock {
            guard !cancelled, !finished else { return true }
            task = work
            return false
        }
        if cancelNow { work.cancel() }
    }

    func cancel() {
        let pending = lock.withLock {
            cancelled = true
            return task
        }
        pending?.cancel()
    }

    private func run() async {
        defer { finish() }
        do {
            try Task.checkCancellation()
            guard !isCancelled, let server else {
                if isCancelled { return }
                throw MobileAPITransportError.invalidResponse
            }
            let reply = try await server.respond(to: request)
            try Task.checkCancellation()
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: reply.statusCode, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]) else {
                throw MobileAPITransportError.invalidResponse
            }
            deliver(response: response, data: reply.data)
        } catch is CancellationError {
            // URLSession already owns cancellation; no callback after stopLoading.
        } catch {
            deliver(error: error)
        }
    }

    private func deliver(response: HTTPURLResponse, data: Data) {
        lock.withLock {
            guard !cancelled, !terminalDelivered, !finished, let client else { return }
            client.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
            guard !cancelled else { return }
            client.urlProtocol(protocolInstance, didLoad: data)
            guard !cancelled else { return }
            terminalDelivered = true
            client.urlProtocolDidFinishLoading(protocolInstance)
        }
    }

    private func deliver(error: any Error) {
        lock.withLock {
            guard !cancelled, !terminalDelivered, !finished, let client else { return }
            terminalDelivered = true
            client.urlProtocol(protocolInstance, didFailWithError: error)
        }
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    private func finish() {
        lock.withLock {
            finished = true
            task = nil
        }
        // Break URLProtocol -> context -> URLProtocol after the task returns.
        protocolInstance.release(self)
    }
}

private final class C11RootNavigationProtocolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var server: C11RootNavigationServer?
    var current: C11RootNavigationServer? { lock.withLock { server } }
    func install(_ value: C11RootNavigationServer) { lock.withLock { server = value } }
}

#endif
