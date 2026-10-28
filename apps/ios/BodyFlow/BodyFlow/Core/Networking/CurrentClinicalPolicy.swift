import Foundation

/// Display policy from one fresh official response. It contains neither risk
/// answers nor authority to calculate, select a phase or write clinical data.
struct CurrentClinicalPolicy: Codable, Equatable, Sendable {
    enum Assessment: String, Codable, Sendable { case complete, incomplete }
    enum TargetSource: String, Codable, Sendable {
        case assignedPhase = "assigned_phase"
        case officialOnly = "official_only"
        case unavailable
    }
    struct Hidden: Codable, Equatable, Sendable {
        let objective: Bool
        let calories: Bool
        let protein: Bool
        let balance: Bool
        let block: Bool
    }
    let version: Int
    let observedAt: APITimestamp
    let assessment: Assessment
    let recordingAllowed: Bool
    let pauseWeightLossGuidance: Bool
    let professionalAssessmentRecommended: Bool
    let phaseSelectionPending: Bool
    let targetSource: TargetSource
    let hide: Hidden

    private enum CodingKeys: String, CodingKey {
        case version, assessment, hide
        case observedAt = "observed_at"
        case recordingAllowed = "recording_allowed"
        case pauseWeightLossGuidance = "pause_weight_loss_guidance"
        case professionalAssessmentRecommended = "professional_assessment_recommended"
        case phaseSelectionPending = "phase_selection_pending"
        case targetSource = "target_source"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c,
                debugDescription: "Unsupported current clinical policy")
        }
        observedAt = try c.decode(APITimestamp.self, forKey: .observedAt)
        assessment = try c.decode(Assessment.self, forKey: .assessment)
        recordingAllowed = try c.decode(Bool.self, forKey: .recordingAllowed)
        pauseWeightLossGuidance = try c.decode(Bool.self, forKey: .pauseWeightLossGuidance)
        professionalAssessmentRecommended = try c.decode(Bool.self, forKey: .professionalAssessmentRecommended)
        phaseSelectionPending = try c.decode(Bool.self, forKey: .phaseSelectionPending)
        targetSource = try c.decode(TargetSource.self, forKey: .targetSource)
        hide = try c.decode(Hidden.self, forKey: .hide)
    }
}

/// Explicit opt-in seam only. The runtime stays on its existing representation
/// until all server, signup, Flow and native consumers can be enabled together.
enum CurrentClinicalRepresentation: Sendable {
    case legacy, currentV1

    var queryItems: [URLQueryItem] {
        switch self {
        case .legacy: []
        case .currentV1: [URLQueryItem(name: "clinical_policy", value: "current_clinical_v1")]
        }
    }

    /// Current reads require an original owner/generation bound by the session
    /// factory. A generic or token-only transport cannot claim that scope.
    func authorizeSession(_ transport: any Sendable) async throws {
        guard case .currentV1 = self else { return }
        guard let scoped = transport as? any CurrentClinicalSessionAuthorizing else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        try Task.checkCancellation()
        try await scoped.validateCurrentClinicalSession()
        try Task.checkCancellation()
    }

    func requirePolicy(_ policy: CurrentClinicalPolicy?) throws {
        if case .currentV1 = self, policy == nil { throw BodyFlowCapabilityError.serviceUnavailable }
    }
}

protocol CurrentClinicalSessionAuthorizing: Sendable {
    func validateCurrentClinicalSession() async throws
}
