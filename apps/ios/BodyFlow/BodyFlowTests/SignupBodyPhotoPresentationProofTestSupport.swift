#if DEBUG
import Foundation
@testable import BodyFlow

enum PresentationEstimateVariant: CaseIterable, Equatable, Sendable { case legacyReadings, unusableDecision }
enum PresentationRejectAction: CaseIterable, Sendable { case reject, skip }

actor PresentationVariantPeer: SignupBodyPhotosProviding {
    let base: PresentationPhotoPeer
    let variant: PresentationEstimateVariant
    init(base: PresentationPhotoPeer, variant: PresentationEstimateVariant) { self.base = base; self.variant = variant }
    func state() async throws -> SignupBodyPhotoState {
        let raw = try await base.state()
        let estimate: SignupBodyPhotoEstimate?
        if let current = raw.estimate {
            if variant == .legacyReadings {
                estimate = .init(isEstimate: current.isEstimate, bySex: current.bySex,
                    sourceIDs: current.sourceIDs, fingerprint: current.fingerprint, readings: nil)
            } else {
                let unusable = SignupBodyPhotoEstimate.Decision(usable: false, bodyFatPercent: nil, reason: "synthetic-outside")
                estimate = .init(isEstimate: current.isEstimate, bySex: .init(masculine: unusable, feminine: unusable),
                    sourceIDs: current.sourceIDs, fingerprint: current.fingerprint,
                    readings: [.init(pose: .front, bodyFatPercent: Decimal(2)),
                        .init(pose: .side, bodyFatPercent: Decimal(24)), .init(pose: .back, bodyFatPercent: Decimal(46))])
            }
        } else { estimate = nil }
        return .init(available: raw.available, unavailableReason: raw.unavailableReason, consent: raw.consent,
            minimumAge: raw.minimumAge, poses: raw.poses, estimate: estimate, remainingUploads: raw.remainingUploads)
    }
    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt { try await base.consent(attempt) }
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await base.create(attempt) }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await base.complete(attempt) }
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.delete(attempt) }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.repair(attempt) }
}

func presentationScope(_ base: SignupBodyPhotoCaptureScope, photos: any SignupBodyPhotosProviding) -> SignupBodyPhotoCaptureScope {
    .init(userID: base.userID, photos: photos, uploader: base.uploader, staging: base.staging, camera: base.camera,
        validateSession: base.validateSession, stagePhoto: base.stagePhoto, performWork: base.performWork,
        discardStaged: base.discardStaged, rememberUnboundCreate: base.rememberUnboundCreate)
}
#endif
