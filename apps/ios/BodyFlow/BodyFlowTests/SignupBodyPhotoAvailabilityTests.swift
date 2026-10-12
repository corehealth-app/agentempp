import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup photo availability civil and current-document contracts")
struct SignupBodyPhotoAvailabilityTests {
    @Test("Nil real capability is unavailable even for an adult and a valid current document")
    func missingCapability() {
        let result = resolve(state: state(), capability: false)
        #expect(result == .unavailable)
    }

    @Test("A capability without a completed state read is loading; nil capability is not loading")
    func pendingRead() {
        #expect(resolve(state: nil, capability: true) == .loading)
        #expect(resolve(state: nil, capability: false) == .unavailable)
    }

    @Test("OFF and missing current text never become available", arguments: [AvailabilityOffReason.disabled, .consentTextMissing])
    func serverOff(_ reason: AvailabilityOffReason) {
        let snapshot = SignupBodyPhotoState(available: false, unavailableReason: reason.rawValue,
            consent: nil, minimumAge: 18, poses: emptySlots, estimate: nil, remainingUploads: 0)
        #expect(resolve(state: snapshot) == .unavailable)
    }

    @Test("An available response with no document cannot use a private-approved-text fallback")
    func documentMissing() {
        #expect(resolve(state: state(document: nil, defaultDocument: false)) == .unavailable)
    }

    @Test("PT and EN current wire documents are offered before or after consent", arguments: AvailabilityLocale.allCases, [false, true])
    func currentLocaleDocument(_ locale: AvailabilityLocale, accepted: Bool) {
        let snapshot = state(document: document(locale: locale.rawValue, accepted: accepted))
        #expect(resolve(state: snapshot, locale: locale.rawValue) == .available)
    }

    @Test("Supported document and draft locale must match exactly", arguments: AvailabilityLocale.allCases)
    func localeMismatch(_ locale: AvailabilityLocale) {
        let opposite = locale == .portuguese ? "en-US" : "pt-BR"
        #expect(resolve(state: state(document: document(locale: opposite)), locale: locale.rawValue) == .consentLocaleMismatch)
    }

    @Test("Current wire locale is never coerced to Portuguese or to an approved English fallback", arguments: ["pt_BR", "en", "fr-FR"])
    func unsupportedDraftLocale(_ locale: String) {
        #expect(resolve(state: state(), locale: locale) == .consentLocaleMismatch)
    }

    @Test("Only the supported server minimum age18 contract is accepted", arguments: [0, 17, 19])
    func unsupportedMinimumAge(_ minimum: Int) {
        #expect(resolve(state: state(minimumAge: minimum)) == .unavailable)
    }

    @Test("Missing DOB blocks only the photo path")
    func birthDateMissing() {
        #expect(resolve(state: state(), birth: nil) == .birthDateRequired)
    }

    @Test("Exact civil birthdays and February29 match declared-age semantics", arguments: AvailabilityCivilCase.allCases)
    func civilBoundary(_ sample: AvailabilityCivilCase) {
        #expect(resolve(state: state(), birth: sample.birth, now: utc(sample.now)) == sample.expected)
    }

    @Test("At one UTC instant, the local civil day changes the UI age", arguments: AvailabilityZoneCase.allCases)
    func timeZoneBoundary(_ sample: AvailabilityZoneCase) {
        #expect(resolve(state: state(), birth: "2008-10-12", zone: sample.zone,
            now: utc("2026-10-12T02:30:00Z")) == sample.expected)
    }

    @Test("An invalid draft timezone has no invented GMT or country default")
    func invalidTimeZone() {
        var candidate = draft(birth: "1990-01-01", zone: "UTC")
        candidate.timeZoneIdentifier = "Not/A_Timezone"
        let result = SignupBodyPhotoAvailability.resolve(draft: candidate, state: state(),
            hasCapability: true, now: utc("2026-10-12T15:00:00Z"))
        #expect(result == .unavailable)
    }

    @Test("Malformed current documents are unavailable", arguments: AvailabilityBadDocument.allCases)
    func malformedDocument(_ sample: AvailabilityBadDocument) {
        let supplied: SignupBodyPhotoConsent
        switch sample {
        case .wrongKey: supplied = document(key: "terms")
        case .emptyVersion: supplied = document(version: "")
        case .invalidVersion: supplied = document(version: "version with spaces")
        case .badHash: supplied = document(hash: "bad-hash")
        case .wrongHashForBody: supplied = document(hash: String(repeating: "f", count: 64))
        case .emptyBody: supplied = document(body: "")
        }
        #expect(resolve(state: state(document: supplied)) == .unavailable)
    }

    @Test("Any current server version with its coherent body/hash is consumed without a private whitelist", arguments: [false, true])
    func currentVersionFromServer(_ secondVersion: Bool) {
        let supplied = secondVersion
            ? document(version: "server-current-v2", body: Self.body2, hash: Self.hash2)
            : document(version: "server-current-v1")
        #expect(resolve(state: state(document: supplied)) == .available)
    }

    @Test("The choice gate does not require an existing estimate, readings or acceptance", arguments: AvailabilityEstimateFixture.allCases)
    func readonlyPhotoNumbersDoNotDefineAvailability(_ sample: AvailabilityEstimateFixture) {
        let supplied = snapshot(sample)
        #expect(resolve(state: supplied) == .available)
    }

    private static let body = "Documento sintético atual do servidor — somente teste.\n"
    private static let hash = "f3efb7cf148050fc3fb60330e04bd05a644386668a36e2e45e6b6126c69a237f"
    private static let body2 = "Current synthetic server document — test only.\n"
    private static let hash2 = "92d118b17a9127a36e654e2db31f07f43f1ee367a2157d7cca1a4e7cce0192a8"
    private var emptySlots: [SignupBodyPhotoSlot] {
        SignupBodyPhotoPose.allCases.map { .init(pose: $0, photo: nil) }
    }
    private func document(key: String = "body_photo_estimate_consent", version: String = "server-current-v1",
                          locale: String = "pt-BR", accepted: Bool = false,
                          body: String? = nil, hash: String? = nil) -> SignupBodyPhotoConsent {
        .init(documentKey: key, version: version, locale: locale, body: body ?? Self.body, bodyHash: hash ?? Self.hash,
            acceptedAt: accepted ? APITimestamp(value: utc("2026-10-12T12:00:00Z")) : nil)
    }
    // nil explicitly means no server document; default supplies a coherent fixture.
    private func state(document: SignupBodyPhotoConsent? = nil, minimumAge: Int = 18,
                       defaultDocument: Bool = true) -> SignupBodyPhotoState {
        .init(available: true, unavailableReason: nil,
            consent: defaultDocument ? (document ?? self.document()) : document,
            minimumAge: minimumAge, poses: emptySlots, estimate: nil, remainingUploads: 9)
    }
    private func draft(birth: String?, locale: String = "pt-BR", zone: String = "America/Sao_Paulo") -> OnboardingDraft {
        var result = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        result.localeIdentifier = locale
        result.timeZoneIdentifier = zone
        result.birthDate = birth.flatMap { OnboardingCivilDate.date(from: $0, timeZoneIdentifier: zone) }
        result.bodyFatPercent = nil
        result.bodyFatOrigin = nil
        result.bodyPhotoConfirmation = nil
        return result
    }
    private func resolve(state: SignupBodyPhotoState?, capability: Bool = true,
                         birth: String? = "1990-01-01", locale: String = "pt-BR",
                         zone: String = "America/Sao_Paulo",
                         now: Date? = nil) -> SignupBodyPhotoAvailability {
        SignupBodyPhotoAvailability.resolve(draft: draft(birth: birth, locale: locale, zone: zone),
            state: state, hasCapability: capability, now: now ?? utc("2026-10-12T15:00:00Z"))
    }
    private func utc(_ literal: String) -> Date {
        ISO8601DateFormatter().date(from: literal)!
    }
    private func snapshot(_ sample: AvailabilityEstimateFixture) -> SignupBodyPhotoState {
        if sample == .noPhotosYet { return state() }
        let ids = SignupBodyPhotoSourceIDs(front: "00000000-0000-4000-8000-00000000b601",
            side: "00000000-0000-4000-8000-00000000b602", back: "00000000-0000-4000-8000-00000000b603")
        let date = APITimestamp(value: utc("2026-10-12T12:00:00Z"))
        let decision = SignupBodyPhotoEstimate.Decision(usable: true, bodyFatPercent: Decimal(24), reason: nil)
        let actualReadings: [SignupBodyPhotoEstimate.Reading]? = sample == .threeRealReadings
            ? [.init(pose: .front, bodyFatPercent: Decimal(18)), .init(pose: .side, bodyFatPercent: Decimal(24)),
               .init(pose: .back, bodyFatPercent: Decimal(30))] : nil
        return .init(available: true, unavailableReason: nil, consent: document(accepted: true), minimumAge: 18,
            poses: zip(SignupBodyPhotoPose.allCases, [ids.front, ids.side, ids.back]).map {
                .init(pose: $0.0, photo: .init(id: $0.1, status: "read", createdAt: date))
            },
            estimate: .init(isEstimate: true, bySex: .init(masculine: decision, feminine: decision),
                sourceIDs: ids, fingerprint: String(repeating: "a", count: 64), readings: actualReadings),
            remainingUploads: 6)
    }
}

// Internal fixture parameter types: not runtime APIs, not publication/config.
enum AvailabilityOffReason: String, Sendable { case disabled, consentTextMissing = "consent_text_missing" }
enum AvailabilityLocale: String, CaseIterable, Equatable, Sendable { case portuguese = "pt-BR", english = "en-US" }
enum AvailabilityBadDocument: CaseIterable, Sendable { case wrongKey, emptyVersion, invalidVersion, badHash, wrongHashForBody, emptyBody }
enum AvailabilityEstimateFixture: CaseIterable, Equatable, Sendable { case noPhotosYet, scalarMeanOnly, threeRealReadings }
enum AvailabilityCivilCase: CaseIterable, Sendable {
    case oneDayBefore, eighteenthBirthday, leapBefore, leapBirthday, futureDOB
    var birth: String { switch self {
        case .oneDayBefore: "2008-10-13"
        case .eighteenthBirthday: "2008-10-12"
        case .leapBefore, .leapBirthday: "2008-02-29"
        case .futureDOB: "2030-01-01"
    } }
    var now: String { switch self {
        case .leapBefore: "2026-02-28T15:00:00Z"
        case .leapBirthday: "2026-03-01T15:00:00Z"
        default: "2026-10-12T15:00:00Z"
    } }
    var expected: SignupBodyPhotoAvailability { switch self {
        case .eighteenthBirthday, .leapBirthday: .available
        default: .underage
    } }
}
enum AvailabilityZoneCase: CaseIterable, Equatable, Sendable {
    case saoPaulo, utc
    var zone: String { self == .saoPaulo ? "America/Sao_Paulo" : "UTC" }
    var expected: SignupBodyPhotoAvailability { self == .saoPaulo ? .underage : .available }
}
