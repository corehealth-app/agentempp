#if DEBUG
import Foundation
@testable import BodyFlow

enum SignupPhotoViewFixture: CaseIterable, Equatable, Sendable {
    case valid, canonicalFraction, legacyReadings, unusable, captureTerminal, captureWaiting
}
private enum SignupPhotoViewFixtureError: Error { case invalidDecimal }
/// Only declared public DTO scripts. No nutrition formula, provider/storage,
/// private camera payload or new runtime field.
actor SignupPhotoViewPeer: SignupBodyPhotosProviding {
    let base: PresentationPhotoPeer
    let fixture: SignupPhotoViewFixture
    init(base: PresentationPhotoPeer, fixture: SignupPhotoViewFixture) { self.base = base; self.fixture = fixture }
    func state() async throws -> SignupBodyPhotoState {
        let raw = try await base.state()
        var estimate = raw.estimate
        var poses = raw.poses
        switch fixture {
        case .valid: break
        case .legacyReadings:
            if let value = estimate {
                estimate = .init(isEstimate: value.isEstimate, bySex: value.bySex,
                    sourceIDs: value.sourceIDs, fingerprint: value.fingerprint, readings: nil)
            }
        case .unusable:
            if let value = estimate {
                let decision = SignupBodyPhotoEstimate.Decision(usable: false, bodyFatPercent: nil,
                    reason: "synthetic-outside")
                estimate = .init(isEstimate: value.isEstimate, bySex: .init(masculine: decision, feminine: decision),
                    sourceIDs: value.sourceIDs, fingerprint: value.fingerprint,
                    readings: [.init(pose: .front, bodyFatPercent: Decimal(2)),
                        .init(pose: .side, bodyFatPercent: Decimal(24)), .init(pose: .back, bodyFatPercent: Decimal(46))])
            }
        case .canonicalFraction:
            if let value = estimate {
                guard let canonical = Decimal(string: "24.13", locale: Locale(identifier: "en_US_POSIX"))
                else { throw SignupPhotoViewFixtureError.invalidDecimal }
                let readings = try zip(SignupBodyPhotoPose.allCases, ["18.125", "24.125", "30.125"]).map { pose, text in
                    guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
                    else { throw SignupPhotoViewFixtureError.invalidDecimal }
                    return SignupBodyPhotoEstimate.Reading(pose: pose, bodyFatPercent: decimal)
                }
                let decision = SignupBodyPhotoEstimate.Decision(usable: true, bodyFatPercent: canonical, reason: nil)
                estimate = .init(isEstimate: value.isEstimate, bySex: .init(masculine: decision, feminine: decision),
                    sourceIDs: value.sourceIDs, fingerprint: value.fingerprint, readings: readings)
            }
        case .captureTerminal, .captureWaiting:
            let statuses = fixture == .captureTerminal
                ? ["read", "unreadable", "reading_failed"] : ["uploaded", "reading", "pending_upload"]
            poses = raw.poses.enumerated().map { index, slot in
                .init(pose: slot.pose, photo: slot.photo.map {
                    .init(id: $0.id, status: statuses[index], createdAt: $0.createdAt)
                })
            }
            estimate = nil
        }
        return .init(available: raw.available, unavailableReason: raw.unavailableReason, consent: raw.consent,
            minimumAge: raw.minimumAge, poses: poses, estimate: estimate, remainingUploads: raw.remainingUploads)
    }
    func consent(_ a: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt { try await base.consent(a) }
    func create(_ a: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await base.create(a) }
    func complete(_ a: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await base.complete(a) }
    func delete(_ a: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.delete(a) }
    func repair(_ a: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.repair(a) }
}
@MainActor
struct SignupPhotoViewHarness {
    let base: PresentationHarness
    let factory: PresentationFactoryPeer
    let model: SignupBodyPhotoPresentationModel
    init(fixture: SignupPhotoViewFixture = .valid, manual: Double? = nil,
         camera: MealCameraAccess? = nil) async throws {
        let base = try await PresentationHarness(manual: manual, hasEstimate: true)
        let peer = SignupPhotoViewPeer(base: base.peer, fixture: fixture)
        let original = presentationScope(base.scope, photos: peer)
        let scope = SignupBodyPhotoCaptureScope(userID: original.userID,
            photos: original.photos, uploader: original.uploader, staging: original.staging,
            camera: camera ?? original.camera, validateSession: original.validateSession,
            stagePhoto: original.stagePhoto, performWork: original.performWork,
            discardStaged: original.discardStaged, rememberUnboundCreate: original.rememberUnboundCreate)
        let factory = PresentationFactoryPeer(scope: scope)
        let box = base.ownerBox, clock = base.clock
        model = .init(flow: base.flow, ownerToken: base.owner, capability: factory.capability,
            timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "capture-result-view"),
            pollingTiming: .init(elapsed: { await clock.elapsed() }, sleep: { try await clock.sleep($0) }),
            isCurrentOwner: { $0 == box.current })
        self.base = base; self.factory = factory
    }
    func prepare() async { await model.load(); model.select(.photos); await model.acceptConsent() }
    func stop() async {
        model.invalidate()
        if let core = model.capture { await core.waitForStoppedPollingWork() }
        base.clean()
    }
}
#endif
