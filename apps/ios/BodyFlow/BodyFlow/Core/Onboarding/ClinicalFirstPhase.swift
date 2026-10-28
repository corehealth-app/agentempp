import Foundation

enum ClinicalFirstPhaseFailure: Error, Equatable, Sendable {
    case offline, changed, busy, unavailable, invalidResponse, sessionEnded
}

struct ClinicalFirstPhaseChoices: Codable, Equatable, Sendable {
    enum Availability: String, Codable, Sendable { case available, blocked, incomplete }
    struct Option: Codable, Equatable, Sendable {
        enum Status: String, Codable, Sendable { case available, blocked; case notOffered = "not_offered" }
        enum Reason: String, Codable, Sendable { case composition = "gain_composition", training = "gain_training" }
        let phase: BodyFlowObjective
        let status: Status
        let reasons: [Reason]
    }
    let version: Int
    let availability: Availability
    let date: String
    let effectiveDate: String
    let professionalAssessmentRecommended: Bool
    let missing: [String]
    let options: [Option]
    private enum CodingKeys: String, CodingKey {
        case version, availability, date, missing, options
        case effectiveDate = "effective_date"
        case professionalAssessmentRecommended = "professional_assessment_recommended"
    }
    func validated() throws -> Self {
        let fields = Set(["sex", "birth_date", "height_cm", "weight_kg", "activity_level", "training_frequency", "hunger_level"])
        guard version == 1, Self.validDate(date), Self.validDate(effectiveDate),
              Set(missing).count == missing.count, Set(missing).isSubset(of: fields),
              options.count <= 3, Set(options.map(\.phase.rawValue)).count == options.count,
              availability != .available || (missing.isEmpty && options.contains { $0.status == .available }),
              availability == .available || options.isEmpty else { throw ClinicalFirstPhaseFailure.invalidResponse }
        return self
    }
    static func validDate(_ value: String) -> Bool {
        !value.hasPrefix("0000") && OnboardingCivilDate.date(from: value, timeZoneIdentifier: "UTC") != nil
    }
    static func validID(_ value: String) -> Bool {
        value.count == 36 && UUID(uuidString: value)?.uuidString.lowercased() == value.lowercased()
    }
}

struct ClinicalFirstPhasePreview: Codable, Equatable, Sendable {
    struct Targets: Codable, Equatable, Sendable {
        let caloriesKcal: Int
        let proteinG: Decimal
        private enum CodingKeys: String, CodingKey { case caloriesKcal = "calories_kcal", proteinG = "protein_g" }
    }
    let version: Int
    let previewID: String
    let phase: BodyFlowObjective
    let effectiveDate: String
    let expiresAt: APITimestamp
    let targets: Targets
    private enum CodingKeys: String, CodingKey {
        case version, phase, targets
        case previewID = "preview_id", effectiveDate = "effective_date", expiresAt = "expires_at"
    }
    func validated() throws -> Self {
        guard version == 1, ClinicalFirstPhaseChoices.validID(previewID),
              ClinicalFirstPhaseChoices.validDate(effectiveDate),
              targets.caloriesKcal > 0, targets.caloriesKcal <= 2_147_483_647,
              !targets.proteinG.isNaN, targets.proteinG >= 0, targets.proteinG <= Decimal(999999) / 100 else {
            throw ClinicalFirstPhaseFailure.invalidResponse
        }
        return self
    }
}

/// Historical ACK only. Refresh current policy/readers after receipt; this
/// cannot restore targets or assert that a more recent health risk was cleared.
struct ClinicalFirstPhaseConfirmation: Codable, Equatable, Sendable {
    let version: Int
    let confirmationID: String
    let phase: BodyFlowObjective
    let effectiveDate: String
    let confirmedAt: APITimestamp
    private enum CodingKeys: String, CodingKey {
        case version, phase
        case confirmationID = "confirmation_id", effectiveDate = "effective_date", confirmedAt = "confirmed_at"
    }
    func validated() throws -> Self {
        guard version == 1, ClinicalFirstPhaseChoices.validID(confirmationID),
              ClinicalFirstPhaseChoices.validDate(effectiveDate) else { throw ClinicalFirstPhaseFailure.invalidResponse }
        return self
    }
}

protocol ClinicalFirstPhaseProviding: Sendable {
    /// userID is the immutable Auth subject of the shell, not the patient row ID.
    func scoped(for userID: String) async throws -> any ClinicalFirstPhaseProviding
    func choices() async throws -> ClinicalFirstPhaseChoices
    func prepare(phase: BodyFlowObjective, key: IdempotencyKey) async throws -> ClinicalFirstPhasePreview
    func confirm(preview: ClinicalFirstPhasePreview, key: IdempotencyKey) async throws -> ClinicalFirstPhaseConfirmation
    func publish(_ operation: @MainActor @Sendable () throws -> Void) async throws
}
