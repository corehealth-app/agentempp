import Foundation

enum ClinicalFullFailure: Error, Equatable, Sendable { case offline, changed, busy, unavailable, invalidInput, invalidResponse, sessionEnded }
enum ClinicalFullKind: String, Codable, Sendable { case regular = "REGULAR", transition = "TRANSITION_FULL", early = "EARLY_FULL", routine = "ROUTINE_REVIEW", safety = "SAFETY"
    var requiresCycle: Bool { self == .regular || self == .transition || self == .early }
    var requiresNewPhotos: Bool { self == .regular || self == .transition }
}
enum ClinicalFullPurpose: String, Codable, Sendable { case normal, considerMaintenance = "consider_maintenance", endDeficit = "end_deficit" }
enum ClinicalFullHealthRisk: String, CaseIterable, Codable, Sendable {
    case unintendedWeightLoss = "unintended_weight_loss", reducedIntake = "reduced_intake"
    case persistentFatigue = "persistent_fatigue_weakness_dizziness", menstrualChange = "menstrual_change"
    case lossOfControlEating = "loss_of_control_eating", appetiteWeightTreatment = "appetite_weight_treatment"
    case professionalDiet = "professional_diet", pregnantOrBreastfeeding = "pregnant_or_breastfeeding"
}
enum ClinicalFullQuestionKey: String, Codable, CaseIterable, Sendable {
    case weightKg, strengthSessions, adherence, hunger, energy, strengthProgression, fatPerception, difficultToMaintain, healthCheck, professionalConversationConfirmed
    case otherExerciseType = "activity.otherExerciseType", otherExerciseDays = "activity.otherExerciseDays", sessionMinutes = "activity.sessionMinutes", sessionIntensity = "activity.sessionIntensity", mostlySitting = "activity.mostlySitting", activityLevel = "activity.activityLevel"
    var isActivity: Bool { rawValue.hasPrefix("activity.") }
}
enum ClinicalFullOptionValue: Codable, Equatable, Hashable, Sendable {
    case string(String), boolean(Bool)
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .boolean(b) }
        else { self = .string(try c.decode(String.self)) }
    }
    func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); switch self { case .string(let v): try c.encode(v); case .boolean(let v): try c.encode(v) } }
}
struct ClinicalFullOption: Codable, Equatable, Sendable { let value: ClinicalFullOptionValue; let label: String }
struct ClinicalFullQuestion: Codable, Equatable, Identifiable, Sendable {
    enum InputKind: String, Codable, Sendable { case decimal, integer, text, boolean, singleChoice = "single_choice", healthSelection = "health_selection" }
    let key: ClinicalFullQuestionKey
    let label: String
    let inputKind: InputKind
    let unit: String?
    let optOutLabel: String
    let options: [ClinicalFullOption]?
    let min: Decimal?
    let max: Decimal?
    let preselected: ActivityLevel?
    let initiallyConfirmed: Bool?
    let hint: String?
    var id: String { key.rawValue }
    private enum CodingKeys: String, CodingKey {
        case key, label, unit, options, min, max, preselected, hint
        case inputKind = "input_kind", optOutLabel = "opt_out_label", initiallyConfirmed = "initially_confirmed"
    }
    func validated() throws {
        guard !label.isEmpty, !optOutLabel.isEmpty, min?.isNaN != true, max?.isNaN != true,
              min == nil || max == nil || min! <= max!, initiallyConfirmed != true,
              Set(options?.map(\.value) ?? []).count == options?.count ?? 0,
              options?.allSatisfy({ !$0.label.isEmpty }) != false else { throw ClinicalFullFailure.invalidResponse }
        let expected: InputKind
        switch key {
        case .weightKg, .sessionMinutes: expected = .decimal
        case .strengthSessions, .otherExerciseDays: expected = .integer
        case .otherExerciseType: expected = .text
        case .mostlySitting, .professionalConversationConfirmed: expected = .boolean
        case .healthCheck: expected = .healthSelection
        default: expected = .singleChoice
        }
        guard inputKind == expected, preselected == nil || key == .activityLevel,
              initiallyConfirmed == nil || key == .activityLevel else { throw ClinicalFullFailure.invalidResponse }
        let expectedUnit: String? = key == .weightKg ? "kg" : [.strengthSessions, .otherExerciseDays].contains(key) ? "per_week" : key == .sessionMinutes ? "minutes" : nil
        guard unit == expectedUnit else { throw ClinicalFullFailure.invalidResponse }
        let allowed: Set<String>
        switch key {
        case .adherence: allowed = ["bem_consistente", "mais_ou_menos", "pouco_consistente"]
        case .hunger: allowed = ["pouca", "moderada", "muita"]
        case .energy: allowed = ["boa", "ok", "baixa"]
        case .strengthProgression: allowed = ["melhorou", "ficou_parecido", "piorou_ou_travou", "nao_sei_avaliar"]
        case .fatPerception: allowed = ["nao_percebi", "um_pouco", "claramente"]
        case .difficultToMaintain: allowed = ["nao", "sim"]
        case .sessionIntensity: allowed = ["leve", "moderada", "alta"]
        case .activityLevel: allowed = Set(ActivityLevel.allCases.map(\.rawValue))
        case .healthCheck: allowed = Set(ClinicalFullHealthRisk.allCases.map(\.rawValue) + ["none"])
        default: allowed = []
        }
        for option in options ?? [] {
            switch option.value {
            case .boolean: guard expected == .boolean else { throw ClinicalFullFailure.invalidResponse }
            case .string(let v): guard allowed.contains(v) else { throw ClinicalFullFailure.invalidResponse }
            }
        }
    }
}
struct ClinicalFullQuestionnaire: Codable, Equatable, Sendable {
    struct Preference: Codable, Equatable, Sendable {
        let label: String; let optional: Bool; let options: [ClinicalFullOption]; let routineOptions: [ClinicalFullOption]; let existingActions: [String]
        private enum CodingKeys: String, CodingKey { case label, optional, options; case routineOptions = "routine_options", existingActions = "existing_actions" }
        func validated() throws {
            let goals: Set<String> = ["weight", "body_fat", "routine", "follow_app", "professional", "skip"]
            let routines: Set<String> = ["regular_training", "more_energy", "organized_food", "maintain_weight"]
            guard optional, !label.isEmpty, !options.isEmpty, options.count <= 6, !routineOptions.isEmpty, routineOptions.count <= 4,
                  Set(existingActions).count == existingActions.count, Set(existingActions).isSubset(of: ["keep", "change", "remove"]) else { throw ClinicalFullFailure.invalidResponse }
            for (values, allowed) in [(options, goals), (routineOptions, routines)] {
                guard Set(values.map(\.value)).count == values.count else { throw ClinicalFullFailure.invalidResponse }
                for option in values {
                    guard case .string(let token) = option.value, allowed.contains(token), !option.label.isEmpty else { throw ClinicalFullFailure.invalidResponse }
                }
            }
        }
    }
    struct PhotoRequirement: Codable, Equatable, Sendable {
        enum Pose: String, Codable, Sendable { case front, side, back }
        let required: Bool; let newOnly: Bool; let poses: [Pose]
        private enum CodingKeys: String, CodingKey { case required, poses; case newOnly = "new_only" }
    }
    struct BodyFat: Codable, Equatable, Sendable {
        enum Status: String, Codable, Sendable { case ready, photosRequired = "photos_required", notRequired = "not_required" }
        let status: Status; let percent: Decimal?; let candidateID: String?
        private enum CodingKeys: String, CodingKey { case status, percent; case candidateID = "candidate_id" }
    }
    let version: Int; let locale: String; let kind: ClinicalFullKind; let cycleID: String?; let activityPurpose: ClinicalFullPurpose
    let questions: [ClinicalFullQuestion]; let preferenceQuestion: Preference?; let supportText: String?
    let purposeOptions: [ClinicalFullPurpose]?
    let photoRequirement: PhotoRequirement; let bodyFat: BodyFat
    private enum CodingKeys: String, CodingKey {
        case version, locale, kind, questions
        case cycleID = "cycle_id", activityPurpose = "activity_purpose", preferenceQuestion = "preference_question", supportText = "support_text", photoRequirement = "photo_requirement", bodyFat = "body_fat", purposeOptions = "activity_purpose_options"
    }
    func validated() throws -> Self {
        guard version == 1, ["pt-BR", "en-US"].contains(locale),
              kind.requiresCycle == (cycleID != nil), cycleID == nil || ClinicalFirstPhaseChoices.validID(cycleID!),
              Set(questions.map(\.key)).count == questions.count, questions.count <= 16,
              photoRequirement.required == kind.requiresNewPhotos, photoRequirement.newOnly,
              photoRequirement.poses == [.front, .side, .back] else { throw ClinicalFullFailure.invalidResponse }
        for q in questions { try q.validated() }
        if let purposeOptions { guard !purposeOptions.isEmpty, purposeOptions.count <= 3, Set(purposeOptions.map(\.rawValue)).count == purposeOptions.count, purposeOptions.contains(activityPurpose) else { throw ClinicalFullFailure.invalidResponse } }
        try preferenceQuestion?.validated()
        if kind.requiresNewPhotos {
            guard bodyFat.status != .notRequired else { throw ClinicalFullFailure.invalidResponse }
        } else if bodyFat.status != .notRequired { throw ClinicalFullFailure.invalidResponse }
        if bodyFat.status == .ready {
            guard let percent = bodyFat.percent, !percent.isNaN, percent >= 3, percent <= 60,
                  let id = bodyFat.candidateID, id.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ClinicalFullFailure.invalidResponse }
        } else if bodyFat.percent != nil || bodyFat.candidateID != nil { throw ClinicalFullFailure.invalidResponse }
        return self
    }
}
