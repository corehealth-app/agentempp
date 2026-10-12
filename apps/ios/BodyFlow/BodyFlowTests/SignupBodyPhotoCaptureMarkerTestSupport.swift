#if DEBUG
import Foundation
@testable import BodyFlow

enum CaptureMarkerHold: String, Sendable { case beforeWrite, afterWrite }

actor CaptureMarkerStorePeer {
    let barrier: CleanupProcessorBarrier
    private let lifecycle: SessionLifecycleCoordinator
    private let lease: SessionLease
    private let store: SignupBodyPhotoCleanupStore
    private let hold: CaptureMarkerHold?
    private(set) var requested: [UUID] = []
    init(state: CleanupProcessorHarness, hold: CaptureMarkerHold?) {
        lifecycle = state.lifecycle; lease = state.lease; store = state.store
        self.hold = hold
        barrier = CleanupProcessorBarrier(holds: hold != nil)
    }
    func remember(_ operationID: UUID) async throws {
        requested.append(operationID)
        if hold == .beforeWrite { await barrier.enter() }
        let store = store, userID = lease.userID
        try await lifecycle.performPatientStateOperation(lease: lease) {
            try store.mutate(for: userID) { current in _ = current.rememberUnbound(operationID) }
        }
        if hold == .afterWrite { await barrier.enter() }
    }
}

/// Records the durable technical queue at CREATE entry, before delegating.
/// It never uses assertions inside a producer as proof of consumer completion.
actor CaptureMarkerPhotos: SignupBodyPhotosProviding {
    let server: CaptureServerPeer
    private let lifecycle: SessionLifecycleCoordinator
    private let lease: SessionLease
    private let store: SignupBodyPhotoCleanupStore
    private(set) var markersBeforeCreate: [[UUID]] = []
    init(server: CaptureServerPeer, state: CleanupProcessorHarness) {
        self.server = server; lifecycle = state.lifecycle; lease = state.lease; store = state.store
    }
    func state() async throws -> SignupBodyPhotoState { try await server.state() }
    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt {
        try await server.consent(attempt)
    }
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt {
        let store = store, userID = lease.userID
        let markers = try await lifecycle.performPatientStateOperation(lease: lease) {
            try store.load(for: userID).unboundCreates
        }
        markersBeforeCreate.append(markers)
        return try await server.create(attempt)
    }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt {
        try await server.complete(attempt)
    }
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        try await server.delete(attempt)
    }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        try await server.repair(attempt)
    }
}

@MainActor
struct CaptureMarkerHarness {
    let state: CleanupProcessorHarness
    let staging: MediaStagingStore
    let server: CaptureServerPeer
    let photos: CaptureMarkerPhotos
    let marker: CaptureMarkerStorePeer
    let model: SignupBodyPhotoCaptureModel
    let scope: SignupBodyPhotoCaptureScope

    init(hold: CaptureMarkerHold? = nil, failOnceAt: CaptureFailurePoint? = nil,
        readingFailsOnce: Bool = false) async throws {
        let state = try await CleanupProcessorHarness()
        let staging = MediaStagingStore(temporaryDirectory: state.folder.appendingPathComponent("capture-stage"))
        let server = CaptureServerPeer(staging: staging, consentGate: CaptureConsentGate(),
            failOnceAt: failOnceAt, readingFailsOnce: readingFailsOnce)
        let marker = CaptureMarkerStorePeer(state: state, hold: hold)
        let photos = CaptureMarkerPhotos(server: server, state: state)
        let lifecycle = state.lifecycle, lease = state.lease
        let scope = SignupBodyPhotoCaptureScope(userID: lease.userID, photos: photos, uploader: server,
            staging: staging, camera: .unavailable,
            validateSession: { try Task.checkCancellation(); try await lifecycle.validate(lease) },
            stagePhoto: { data, channel in try await server.stage(data, channel: channel) },
            performWork: { try await SignupSessionBoundWork(lifecycle: lifecycle, lease: lease).run($0) },
            discardStaged: { url in
                try await lifecycle.performPatientStateOperation(lease: lease) { staging.remove(url) }
            },
            rememberUnboundCreate: { try await marker.remember($0) })
        let owner = OnboardingOwnerToken(userID: lease.userID, restoreGeneration: 1)
        self.state = state; self.staging = staging; self.server = server
        self.photos = photos; self.marker = marker; self.scope = scope
        model = SignupBodyPhotoCaptureModel(scope: scope, ownerToken: owner,
            timeProvider: CaptureAttemptTime(),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "marker-create-key"),
            isCurrentOwner: { $0 == owner })
    }
    func accept() async {
        await model.load()
        await model.acceptConsent(birthDate: "1990-01-01")
    }
    func capture() async {
        await model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
    }
    func clean() { state.removeFolder() }
}
#endif
