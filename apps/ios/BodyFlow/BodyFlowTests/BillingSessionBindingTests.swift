import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Billing original Auth binding", .serialized)
struct BillingSessionBindingTests {
    @Test("lazy construction; the SDK uses the domain patient UUID, never the Auth subject")
    func lazyDomainIdentity() async throws {
        try await withBillingWire { h in
            #expect(await h.http.paths.isEmpty)
            #expect(await h.sdk.events.isEmpty)
            let binding = try h.reserve()
            #expect(await h.http.paths.isEmpty)
            let context = try await h.source.bind(binding)
            #expect(context.isActive)
            #expect(await h.sdk.events.isEmpty)
            let catalog = try await context.provider.offers()
            #expect(catalog.products.first?.localizedPrice == "synthetic localized price")
            #expect(await h.sdk.events == ["configure:\(BillingWire.patient)", "offers"])
            #expect(binding.capturedLease?.userID == BillingWire.authA)
            #expect(await h.registry.activeCount == 1)
        }
    }

    @Test("checkout off or absent SDK key preserves server access reads", arguments: [false, true])
    func disabledCheckout(missingKey: Bool) async throws {
        try await withBillingWire(configured: !missingKey, available: missingKey) { h in
            let context = try await h.source.bind(h.reserve())
            let access = try await context.provider.entitlement()
            #expect(!access.data.hasActiveAccess)
            await #expect(throws: BillingStoreError.configurationUnavailable) { try await context.provider.offers() }
            #expect(await h.sdk.events.isEmpty)
            #expect(await h.http.paths.contains("/api/mobile/v1/entitlements"))
        }
    }

    @Test("an invalid domain UUID cannot initialize the store")
    func invalidPatientID() async throws {
        try await withBillingWire { h in
            await h.http.setPatient("not-a-domain-uuid")
            await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await h.source.bind(h.reserve()) }
            #expect(await h.sdk.events.isEmpty)
        }
    }

    @Test("a retained context cannot start HTTP or store work after logout")
    func retainedContextDenied() async throws {
        try await withBillingWire { h in
            let context = try await h.source.bind(h.reserve())
            _ = try await context.provider.entitlement()
            let count = await h.http.paths.count
            await h.lifetime.endSession()
            #expect(!context.isActive)
            await #expect(throws: CancellationError.self) { try await context.provider.entitlement() }
            await #expect(throws: CancellationError.self) { try await context.provider.restore() }
            #expect(await h.http.paths.count == count)
            #expect(await h.sdk.events.isEmpty)
            await h.owner.endSession()
            #expect(!h.owner.hasRetainedCapabilities)
            #expect(await h.registry.activeCount == 0)
        }
    }

    @Test("a lease returning after same-user or ABA replacement cannot admit the old ticket", arguments: [false, true])
    func lateLease(aba: Bool) async throws {
        try await withBillingWire { h in
            await h.probe.holdLease()
            let binding = try h.reserve()
            let task = billingObserved(h.probe.leaseHold) { try await h.source.bind(binding) }
            try #require(await h.probe.leaseHold.waitUntilEnteredOrCompleted())
            try await h.replace(aba: aba)
            await h.probe.leaseHold.release()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(await h.http.paths.isEmpty)
            #expect(await h.sdk.events.isEmpty)
            #expect(await h.registry.activeCount == 0)
        }
    }

    @Test("a late admitted work ID is finished exactly once by concurrent ends")
    func lateWorkID() async throws {
        try await withBillingWire { h in
            await h.probe.holdBegin()
            let binding = try h.reserve()
            let task = billingObserved(h.probe.beginHold) { try await h.source.bind(binding) }
            try #require(await h.probe.beginHold.waitUntilEnteredOrCompleted())
            #expect(await h.registry.activeCount == 1)
            h.lifetime.withdrawVisibleActivation()
            let ends = BillingEndObservation()
            let end1 = Task { await ends.end(binding) }
            let end2 = Task { await ends.end(binding) }
            await ends.waitForTwoStarts()
            #expect(ends.count == 0)
            await h.probe.beginHold.release()
            await #expect(throws: CancellationError.self) { try await task.value }
            await end1.value
            await end2.value
            #expect(await h.probe.finished == h.probe.admitted)
            #expect(await h.probe.finished.count == 1)
            #expect(await h.registry.activeCount == 0)
            #expect(await h.http.paths.isEmpty)
        }
    }

    @Test("same-user and ABA tickets reject late SDK success and error; teardown joins the real callback",
          arguments: [false, true], [false, true])
    func lateSDK(aba: Bool, fails: Bool) async throws {
        try await withBillingWire { h in
            let old = try h.reserve()
            let context = try await h.source.bind(old)
            await h.sdk.holdNextOffers(fails: fails)
            let operation = billingObserved(h.sdk.offersHold) { try await context.provider.offers() }
            try #require(await h.sdk.offersHold.waitUntilEnteredOrCompleted())
            try await h.replace(aba: aba)
            let finished = BillingEndObservation()
            let end1 = Task { await finished.end(old) }
            let end2 = Task { await finished.end(old) }
            await finished.waitForTwoStarts()
            #expect(!context.isActive)
            #expect(finished.count == 0)
            #expect(await h.sdk.events == ["configure:\(BillingWire.patient)", "offers"])
            await h.sdk.offersHold.release()
            await #expect(throws: CancellationError.self) { try await operation.value }
            await end1.value
            await end2.value
            #expect(finished.count == 2)
            #expect(await h.sdk.events.last == "logout")
            let replacement = try h.reserve()
            let ready = try await h.source.bind(replacement)
            _ = try await ready.provider.offers()
            let events = await h.sdk.events
            await old.endSession()
            #expect(await h.sdk.events == events)
            #expect(ready.isActive)
        }
    }

    @Test("BFF access remains granted when store checkout is disabled or unconfigured", arguments: [false, true])
    func serverGrantIsPreserved(missingKey: Bool) async throws {
        try await withBillingWire(configured: !missingKey, available: missingKey) { h in
            await h.http.setAccess(true)
            let context = try await h.source.bind(h.reserve())
            #expect(try await context.provider.entitlement().data.hasActiveAccess)
            await #expect(throws: BillingStoreError.configurationUnavailable) { try await context.provider.restore() }
            #expect(try await context.provider.entitlement().data.hasActiveAccess)
            #expect(await h.sdk.events.isEmpty)
        }
    }

    @Test("store completion does not manufacture BFF access")
    func storeCompletionIsNotAccess() async throws {
        try await withBillingWire { h in
            let context = try await h.source.bind(h.reserve())
            let catalog = try await context.provider.offers()
            #expect(try await context.provider.purchase(productID: "synthetic-product", catalogRevision: catalog.revision) == .completed)
            #expect(!(try await context.provider.entitlement().data.hasActiveAccess))
            #expect(try await context.provider.restore() == .completed)
            #expect(!(try await context.provider.entitlement().data.hasActiveAccess))
        }
    }

    @Test("Auth invalidation withdraws the grant even before the UI ticket changes")
    func authCancellationAlone() async throws {
        try await withBillingWire { h in
            let binding = try h.reserve()
            let context = try await h.source.bind(binding)
            _ = try await context.provider.offers()
            let activation = h.lifetime.currentActivation
            try await h.lifecycle.switch(to: BillingWire.record(BillingWire.authB))
            #expect(h.lifetime.currentActivation == activation)
            #expect(!context.isActive)
            let count = await h.http.paths.count
            await #expect(throws: CancellationError.self) { try await context.provider.entitlement() }
            await #expect(throws: CancellationError.self) { try await context.provider.restore() }
            #expect(await h.http.paths.count == count)
            await binding.endSession()
            #expect(await h.probe.finished == h.probe.admitted)
        }
    }

    @Test("retry reads /me in the same original lease, without recapturing admission")
    func retryOriginalLease() async throws {
        try await withBillingWire { h in
            await h.http.failNextMe()
            let binding = try h.reserve()
            do { _ = try await h.source.bind(binding); Issue.record("Expected the controlled offline /me error") }
            catch { #expect(!(error is CancellationError)) }
            #expect(binding.canRetryMe)
            let original = binding.capturedLease
            let context = try await h.source.retryMe(binding)
            #expect(context.isActive)
            #expect(binding.capturedLease == original)
            #expect(await h.probe.leaseCaptures == 1)
            #expect(await h.probe.admitted.count == 1)
            #expect(await h.http.paths == ["/api/mobile/v1/me", "/api/mobile/v1/me"])
        }
    }

    @Test("an old /me success or error cannot replace the same-user or ABA owner's new context",
          arguments: [false, true], [false, true])
    func ownerLateMe(aba: Bool, fails: Bool) async throws {
        try await withBillingWire { h in
            await h.http.holdNextMe(fails: fails)
            let old = try h.reserve()
            let operation = billingObserved(h.http.meHold) { await h.owner.resolveBilling(old) }
            try #require(await h.http.meHold.waitUntilEnteredOrCompleted())
            try await h.replace(aba: aba)
            let replacement = try h.reserve()
            await h.owner.resolveBilling(replacement)
            let ready = try #require(h.owner.billingContext)
            #expect(ready.isActive)
            await h.http.meHold.release()
            try await operation.value
            #expect(h.owner.billingBinding === replacement)
            #expect(h.owner.billingContext === ready)
            #expect(h.owner.billingError == nil)
            #expect(!h.owner.isResolvingBilling)
            #expect(await h.sdk.events.isEmpty)
        }
    }

    @Test("replacing an owner whose weak reference expired still retires its original SDK and patient work")
    func abandonedOwnerCleanup() async throws {
        try await withBillingWire { h in
            var abandoned: Prompt14SessionOwner? = Prompt14SessionOwner(userID: BillingWire.authA, dependencies: .scaffold())
            weak var observedOwner = abandoned
            let lifetime = h.lifetime
            let activation = try #require(lifetime.currentActivation)
            let reservation = abandoned?.reserveBillingBinding(activation: activation,
                lifetime: lifetime, currentActivation: { lifetime.currentActivation })
            let old = try #require(reservation)
            let oldContext = try await h.source.bind(old)
            _ = try await oldContext.provider.offers()
            abandoned = nil
            #expect(observedOwner == nil)
            #expect(!oldContext.isActive)
            _ = try await h.source.bind(h.reserve())
            await lifetime.endSession()
            #expect(await h.registry.activeCount == 0)
            #expect(await h.probe.finished.count == 2)
            #expect(await h.sdk.events.last == "logout")
            // Clean the original ID even on the RED implementation.
            await old.endSession()
        }
    }

    @Test("retiring only the scene's billing leaf preserves Auth and neighboring capabilities")
    func sceneRetirementKeepsAuth() async throws {
        try await withBillingWire { h in
            let original = try h.reserve()
            let context = try await h.source.bind(original)
            let activation = h.lifetime.currentActivation
            _ = try await h.owner.today.today()
            original.invalidateSynchronously()
            await original.endSession()
            #expect(!context.isActive)
            #expect(h.lifetime.currentActivation == activation)
            #expect(!h.owner.isInvalidated)
            _ = try await h.owner.today.today()
            let replacement = try h.reserve()
            let next = try await h.source.bind(replacement)
            #expect(next.isActive)
            #expect(next.activation == activation)
            await original.endSession()
            #expect(next.isActive)
        }
    }

    @Test("real DI composes billing independently from meal editing and workout admission")
    func composition() throws {
        let deps = AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: try MobileAPIConfiguration(originString: "https://billing.example.test")),
            supabaseAuthConfiguration: try SupabaseAuthConfiguration(
                originString: "https://project.example.test", key: "sb_publishable_synthetic"),
            authenticationSessionStore: AuthenticationSessionStore(secureStore: InMemorySecureStore()),
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) })
        #expect(deps.billingSessionSource != nil)
        #expect(deps.mealRecordBindingSource == nil)
        #expect(AppDependencies.scaffold().billingSessionSource == nil)
    }

    @Test("the original context keeps pending model state across navigation and clears it on retirement")
    func plansModelBelongsToContext() async throws {
        try await withBillingWire { h in
            let binding = try h.reserve()
            let context = try await h.source.bind(binding)
            let first = context.plansModel()
            await first.load()
            await first.purchase(productID: "synthetic-product")
            #expect(first.operationState == .syncPending)
            #expect(context.plansModel() === first)
            #expect(context.plansModel().operationState == .syncPending)
            await binding.endSession()
            #expect(first.access == nil)
            #expect(!first.hasActiveAccess)
            let calls = await h.http.paths.count
            await first.load()
            await first.restore()
            #expect(await h.http.paths.count == calls)
        }
    }
}

@MainActor
private func withBillingWire(configured: Bool = true, available: Bool = true,
                             _ body: (BillingWire) async throws -> Void) async throws {
    let h = try await BillingWire(configured: configured, available: available)
    do { try await body(h); await h.end() }
    catch { await h.end(); throw error }
}

@MainActor
private final class BillingWire {
    static let authA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let authB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static let patient = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    let http: BillingHTTPBoundary
    let sdk = BillingBindingSDKBoundary()
    let registry = PatientWorkRegistry()
    let lifecycle: SessionLifecycleCoordinator
    let probe: BillingLifecycleProbe
    let source: BillingSessionSource
    let owner: Prompt14SessionOwner
    let lifetime = MealRecordAuthenticationLifetime()

    init(configured: Bool, available: Bool) async throws {
        let store = AuthenticationSessionStore(secureStore: InMemorySecureStore(), now: { Date(timeIntervalSince1970: 1000) })
        try await store.replace(with: Self.record(Self.authA))
        lifecycle = SessionLifecycleCoordinator(store: store, remote: BillingAuthBoundary(), patientWorkRegistry: registry,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        probe = BillingLifecycleProbe(base: lifecycle)
        http = BillingHTTPBoundary(available: available)
        BillingBindingURLProtocol.install(http)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BillingBindingURLProtocol.self]
        let transport = MobileAPITransport(configuration: try MobileAPIConfiguration(originString: "https://billing.example.test"),
            sessionLifecycle: lifecycle, session: URLSession(configuration: config), clock: ContinuousClock(), timeout: .seconds(2))
        source = BillingSessionSource(transport: transport, lifecycle: probe,
            coordinator: BillingSDKCoordinator(configuration: configured ? BillingConfiguration(publicAPIKey: "appl_synthetic_not_real") : nil, driver: sdk))
        let base = AppDependencies.scaffold()
        let deps = AppDependencies(apiClient: base.apiClient, authentication: base.authentication,
            onboarding: base.onboarding, coachPersona: base.coachPersona, secureStore: base.secureStore,
            telemetry: base.telemetry, today: BillingNeighborToday(), history: base.history,
            plan: base.plan, progress: base.progress, mealDetection: base.mealDetection,
            registration: base.registration, hydration: base.hydration, weight: base.weight,
            routine: base.routine, me: base.me, publishedContentSessions: base.publishedContentSessions,
            coachExperienceSessions: base.coachExperienceSessions, contentCoverSessions: base.contentCoverSessions,
            timeProvider: base.timeProvider, idempotencyKeyProvider: base.idempotencyKeyProvider,
            patientTimeZoneStore: base.patientTimeZoneStore, flowChat: base.flowChat, billingSessionSource: source)
        owner = Prompt14SessionOwner(userID: Self.authA, dependencies: deps)
        await owner.awaitPatientTimeZoneResolution()
        _ = try await lifecycle.leaseForRequest()
        _ = lifetime.publishAuthenticated(userID: Self.authA, ticket: lifetime.beginAuthenticationBoundary())
    }

    func reserve() throws -> BillingSessionBinding {
        let activation = try #require(lifetime.currentActivation)
        let lifetime = lifetime
        let binding = owner.reserveBillingBinding(activation: activation,
            lifetime: lifetime, currentActivation: { lifetime.currentActivation })
        return try #require(binding)
    }
    func replace(aba: Bool) async throws {
        _ = lifetime.beginAuthenticationBoundary()
        if aba {
            try await lifecycle.switch(to: Self.record(Self.authB))
            try await lifecycle.switch(to: Self.record(Self.authA))
        }
        let ticket = lifetime.beginAuthenticationBoundary()
        _ = lifetime.publishAuthenticated(userID: Self.authA, ticket: ticket)
    }
    func end() async {
        await probe.leaseHold.release()
        await probe.beginHold.release()
        await sdk.offersHold.release()
        await http.meHold.release()
        await lifetime.endSession()
        await owner.endSession()
    }
    static func record(_ subject: String) -> AuthenticationSessionRecord {
        func b64(_ value: String) -> String {
            Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return AuthenticationSessionRecord(userID: subject, email: "billing-qa@example.invalid", isEmailConfirmed: true,
            isOnboardingCompleted: true, accessToken: b64(#"{"alg":"none"}"#) + "." + b64("{\"sub\":\"\(subject)\"}") + ".synthetic",
            refreshToken: "synthetic-refresh", expiresAt: Date(timeIntervalSince1970: 2000))
    }
}

private actor BillingAuthBoundary: SupabaseAuthRemoteOperating {
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord { throw SupabaseAuthRemoteError.requestFailed }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult { throw SupabaseAuthRemoteError.requestFailed }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) -> AuthenticationSessionRecord { record }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}

private struct BillingNeighborToday: TodayProviding {
    func today() async throws -> TodayResponse { BodyFlowTestFixtures.todayResponseWithoutBlock }
}

private actor BillingLifecycleProbe: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    let leaseHold = BillingBindingHold()
    let beginHold = BillingBindingHold()
    private var holdsLease = false
    private var holdsBegin = false
    private(set) var leaseCaptures = 0
    private(set) var admitted: [UUID] = []
    private(set) var finished: [UUID] = []
    init(base: SessionLifecycleCoordinator) { self.base = base }
    func holdLease() { holdsLease = true }
    func holdBegin() { holdsBegin = true }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease {
        leaseCaptures += 1
        if holdsLease {
            holdsLease = false
            await leaseHold.suspend()
            return try await Task { try await base.leaseForRequest() }.value
        }
        return try await base.leaseForRequest()
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease { try await base.refreshAfterUnauthorized(lease: lease) }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        let id = try await base.beginPatientWork(lease: lease, cancel: cancel)
        admitted.append(id)
        if holdsBegin { holdsBegin = false; await beginHold.suspend() }
        return id
    }
    func finishPatientWork(_ id: UUID) async { finished.append(id); await base.finishPatientWork(id) }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

private actor BillingBindingHold {
    private var entered = false
    private var released = false
    private var completed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pending: CheckedContinuation<Void, Never>?
    func suspend() async {
        entered = true
        let entries = waiters; waiters = []; entries.forEach { $0.resume() }
        if !released { await withCheckedContinuation { pending = $0 } }
    }
    func waitUntilEnteredOrCompleted() async -> Bool {
        if !entered && !completed && !released { await withCheckedContinuation { waiters.append($0) } }
        return entered
    }
    func finish() { completed = true; let entries = waiters; waiters = []; entries.forEach { $0.resume() } }
    func release() {
        released = true; pending?.resume(); pending = nil
        let entries = waiters; waiters = []; entries.forEach { $0.resume() }
    }
}

@MainActor
private func billingObserved<Value: Sendable>(_ hold: BillingBindingHold,
    _ operation: @escaping @MainActor @Sendable () async throws -> Value) -> Task<Value, Error> {
    Task {
        do { let result = try await operation(); await hold.finish(); return result }
        catch { await hold.finish(); throw error }
    }
}

@MainActor
private final class BillingEndObservation {
    private(set) var count = 0
    private var starts = 0
    private var waiter: CheckedContinuation<Void, Never>?
    func end(_ binding: BillingSessionBinding) async {
        starts += 1
        if starts == 2 { waiter?.resume(); waiter = nil }
        await binding.endSession()
        count += 1
    }
    func waitForTwoStarts() async {
        if starts < 2 { await withCheckedContinuation { waiter = $0 } }
    }
}

private actor BillingBindingSDKBoundary: BillingSDKDriving {
    let offersHold = BillingBindingHold()
    private var holdsOffers = false
    private var failsOffers = false
    private(set) var events: [String] = []
    func holdNextOffers(fails: Bool) { holdsOffers = true; failsOffers = fails }
    func configure(publicAPIKey: String, patientID: UUID) { events.append("configure:\(patientID)") }
    func logIn(patientID: UUID) { events.append("login:\(patientID)") }
    func logOut() { events.append("logout") }
    func offers() async throws -> [BillingProduct] {
        events.append("offers")
        if holdsOffers { holdsOffers = false; await offersHold.suspend() }
        if failsOffers { failsOffers = false; throw BillingStoreError.storeUnavailable }
        return [BillingProduct(id: "synthetic-product", title: "Synthetic title", localizedPrice: "synthetic localized price", period: nil)]
    }
    func purchase(productID: String) -> BillingStoreOutcome { events.append("purchase"); return .completed }
    func restore() -> BillingStoreOutcome { events.append("restore"); return .completed }
}

private actor BillingHTTPBoundary {
    private(set) var paths: [String] = []
    private var patient = "22222222-2222-4222-8222-222222222222"
    let meHold = BillingBindingHold()
    private var holdsMe = false
    private var failsMe = false
    private var access = false
    let available: Bool
    init(available: Bool) { self.available = available }
    func setPatient(_ id: String) { patient = id }
    func setAccess(_ granted: Bool) { access = granted }
    func failNextMe() { failsMe = true }
    func holdNextMe(fails: Bool) { holdsMe = true; failsMe = fails }
    func response(_ request: URLRequest) async throws -> Data {
        let path = request.url!.path
        paths.append(path)
        let row: [String: Any]
        if path == "/api/mobile/v1/me" {
            let held = holdsMe, failed = failsMe
            holdsMe = false; failsMe = false
            if held { await meHold.suspend() }
            if failed { throw URLError(.notConnectedToInternet) }
            row = ["id": patient]
        } else {
            row = ["entitlement": "bodyflow_full", "has_active_access": access, "status": access ? "active" : "expired",
                "source": NSNull(), "plan": NSNull(), "access_expires_at": NSNull(), "grace_expires_at": NSNull(),
                "cancel_at_period_end": false, "reason": "synthetic", "decision_at": "2026-10-29T15:00:00Z",
                "mobile_billing": ["provider": "revenuecat", "available": available, "reason": "synthetic"]]
        }
        return try JSONSerialization.data(withJSONObject: ["data": row, "meta": ["api_version": "v1", "request_id": "billing-synthetic"]])
    }
}

private final class BillingBindingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var boundary: BillingHTTPBoundary?
    private let controlLock = NSLock()
    private var delivery: BillingURLDelivery?
    static func install(_ value: BillingHTTPBoundary) { lock.withLock { boundary = value } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "billing.example.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let http = Self.lock.withLock({ Self.boundary }) else { return }
        let context = BillingURLDelivery(instance: self, request: request, http: http)
        controlLock.withLock { delivery = context }
        context.start()
    }
    override func stopLoading() {
        let original = controlLock.withLock { delivery }
        original?.stop()
    }
}

/// Only the external URLSession boundary is replaced; the concrete transport,
/// repositories, lifecycle, registry, owner and authentication ticket are real.
private final class BillingURLDelivery: @unchecked Sendable {
    private let instance: URLProtocol
    private let request: URLRequest
    private let http: BillingHTTPBoundary
    private let lock = NSRecursiveLock()
    private var stopped = false
    init(instance: URLProtocol, request: URLRequest, http: BillingHTTPBoundary) {
        self.instance = instance; self.request = request; self.http = http
    }
    func stop() { lock.withLock { stopped = true } }
    func start() { Task { await run() } }
    private func run() async {
        do {
            let data = try await http.response(request)
            lock.withLock {
                guard !stopped else { return }
                instance.client?.urlProtocol(instance, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
                instance.client?.urlProtocol(instance, didLoad: data)
                instance.client?.urlProtocolDidFinishLoading(instance)
            }
        } catch { lock.withLock { if !stopped { instance.client?.urlProtocol(instance, didFailWithError: error) } } }
    }
}
