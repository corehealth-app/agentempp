#if DEBUG
import Foundation
import Observation
import SwiftUI

enum BillingUISelection: String, Sendable {
    case configOff = "config-off"
    case sync
    static func resolve(arguments: [String]) -> Self? {
        guard arguments.contains("--ui-testing") else { return nil }
        let choices: [(String, Self)] = [("--ui-testing-billing-config-off", .configOff), ("--ui-testing-billing-sync", .sync)]
        let selected = choices.filter { arguments.contains($0.0) }
        return selected.count == 1 ? selected[0].1 : nil
    }
}

/// Explicit, local-only HTTP/SDK boundaries. Auth, Root, transport, original
/// owner/ticket and billing binding are the same implementations as the app.
@MainActor
struct BillingUIFixture {
    let configuration: AppLaunchConfiguration
    let dependencies: AppDependencies
    let probe: BillingUIProbe
    static func make(selection: BillingUISelection) throws -> Self {
        let configuration = AppLaunchConfiguration(mode: .releaseUnavailable,
            shouldResetDemoState: false, startsWithCompletedFixture: true,
            preloadsSyntheticOnboardingValues: false, authBehavior: .succeed(after: nil))
        let record = try BillingUIFacts.record()
        let secure = try BillingUISecureStore(record: record)
        let store = AuthenticationSessionStore(secureStore: secure, now: { Date(timeIntervalSince1970: 1000) })
        let remote = BillingUIAuth()
        let lifecycle = SessionLifecycleCoordinator(store: store, remote: remote,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        let probe = BillingUIProbe(selection: selection)
        BillingUIURLProtocol.install(probe)
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [BillingUIURLProtocol.self]
        let transport = MobileAPITransport(configuration: try MobileAPIConfiguration(originString: "https://billing-ui.fixture.invalid"),
            sessionLifecycle: lifecycle, session: URLSession(configuration: session), clock: ContinuousClock(), timeout: .seconds(5))
        let coordinator = BillingSDKCoordinator(configuration: selection == .configOff ? nil : BillingConfiguration(publicAPIKey: "appl_synthetic_ui_only"),
            driver: BillingUISDK(probe: probe))
        let base = AppDependencies.scaffold()
        let unavailable = UnavailableBodyFlowCapabilities()
        let reads = MobileBodyFlowRepository(transport: transport)
        let dependencies = AppDependencies(apiClient: transport,
            authentication: SupabaseAuthenticationService(remote: remote, lifecycle: lifecycle),
            onboarding: BillingUIOnboarding(), coachPersona: base.coachPersona, secureStore: secure,
            telemetry: DisabledTelemetryClient(), today: reads, history: unavailable, plan: unavailable,
            progress: unavailable, mealDetection: unavailable, registration: unavailable, hydration: unavailable,
            weight: unavailable, routine: unavailable, me: reads,
            publishedContentSessions: UnavailablePublishedContentSessionFactory(),
            coachExperienceSessions: UnavailableCoachExperienceSessionFactory(), contentCoverSessions: UnavailableContentCoverSessionFactory(),
            timeProvider: SystemTimeProvider(), idempotencyKeyProvider: RandomIdempotencyKeyProvider(),
            patientTimeZoneStore: PatientTimeZoneStore(seed: PatientTimeZoneContext(documentedIANAIdentifier: nil)),
            flowChat: base.flowChat, billingSessionSource: BillingSessionSource(transport: transport, lifecycle: lifecycle, coordinator: coordinator))
        return Self(configuration: configuration, dependencies: dependencies, probe: probe)
    }
}

@MainActor
@Observable
final class BillingUIProbe {
    let selection: BillingUISelection
    private(set) var sdk = 0
    private(set) var offers = 0
    private(set) var purchases = 0
    private(set) var restores = 0
    private(set) var today402 = 0
    private(set) var unexpected = 0
    private var completed = false
    private var postCompletionReads = 0
    init(selection: BillingUISelection) { self.selection = selection }
    var status: String {
        "BILLING \(selection.rawValue) sdk=\(sdk) offers=\(offers) purchase=\(purchases) restore=\(restores) today402=\(today402) unexpected=\(unexpected)"
    }
    func sdkIdentity() { sdk += 1 }
    func sdkOffers() -> [BillingProduct] {
        sdk += 1; offers += 1
        return [BillingProduct(id: "qa-subscription-ui", title: "Synthetic QA plan", localizedPrice: "QA price",
            period: BillingSubscriptionPeriod(value: 1, unit: .month))]
    }
    func sdkPurchase() -> BillingStoreOutcome { sdk += 1; purchases += 1; completed = true; return .completed }
    func sdkRestore() -> BillingStoreOutcome { sdk += 1; restores += 1; completed = true; return .completed }
    func response(path: String) throws -> (Int, Data) {
        let row: [String: Any]
        var code = 200
        switch path {
        case "/api/mobile/v1/me":
            row = ["id": "22222222-2222-4222-8222-222222222222", "timezone": "America/Sao_Paulo"]
        case "/api/mobile/v1/entitlements":
            if completed { postCompletionReads += 1 }
            let granted = selection == .configOff || (completed && postCompletionReads > 1)
            row = ["entitlement": "bodyflow_full", "has_active_access": granted, "status": granted ? "active" : "expired",
                "source": NSNull(), "plan": NSNull(), "access_expires_at": NSNull(), "grace_expires_at": NSNull(),
                "cancel_at_period_end": false, "reason": "synthetic_only", "decision_at": "2026-10-29T15:00:00Z",
                "mobile_billing": ["provider": "revenuecat", "available": true, "reason": "synthetic_only"]]
        case "/api/mobile/v1/today":
            today402 += 1; code = 402
            row = ["code": "subscription_required", "message": "Synthetic adjacent subscription gate"]
        default:
            unexpected += 1; code = 500
            row = ["code": "unexpected_fixture_endpoint", "message": "Unexpected synthetic request"]
        }
        return (code, try JSONSerialization.data(withJSONObject: [code == 200 ? "data" : "error": row,
            "meta": ["api_version": "v1", "request_id": "billing-ui-synthetic"]]))
    }
}

private struct BillingUISDK: BillingSDKDriving {
    let probe: BillingUIProbe
    func configure(publicAPIKey: String, patientID: UUID) async { await probe.sdkIdentity() }
    func logIn(patientID: UUID) async { await probe.sdkIdentity() }
    func logOut() async { await probe.sdkIdentity() }
    func offers() async -> [BillingProduct] { await probe.sdkOffers() }
    func purchase(productID: String) async -> BillingStoreOutcome { await probe.sdkPurchase() }
    func restore() async -> BillingStoreOutcome { await probe.sdkRestore() }
}

struct BillingUIDiagnosticView: View {
    let probe: BillingUIProbe
    var body: some View {
        Text(verbatim: probe.status).font(.system(size: 8)).dynamicTypeSize(.medium).lineLimit(1)
            .accessibilityLabel(probe.status).accessibilityIdentifier("billing.fixture.status")
            .allowsHitTesting(false)
    }
}

private final class BillingUIURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var probe: BillingUIProbe?
    private let contextLock = NSLock()
    private var delivery: BillingUIDelivery?
    static func install(_ value: BillingUIProbe) { lock.withLock { probe = value } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "billing-ui.fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let probe = Self.lock.withLock({ Self.probe }) else { return }
        let context = BillingUIDelivery(instance: self, request: request, probe: probe)
        contextLock.withLock { delivery = context }
        context.start()
    }
    override func stopLoading() {
        let original = contextLock.withLock { delivery }
        original?.cancel()
    }
}

private final class BillingUIDelivery: @unchecked Sendable {
    private let instance: URLProtocol
    private let request: URLRequest
    private let probe: BillingUIProbe
    private let lock = NSRecursiveLock()
    private var cancelled = false
    init(instance: URLProtocol, request: URLRequest, probe: BillingUIProbe) {
        self.instance = instance; self.request = request; self.probe = probe
    }
    func cancel() { lock.withLock { cancelled = true } }
    func start() { Task { await run() } }
    private func run() async {
        do {
            let (status, data) = try await probe.response(path: request.url!.path)
            lock.withLock {
                guard !cancelled else { return }
                instance.client?.urlProtocol(instance, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                    httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
                instance.client?.urlProtocol(instance, didLoad: data)
                instance.client?.urlProtocolDidFinishLoading(instance)
            }
        } catch { lock.withLock { if !cancelled { instance.client?.urlProtocol(instance, didFailWithError: error) } } }
    }
}

private enum BillingUIFacts {
    static func record() throws -> AuthenticationSessionRecord {
        func part(_ value: [String: String]) throws -> String {
            try JSONSerialization.data(withJSONObject: value).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let user = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let token = try part(["alg": "none"]) + "." + part(["sub": user]) + ".synthetic"
        return AuthenticationSessionRecord(userID: user, email: "billing-ui@example.invalid", isEmailConfirmed: true,
            isOnboardingCompleted: true, accessToken: token, refreshToken: "synthetic-billing-ui-refresh", expiresAt: Date(timeIntervalSince1970: 2000))
    }
}
private final class BillingUISecureStore: SecureStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    init(record: AuthenticationSessionRecord) throws { values = [AuthenticationSessionStore.storageKey: try JSONEncoder().encode(record)] }
    func data(forKey key: String) -> Data? { lock.withLock { values[key] } }
    func store(_ data: Data, forKey key: String) async throws { lock.withLock { values[key] = data } }
    func removeData(forKey key: String) { lock.withLock { _ = values.removeValue(forKey: key) } }
}
private actor BillingUIAuth: SupabaseAuthRemoteOperating {
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord { throw SupabaseAuthRemoteError.requestFailed }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult { throw SupabaseAuthRemoteError.requestFailed }
    func requestPasswordRecovery(email: String) throws { throw SupabaseAuthRemoteError.requestFailed }
    func refresh(record: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord { throw SupabaseAuthRemoteError.requestFailed }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}
private actor BillingUIOnboarding: OnboardingRepository {
    func loadDraft(for userID: String) -> OnboardingDraft? { nil }
    func loadState(for userID: String) -> OnboardingServerState {
        OnboardingServerState(locale: "pt-BR", completion: .init(completed: true, completedAt: "2026-10-29T00:00:00Z"),
            requirements: .unavailable, acceptedActions: [], draft: nil)
    }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) {}
    func complete(_ draft: OnboardingDraft, for userID: String) {}
    func clear(for userID: String) {}
}
#endif
