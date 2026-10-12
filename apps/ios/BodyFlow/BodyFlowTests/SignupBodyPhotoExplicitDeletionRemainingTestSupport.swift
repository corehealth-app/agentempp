#if DEBUG
import Foundation
import Observation
import Testing
@testable import BodyFlow

enum ExplicitDeleteR3LiveRequest: String, CaseIterable, Equatable, Sendable { case initial, retryAfterUncertain }
enum ExplicitDeleteR3FinishOutcome: String, CaseIterable, Equatable, Sendable { case unchanged, newUIRestore, supersededLease }

struct ExplicitDeleteR3WorkReport: Sendable {
    let begun: Set<UUID>
    let finished: Set<UUID>
    let active: Set<UUID>
}

/// Stateful retained-lease authority fixture. It executes the real callback,
/// tracks each work registration, always finishes, and validates after finish.
/// No new runtime authority/API and no identity renewed during an operation.
actor ExplicitDeleteR3Registry {
    private let retainedLease = UUID()
    private var leaseValid = true
    private var begun: Set<UUID> = []
    private var finished: Set<UUID> = []
    private var active: Set<UUID> = []
    private var nextFinish: CaptureConsentGate?
    func armNextFinish(_ gate: CaptureConsentGate) { nextFinish = gate }
    func supersedeLease() { leaseValid = false }
    func validate() throws {
        guard leaseValid else { throw SessionLifecycleError.sessionSuperseded }
        try Task.checkCancellation()
    }
    func report() -> ExplicitDeleteR3WorkReport {
        ExplicitDeleteR3WorkReport(begun: begun, finished: finished, active: active)
    }
    func run(_ operation: @Sendable () async throws -> Void) async throws {
        try validate()
        let lease = retainedLease, id = UUID(), gate = nextFinish
        nextFinish = nil
        begun.insert(id); active.insert(id)
        let outcome: Result<Void, Error>
        do {
            try await operation()
            try validate()
            outcome = .success(())
        } catch { outcome = .failure(error) }
        // Like finishPatientWork, this completes even if the caller cancelled.
        await gate?.enter()
        active.remove(id); finished.insert(id)
        guard lease == retainedLease else { throw SessionLifecycleError.sessionSuperseded }
        try validate()
        try outcome.get()
    }
}

actor ExplicitDeleteR3Cleanup {
    let peer: CaptureCleanupPeer
    private var files: [URL] = []
    init(failOnce: Bool) { peer = CaptureCleanupPeer(gate: CaptureConsentGate(), failOnce: failOnce) }
    func discard(_ file: URL, staging: MediaStagingStore) async throws {
        files.append(file)
        try await peer.discard(file, staging: staging)
    }
    func attemptedFiles() -> [URL] { files }
}

/// Adds one held provider invocation to R2's receipt/read script. The attempt
/// is recorded on entry, before the cancellation-ignoring provider wait.
actor ExplicitDeleteR3Photos: SignupBodyPhotosProviding {
    let inner: ExplicitDeletePhotos
    private var nextDelete: CaptureConsentGate?
    private var requests: [MutationAttempt<SignupBodyPhotoDeleteCommand>] = []
    init(inner: ExplicitDeletePhotos) { self.inner = inner }
    func armNextDelete(_ gate: CaptureConsentGate) { nextDelete = gate }
    func attempts() -> [MutationAttempt<SignupBodyPhotoDeleteCommand>] { requests }
    func state() async throws -> SignupBodyPhotoState { try await inner.state() }
    func consent(_ a: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt { try await inner.consent(a) }
    func create(_ a: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await inner.create(a) }
    func complete(_ a: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await inner.complete(a) }
    func delete(_ a: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        requests.append(a)
        let gate = nextDelete; nextDelete = nil
        await gate?.enter()
        return try await inner.delete(a)
    }
    func repair(_ a: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await inner.repair(a) }
}

@MainActor @Observable
final class ExplicitDeleteR3CallerProbe { var started = false }

@MainActor
struct ExplicitDeleteR3Harness {
    let model: SignupBodyPhotoExplicitDeletionModel
    let original: SignupBodyPhotoCaptureModel
    let peer: CaptureServerPeer
    let photos: ExplicitDeleteR3Photos
    let inner: ExplicitDeletePhotos
    let registry: ExplicitDeleteR3Registry
    let cleanup: ExplicitDeleteR3Cleanup
    let owner: OnboardingOwnerToken
    let ownerBox: ExplicitDeleteOwnerBox
    let staging: MediaStagingStore
    let base: URL

    init(failCreateOnce: Bool = false, failCleanupOnce: Bool = false,
         uncertainFirst: ExplicitDeleteUncertainFailure? = nil) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signup-explicit-delete-r3-\(UUID().uuidString)", isDirectory: true)
        let staging = MediaStagingStore(temporaryDirectory: base)
        let peer = CaptureServerPeer(staging: staging, consentGate: CaptureConsentGate(),
            failOnceAt: failCreateOnce ? .create : nil)
        let inner = ExplicitDeletePhotos(peer: peer, deleteGate: CaptureConsentGate(), reloadGate: CaptureConsentGate(), uncertainFirst: uncertainFirst)
        let photos = ExplicitDeleteR3Photos(inner: inner), registry = ExplicitDeleteR3Registry()
        let cleanup = ExplicitDeleteR3Cleanup(failOnce: failCleanupOnce)
        let owner = OnboardingOwnerToken(userID: CaptureModelHarness.owner, restoreGeneration: 1)
        let box = ExplicitDeleteOwnerBox(owner)
        let scope = SignupBodyPhotoCaptureScope(userID: owner.userID, photos: photos, uploader: peer,
            staging: staging, camera: .unavailable,
            validateSession: { try await registry.validate() },
            stagePhoto: { data, channel in try await peer.stage(data, channel: channel) },
            performWork: { operation in try await registry.run(operation) },
            discardStaged: { file in try await cleanup.discard(file, staging: staging) },
            rememberUnboundCreate: { _ in try await registry.validate() })
        let original = SignupBodyPhotoCaptureModel(scope: scope, ownerToken: owner,
            timeProvider: CaptureAttemptTime(), keyProvider: DeterministicIdempotencyKeyProvider(prefix: "explicit-r3-capture"),
            isCurrentOwner: { $0 == box.current })
        self.model = SignupBodyPhotoExplicitDeletionModel(scope: scope, ownerToken: owner, captureModel: original,
            timeProvider: CaptureAttemptTime(), keyProvider: DeterministicIdempotencyKeyProvider(prefix: "explicit-r3-delete"),
            isCurrentOwner: { $0 == box.current })
        self.original = original; self.peer = peer; self.photos = photos; self.inner = inner
        self.registry = registry; self.cleanup = cleanup; self.owner = owner; self.ownerBox = box
        self.staging = staging; self.base = base
    }
    func prepare() async {
        await original.load()
        await original.acceptConsent(birthDate: "1990-01-01")
    }
    func clean() { try? FileManager.default.removeItem(at: base) }
    func begin(retry: Bool, completion: ExplicitDeleteCompletion, ended: CaptureConsentGate) -> Task<Void, Never> {
        Task {
            if retry { await model.retryDeletion() } else { await model.deletePhotos() }
            completion.finished = true
            await ended.operationFinished()
        }
    }
    /// A private MainActor prefix proves the caller reached the async method
    /// while the first request is held. Either join or early busy-return is OK.
    /// The observation task runs only after that caller yields/returns; no sleep.
    func beginConcurrent(retry: Bool, entered: CaptureConsentGate) -> Task<Void, Never> {
        let probe = ExplicitDeleteR3CallerProbe()
        withObservationTracking { _ = probe.started } onChange: { Task { await entered.enter() } }
        return Task {
            probe.started = true
            if retry { await model.retryDeletion() } else { await model.deletePhotos() }
            await entered.operationFinished()
        }
    }
}
#endif
