import Foundation

/// The shell retains raw edits as well as typed answers. An invalid number
/// never becomes a skipped answer, zero, or a truncated integer on navigation.
struct ClinicalFullInputState: Equatable, Sendable {
    private(set) var text: [ClinicalFullQuestionKey: String] = [:]
    private(set) var invalid: Set<ClinicalFullQuestionKey> = []
    private(set) var preferenceSelection = ""
    private(set) var preferenceText = ""
    private(set) var preferenceRoutine = ""
    private(set) var invalidPreference = false
    var hasInvalidValues: Bool { !invalid.isEmpty || invalidPreference }
    mutating func refresh(_ form: ClinicalFullQuestionnaire) {
        let keys = Set(form.questions.map(\.key))
        text = text.filter { keys.contains($0.key) }; invalid.formIntersection(keys)
        if form.preferenceQuestion == nil {
            preferenceSelection = ""; preferenceText = ""; preferenceRoutine = ""; invalidPreference = false
        }
    }
    mutating func setText(_ value: String, question: ClinicalFullQuestion, draft: inout ClinicalFullDraft, language: SupportedAppLanguage) {
        guard [.decimal, .integer, .text].contains(question.inputKind) else { return }
        text[question.key] = value
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var number: Decimal?
        if !trimmed.isEmpty, question.inputKind != .text {
            guard let parsed = MealProposalNumberParser.parse(trimmed,language:language),
                  question.key != .sessionMinutes || parsed > 0,
                  question.min == nil || parsed >= question.min!, question.max == nil || parsed <= question.max! else { invalid.insert(question.key); return }
            if question.inputKind == .integer {
                var input = parsed, rounded = Decimal()
                NSDecimalRound(&rounded,&input,0,.plain)
                guard parsed == rounded, parsed >= Decimal(Int32.min), parsed <= Decimal(Int32.max) else { invalid.insert(question.key); return }
            }
            number = parsed
        }
        invalid.remove(question.key)
        switch question.key {
        case .weightKg: draft.answers.weightKg = number
        case .strengthSessions: draft.answers.strengthSessions = number.map { NSDecimalNumber(decimal:$0).intValue }
        case .otherExerciseDays: draft.answers.activity?.otherExerciseDays = number.map { NSDecimalNumber(decimal:$0).intValue }
        case .sessionMinutes: draft.answers.activity?.sessionMinutes = number
        case .otherExerciseType: draft.answers.activity?.otherExerciseType = trimmed.isEmpty ? nil : trimmed
        default: break
        }
    }
    static func selected(_ key: ClinicalFullQuestionKey, draft: ClinicalFullDraft) -> ClinicalFullOptionValue? {
        let answer = draft.answers
        switch key {
        case .adherence: return answer.adherence.map { .string($0) }
        case .hunger: return answer.hunger.map { .string($0.rawValue) }
        case .energy: return answer.energy.map { .string($0) }
        case .strengthProgression: return answer.strengthProgression.map { .string($0) }
        case .fatPerception: return answer.fatPerception.map { .string($0) }
        case .difficultToMaintain: return answer.difficultToMaintain.map { .string($0) }
        case .sessionIntensity: return answer.activity?.sessionIntensity.map { .string($0) }
        case .activityLevel: return answer.activity?.activityLevel.map { .string($0.rawValue) }
        case .mostlySitting: return answer.activity?.mostlySitting.map { .boolean($0) }
        case .professionalConversationConfirmed: return answer.professionalConversationConfirmed.map { .boolean($0) }
        default: return nil
        }
    }
    static func select(_ option: ClinicalFullOptionValue?, question: ClinicalFullQuestion, draft: inout ClinicalFullDraft) {
        guard option == nil || question.options?.contains(where: { $0.value == option }) == true else { return }
        let string: String? = if case .string(let value) = option { value } else { nil }
        let boolean: Bool? = if case .boolean(let value) = option { value } else { nil }
        switch question.key {
        case .adherence: draft.answers.adherence = string
        case .hunger: draft.answers.hunger = string.flatMap(HungerLevel.init(rawValue:))
        case .energy: draft.answers.energy = string
        case .strengthProgression: draft.answers.strengthProgression = string
        case .fatPerception: draft.answers.fatPerception = string
        case .difficultToMaintain: draft.answers.difficultToMaintain = string
        case .sessionIntensity: draft.answers.activity?.sessionIntensity = string
        case .activityLevel: draft.answers.activity?.activityLevel = string.flatMap(ActivityLevel.init(rawValue:)); draft.answers.activity?.activityLevelConfirmed = false
        case .mostlySitting: draft.answers.activity?.mostlySitting = boolean
        case .professionalConversationConfirmed: draft.answers.professionalConversationConfirmed = boolean
        default: break
        }
    }
    mutating func selectPreference(_ token: String, form: ClinicalFullQuestionnaire, draft: inout ClinicalFullDraft, language: SupportedAppLanguage) {
        guard let question = form.preferenceQuestion else { return }
        let allowed = question.existingActions + question.options.compactMap { if case .string(let value) = $0.value { value } else { nil } }
        guard token.isEmpty || allowed.contains(token) else { return }
        preferenceSelection = token; preferenceText = ""; preferenceRoutine = ""; invalidPreference = false
        switch token {
        case "keep": draft.preference = .keep
        case "remove": draft.preference = .remove
        case "skip": draft.preference = .skip
        case "follow_app": draft.preference = .change(.followApp)
        case "professional": draft.preference = .change(.professional)
        case "weight", "body_fat", "routine": draft.preference = nil; invalidPreference = true
        default: draft.preference = nil
        }
    }
    mutating func setPreferenceText(_ value: String, draft: inout ClinicalFullDraft, language: SupportedAppLanguage) {
        guard ["weight", "body_fat"].contains(preferenceSelection) else { return }
        preferenceText = value
        guard let number = MealProposalNumberParser.parse(value,language:language),
              preferenceSelection == "weight" ? (30...300).contains(number) : (3...60).contains(number) else { invalidPreference = true; return }
        invalidPreference = false
        draft.preference = .change(preferenceSelection == "weight" ? .weight(number) : .bodyFat(number))
    }
    mutating func setPreferenceRoutine(_ token: String, form: ClinicalFullQuestionnaire, draft: inout ClinicalFullDraft) {
        guard preferenceSelection == "routine", let routine = ClinicalFullPreference.Routine(rawValue:token),
              form.preferenceQuestion?.routineOptions.contains(where: { $0.value == .string(token) }) == true else { return }
        preferenceRoutine = token; invalidPreference = false; draft.preference = .change(.routine(routine))
    }
}
