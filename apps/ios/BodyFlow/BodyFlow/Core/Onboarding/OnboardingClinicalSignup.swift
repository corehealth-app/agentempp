import Foundation

/// Absence is legacy. A present unknown or null capability cannot downgrade.
struct OnboardingClinicalSignupCapability: Codable, Equatable, Sendable {
    enum Representation: String, Codable, Sendable { case current = "current_clinical_v2" }
    let representation: Representation
    static let current = Self(representation: .current)
}

/// Historical observation only. Never restores current targets or clears HOLD.
struct OnboardingClinicalSafety: Codable, Equatable, Sendable {
    let version: Int
    let noPlan: Bool
    let holdActive: Bool
    let lossGuard: Bool
    let hideProtein: Bool
    let recordingAllowed: Bool
    let date: String
    let timezone: String
    let observedAt: APITimestamp
    private enum CodingKeys: String, CodingKey {
        case version, date, timezone
        case noPlan = "no_plan", holdActive = "hold_active", lossGuard = "loss_guard"
        case hideProtein = "hide_protein", recordingAllowed = "recording_allowed", observedAt = "observed_at"
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        noPlan = try c.decode(Bool.self, forKey: .noPlan)
        holdActive = try c.decode(Bool.self, forKey: .holdActive)
        lossGuard = try c.decode(Bool.self, forKey: .lossGuard)
        hideProtein = try c.decode(Bool.self, forKey: .hideProtein)
        recordingAllowed = try c.decode(Bool.self, forKey: .recordingAllowed)
        date = try c.decode(String.self, forKey: .date)
        timezone = try c.decode(String.self, forKey: .timezone)
        observedAt = try c.decode(APITimestamp.self, forKey: .observedAt)
        guard version == 1, recordingAllowed, ClinicalFirstPhaseChoices.validDate(date),
              TimeZone(identifier: timezone) != nil, !noPlan || hideProtein,
              !hideProtein || noPlan || holdActive else { throw OnboardingRepositoryError.serviceUnavailable }
    }
}

/// A nonoptional field wrapper keeps missing distinct from a literal JSON null.
struct OnboardingObjectiveValue: Codable, Sendable {
    let value: BodyFlowObjective?
    init(_ value: BodyFlowObjective?) { self.value = value }
    init(from decoder: any Decoder) throws {
        value = try decoder.singleValueContainer().decode(BodyFlowObjective?.self)
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        if let value { try c.encode(value) } else { try c.encodeNil() }
    }
}

/// Only the explicit marked risks and exact legal actions. No owner, epoch,
/// ordinary answers, clinical effects or local clock enter this command.
struct OnboardingSignupHealthDeclaration: Encodable, Equatable, Sendable {
    let version = 1
    let intentID: UUID
    let requestKey: String
    let locale: String
    let documentActions: [OnboardingDocumentAction]
    let risks: [ClinicalFullHealthRisk]
    init(intent: OnboardingCompletionIntent, locale: String, actions: [OnboardingDocumentAction], risks: Set<ClinicalFullHealthRisk>) throws {
        guard OnboardingLocalePolicy.isSupported(locale), !risks.isEmpty, (1...16).contains(actions.count),
              Set(actions.map(\.documentKey)).count == actions.count,
              actions.allSatisfy({$0.locale == locale && !$0.documentKey.hasPrefix("dev_") && !$0.documentKey.hasPrefix("dev.")}) else {throw OnboardingRepositoryError.invalidDraft}
        intentID=intent.intentID;requestKey=intent.requestKey.value;self.locale=locale
        documentActions=actions.sorted{$0.documentKey < $1.documentKey}
        self.risks=ClinicalFullHealthRisk.allCases.filter{risks.contains($0)}
    }
    private enum CodingKeys: String, CodingKey {
        case version,locale,risks
        case intentID = "intent_id",requestKey = "request_key",documentActions = "document_actions"
    }
}
/// Historical acknowledgement; the next eligibility read supplies current
/// health policy. The response's state is deliberately not clinical authority.
struct OnboardingSignupHealthAcknowledgement: Decodable, Sendable {
    struct Receipt: Decodable, Sendable {
        let id: UUID;let intentID:UUID;let requestKey:String;let locale:String
        let requirementSetID:UUID;let documentActions:[OnboardingDocumentAction];let risks:[ClinicalFullHealthRisk];let admittedAt:APITimestamp
        private enum CodingKeys:String,CodingKey {
            case id,locale,risks
            case intentID="intent_id",requestKey="request_key",requirementSetID="requirement_set_id",documentActions="document_actions",admittedAt="admitted_at"
        }
    }
    let availability:String;let version:Int;let operationKey:UUID;let receipt:Receipt
    private enum CodingKeys:String,CodingKey {case availability,version,receipt;case operationKey="operation_key"}
    func matches(_ input:OnboardingSignupHealthDeclaration,key:IdempotencyKey)->Bool {
        availability == "available" && version == 1 && operationKey.uuidString.lowercased() == key.value.lowercased()
          && receipt.intentID == input.intentID && receipt.requestKey == input.requestKey && receipt.locale == input.locale
          && receipt.documentActions == input.documentActions && receipt.risks == input.risks
    }
}
