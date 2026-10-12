#if DEBUG
import CryptoKit
import Foundation

/// B6b preparation: public state fixtures only, not a capture/backend simulation.
/// No ticket, replay claim, network, persistence or mutation authority is supplied.
struct SignupBodyPhotoPreviewProvider: SignupBodyPhotosProviding {
    let scenario: SignupBodyPhotoPreviewScenario
    let mode: AppRuntimeMode
    let buildFlavor: AppBuildFlavor

    func state() async throws -> SignupBodyPhotoState {
        try Task.checkCancellation()
        guard mode == .demo, buildFlavor == .debug else {
            throw SignupBodyPhotoFailure.unavailable
        }
        if scenario == .offline { throw SignupBodyPhotoFailure.offline }
        if scenario == .unavailable {
            return SignupBodyPhotoState(
                available: false, unavailableReason: "disabled", consent: nil,
                minimumAge: 18, poses: Self.emptySlots, estimate: nil, remainingUploads: 0
            )
        }
        let inputs: [ReferencePhoto]
        switch scenario {
        case .read: inputs = Self.readInputs
        case .unreadable: inputs = Self.unreadableInputs
        case .outOfRange: inputs = Self.outOfRangeInputs
        default: inputs = []
        }
        let poses = inputs.isEmpty ? Self.emptySlots : inputs.map { input in
            SignupBodyPhotoSlot(pose: input.pose, photo: SignupBodyPhoto(
                id: input.id, status: input.percent == nil ? "unreadable" : "read",
                createdAt: Self.timestamp
            ))
        }
        let estimate: SignupBodyPhotoEstimate?
        if scenario == .read {
            // Known backend fixture inputs18/24/30 produce aggregate24, equal weights.
            // Individual percentages remain private fixture data, never public slots.
            let decision = SignupBodyPhotoEstimate.Decision(
                usable: true, bodyFatPercent: Decimal(24), reason: nil
            )
            estimate = SignupBodyPhotoEstimate(
                isEstimate: true, bySex: .init(masculine: decision, feminine: decision),
                sourceIDs: .init(front: Self.readInputs[0].id, side: Self.readInputs[1].id,
                                back: Self.readInputs[2].id),
                fingerprint: Self.digest("synthetic-signup-inputs-18-24-30")
            )
        } else if scenario == .outOfRange {
            // Known input2/24/46 is unusable even though its raw mean would be24.
            // This is a fixed server-shaped fixture, not a second clinical algorithm.
            let decision = SignupBodyPhotoEstimate.Decision(
                usable: false, bodyFatPercent: nil, reason: "out_of_range"
            )
            estimate = SignupBodyPhotoEstimate(
                isEstimate: true, bySex: .init(masculine: decision, feminine: decision),
                sourceIDs: nil, fingerprint: nil
            )
        } else { estimate = nil }
        return SignupBodyPhotoState(
            available: true, unavailableReason: nil,
            consent: SignupBodyPhotoConsent(
                documentKey: "body_photo_estimate_consent", version: "test-2026-10-12",
                locale: "pt-BR", body: Self.testConsent, bodyHash: Self.digest(Self.testConsent),
                acceptedAt: scenario == .minor ? nil : Self.timestamp
            ),
            minimumAge: 18, poses: poses, estimate: estimate,
            remainingUploads: scenario == .limit ? 0 : (inputs.isEmpty ? 9 : 6)
        )
    }

    // B7 must define session-owned synthetic capture before enabling mutations.
    // In particular, delete takes the whole-scope empty command, never asset IDs.
    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws
        -> SignupBodyPhotoConsentReceipt {
        try Task.checkCancellation()
        throw SignupBodyPhotoFailure.unavailable
    }
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws
        -> SignupBodyPhotoCreateReceipt {
        try Task.checkCancellation()
        throw SignupBodyPhotoFailure.unavailable
    }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws
        -> SignupBodyPhotoCompleteReceipt {
        try Task.checkCancellation()
        throw SignupBodyPhotoFailure.unavailable
    }
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws
        -> SignupBodyPhotoDeleteReceipt {
        try Task.checkCancellation()
        throw SignupBodyPhotoFailure.unavailable
    }

    private struct ReferencePhoto: Sendable {
        let pose: SignupBodyPhotoPose
        let id: String
        let percent: Int?
    }
    private static let readInputs: [ReferencePhoto] = [
        .init(pose: .front, id: "00000000-0000-4000-8000-00000000b601", percent: 18),
        .init(pose: .side, id: "00000000-0000-4000-8000-00000000b602", percent: 24),
        .init(pose: .back, id: "00000000-0000-4000-8000-00000000b603", percent: 30),
    ]
    private static let unreadableInputs: [ReferencePhoto] = [
        .init(pose: .front, id: "00000000-0000-4000-8000-00000000b601", percent: 18),
        .init(pose: .side, id: "00000000-0000-4000-8000-00000000b602", percent: 24),
        .init(pose: .back, id: "00000000-0000-4000-8000-00000000b603", percent: nil),
    ]
    private static let outOfRangeInputs: [ReferencePhoto] = [
        .init(pose: .front, id: "00000000-0000-4000-8000-00000000b601", percent: 2),
        .init(pose: .side, id: "00000000-0000-4000-8000-00000000b602", percent: 24),
        .init(pose: .back, id: "00000000-0000-4000-8000-00000000b603", percent: 46),
    ]
    private static let emptySlots = SignupBodyPhotoPose.allCases.map {
        SignupBodyPhotoSlot(pose: $0, photo: nil)
    }
    private static let timestamp = APITimestamp(value: Date(timeIntervalSince1970: 1_791_849_600))
    private static let testConsent = "TEXTO DE TESTE — não é o consentimento do app."
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
