#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

// Existing CaptureServerPeer/CaptureConsentGate remain the real pipeline
// fixtures. This thin provider adds only explicit DELETE / subsequent GET.
enum ExplicitDeleteUncertainFailure: String, CaseIterable, Equatable, Sendable {
    case offline, server500
    var failure: SignupBodyPhotoFailure { self == .offline ? .offline : .unavailable }
}
enum ExplicitDeleteOwnerStage: String, CaseIterable, Equatable, Sendable { case validation, receipt, reload }
enum ExplicitDeleteOwnerTransition: String, CaseIterable, Equatable, Sendable { case foreign, sameAccountNewRestore }
enum ExplicitDeleteLocalExit: String, CaseIterable, Equatable, Sendable { case cancelledProducer, declineConsent, retake, invalidate }

struct ExplicitDeleteReport: Sendable {
    let attempts: [MutationAttempt<SignupBodyPhotoDeleteCommand>]
    let postDeleteReads: Int
    let repairCalls: Int
}

actor ExplicitDeletePhotos: SignupBodyPhotosProviding {
    let peer: CaptureServerPeer
    let deleteGate: CaptureConsentGate
    let reloadGate: CaptureConsentGate
    private let deleted: Int
    private let reloadAvailable: Bool
    private var uncertainFirst: ExplicitDeleteUncertainFailure?
    private var failReloadOnce: Bool
    private var applied = false
    private var attempts: [MutationAttempt<SignupBodyPhotoDeleteCommand>] = []
    private var postDeleteReads = 0
    private var repairCalls = 0

    init(peer: CaptureServerPeer, deleteGate: CaptureConsentGate, reloadGate: CaptureConsentGate,
         uncertainFirst: ExplicitDeleteUncertainFailure? = nil, failReloadOnce: Bool = false,
         deleted: Int = 3, reloadAvailable: Bool = true) {
        self.peer = peer; self.deleteGate = deleteGate; self.reloadGate = reloadGate
        self.uncertainFirst = uncertainFirst; self.failReloadOnce = failReloadOnce
        self.deleted = deleted; self.reloadAvailable = reloadAvailable
    }
    func report() -> ExplicitDeleteReport {
        ExplicitDeleteReport(attempts: attempts, postDeleteReads: postDeleteReads, repairCalls: repairCalls)
    }
    func state() async throws -> SignupBodyPhotoState {
        guard applied else { return try await peer.state() }
        postDeleteReads += 1
        await reloadGate.enter() // ignores cancellation on purpose
        if failReloadOnce { failReloadOnce = false; throw SignupBodyPhotoFailure.offline }
        let source = try await peer.state()
        return SignupBodyPhotoState(available: reloadAvailable,
            unavailableReason: reloadAvailable ? nil : "disabled",
            consent: reloadAvailable ? source.consent : nil, minimumAge: source.minimumAge,
            poses: SignupBodyPhotoPose.allCases.map { SignupBodyPhotoSlot(pose: $0, photo: nil) },
            estimate: nil, remainingUploads: reloadAvailable ? 9 : 0)
    }
    func consent(_ a: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt { try await peer.consent(a) }
    func create(_ a: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await peer.create(a) }
    func complete(_ a: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await peer.complete(a) }
    func delete(_ a: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        attempts.append(a)
        await deleteGate.enter() // applies even if caller cancelled or reply is lost
        applied = true
        if let failure = uncertainFirst {
            uncertainFirst = nil
            switch failure {
            case .offline: throw SignupBodyPhotoFailure.offline
            case .server500: throw MobileAPITransportError.server(status: 500, code: "synthetic_delete_unknown", requestID: nil)
            }
        }
        return SignupBodyPhotoDeleteReceipt(deleted: deleted)
    }
    func repair(_ a: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        repairCalls += 1
        throw SignupBodyPhotoFailure.unavailable
    }
}

actor ExplicitDeleteValidation {
    private var next: CaptureConsentGate?
    func armNext(_ gate: CaptureConsentGate) { next = gate }
    func validate() async throws {
        try Task.checkCancellation()
        let held = next; next = nil
        await held?.enter() // consumer must recheck epoch/owner after this await
    }
}

actor ExplicitDeleteMarkers {
    private var values: Set<UUID> = []
    func remember(_ id: UUID) { values.insert(id) }
    func snapshot() -> Set<UUID> { values }
}

struct ExplicitDeleteUploader: StorageUploading {
    let peer: CaptureServerPeer
    let gate: CaptureConsentGate
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        try await peer.upload(media, with: ticket)
        await gate.enter() // noncooperative PUT; Task.cancel does not finish it
    }
}

@MainActor
final class ExplicitDeleteOwnerBox {
    var current: OnboardingOwnerToken
    init(_ owner: OnboardingOwnerToken) { current = owner }
}

@MainActor
final class ExplicitDeleteCompletion { var finished = false }

@MainActor
struct ExplicitDeleteHarness {
    let model: SignupBodyPhotoExplicitDeletionModel
    let original: SignupBodyPhotoCaptureModel
    let peer: CaptureServerPeer
    let photos: ExplicitDeletePhotos
    let validation: ExplicitDeleteValidation
    let markers: ExplicitDeleteMarkers
    let owner: OnboardingOwnerToken
    let ownerBox: ExplicitDeleteOwnerBox
    let putGate: CaptureConsentGate
    let deleteGate: CaptureConsentGate
    let reloadGate: CaptureConsentGate
    let cleanupPeer: CaptureCleanupPeer
    let staging: MediaStagingStore
    let base: URL

    init(holdPUT: Bool = false, holdDelete: Bool = false, holdReload: Bool = false,
         uncertainFirst: ExplicitDeleteUncertainFailure? = nil, failReloadOnce: Bool = false,
         deleted: Int = 3, reloadAvailable: Bool = true, failCleanupOnce: Bool = false) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signup-explicit-delete-\(UUID().uuidString)", isDirectory: true)
        let staging = MediaStagingStore(temporaryDirectory: base)
        let peer = CaptureServerPeer(staging: staging, consentGate: CaptureConsentGate())
        let put = CaptureConsentGate(holds: holdPUT)
        let deletion = CaptureConsentGate(holds: holdDelete)
        let reload = CaptureConsentGate(holds: holdReload)
        let photos = ExplicitDeletePhotos(peer: peer, deleteGate: deletion, reloadGate: reload,
            uncertainFirst: uncertainFirst, failReloadOnce: failReloadOnce, deleted: deleted, reloadAvailable: reloadAvailable)
        let validation = ExplicitDeleteValidation(), markers = ExplicitDeleteMarkers()
        let cleanup = CaptureCleanupPeer(gate: CaptureConsentGate(), failOnce: failCleanupOnce)
        let owner = OnboardingOwnerToken(userID: CaptureModelHarness.owner, restoreGeneration: 1)
        let ownerBox = ExplicitDeleteOwnerBox(owner)
        let scope = SignupBodyPhotoCaptureScope(userID: owner.userID, photos: photos,
            uploader: ExplicitDeleteUploader(peer: peer, gate: put), staging: staging, camera: .unavailable,
            validateSession: { try await validation.validate() },
            stagePhoto: { data, channel in try await peer.stage(data, channel: channel) },
            performWork: { operation in try await operation() },
            discardStaged: { file in try await cleanup.discard(file, staging: staging) },
            rememberUnboundCreate: { id in await markers.remember(id) })
        let capture = SignupBodyPhotoCaptureModel(scope: scope, ownerToken: owner,
            timeProvider: CaptureAttemptTime(), keyProvider: DeterministicIdempotencyKeyProvider(prefix: "explicit-capture-key"),
            isCurrentOwner: { $0 == ownerBox.current })
        self.model = SignupBodyPhotoExplicitDeletionModel(scope: scope, ownerToken: owner, captureModel: capture,
            timeProvider: CaptureAttemptTime(), keyProvider: DeterministicIdempotencyKeyProvider(prefix: "explicit-delete-key"),
            isCurrentOwner: { $0 == ownerBox.current })
        self.original = capture; self.peer = peer; self.photos = photos
        self.validation = validation; self.markers = markers; self.owner = owner; self.ownerBox = ownerBox
        self.putGate = put; self.deleteGate = deletion; self.reloadGate = reload; self.cleanupPeer = cleanup
        self.staging = staging; self.base = base
    }
    func prepare() async {
        await original.load()
        await original.acceptConsent(birthDate: "1990-01-01")
    }
    func clean() { try? FileManager.default.removeItem(at: base) }
    func beginDeletion(completion: ExplicitDeleteCompletion,
                       operationEnded: [CaptureConsentGate] = []) -> Task<Void, Never> {
        Task {
            await model.deletePhotos()
            completion.finished = true
            for gate in operationEnded { await gate.operationFinished() }
            await deleteGate.operationFinished()
            await reloadGate.operationFinished()
        }
    }
}
#endif
