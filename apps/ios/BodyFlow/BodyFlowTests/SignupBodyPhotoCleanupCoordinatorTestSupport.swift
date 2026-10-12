#if DEBUG
import Foundation
@testable import BodyFlow

// Test target only: local state closures use the real protected store and gate.
enum CleanupProcessorHold: String, CaseIterable, Sendable {
    case load, read, prepare, repair, acknowledge, finish
}
enum CleanupProcessorMode: Sendable {
    case pending, currentUnknown, currentNotRequired, currentAbsent
    case unknown, absent, readFailure, repairFailure, invalidRepair
}
enum CleanupProcessorFailure: Error, Sendable { case scripted, write }

actor CleanupProcessorBarrier {
    private let holds: Bool
    private var entered = false
    private var ended = false
    private var released = false
    private var observers: [CheckedContinuation<Bool, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(holds: Bool) { self.holds = holds }
    func enter() async {
        entered = true
        let ready = observers; observers.removeAll()
        ready.forEach { $0.resume(returning: true) }
        if holds && !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func entryOrOperationEnd() async -> Bool {
        if entered { return true }
        if ended { return false }
        return await withCheckedContinuation { observers.append($0) }
    }
    func operationFinished() {
        ended = true
        if !entered {
            let ready = observers; observers.removeAll()
            ready.forEach { $0.resume(returning: false) }
        }
    }
    func release() {
        released = true
        let ready = waiters; waiters.removeAll(); ready.forEach { $0.resume() }
    }
}

struct CleanupProcessorPeerSnapshot: Sendable {
    let reads: [String?]
    let repairs: [MutationAttempt<SignupBodyPhotoRepairCommand>]
    let acknowledgementResults: [Bool]
}
actor CleanupProcessorPeer {
    private var mode: CleanupProcessorMode
    private var reads: [String?] = []
    private var repairs: [MutationAttempt<SignupBodyPhotoRepairCommand>] = []
    private var acknowledgementResults: [Bool] = []
    init(mode: CleanupProcessorMode) { self.mode = mode }
    func setMode(_ value: CleanupProcessorMode) { mode = value }
    func snapshot() -> CleanupProcessorPeerSnapshot {
        .init(reads: reads, repairs: repairs, acknowledgementResults: acknowledgementResults)
    }
    // Capture the typed answer before the caller enters its adverse hold.
    func read(_ requested: String?) -> Result<OnboardingBodyPhotoCleanupScope?, CleanupProcessorFailure> {
        reads.append(requested)
        let generation = requested ?? CleanupProcessorHarness.g1
        switch mode {
        case .readFailure: return .failure(.scripted)
        case .unknown: return .success(.init(generation: generation, state: .unknown))
        case .absent: return .success(nil)
        case .currentUnknown where requested == nil:
            return .success(.init(generation: generation, state: .unknown))
        case .currentNotRequired where requested == nil:
            return .success(.init(generation: generation, state: .notRequired))
        case .currentAbsent where requested == nil: return .success(nil)
        default: return .success(.init(generation: generation, state: .pending))
        }
    }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>)
        -> Result<SignupBodyPhotoDeleteReceipt, CleanupProcessorFailure> {
        repairs.append(attempt)
        switch mode {
        case .repairFailure: return .failure(.scripted)
        case .invalidRepair: return .success(.init(deleted: -1))
        default: return .success(.init(deleted: 0))
        }
    }
    func acknowledged(_ value: Bool) { acknowledgementResults.append(value) }
}

// Same lock discipline as existing deterministic providers, never actual credentials.
final class CleanupProcessorInputs: @unchecked Sendable, IdempotencyKeyProviding, TimeProviding {
    struct Counts: Equatable, Sendable { let keys: Int; let dates: Int }
    private let lock = NSLock()
    private var keys = 0
    private var dates = 0
    func nextKey() throws -> IdempotencyKey {
        try lock.withLock {
            keys += 1
            return try IdempotencyKey(validating: "cleanup-processor-key-\(keys)")
        }
    }
    var now: Date {
        lock.withLock {
            dates += 1
            return Date(timeIntervalSince1970: 1_790_000_000 + Double(dates))
        }
    }
    var counts: Counts { lock.withLock { .init(keys: keys, dates: dates) } }
}
final class CleanupProcessorWriteFault: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    func arm() { lock.withLock { armed = true } }
    func disarm() { lock.withLock { armed = false } }
    func trip() throws {
        let fail = lock.withLock { let value = armed; armed = false; return value }
        if fail { throw CleanupProcessorFailure.write }
    }
}
struct CleanupProcessorHarness: Sendable {
    static let a = "00000000-0000-4000-8000-000000d90101"
    static let b = "00000000-0000-4000-8000-000000d90102"
    static let g1 = "2026-10-12T12:34:56.123456+03:00"
    static let g2 = "2026-10-12T12:35:00.654321Z"
    static let marker = UUID(uuidString: "00000000-0000-4000-8000-000000d90301")!
    static let retainedDate = Date(timeIntervalSince1970: 1_790_000_000)
    let folder: URL
    let store: SignupBodyPhotoCleanupStore
    let inputs: CleanupProcessorInputs
    let writeFault: CleanupProcessorWriteFault
    let registry: PatientWorkRegistry
    let lifecycle: SessionLifecycleCoordinator
    let lease: SessionLease
    let peer: CleanupProcessorPeer
    let gate: CleanupProcessorBarrier
    let hold: CleanupProcessorHold?

    init(mode: CleanupProcessorMode = .pending, hold: CleanupProcessorHold? = nil) async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanup-processor-\(UUID().uuidString)", isDirectory: true)
        let fault = CleanupProcessorWriteFault()
        writeFault = fault
        store = SignupBodyPhotoCleanupStore(directory: folder, beforeAtomicWrite: { try fault.trip() })
        inputs = CleanupProcessorInputs()
        registry = PatientWorkRegistry()
        let authStore = AuthenticationSessionStore(secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) })
        try await authStore.replace(with: Self.record(Self.a))
        lifecycle = SessionLifecycleCoordinator(store: authStore, remote: CleanupProcessorAuthRemote(),
            patientWorkRegistry: registry,
            refreshPolicy: .init(now: { Date(timeIntervalSince1970: 1_000) }, leeway: 60))
        lease = try await lifecycle.leaseForRequest()
        peer = CleanupProcessorPeer(mode: mode)
        gate = CleanupProcessorBarrier(holds: hold != nil)
        self.hold = hold
    }

    var scope: SignupBodyPhotoCleanupScope {
        let userID = lease.userID, lifecycle = lifecycle, lease = lease
        let store = store, inputs = inputs, peer = peer
        return SignupBodyPhotoCleanupScope(userID: userID,
            validateSession: { try Task.checkCancellation(); try await lifecycle.validate(lease) },
            loadQueue: {
                await self.holdAt(.load)
                return try await lifecycle.performPatientStateOperation(lease: lease) { try store.load(for: userID) }
            },
            observePending: { generation, authorization in
                try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                    try authorization.validate()
                    try store.mutate(for: userID) { current in
                        _ = try current.observePending(generation, newRevision: UUID())
                    }
                }
            },
            prepareRepair: { generation, expectedRevision, authorization in
                await self.holdAt(.prepare)
                return try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                    try authorization.validate()
                    return try store.mutate(for: userID) { current -> SignupBodyPhotoCleanupTicket? in
                        guard current.scope(generation)?.revision == expectedRevision else { return nil }
                        _ = try current.observePending(generation, newRevision: UUID())
                        guard let observed = current.scope(generation) else { throw CleanupProcessorFailure.scripted }
                        return try current.prepareRepair(generation, expectedRevision: observed.revision,
                            newRevision: UUID(), operationID: UUID(),
                            takeKey: { try inputs.nextKey() }, takeDate: { inputs.now })
                    }
                }
            },
            acknowledge: { ticket, authorization in
                await self.holdAt(.acknowledge)
                let value = try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                    try authorization.validate()
                    return try store.mutate(for: userID) { current in try current.acknowledge(ticket, newRevision: UUID()) }
                }
                await peer.acknowledged(value)
                return value
            },
            resolveNotRequired: { generation, revision, authorization in
                try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                    try authorization.validate()
                    return try store.mutate(for: userID) { current in current.resolveNotRequired(generation, expectedRevision: revision) }
                }
            },
            readScope: { generation in
                try await lifecycle.validate(lease)
                let answer = await peer.read(generation)
                await self.holdAt(.read)
                try await lifecycle.validate(lease)
                return try answer.get()
            },
            repair: { attempt in
                try await lifecycle.validate(lease)
                let answer = await peer.repair(attempt)
                await self.holdAt(.repair)
                try await lifecycle.validate(lease)
                return try answer.get()
            },
            performWork: { operation in
                try await SignupSessionBoundWork(lifecycle: lifecycle, lease: lease).run(operation)
                await self.holdAt(.finish)
                try await lifecycle.validate(lease)
                try Task.checkCancellation()
            })
    }

    private func holdAt(_ point: CleanupProcessorHold) async {
        if hold == point { await gate.enter() }
    }
    func seed(generations: [String] = [CleanupProcessorHarness.g1, CleanupProcessorHarness.g2], unbound: Bool = false,
        ackedG1: Bool = false) async throws {
        let userID = lease.userID, store = store
        try await lifecycle.performPatientStateOperation(lease: lease) {
            try store.mutate(for: userID) { current in
                for generation in generations {
                    current.knownScopes.append(.init(generation: generation, revision: UUID(), operationID: nil,
                        pending: !(ackedG1 && generation == Self.g1),
                        repair: ackedG1 && generation == Self.g1
                            ? .init(key: "cleanup-retained-key-g1", createdAt: Self.retainedDate) : nil))
                }
                if unbound { _ = current.rememberUnbound(Self.marker) }
            }
        }
    }
    func mutate<Value: Sendable>(_ operation: @Sendable (inout SignupBodyPhotoCleanupQueue) throws -> Value)
        async throws -> Value {
        let store = store, userID = lease.userID
        return try await lifecycle.performPatientStateOperation(lease: lease) { try store.mutate(for: userID, operation) }
    }
    func queue(for userID: String = CleanupProcessorHarness.a) async throws -> SignupBodyPhotoCleanupQueue {
        let fresh = try await lifecycle.leaseForRequest(), store = store
        guard fresh.userID == userID else { throw SessionLifecycleError.sessionSuperseded }
        return try await lifecycle.performPatientStateOperation(lease: fresh) { try store.load(for: userID) }
    }
    func seedLaterOwner(_ userID: String) async throws -> Data {
        let fresh = try await lifecycle.leaseForRequest(), store = store
        guard fresh.userID == userID else { throw SessionLifecycleError.sessionSuperseded }
        return try await lifecycle.performPatientStateOperation(lease: fresh) {
            try store.mutate(for: userID) { current in
                _ = try current.observePending(Self.g2, newRevision: UUID())
                _ = current.rememberUnbound(UUID())
            }
            return try Data(contentsOf: store.fileURL(for: userID))
        }
    }
    func removeFolder() { try? FileManager.default.removeItem(at: folder) }
    static func record(_ userID: String) -> AuthenticationSessionRecord {
        let header = Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8).base64EncodedString()
        let payload = Data(#"{"sub":"\#(userID)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return AuthenticationSessionRecord(userID: userID, email: "synthetic@example.invalid",
            isEmailConfirmed: true, isOnboardingCompleted: true,
            accessToken: "\(header).\(payload).synthetic-signature", refreshToken: "synthetic-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_500))
    }
}

private actor CleanupProcessorAuthRemote: SupabaseAuthRemoteOperating {
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord { throw SupabaseAuthRemoteError.requestFailed }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult { throw SupabaseAuthRemoteError.requestFailed }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord { CleanupProcessorHarness.record(record.userID) }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}

actor CleanupProcessorCountingLifecycle: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    private(set) var leaseRequests = 0
    init(base: SessionLifecycleCoordinator) { self.base = base }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease { leaseRequests += 1; return try await base.leaseForRequest() }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease { try await base.refreshAfterUnauthorized(lease: lease) }
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
#endif
