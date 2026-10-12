import Foundation
import CryptoKit

/// UI preflight only. It does not grant consent, apply an estimate or mutate a draft.
/// The server remains the final age/locale/document authority before upload.
enum SignupBodyPhotoAvailability: Equatable, Sendable {
    case loading
    case available
    case unavailable
    case birthDateRequired
    case underage
    case consentLocaleMismatch

    static func resolve(
        draft: OnboardingDraft,
        state: SignupBodyPhotoState?,
        hasCapability: Bool,
        now: Date
    ) -> Self {
        guard hasCapability else { return .unavailable }
        guard let state else { return .loading }
        guard state.available, state.minimumAge == 18, let document = state.consent,
              document.documentKey == "body_photo_estimate_consent",
              document.version.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil,
              !document.body.isEmpty, document.body.count <= 4_000,
              document.bodyHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              SHA256.hash(data: Data(document.body.utf8)).map({ String(format: "%02x", $0) }).joined() == document.bodyHash
        else { return .unavailable }
        guard ["pt-BR", "en-US"].contains(draft.localeIdentifier),
              document.locale == draft.localeIdentifier else { return .consentLocaleMismatch }
        guard OnboardingCivilDate.timeZone(for: draft.timeZoneIdentifier) != nil else { return .unavailable }
        guard let birthDate = draft.birthDate else { return .birthDateRequired }
        guard let birth = OnboardingCivilDate.string(from: birthDate, timeZoneIdentifier: draft.timeZoneIdentifier),
              let today = OnboardingCivilDate.string(from: now, timeZoneIdentifier: draft.timeZoneIdentifier),
              let birthYear = Int(birth.prefix(4)), let currentYear = Int(today.prefix(4)) else { return .unavailable }
        // Civil month/day comparison preserves February 29's March 1 boundary
        // in a non-leap year. No elapsed-seconds approximation is involved.
        let years = currentYear - birthYear - (today.suffix(5) < birth.suffix(5) ? 1 : 0)
        return birth <= today && years >= state.minimumAge ? .available : .underage
    }
}
