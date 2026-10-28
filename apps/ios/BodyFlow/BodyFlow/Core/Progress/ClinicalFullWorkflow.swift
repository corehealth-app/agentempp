import Foundation

struct ClinicalFullScope: Equatable, Sendable {
    let kind: ClinicalFullKind
    let cycleID: String?
    init(kind: ClinicalFullKind, cycleID: String?) { self.kind = kind; self.cycleID = cycleID?.lowercased() }
    func matches(kind: ClinicalFullKind, cycleID: String?) -> Bool { self.kind == kind && self.cycleID == cycleID?.lowercased() }
    func validated() throws -> Self {
        guard kind.requiresCycle == (cycleID != nil), cycleID == nil || ClinicalFirstPhaseChoices.validID(cycleID!) else { throw ClinicalFullFailure.invalidResponse }
        return self
    }
}
enum ClinicalFullStartReason: String, Codable, Sendable { case notWellWithPlan = "not_well_with_plan", gainReviewNotice = "gain_review_notice" }
struct ClinicalFullEntry: Decodable, Equatable, Sendable {
    enum Availability: String, Decodable, Sendable { case available, unavailable }
    enum Reason: String, Decodable, Sendable { case notDue = "not_due", onboardingIncomplete = "onboarding_incomplete", anchorUnproven = "anchor_unproven" }
    struct Clock: Decodable, Equatable, Sendable {
        let baseDate: String; let dueDate: String; let timezone: String
        private enum CodingKeys: String, CodingKey { case baseDate = "base_date", dueDate = "due_date", timezone }
    }
    struct Cycle: Decodable, Equatable, Sendable {
        enum Status: String, Decodable, Sendable { case open, collecting, reviewReady = "review_ready" }
        let id: String; let kind: ClinicalFullKind; let status: Status; let revision: String
        var scope: ClinicalFullScope { ClinicalFullScope(kind:kind,cycleID:id) }
    }
    let version: Int; let availability: Availability; let unavailableReason: Reason?; let clock: Clock?; let cycle: Cycle?
    var canOfferEarlyFull: Bool { availability == .unavailable && unavailableReason == .notDue && clock != nil }
    private enum CodingKeys: String, CodingKey { case version, availability, clock, cycle; case unavailableReason = "unavailable_reason" }
    func validated() throws -> Self {
        guard version == 1, (availability == .available) == (unavailableReason == nil),
              clock != nil || (availability == .unavailable && unavailableReason != .notDue && cycle == nil) else { throw ClinicalFullFailure.invalidResponse }
        if let clock { guard ClinicalFirstPhaseChoices.validDate(clock.baseDate), ClinicalFirstPhaseChoices.validDate(clock.dueDate), !clock.timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClinicalFullFailure.invalidResponse } }
        if let cycle {
            guard cycle.kind.requiresCycle, ClinicalFirstPhaseChoices.validID(cycle.id),
                  let revision = UInt64(cycle.revision), revision > 0, revision <= UInt64(Int64.max), String(revision) == cycle.revision,
                  cycle.kind != .early || availability == .available else { throw ClinicalFullFailure.invalidResponse }
        }
        return self
    }
}
struct ClinicalFullChoice: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case keep, phase, activity, calorieStep = "phase_calorie_step", schedule, neutralExit = "neutral_exit" }
    enum Schedule: String, Codable, Sendable { case reconfirm, pause }
    let kind: Kind; var phase: BodyFlowObjective?; var action: Schedule?
    var id: String { kind.rawValue + ":" + (phase?.rawValue ?? action?.rawValue ?? "") }
    private enum CodingKeys: String, CodingKey { case kind, phase, action }
    func validated() throws -> Self {
        guard (kind == .phase) == (phase != nil), (kind == .schedule) == (action != nil) else { throw ClinicalFullFailure.invalidResponse }
        return self
    }
    func encode(to encoder: any Encoder) throws {
        _ = try validated()
        var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(kind,forKey:.kind)
        if let phase { try c.encode(phase,forKey:.phase) }; if let action { try c.encode(action,forKey:.action) }
    }
}
struct ClinicalFullTargets: Decodable, Equatable, Sendable {
    let caloriesKcal: Int?; let proteinG: Decimal?
    private enum CodingKeys: String, CodingKey { case caloriesKcal = "calories_kcal", proteinG = "protein_g" }
    func validate() throws {
        guard caloriesKcal == nil || (caloriesKcal! > 0 && caloriesKcal! <= 2_147_483_647), proteinG?.isNaN != true,
              proteinG == nil || (proteinG! >= 0 && proteinG! <= Decimal(999999)/100) else { throw ClinicalFullFailure.invalidResponse }
    }
}
struct ClinicalFullAssessment: Decodable, Equatable, Sendable {
    enum Status: String, Decodable, Sendable { case available, noChangeAvailable = "no_change_available", healthDeclarationRequired = "health_declaration_required", photosRequired = "photos_required", bodyFatConfirmationRequired = "body_fat_confirmation_required" }
    struct Action: Decodable, Equatable, Sendable, Identifiable {
        let choice: ClinicalFullChoice; let phase: BodyFlowObjective?; let targets: ClinicalFullTargets
        let professionalAssessmentRecommended: Bool; let pauseWeightLossGuidance: Bool
        var id: String { choice.id }
        private enum CodingKeys: String, CodingKey { case choice, phase, targets; case professionalAssessmentRecommended = "professional_assessment_recommended", pauseWeightLossGuidance = "pause_weight_loss_guidance" }
    }
    struct Preference: Decodable, Equatable, Sendable {
        enum Status: String, Decodable, Sendable { case unchanged, removed, accepted, refused, missing }
        enum Reason: String, Decodable, Sendable { case bodyFatFloor = "body_fat_floor", weightBMIFloor = "weight_bmi_floor", dependentContext = "dependent_context" }
        let status: Status; let reason: Reason?; let missing: [String]
    }
    let version: Int; let status: Status; let actions: [Action]; let preference: Preference?
    func validated() throws -> Self {
        guard version == 1, actions.count <= 8, Set(actions.map(\.id)).count == actions.count,
              (status == .available) == !actions.isEmpty else { throw ClinicalFullFailure.invalidResponse }
        for action in actions { _ = try action.choice.validated(); try action.targets.validate() }
        if let preference { guard Set(preference.missing).count == preference.missing.count, Set(preference.missing).isSubset(of:["sex","heightCm"]) else { throw ClinicalFullFailure.invalidResponse } }
        return self
    }
}
struct ClinicalFullPreview: Decodable, Equatable, Sendable {
    enum Status: String, Decodable, Sendable { case ready, historicalDisplayUnavailable = "historical_display_unavailable" }
    let version: Int; let status: Status; let previewID: String; let kind: ClinicalFullKind; let cycleID: String?; let expiresAt: APITimestamp
    let choice: ClinicalFullChoice?; let phase: BodyFlowObjective?; let targets: ClinicalFullTargets?
    let professionalAssessmentRecommended: Bool?; let pauseWeightLossGuidance: Bool?
    private enum CodingKeys: String, CodingKey { case version, status, kind, choice, phase, targets; case previewID = "preview_id", cycleID = "cycle_id", expiresAt = "expires_at", professionalAssessmentRecommended = "professional_assessment_recommended", pauseWeightLossGuidance = "pause_weight_loss_guidance" }
    func validated() throws -> Self {
        guard version == 1, ClinicalFirstPhaseChoices.validID(previewID) else { throw ClinicalFullFailure.invalidResponse }
        _ = try ClinicalFullScope(kind:kind,cycleID:cycleID).validated()
        if status == .ready {
            guard let choice, let targets, professionalAssessmentRecommended != nil, pauseWeightLossGuidance != nil else { throw ClinicalFullFailure.invalidResponse }
            _ = try choice.validated(); try targets.validate()
        } else if choice != nil || phase != nil || targets != nil || professionalAssessmentRecommended != nil || pauseWeightLossGuidance != nil { throw ClinicalFullFailure.invalidResponse }
        return self
    }
}
/// Historical receipt. Never derive or restore current targets/safety from it.
struct ClinicalFullConfirmation: Decodable, Equatable, Sendable {
    let version: Int; let reviewID: String; let kind: ClinicalFullKind; let cycleID: String?; let completedAt: APITimestamp; let nextDueDate: String
    private enum CodingKeys: String, CodingKey { case version, kind; case reviewID = "review_id", cycleID = "cycle_id", completedAt = "completed_at", nextDueDate = "next_due_date" }
    func validated() throws -> Self {
        guard version == 1, ClinicalFirstPhaseChoices.validID(reviewID), ClinicalFirstPhaseChoices.validDate(nextDueDate),
              (kind == .routine) == (cycleID == nil), cycleID == nil || ClinicalFirstPhaseChoices.validID(cycleID!) else { throw ClinicalFullFailure.invalidResponse }
        return self
    }
}
struct ClinicalFullHealthReceipt: Decodable, Equatable, Sendable {
    let version: Int; let receiptID: String; let declaredAt: APITimestamp
    private enum CodingKeys: String, CodingKey { case version; case receiptID = "receipt_id", declaredAt = "declared_at" }
    func validated() throws -> Self { guard version == 1, ClinicalFirstPhaseChoices.validID(receiptID) else { throw ClinicalFullFailure.invalidResponse }; return self }
}
protocol ClinicalFullProviding: Sendable {
    func scoped(for userID: String) async throws -> any ClinicalFullProviding
    func entry() async throws -> ClinicalFullEntry
    func start(reason: ClinicalFullStartReason?, key: IdempotencyKey) async throws -> ClinicalFullEntry
    func describe(scope: ClinicalFullScope, purpose: ClinicalFullPurpose) async throws -> ClinicalFullQuestionnaire
    func assess(scope: ClinicalFullScope, draft: ClinicalFullDraft) async throws -> ClinicalFullAssessment
    func prepare(scope: ClinicalFullScope, draft: ClinicalFullDraft, choice: ClinicalFullChoice, key: IdempotencyKey) async throws -> ClinicalFullPreview
    func confirm(scope: ClinicalFullScope, draft: ClinicalFullDraft, choice: ClinicalFullChoice, preview: ClinicalFullPreview, key: IdempotencyKey) async throws -> ClinicalFullConfirmation
    func declareHealth(items: [ClinicalFullHealthRisk], key: IdempotencyKey) async throws -> ClinicalFullHealthReceipt
    func publish(_ operation: @MainActor @Sendable () throws -> Void) async throws
}
