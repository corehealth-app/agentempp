import Foundation

/// Local draft provenance. It is not an eligibility or legacy API field.
enum OnboardingBodyFatOrigin: String, Codable, Sendable {
    case typed, photos
}

struct OnboardingBodyPhotoConfirmation: Codable, Equatable, Sendable {
    let value: Decimal
    let sex: BiologicalSex
    let sourceIDs: SignupBodyPhotoSourceIDs
    let fingerprint: String

    /// Uses the official canonical value; never recomputes the three-photo mean.
    static func candidate(from state: SignupBodyPhotoState, sex: BiologicalSex) -> Self? {
        guard state.available, state.consent?.acceptedAt != nil,
              state.consent?.documentKey == "body_photo_estimate_consent",
              let estimate = state.estimate, estimate.isEstimate,
              let ids = estimate.sourceIDs, let fingerprint = estimate.fingerprint,
              let readings = estimate.readings,
              readings.map(\.pose) == SignupBodyPhotoPose.allCases,
              readings.allSatisfy({ NSDecimalNumber(decimal: $0.bodyFatPercent).doubleValue.isFinite }),
              state.poses.map(\.pose) == SignupBodyPhotoPose.allCases,
              state.poses.map({ $0.photo?.id }) == [ids.front, ids.side, ids.back],
              state.poses.allSatisfy({ $0.photo?.status == "read" })
        else { return nil }
        let decision = sex == .masculine ? estimate.bySex.masculine : estimate.bySex.feminine
        guard decision.usable, let value = decision.bodyFatPercent else { return nil }
        let result = Self(value: value, sex: sex, sourceIDs: ids, fingerprint: fingerprint)
        return result.isValid ? result : nil
    }

    var isValid: Bool {
        let ids = [sourceIDs.front, sourceIDs.side, sourceIDs.back]
        var original = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, 2, .plain)
        return NSDecimalNumber(decimal: value).doubleValue.isFinite
            && (Decimal(3)...Decimal(60)).contains(value) && value == rounded
            && ids.allSatisfy { UUID(uuidString: $0) != nil }
            && Set(ids.map { $0.lowercased() }).count == 3
            && fingerprint.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }

    func matches(_ draft: OnboardingDraft) -> Bool {
        guard isValid, draft.bodyFatOrigin == .photos, draft.biologicalSex == sex,
              let number = draft.bodyFatPercent, number.isFinite,
              let decimal = Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX")) else { return false }
        return decimal == value
    }

    struct Intent: Encodable, Sendable {
        let decision = "accept"
        let sourceIDs: SignupBodyPhotoSourceIDs
        let fingerprint: String
        enum CodingKeys: String, CodingKey {
            case decision, fingerprint
            case sourceIDs = "source_ids"
        }
    }
    var intent: Intent { .init(sourceIDs: sourceIDs, fingerprint: fingerprint) }
}
