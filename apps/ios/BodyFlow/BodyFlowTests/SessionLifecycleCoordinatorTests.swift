import Foundation
import Testing
@testable import BodyFlow

@Suite("Session Lifecycle Coordinator")
struct SessionLifecycleCoordinatorTests {
    @Test("valid bootstrap returns a lease without refresh")
    func validBootstrapUsesStoredBearer() async throws {
        let harness = try await LifecycleHarness(expiresAt: 1_100)
        let lease = try await harness.coordinator.leaseForRequest()

        #expect(lease.userID == harness.record.userID)
        #expect(lease.generation == 0)
        #expect(await harness.remote.refreshCount == 0)
    }

    @Test("N concurrent waiters share exactly one refresh")
    func concurrentWaitersUseSingleFlight() async throws {
        let harness = try await LifecycleHarness(expiresAt: 1_030, refreshDelay: .milliseconds(50))

        let leases = try await withThrowingTaskGroup(of: SessionLease.self) { group in
            for _ in 0..<12 {
                group.addTask { try await harness.coordinator.leaseForRequest() }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(leases.count == 12)
        #expect(Set(leases.map(\.bearer)).count == 1)
        #expect(await harness.remote.refreshCount == 1)
        #expect(await harness.store.currentRecord()?.refreshToken == "refresh-rotated")
    }

    @Test("different-user switch advances generation and cancels old work")
    func differentUserSwitchCancelsOldWork() async throws {
        let harness = try await LifecycleHarness(expiresAt: 1_100)
        let oldLease = try await harness.coordinator.leaseForRequest()
        let signal = CancellationSignalForLifecycle()
        let workID = try await harness.coordinator.beginPatientWork(
            lease: oldLease,
            cancel: signal.cancel
        )
        let replacement = lifecycleRecord(
            userID: "00000000-0000-4000-8000-000000000002",
            marker: "replacement",
            expiresAt: 1_200
        )

        try await harness.coordinator.switch(to: replacement)

        #expect(signal.count == 1)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) {
            try await harness.coordinator.validate(oldLease)
        }
        await harness.coordinator.finishPatientWork(workID)
    }

    @Test("same-user rotation preserves generation and patient work")
    func sameUserSwitchPreservesWork() async throws {
        let harness = try await LifecycleHarness(expiresAt: 1_100)
        let oldLease = try await harness.coordinator.leaseForRequest()
        let signal = CancellationSignalForLifecycle()
        let workID = try await harness.coordinator.beginPatientWork(
            lease: oldLease,
            cancel: signal.cancel
        )

        try await harness.coordinator.switch(to: lifecycleRecord(
            userID: harness.record.userID,
            marker: "reauthenticated",
            expiresAt: 1_200
        ))
        let newLease = try await harness.coordinator.leaseForRequest()

        #expect(newLease.generation == oldLease.generation)
        #expect(signal.count == 0)
        await harness.coordinator.finishPatientWork(workID)
    }

    @Test("logout invalidates locally before classifying remote revocation")
    func logoutInvalidatesAndCancels() async throws {
        let harness = try await LifecycleHarness(expiresAt: 1_100)
        let lease = try await harness.coordinator.leaseForRequest()
        let signal = CancellationSignalForLifecycle()
        _ = try await harness.coordinator.beginPatientWork(
            lease: lease,
            cancel: signal.cancel
        )

        #expect(await harness.coordinator.signOut() == .confirmed)
        #expect(signal.count == 1)
        await #expect(throws: SessionLifecycleError.missingSession) {
            try await harness.coordinator.leaseForRequest()
        }
    }

    @Test("logout and cross-user switch invoke only the narrow sensitive owner")
    func sensitiveClearingUsesNarrowBoundary() async throws {
        let clearer = SensitiveClearerSpy()
        let harness = try await LifecycleHarness(
            expiresAt: 1_100,
            sensitiveStateClearer: clearer
        )
        _ = try await harness.coordinator.leaseForRequest()
        try await harness.coordinator.switch(to: lifecycleRecord(
            userID: "00000000-0000-4000-8000-000000000002",
            marker: "replacement",
            expiresAt: 1_200
        ))
        #expect(await clearer.clearCount == 1)

        _ = await harness.coordinator.signOut()
        #expect(await clearer.clearCount == 2)
    }

    @Test("marker failure preserves lease generation work and remote silence")
    func markerFailurePreservesActiveBoundary() async throws {
        let secureStore = LifecycleMarkerFailingStore()
        let record = lifecycleRecord(marker: "initial", expiresAt: 1_100)
        let store = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await store.replace(with: record)
        let remote = LifecycleRemoteStub(
            refreshed: record,
            delay: .zero
        )
        let coordinator = SessionLifecycleCoordinator(
            store: store,
            remote: remote,
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )
        let lease = try await coordinator.leaseForRequest()
        let signal = CancellationSignalForLifecycle()
        _ = try await coordinator.beginPatientWork(
            lease: lease,
            cancel: signal.cancel
        )
        await secureStore.failMarkerWrites()

        #expect(await coordinator.signOut() == .localInvalidationFailed)
        try await coordinator.validate(lease)
        #expect(signal.count == 0)
        #expect(await remote.revokeCount == 0)
    }

    @Test("invalid refresh grant invalidates while transient refresh preserves old record")
    func refreshFailureClassificationPreservesBoundary() async throws {
        let invalidStore = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let record = lifecycleRecord(marker: "initial", expiresAt: 1_030)
        try await invalidStore.replace(with: record)
        let invalid = SessionLifecycleCoordinator(
            store: invalidStore,
            remote: FailingLifecycleRemote(error: .invalidGrant),
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )
        await #expect(throws: SessionLifecycleError.missingSession) {
            _ = try await invalid.leaseForRequest()
        }
        #expect(await invalidStore.currentRecord() == nil)

        let transientStore = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await transientStore.replace(with: record)
        let transient = SessionLifecycleCoordinator(
            store: transientStore,
            remote: FailingLifecycleRemote(error: .rateLimited),
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )
        await #expect(throws: SessionLifecycleError.refreshFailed) {
            _ = try await transient.leaseForRequest()
        }
        #expect(await transientStore.currentRecord() == record)
    }

    @Test("new-record persistence failure keeps the old user generation and work")
    func switchPersistenceFailurePreservesOldUser() async throws {
        let secureStore = LifecycleMarkerFailingStore()
        let old = lifecycleRecord(marker: "initial", expiresAt: 1_100)
        let store = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await store.replace(with: old)
        let remote = LifecycleRemoteStub(refreshed: old, delay: .zero)
        let coordinator = SessionLifecycleCoordinator(
            store: store,
            remote: remote,
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )
        let lease = try await coordinator.leaseForRequest()
        let signal = CancellationSignalForLifecycle()
        _ = try await coordinator.beginPatientWork(
            lease: lease,
            cancel: signal.cancel
        )
        await secureStore.failRecordWrites()

        await #expect(throws: AuthenticationSessionStoreError.storageUnavailable) {
            try await coordinator.switch(to: lifecycleRecord(
                userID: "00000000-0000-4000-8000-000000000002",
                marker: "replacement",
                expiresAt: 1_200
            ))
        }
        try await coordinator.validate(lease)
        #expect(signal.count == 0)
        #expect(await store.currentRecord() == old)
    }

    @Test("same-user reauthentication wins over an in-flight refresh")
    func sameUserSwitchWinsRefreshRace() async throws {
        let harness = try await LifecycleHarness(
            expiresAt: 1_030,
            refreshDelay: .milliseconds(150)
        )
        let refresh = Task {
            try await harness.coordinator.leaseForRequest()
        }
        await harness.remote.waitForRefreshStart()
        let replacement = lifecycleRecord(
            userID: harness.record.userID,
            marker: "reauthenticated-newest",
            expiresAt: 1_300
        )

        try await harness.coordinator.switch(to: replacement)
        let finalLease = try await refresh.value

        #expect(finalLease.bearer == replacement.accessToken)
        #expect(await harness.store.currentRecord() == replacement)
    }

    @Test("logout is marker-first and serializes a concurrent switch")
    func logoutMarkerBoundarySerializesSwitch() async throws {
        let secureStore = BlockingLifecycleMarkerStore()
        let old = lifecycleRecord(marker: "old", expiresAt: 1_100)
        let store = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await store.replace(with: old)
        let remote = LifecycleRemoteStub(refreshed: old, delay: .zero)
        let coordinator = SessionLifecycleCoordinator(
            store: store,
            remote: remote,
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )
        let oldLease = try await coordinator.leaseForRequest()
        await secureStore.blockMarkerWrite()
        let logout = Task { await coordinator.signOut() }
        await secureStore.waitForMarkerWrite()

        let validation = Task { try await coordinator.validate(oldLease) }
        let replacement = lifecycleRecord(
            userID: "00000000-0000-4000-8000-000000000002",
            marker: "new-user",
            expiresAt: 1_300
        )
        let switching = Task { try await coordinator.switch(to: replacement) }
        await secureStore.releaseMarkerWrite()

        _ = await logout.value
        await #expect(throws: SessionLifecycleError.missingSession) {
            try await validation.value
        }
        try await switching.value
        #expect(try await coordinator.leaseForRequest().bearer == replacement.accessToken)
        #expect(await store.currentRecord() == replacement)
    }

    @Test("invalid grant reports marker failure and preserves the old session")
    func invalidGrantReportsLocalInvalidationFailure() async throws {
        let secureStore = LifecycleMarkerFailingStore()
        let old = lifecycleRecord(marker: "old", expiresAt: 1_030)
        let store = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await store.replace(with: old)
        await secureStore.failMarkerWrites()
        let coordinator = SessionLifecycleCoordinator(
            store: store,
            remote: FailingLifecycleRemote(error: .invalidGrant),
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )

        await #expect(throws: SessionLifecycleError.localInvalidationFailed) {
            _ = try await coordinator.leaseForRequest()
        }
        #expect(await store.currentRecord() == old)
        #expect(await store.currentBearerToken() == old.accessToken)
    }

    @Test("stale invalid grant cannot revoke a same-user replacement")
    func staleInvalidGrantCannotRevokeReplacement() async throws {
        let secureStore = BlockingLifecycleMarkerStore()
        let old = lifecycleRecord(marker: "old", expiresAt: 1_030)
        let store = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await store.replace(with: old)
        let remote = ControlledInvalidGrantRemote()
        let coordinator = SessionLifecycleCoordinator(
            store: store,
            remote: remote,
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )
        let refreshing = Task { try await coordinator.leaseForRequest() }
        await remote.waitForRefreshStart()
        await secureStore.blockNextRecordWrite()
        let replacement = lifecycleRecord(
            marker: "newest",
            expiresAt: 1_300
        )
        let switching = Task { try await coordinator.switch(to: replacement) }
        await secureStore.waitForRecordWrite()

        await remote.releaseInvalidGrant()
        await secureStore.releaseRecordWrite()

        try await switching.value
        #expect(try await refreshing.value.bearer == replacement.accessToken)
        #expect(await store.currentRecord() == replacement)
        #expect(await remote.revokeCount == 0)
    }

    @Test("cancelled refresh waiter cannot discard a rotated session")
    func cancelledWaiterStillCommitsSuccessfulRefresh() async throws {
        let old = lifecycleRecord(marker: "old", expiresAt: 1_030)
        let refreshed = lifecycleRecord(
            marker: "rotated",
            refreshToken: "refresh-rotated",
            expiresAt: 1_300
        )
        let store = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await store.replace(with: old)
        let cancellation = LifecycleRequestCancellationRelay()
        let remote = CancellingRefreshRemote(
            outcome: .success(refreshed),
            cancelWaiter: cancellation.cancel
        )
        let coordinator = SessionLifecycleCoordinator(
            store: store,
            remote: remote,
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )
        let request = Task { try await coordinator.leaseForRequest() }
        cancellation.install(request)
        await remote.waitForRefreshStart()

        await remote.releaseRefresh()

        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
        #expect(await store.currentRecord() == refreshed)
    }

    @Test("cancelled refresh waiter cannot discard terminal invalidation")
    func cancelledWaiterStillCommitsInvalidGrant() async throws {
        let old = lifecycleRecord(marker: "old", expiresAt: 1_030)
        let store = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await store.replace(with: old)
        let cancellation = LifecycleRequestCancellationRelay()
        let remote = CancellingRefreshRemote(
            outcome: .invalidGrant,
            cancelWaiter: cancellation.cancel
        )
        let coordinator = SessionLifecycleCoordinator(
            store: store,
            remote: remote,
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )
        let request = Task { try await coordinator.leaseForRequest() }
        cancellation.install(request)
        await remote.waitForRefreshStart()

        await remote.releaseRefresh()

        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
        #expect(await store.currentRecord() == nil)
    }

    @Test("terminal invalid grant during restore becomes signed out")
    func restoreReturnsNilAfterInvalidGrant() async throws {
        let old = lifecycleRecord(marker: "old", expiresAt: 1_030)
        let store = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await store.replace(with: old)
        let coordinator = SessionLifecycleCoordinator(
            store: store,
            remote: FailingLifecycleRemote(error: .invalidGrant),
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )

        #expect(try await coordinator.restorePublicSession() == nil)
        #expect(await store.currentRecord() == nil)
    }
}

private struct LifecycleHarness: Sendable {
    let record: AuthenticationSessionRecord
    let store: AuthenticationSessionStore
    let remote: LifecycleRemoteStub
    let coordinator: SessionLifecycleCoordinator

    init(
        expiresAt: TimeInterval,
        refreshDelay: Duration = .zero,
        sensitiveStateClearer: any SensitiveStateClearing =
            NoopSensitiveStateClearer()
    ) async throws {
        record = lifecycleRecord(marker: "initial", expiresAt: expiresAt)
        store = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await store.replace(with: record)
        remote = LifecycleRemoteStub(
            refreshed: lifecycleRecord(
                marker: "rotated",
                refreshToken: "refresh-rotated",
                expiresAt: 1_200
            ),
            delay: refreshDelay
        )
        coordinator = SessionLifecycleCoordinator(
            store: store,
            remote: remote,
            sensitiveStateClearer: sensitiveStateClearer,
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) },
                leeway: 60
            )
        )
    }
}

private actor SensitiveClearerSpy: SensitiveStateClearing {
    private(set) var clearCount = 0
    func clearSensitiveState() { clearCount += 1 }
}

private actor LifecycleRemoteStub: SupabaseAuthRemoteOperating {
    let refreshed: AuthenticationSessionRecord
    let delay: Duration
    private(set) var refreshCount = 0
    private(set) var revokeCount = 0
    private var refreshStartWaiters: [CheckedContinuation<Void, Never>] = []

    init(refreshed: AuthenticationSessionRecord, delay: Duration) {
        self.refreshed = refreshed
        self.delay = delay
    }

    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) async throws -> AuthenticationSessionRecord {
        refreshCount += 1
        let waiters = refreshStartWaiters
        refreshStartWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        try await Task.sleep(for: delay)
        return refreshed
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome {
        revokeCount += 1
        return .confirmed
    }
    func waitForRefreshStart() async {
        guard refreshCount == 0 else { return }
        await withCheckedContinuation { refreshStartWaiters.append($0) }
    }
}

private actor BlockingLifecycleMarkerStore: SecureStoring {
    private var values: [String: Data] = [:]
    private var markerBlocked = false
    private var markerWriteStarted = false
    private var markerRelease: CheckedContinuation<Void, Never>?
    private var markerStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var recordBlocked = false
    private var recordWriteStarted = false
    private var recordRelease: CheckedContinuation<Void, Never>?
    private var recordStartWaiters: [CheckedContinuation<Void, Never>] = []

    func data(forKey key: String) -> Data? { values[key] }
    func store(_ data: Data, forKey key: String) async {
        if key == AuthenticationSessionStore.invalidationMarkerKey, markerBlocked {
            markerWriteStarted = true
            let waiters = markerStartWaiters
            markerStartWaiters.removeAll(keepingCapacity: false)
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { markerRelease = $0 }
        }
        if key == AuthenticationSessionStore.storageKey, recordBlocked {
            recordWriteStarted = true
            let waiters = recordStartWaiters
            recordStartWaiters.removeAll(keepingCapacity: false)
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { recordRelease = $0 }
        }
        values[key] = data
    }
    func removeData(forKey key: String) { values[key] = nil }
    func blockMarkerWrite() { markerBlocked = true }
    func waitForMarkerWrite() async {
        guard !markerWriteStarted else { return }
        await withCheckedContinuation { markerStartWaiters.append($0) }
    }
    func releaseMarkerWrite() {
        markerBlocked = false
        markerRelease?.resume()
        markerRelease = nil
    }
    func blockNextRecordWrite() { recordBlocked = true }
    func waitForRecordWrite() async {
        guard !recordWriteStarted else { return }
        await withCheckedContinuation { recordStartWaiters.append($0) }
    }
    func releaseRecordWrite() {
        recordBlocked = false
        recordRelease?.resume()
        recordRelease = nil
    }
}

private actor ControlledInvalidGrantRemote: SupabaseAuthRemoteOperating {
    private var refreshStarted = false
    private var refreshStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var failureRelease: CheckedContinuation<Void, Never>?
    private(set) var revokeCount = 0

    func signIn(email: String, password: String) throws
        -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws
        -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) async throws
        -> AuthenticationSessionRecord {
        refreshStarted = true
        let waiters = refreshStartWaiters
        refreshStartWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { failureRelease = $0 }
        throw SupabaseAuthRemoteError.invalidGrant
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome {
        revokeCount += 1
        return .confirmed
    }
    func waitForRefreshStart() async {
        guard !refreshStarted else { return }
        await withCheckedContinuation { refreshStartWaiters.append($0) }
    }
    func releaseInvalidGrant() {
        failureRelease?.resume()
        failureRelease = nil
    }
}

private actor CancellingRefreshRemote: SupabaseAuthRemoteOperating {
    enum Outcome: Sendable {
        case success(AuthenticationSessionRecord)
        case invalidGrant
    }

    let outcome: Outcome
    let cancelWaiter: @Sendable () -> Void
    private var refreshStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var refreshRelease: CheckedContinuation<Void, Never>?

    init(outcome: Outcome, cancelWaiter: @escaping @Sendable () -> Void) {
        self.outcome = outcome
        self.cancelWaiter = cancelWaiter
    }

    func signIn(email: String, password: String) throws
        -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws
        -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) async throws
        -> AuthenticationSessionRecord {
        refreshStarted = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { refreshRelease = $0 }
        cancelWaiter()
        switch outcome {
        case .success(let record):
            return record
        case .invalidGrant:
            throw SupabaseAuthRemoteError.invalidGrant
        }
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome {
        .confirmed
    }
    func waitForRefreshStart() async {
        guard !refreshStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func releaseRefresh() {
        refreshRelease?.resume()
        refreshRelease = nil
    }
}

private actor LifecycleMarkerFailingStore: SecureStoring {
    private var values: [String: Data] = [:]
    private var markerWritesFail = false
    private var recordWritesFail = false

    func data(forKey key: String) -> Data? { values[key] }
    func store(_ data: Data, forKey key: String) throws {
        if key == AuthenticationSessionStore.invalidationMarkerKey,
           markerWritesFail {
            throw LifecycleStoreFailure.unavailable
        }
        if key == AuthenticationSessionStore.storageKey, recordWritesFail {
            throw LifecycleStoreFailure.unavailable
        }
        values[key] = data
    }
    func removeData(forKey key: String) { values[key] = nil }
    func failMarkerWrites() { markerWritesFail = true }
    func failRecordWrites() { recordWritesFail = true }
}

private actor FailingLifecycleRemote: SupabaseAuthRemoteOperating {
    let error: SupabaseAuthRemoteError
    init(error: SupabaseAuthRemoteError) { self.error = error }
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw error
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw error
    }
    func requestPasswordRecovery(email: String) throws { throw error }
    func refresh(record: AuthenticationSessionRecord) throws
        -> AuthenticationSessionRecord {
        throw error
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome {
        .unconfirmed
    }
}

private enum LifecycleStoreFailure: Error { case unavailable }

private final class CancellationSignalForLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func cancel() { lock.withLock { value += 1 } }
}

private final class LifecycleRequestCancellationRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<SessionLease, Error>?

    func install(_ task: Task<SessionLease, Error>) {
        lock.withLock { self.task = task }
    }

    func cancel() {
        lock.withLock { task }?.cancel()
    }
}

private func lifecycleRecord(
    userID: String = "00000000-0000-4000-8000-000000000001",
    marker: String,
    refreshToken: String = "refresh-synthetic",
    expiresAt: TimeInterval
) -> AuthenticationSessionRecord {
    AuthenticationSessionRecord(
        userID: userID,
        email: "member@fixture.invalid",
        isEmailConfirmed: true,
        isOnboardingCompleted: false,
        accessToken: lifecycleToken(subject: userID, marker: marker),
        refreshToken: refreshToken,
        expiresAt: Date(timeIntervalSince1970: expiresAt)
    )
}

private func lifecycleToken(subject: String, marker: String) -> String {
    let header = Data(#"{"alg":"none"}"#.utf8).lifecycleBase64URL
    let payload = Data(#"{"sub":"\#(subject)","marker":"\#(marker)"}"#.utf8)
        .lifecycleBase64URL
    return "\(header).\(payload).synthetic"
}

private extension Data {
    var lifecycleBase64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
