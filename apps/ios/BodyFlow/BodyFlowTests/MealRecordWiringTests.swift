import Foundation
import Observation
import Testing
@testable import BodyFlow

// Separate registry/protocol from MobileAPITransportTests. Only synthetic local fixtures.
@Suite("C11 actual Root/Shell consumer composition", .serialized)
@MainActor
struct MealRecordWiringTests {
    @Test("DI requires an explicit flag, non-demo mode and the real transport/lifecycle pair",
          arguments: C11WireSourceCase.allCases)
    func sourceAdmission(_ scenario: C11WireSourceCase) async throws {
        try await withWireFixture { fixture in
            let client: any APIClient = scenario == .wrongClient
                ? AppDependencies.scaffold().apiClient : fixture.transport
            let source = AppDependencies.makeMealRecordBindingSource(
                enabled: scenario != .disabled,
                mode: scenario == .demo ? .demo : .releaseUnavailable,
                client: client, lifecycle: scenario == .missingLifecycle ? nil : fixture.bindProbe)
            #expect((source != nil) == (scenario == .enabled))
            #expect(AppDependencies.scaffold().mealRecordBindingSource == nil)
            #expect(await fixture.bindProbe.bindLeaseCalls == 0)
            #expect(await fixture.server.requestCount == 0)
        }
    }

    @Test("Missing lifetime or missing source keeps the actual driver and owner OFF",
          arguments: C11WireOffCase.allCases)
    func defaultOff(_ scenario: C11WireOffCase) async throws {
        try await withWireFixture(sourceEnabled: scenario != .noSource,
                                  lifetimeEnabled: scenario != .noLifetime) { fixture in
            #expect(fixture.flow.state == .authenticated(userID: C11WireFixtures.userID))
            #expect(!fixture.driver.isEnabled)
            #expect(fixture.driver.taskID == nil)
            #expect(await fixture.driver.synchronize(expected: nil) == nil)
            #expect(fixture.driver.readyContext == nil)
            #expect(fixture.owner.mealRecordBinding == nil)
            #expect(fixture.owner.reserveNewMealRecordBinding() == nil)
            #expect(!fixture.owner.isInvalidated)
            #expect(await fixture.bindProbe.bindLeaseCalls == 0)
            #expect(await fixture.server.requestCount == 0)
        }
    }

    @Test("The actual View driver captures the original owner and publishes observable readiness without GET")
    func driverCapturesOwnerAndPublishesReady() async throws {
        try await withWireFixture { fixture in
            let original = try #require(fixture.driver.taskID)
            #expect(original.owner == ObjectIdentifier(fixture.owner))
            #expect(original.activation == fixture.flow.mealRecordActivation)
            #expect(fixture.driver.readyContext == nil)
            let change = C11WireObservationProbe()
            withObservationTracking {
                _ = fixture.driver.readyContext
            } onChange: { change.markChanged() }
            let context = try #require(await fixture.driver.synchronize(expected: original))
            #expect(context.isActive)
            #expect(context.activation == original.activation)
            #expect(fixture.driver.readyContext === context)
            #expect(change.didChange)
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let model = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            #expect(model.detail == nil)
            #expect(model.draft == nil)
            #expect(await fixture.bindProbe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
        }
    }

    @Test("Dismiss/reentry with the same original context preserves the actual cached Model, draft and unknown command")
    func cachePreservesDismissedUnknownCommand() async throws {
        try await withWireFixture { fixture in
            let context = try #require(await fixture.driver.synchronize(expected: fixture.driver.taskID))
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let model = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            await model.load()
            try #require(model.canSave(language: .portugueseBrazil))
            model.draft?.items[0].quantityText = "25"
            await fixture.server.loseNextMutationResponse()
            await model.save(language: .portugueseBrazil)
            let originalAttempt = try #require(model.retainedAttempt)
            #expect(model.confirmedReceipt == nil)
            #expect(fixture.keys.count == 1)
            #expect(await fixture.server.requestCount == 2)
            model.discardPresentation()
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let reentered = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            #expect(reentered === model)
            #expect(reentered.retainedAttempt == originalAttempt)
            #expect(reentered.draft?.items[0].quantityText == "25")
            #expect(fixture.keys.count == 1)
            #expect(await fixture.bindProbe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 2)
            #expect(fixture.center.revision(for: .today) == 0)
            #expect(fixture.center.revision(for: .history) == 0)
        }
    }

    @Test("Same-user real reauthentication changes the leaf/cache while keeping the actual parent owner and generation")
    func sameUserReauthenticationReplacesOnlyMealCache() async throws {
        try await withWireFixture { fixture in
            let originalTask = try #require(fixture.driver.taskID)
            let first = try #require(await fixture.driver.synchronize(expected: originalTask))
            let firstLease = try await fixture.coordinator.leaseForRequest()
            fixture.cache.synchronize(context: first, owner: fixture.owner)
            let old = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: first, owner: fixture.owner))
            await old.load()
            old.draft?.items[0].quantityText = "25"
            try #require(old.canSave(language: .portugueseBrazil))
            await fixture.remote.setSignInRecord(try C11WireFixtures.record(ordinal: 2))
            // The real service/coordinator and AppFlowModel hooks own this boundary.
            await fixture.flow.signIn(email: "wire@example.invalid", password: "synthetic-password-only")
            let nextTask = try #require(fixture.driver.taskID)
            let nextLease = try await fixture.coordinator.leaseForRequest()
            #expect(nextTask.activation != originalTask.activation)
            #expect(nextTask.owner == originalTask.owner)
            #expect(nextLease.userID == firstLease.userID)
            #expect(nextLease.generation == firstLease.generation)
            #expect(!fixture.owner.isInvalidated)
            #expect(fixture.owners.renderableOwner(for: C11WireFixtures.userID) === fixture.owner)
            #expect(!first.isActive)
            // No redraw/cache effect has happened yet: the old Model's predicate denies starts.
            #expect(!old.canSave(language: .portugueseBrazil))
            await old.save(language: .portugueseBrazil)
            #expect(fixture.keys.count == 0)
            #expect(await fixture.server.requestCount == 1)
            let second = try #require(await fixture.driver.synchronize(expected: nextTask))
            #expect(second.isActive)
            #expect(second.capability !== first.capability)
            fixture.cache.synchronize(context: second, owner: fixture.owner)
            let fresh = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: second, owner: fixture.owner))
            #expect(fresh !== old)
            #expect(old.detail == nil)
            #expect(old.draft == nil)
            #expect(old.retainedAttempt == nil)
            #expect(fresh.detail == nil)
            #expect(fresh.draft == nil)
            // Stale/nil View effects cannot revoke this live A2.
            #expect(await fixture.driver.synchronize(expected: originalTask) == nil)
            #expect(await fixture.driver.synchronize(expected: nil) == nil)
            fixture.cache.synchronize(context: first, owner: fixture.owner)
            fixture.cache.synchronize(context: nil, owner: fixture.owner)
            #expect(fixture.driver.readyContext === second)
            #expect(fixture.cache.isCurrent(context: second, owner: fixture.owner))
            #expect(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: second, owner: fixture.owner) === fresh)
            #expect(await fixture.bindProbe.bindLeaseCalls == 2)
            #expect(await fixture.server.requestCount == 1)
            #expect(fixture.center.revision(for: .today) == 0)
            #expect(fixture.center.revision(for: .history) == 0)
        }
    }

    @Test("A receipt from the real cached Model invalidates the Shell's SAME Today/History center once")
    func cachedModelUsesOriginalInvalidationCenter() async throws {
        try await withWireFixture { fixture in
            let context = try #require(await fixture.driver.synchronize(expected: fixture.driver.taskID))
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let model = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            await model.load()
            model.draft?.items[0].quantityText = "25"
            await model.save(language: .portugueseBrazil)
            let receipt = try #require(model.confirmedReceipt)
            #expect(receipt.data.operation == .updated)
            #expect(receipt.data.snapshot.caloriesConsumed == 321)
            #expect(receipt.data.nextRecordID == C11WireFixtures.replacementID)
            #expect(fixture.center.revision(for: .today) == 1)
            #expect(fixture.center.revision(for: .history) == 1)
            model.discardPresentation()
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            #expect(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner) === model)
            #expect(fixture.center.revision(for: .today) == 1)
            #expect(fixture.center.revision(for: .history) == 1)
            #expect(fixture.keys.count == 1)
            #expect(await fixture.server.requestCount == 2)
        }
    }

    @Test("Nil and foreign-owner Shell effects preserve a live original cached context")
    func foreignOrNilCacheEffectsCannotDiscardCurrent() async throws {
        try await withWireFixture { fixture in
            let context = try #require(await fixture.driver.synchronize(expected: fixture.driver.taskID))
            fixture.cache.synchronize(context: context, owner: fixture.owner)
            let model = try #require(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner))
            let other = Prompt14SessionOwner(userID: C11WireFixtures.userID,
                dependencies: fixture.dependencies, enablesMealRecordBinding: true)
            // This constructor starts only the owner's existing /me task; join it explicitly.
            await other.awaitPatientTimeZoneResolution()
            fixture.cache.synchronize(context: context, owner: other)
            fixture.cache.synchronize(context: nil, owner: fixture.owner)
            #expect(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: other) == nil)
            #expect(fixture.cache.isCurrent(context: context, owner: fixture.owner))
            #expect(fixture.cache.prepareModel(recordID: C11WireFixtures.recordID,
                context: context, owner: fixture.owner) === model)
            #expect(fixture.driver.readyContext === context)
            #expect(context.isActive)
            #expect(await fixture.bindProbe.bindLeaseCalls == 1)
            #expect(await fixture.server.requestCount == 0)
            #expect(fixture.keys.count == 0)
            await other.endSession()
        }
    }
}

enum C11WireSourceCase: CaseIterable, Sendable { case disabled, demo, wrongClient, missingLifecycle, enabled }
enum C11WireOffCase: CaseIterable, Sendable { case noSource, noLifetime }

@MainActor
private func withWireFixture(sourceEnabled: Bool = true, lifetimeEnabled: Bool = true,
    _ operation: @MainActor (C11WireFixture) async throws -> Void) async throws {
    let fixture = try await C11WireFixture.make(sourceEnabled: sourceEnabled, lifetimeEnabled: lifetimeEnabled)
    do {
        try await operation(fixture)
        await fixture.end()
    } catch {
        await fixture.end()
        throw error
    }
}

@MainActor
private struct C11WireFixture {
    let transport: MobileAPITransport
    let coordinator: SessionLifecycleCoordinator
    let bindProbe: C11WireLifecycleProbe
    let remote: C11WireRemote
    let server: C11WireServer
    let dependencies: AppDependencies
    let lifetime: MealRecordAuthenticationLifetime?
    let flow: AppFlowModel
    let owners: Prompt14AuthenticatedShellCoordinator
    let owner: Prompt14SessionOwner
    let driver: MealRecordRootWiringDriver
    let cache: MealRecordShellSessionCoordinator
    let keys: C11WireKeys
    let center: FeatureInvalidationCenter

    static func make(sourceEnabled: Bool, lifetimeEnabled: Bool) async throws -> Self {
        let store = AuthenticationSessionStore(secureStore: InMemorySecureStore(), now: {
            Date(timeIntervalSince1970: 1000)
        })
        let record = try C11WireFixtures.record(ordinal: 1)
        try await store.replace(with: record)
        let remote = C11WireRemote(record: record)
        let coordinator = SessionLifecycleCoordinator(store: store, remote: remote,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        let bindProbe = C11WireLifecycleProbe(base: coordinator)
        let server = C11WireServer()
        C11WireURLProtocol.install(server)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [C11WireURLProtocol.self]
        let transport = MobileAPITransport(configuration: try MobileAPIConfiguration(originString: "https://wire.example.test"),
            sessionLifecycle: coordinator, session: URLSession(configuration: config),
            clock: ContinuousClock(), timeout: .seconds(2))
        let source = AppDependencies.makeMealRecordBindingSource(enabled: sourceEnabled,
            mode: .releaseUnavailable, client: transport, lifecycle: bindProbe)
        let lifetime = lifetimeEnabled ? MealRecordAuthenticationLifetime() : nil
        let scaffold = AppDependencies.scaffold()
        let authentication = SupabaseAuthenticationService(remote: remote, lifecycle: coordinator)
        let onboarding = C11WireOnboarding()
        let keys = C11WireKeys()
        let dependencies = AppDependencies(apiClient: transport, authentication: authentication,
            onboarding: onboarding, coachPersona: scaffold.coachPersona, secureStore: scaffold.secureStore,
            telemetry: scaffold.telemetry, today: scaffold.today, history: scaffold.history, plan: scaffold.plan,
            progress: scaffold.progress, mealDetection: scaffold.mealDetection, registration: scaffold.registration,
            hydration: scaffold.hydration, weight: scaffold.weight, routine: scaffold.routine, me: scaffold.me,
            publishedContentSessions: scaffold.publishedContentSessions, coachExperienceSessions: scaffold.coachExperienceSessions,
            contentCoverSessions: scaffold.contentCoverSessions, timeProvider: C11WireTime(), idempotencyKeyProvider: keys,
            patientTimeZoneStore: scaffold.patientTimeZoneStore, flowChat: scaffold.flowChat,
            mealRecordBindingSource: source)
        let flow = AppFlowModel(authentication: authentication, onboarding: onboarding,
            persona: scaffold.coachPersona, telemetry: scaffold.telemetry,
            mealRecordAuthenticationLifetime: lifetime, now: { C11WireFixtures.date })
        let owners = Prompt14AuthenticatedShellCoordinator(dependencies: dependencies,
            enablesMealRecordBinding: lifetime != nil && source != nil)
        let driver = MealRecordRootWiringDriver(model: flow, ownerCoordinator: owners,
            lifetime: lifetime, source: source)
        let center = FeatureInvalidationCenter()
        let cache = MealRecordShellSessionCoordinator(time: C11WireTime(), keys: keys, invalidation: center)
        do {
            await flow.start()
            try #require(flow.state == .authenticated(userID: C11WireFixtures.userID))
            await owners.transition(to: C11WireFixtures.userID)
            let owner = try #require(owners.renderableOwner(for: C11WireFixtures.userID))
            await owner.awaitPatientTimeZoneResolution()
            return Self(transport: transport, coordinator: coordinator, bindProbe: bindProbe,
                remote: remote, server: server, dependencies: dependencies, lifetime: lifetime, flow: flow,
                owners: owners, owner: owner, driver: driver, cache: cache, keys: keys, center: center)
        } catch {
            cache.endSession()
            await driver.endSession()
            await lifetime?.endSession()
            await owners.transition(to: nil)
            throw error
        }
    }

    func end() async {
        cache.endSession()
        await driver.endSession()
        await lifetime?.endSession()
        await owners.transition(to: nil)
    }
}

private enum C11WireFixtures {
    static let userID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let recordID = "11111111-1111-4111-8111-111111111111"
    static let replacementID = "33333333-3333-4333-8333-333333333333"
    static let date = Date(timeIntervalSince1970: 1_790_000_000)
    static let meta = MobileResponseMetadata(apiVersion: "v1", requestID: "c11-wire-synthetic")
    static func record(ordinal: Int) throws -> AuthenticationSessionRecord {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: ["sub": userID, "marker": ordinal])
        func part(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let syntheticToken = "\(part(header)).\(part(payload)).synthetic-signature"
        return AuthenticationSessionRecord(userID: userID, email: "wire@example.invalid", isEmailConfirmed: true,
            isOnboardingCompleted: true, accessToken: syntheticToken, refreshToken: "wire-synthetic-refresh-\(ordinal)",
            expiresAt: Date(timeIntervalSince1970: 2000))
    }
    static func detail() -> MealRecordResponse {
        let item = MealRecordItemSnapshot(id: recordID, foodName: "Synthetic wire item", quantityG: 50,
            kcal: 100, proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact",
            consumedAt: APITimestamp(value: date), mealType: nil)
        return MealRecordResponse(data: MealRecordSnapshot(recordID: recordID, scope: .group,
            expectedVersion: "opaque-wire-version", itemIDs: [recordID], items: [item], editable: true,
            dayClosed: false, localDate: "2026-10-13", timezone: "America/Sao_Paulo", editBlockReason: nil), meta: meta)
    }
    static func receipt() -> MealRecordMutationResponse {
        MealRecordMutationResponse(data: MealRecordMutationSnapshot(recordID: recordID, operation: .updated,
            newItemIDs: [replacementID], removedItemIDs: [recordID], nextRecordID: replacementID,
            snapshot: MealRecordPersistedSnapshot(id: "synthetic-wire-snapshot", date: "2026-10-13",
                caloriesConsumed: 321, proteinG: 3, carbsG: 4, fatG: 5, dailyBalance: 77)), meta: meta)
    }
}

private struct C11WireTime: TimeProviding { var now: Date { C11WireFixtures.date } }
private final class C11WireKeys: IdempotencyKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0
    var count: Int { lock.withLock { issued } }
    func nextKey() throws -> IdempotencyKey {
        try lock.withLock {
            issued += 1
            return try IdempotencyKey(validating: "c11-wire-synthetic-key-\(issued)")
        }
    }
}
private final class C11WireObservationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    var didChange: Bool { lock.withLock { changed } }
    func markChanged() { lock.withLock { changed = true } }
}

private actor C11WireRemote: SupabaseAuthRemoteOperating {
    private var signInRecord: AuthenticationSessionRecord
    init(record: AuthenticationSessionRecord) { signInRecord = record }
    func setSignInRecord(_ value: AuthenticationSessionRecord) { signInRecord = value }
    func signIn(email: String, password: String) -> AuthenticationSessionRecord { signInRecord }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult { throw SupabaseAuthRemoteError.requestFailed }
    func requestPasswordRecovery(email: String) {}
    func refresh(record: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord { try C11WireFixtures.record(ordinal: 10) }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}
private actor C11WireOnboarding: OnboardingRepository {
    func loadDraft(for userID: String) -> OnboardingDraft? { nil }
    func loadState(for userID: String) -> OnboardingServerState {
        OnboardingServerState(locale: "pt-BR", completion: OnboardingCompletionState(completed: true,
            completedAt: "2026-10-13T00:00:00.000Z"), requirements: .unavailable, acceptedActions: [], draft: nil)
    }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) {}
    func complete(_ draft: OnboardingDraft, for userID: String) {}
    func clear(for userID: String) {}
}

/// Counts only Source.bind lease capture. Transport uses the SAME real base directly.
/// All validation/registry/visible-state operations delegate without changing authority.
private actor C11WireLifecycleProbe: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    private(set) var bindLeaseCalls = 0
    init(base: SessionLifecycleCoordinator) { self.base = base }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease {
        bindLeaseCalls += 1
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

private actor C11WireServer {
    private(set) var requestCount = 0
    private var loseMutation = false
    func loseNextMutationResponse() { loseMutation = true }
    func respond(to request: URLRequest) throws -> Data {
        requestCount += 1
        switch request.httpMethod {
        case "GET": return try JSONEncoder().encode(C11WireFixtures.detail())
        case "PATCH":
            if loseMutation {
                loseMutation = false
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
            }
            return try JSONEncoder().encode(C11WireFixtures.receipt())
        default: throw MobileAPITransportError.invalidResponse
        }
    }
}

// URLProtocol itself is not transferred into an async closure. Only the narrow
// immutable-handle loading context below crosses that boundary.
private final class C11WireURLProtocol: URLProtocol {
    private static let registry = C11WireProtocolRegistry()
    private let lock = NSLock()
    private var loadingContext: C11WireLoadingContext?
    private var stopped = false

    static func install(_ server: C11WireServer) { registry.install(server) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "wire.example.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let context = C11WireLoadingContext(protocolInstance: self, request: request,
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

    fileprivate func release(_ context: C11WireLoadingContext) {
        lock.withLock {
            if loadingContext === context { loadingContext = nil }
        }
    }
}

/// The known loading-context pattern, with one immutable request/server/client
/// and serialized terminal delivery. No mutable URLProtocol properties are read
/// by the task. Its own start/cancel/finish state is protected by this lock.
private final class C11WireLoadingContext: @unchecked Sendable {
    private let protocolInstance: C11WireURLProtocol
    private let request: URLRequest
    private let server: C11WireServer?
    private let client: (any URLProtocolClient)?
    // Client delivery may synchronously call stopLoading: allow that reentry.
    private let lock = NSRecursiveLock()
    private var started = false
    private var cancelled = false
    private var terminalDelivered = false
    private var finished = false
    private var task: Task<Void, Never>?

    init(protocolInstance: C11WireURLProtocol, request: URLRequest,
         server: C11WireServer?, client: (any URLProtocolClient)?) {
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
            let data = try await server.respond(to: request)
            try Task.checkCancellation()
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]) else {
                throw MobileAPITransportError.invalidResponse
            }
            deliver(response: response, data: data)
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

private final class C11WireProtocolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var server: C11WireServer?
    var current: C11WireServer? { lock.withLock { server } }
    func install(_ value: C11WireServer) { lock.withLock { server = value } }
}
