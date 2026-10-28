import Foundation

enum ClinicalFullPreference: Encodable, Equatable, Sendable {
    enum Routine: String, Codable, Sendable { case regularTraining = "regular_training", moreEnergy = "more_energy", organizedFood = "organized_food", maintainWeight = "maintain_weight" }
    enum Goal: Encodable, Equatable, Sendable {
        case weight(Decimal), bodyFat(Decimal), routine(Routine), followApp, professional
        private enum CodingKeys: String, CodingKey { case kind, kg, percent, value }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .weight(let value):
                guard !value.isNaN, value >= 30, value <= 300 else { throw ClinicalFullFailure.invalidResponse }
                try c.encode("weight", forKey: .kind); try c.encode(value, forKey: .kg)
            case .bodyFat(let value):
                guard !value.isNaN, value >= 3, value <= 60 else { throw ClinicalFullFailure.invalidResponse }
                try c.encode("body_fat", forKey: .kind); try c.encode(value, forKey: .percent)
            case .routine(let value): try c.encode("routine", forKey: .kind); try c.encode(value, forKey: .value)
            case .followApp: try c.encode("follow_app", forKey: .kind)
            case .professional: try c.encode("professional", forKey: .kind)
            }
        }
    }
    case keep, remove, skip, change(Goal)
    private enum CodingKeys: String, CodingKey { case action, value }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keep: try c.encode("keep", forKey: .action)
        case .remove: try c.encode("remove", forKey: .action)
        case .skip: try c.encode("skip", forKey: .action)
        case .change(let goal): try c.encode("change", forKey: .action); try c.encode(goal, forKey: .value)
        }
    }
}
enum ClinicalFullHealthAnswer: Encodable, Equatable, Sendable {
    case noneReported, risks(Set<ClinicalFullHealthRisk>)
    private enum CodingKeys: String, CodingKey { case kind, items }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noneReported: try c.encode("none", forKey: .kind)
        case .risks(let items):
            guard !items.isEmpty else { throw ClinicalFullFailure.invalidResponse }
            try c.encode("risks", forKey: .kind)
            try c.encode(ClinicalFullHealthRisk.allCases.filter { items.contains($0) }, forKey: .items)
        }
    }
}
struct ClinicalFullActivityAnswers: Encodable, Equatable, Sendable {
    var otherExerciseType: String?; var otherExerciseDays: Int?; var sessionMinutes: Decimal?; var sessionIntensity: String?
    var mostlySitting: Bool?; var activityLevel: ActivityLevel?; var activityLevelConfirmed = false
    private enum CodingKeys: String, CodingKey { case otherExerciseType, otherExerciseDays, sessionMinutes, sessionIntensity, mostlySitting, activityLevel, activityLevelConfirmed }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(otherExerciseType, forKey: .otherExerciseType); try c.encode(otherExerciseDays, forKey: .otherExerciseDays)
        try c.encode(sessionMinutes, forKey: .sessionMinutes); try c.encode(sessionIntensity, forKey: .sessionIntensity)
        try c.encode(mostlySitting, forKey: .mostlySitting); try c.encode(activityLevel, forKey: .activityLevel)
        try c.encode(activityLevelConfirmed, forKey: .activityLevelConfirmed)
    }
}
struct ClinicalFullAnswers: Encodable, Equatable, Sendable {
    var weightKg: Decimal?; var strengthSessions: Int?; var adherence: String?; var hunger: HungerLevel?; var energy: String?
    var strengthProgression: String?; var fatPerception: String?; var difficultToMaintain: String?
    var activity: ClinicalFullActivityAnswers?; var healthCheck: ClinicalFullHealthAnswer?; var professionalConversationConfirmed: Bool?
    private enum CodingKeys: String, CodingKey { case weightKg, strengthSessions, adherence, hunger, energy, strengthProgression, fatPerception, difficultToMaintain, activity, healthCheck, professionalConversationConfirmed }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weightKg, forKey: .weightKg); try c.encode(strengthSessions, forKey: .strengthSessions)
        try c.encode(adherence, forKey: .adherence); try c.encode(hunger, forKey: .hunger); try c.encode(energy, forKey: .energy)
        try c.encode(strengthProgression, forKey: .strengthProgression); try c.encode(fatPerception, forKey: .fatPerception)
        try c.encode(difficultToMaintain, forKey: .difficultToMaintain); try c.encode(activity, forKey: .activity)
        try c.encode(healthCheck, forKey: .healthCheck); try c.encode(professionalConversationConfirmed, forKey: .professionalConversationConfirmed)
    }
    func filtered(to keys: Set<ClinicalFullQuestionKey>) -> Self {
        var copy = self
        if !keys.contains(.weightKg) { copy.weightKg = nil }; if !keys.contains(.strengthSessions) { copy.strengthSessions = nil }
        if !keys.contains(.adherence) { copy.adherence = nil }; if !keys.contains(.hunger) { copy.hunger = nil }; if !keys.contains(.energy) { copy.energy = nil }
        if !keys.contains(.strengthProgression) { copy.strengthProgression = nil }; if !keys.contains(.fatPerception) { copy.fatPerception = nil }
        if !keys.contains(.difficultToMaintain) { copy.difficultToMaintain = nil }; if !keys.contains(.healthCheck) { copy.healthCheck = nil }
        if !keys.contains(.professionalConversationConfirmed) { copy.professionalConversationConfirmed = nil }
        if !keys.contains(where: \.isActivity) { copy.activity = nil }
        else if var activity = copy.activity {
            if !keys.contains(.otherExerciseType) { activity.otherExerciseType = nil }; if !keys.contains(.otherExerciseDays) { activity.otherExerciseDays = nil }
            if !keys.contains(.sessionMinutes) { activity.sessionMinutes = nil }; if !keys.contains(.sessionIntensity) { activity.sessionIntensity = nil }
            if !keys.contains(.mostlySitting) { activity.mostlySitting = nil }; if !keys.contains(.activityLevel) { activity.activityLevel = nil; activity.activityLevelConfirmed = false }
            copy.activity = activity
        }
        return copy
    }
}
/// Editable answers only, with server-owned field presence. No clinical phase,
/// effect, formula, raw proof, body-fat number or owner can be encoded here.
struct ClinicalFullDraft: Encodable, Equatable, Sendable {
    struct AcceptedBodyFat: Encodable, Equatable, Sendable { let confirmed = true; let candidateId: String }
    private(set) var activityPurpose: ClinicalFullPurpose
    var answers = ClinicalFullAnswers()
    var measureConfirmed = false
    var preference: ClinicalFullPreference?
    private(set) var acceptedBodyFat: AcceptedBodyFat?
    private let kind: ClinicalFullKind
    private let cycleID: String?
    private var fields: Set<ClinicalFullQuestionKey>
    private var allowsPreference: Bool
    private enum CodingKeys: String, CodingKey { case activityPurpose, answers, preference, measureConfirmed, bodyFat, choice }
    init(questionnaire: ClinicalFullQuestionnaire) {
        kind = questionnaire.kind; cycleID = questionnaire.cycleID?.lowercased(); activityPurpose = questionnaire.activityPurpose
        fields = Set(questionnaire.questions.map(\.key))
        allowsPreference = questionnaire.preferenceQuestion != nil
        if fields.contains(where: \.isActivity) {
            answers.activity = ClinicalFullActivityAnswers()
            answers.activity?.activityLevel = questionnaire.questions.first { $0.key == .activityLevel }?.preselected
        }
    }
    mutating func refresh(from form: ClinicalFullQuestionnaire) throws {
        guard kind == form.kind, cycleID == form.cycleID?.lowercased() else { throw ClinicalFullFailure.changed }
        if acceptedBodyFat?.candidateId != form.bodyFat.candidateID { acceptedBodyFat = nil }
        activityPurpose = form.activityPurpose; fields = Set(form.questions.map(\.key)); answers = answers.filtered(to: fields)
        allowsPreference = form.preferenceQuestion != nil
        if !allowsPreference { preference = nil }
        if fields.contains(where: \.isActivity) {
            if answers.activity == nil { answers.activity = ClinicalFullActivityAnswers() }
            answers.activity?.activityLevelConfirmed = false
        }
    }
    mutating func acceptBodyFat(from form: ClinicalFullQuestionnaire) {
        guard kind == form.kind, cycleID == form.cycleID?.lowercased(), form.bodyFat.status == .ready, let id = form.bodyFat.candidateID else { acceptedBodyFat = nil; return }
        acceptedBodyFat = AcceptedBodyFat(candidateId: id)
    }
    mutating func revokeBodyFatAcceptance() { acceptedBodyFat = nil }
    func belongs(to scope: ClinicalFullScope) -> Bool { kind == scope.kind && cycleID?.lowercased() == scope.cycleID?.lowercased() }
    mutating func selectNoHealthRisks() { answers.healthCheck = .noneReported }
    mutating func setHealthRisk(_ code: ClinicalFullHealthRisk, selected: Bool) {
        var items: Set<ClinicalFullHealthRisk> = if case .risks(let existing) = answers.healthCheck { existing } else { [] }
        if selected { items.insert(code) } else { items.remove(code) }
        answers.healthCheck = items.isEmpty ? nil : .risks(items)
    }
    func encode(to encoder: any Encoder) throws {
        try encode(to:encoder,choice:nil)
    }
    func encode(to encoder: any Encoder, choice: ClinicalFullChoice?) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(activityPurpose, forKey: .activityPurpose); try c.encode(answers.filtered(to: fields), forKey: .answers)
        // Preference is an optional statement, never a locally calculated target.
        try c.encode(allowsPreference ? preference : nil, forKey: .preference)
        try c.encode(measureConfirmed, forKey: .measureConfirmed); try c.encode(acceptedBodyFat, forKey: .bodyFat)
        if let choice { try c.encode(choice,forKey:.choice) }
    }
}
