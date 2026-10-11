import Foundation

/// Words of the plan drafts. One message per cause, and the two sentences
/// that must never be missing: a draft is not a plan, and the patient's
/// confirmation is not a professional review.
enum PlanDraftCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        PlanCopy.string(key, language: language)
    }

    static func domainTitle(
        _ domain: PlanDraftDomain,
        language: SupportedAppLanguage
    ) -> String {
        string(domain == .training ? "plan.draft.domain.training" : "plan.draft.domain.nutrition",
               language: language)
    }

    static func originKey(imported: Bool) -> String.LocalizationValue {
        imported ? "plan.draft.origin.imported" : "plan.draft.origin.flow"
    }

    /// `nil` while the draft is still loading: its origin is not known yet.
    static func navigationTitleKey(imported: Bool?) -> String.LocalizationValue {
        switch imported {
        case .some(true): "plan.draft.navigation.title.imported"
        case .some(false): "plan.draft.navigation.title"
        case .none: "plan.draft.navigation.title.pending"
        }
    }

    static func discardKey(imported: Bool) -> String.LocalizationValue {
        imported ? "plan.draft.discard.imported" : "plan.draft.discard"
    }

    static func discardTitleKey(imported: Bool) -> String.LocalizationValue {
        imported ? "plan.draft.discard.title.imported" : "plan.draft.discard.title"
    }

    static func discardedTitleKey(imported: Bool) -> String.LocalizationValue {
        imported ? "plan.draft.discarded.title.imported" : "plan.draft.discarded.title"
    }

    static func fieldKey(_ key: String) -> String.LocalizationValue {
        switch key {
        case "day": "plan.draft.field.day"
        case "focus": "plan.draft.field.focus"
        case "duration_min": "plan.draft.field.duration"
        case "name": "plan.draft.field.exercise"
        case "muscle_group": "plan.draft.field.muscle-group"
        case "sets": "plan.draft.field.sets"
        case "reps_range": "plan.draft.field.reps"
        case "rest_seconds": "plan.draft.field.rest"
        case "meal_type": "plan.draft.field.meal"
        case "time_suggestion": "plan.draft.field.time"
        case "food_name": "plan.draft.field.food"
        case "quantity_g": "plan.draft.field.quantity"
        default: "plan.draft.field.other"
        }
    }

    /// Labels of the values the screen shows without editing.
    static func detailKey(_ key: String) -> String.LocalizationValue {
        switch key {
        case "plan_type": "plan.draft.detail.plan-type"
        case "equipment_summary": "plan.draft.detail.equipment"
        case "progression_rule": "plan.draft.detail.progression"
        case "notes": "plan.draft.detail.notes"
        case "mode": "plan.draft.detail.mode"
        case "horizon": "plan.draft.detail.horizon"
        case "meta_kcal": "plan.draft.detail.meta-kcal"
        case "meta_protein_g": "plan.draft.detail.meta-protein"
        case "day_of_week": "plan.draft.detail.day-of-week"
        case "total_kcal": "plan.draft.detail.total-kcal"
        case "total_protein_g": "plan.draft.detail.total-protein"
        case "kcal": "plan.draft.detail.kcal"
        case "protein_g": "plan.draft.detail.protein"
        case "carbs_g": "plan.draft.detail.carbs"
        case "fat_g": "plan.draft.detail.fat"
        case "rpe_target": "plan.draft.detail.rpe"
        case "execution_steps": "plan.draft.detail.execution"
        case "common_mistakes": "plan.draft.detail.mistakes"
        default: "plan.draft.field.other"
        }
    }

    /// How a value the screen shows without editing is drawn. Free text —
    /// written by the generator or read from the patient's document, up to
    /// hundreds of characters — goes below its label, across the card;
    /// closed values, numbers and the equipment list stay beside it. Decided
    /// by what the value is, never by its length on screen.
    static func detailLayout(_ key: String) -> FeatureFieldLayout {
        switch key {
        case "notes", "progression_rule", "execution_steps", "common_mistakes": .stacked
        default: .row
        }
    }

    static func detailValue(
        key: String,
        text: String,
        language: SupportedAppLanguage
    ) -> String {
        let localizationKey: String
        switch (key, text) {
        case ("plan_type", "split"), ("plan_type", "full_body"), ("plan_type", "custom"):
            localizationKey = "plan.training.type." + text
        case ("mode", "rigida"), ("mode", "referencia"):
            localizationKey = "plan.draft.value.mode." + text
        case ("horizon", "daily"), ("horizon", "weekly"):
            localizationKey = "plan.draft.value.horizon." + text
        default: return text
        }
        return string(String.LocalizationValue(stringLiteral: localizationKey), language: language)
    }

    /// The same value as the screen draws it for a draft of a given origin.
    ///
    /// The effort of a SUGGESTION WRITTEN BY FLOW gains its scale when it is
    /// a bare grade or range from 1 to 10: "9" reads "9 de 10". This is the
    /// "decisão do orquestrador, anunciada ao dono em 2026-10-10, que pode
    /// riscar qualquer uma" — not an approval by the owner or by the
    /// physician. Everything else is shown as it came: a phrase, a grade
    /// that already says its scale ("9 de 10", "8/10"), a number outside 1
    /// to 10.
    ///
    /// A plan IMPORTED from the person's own photo or PDF never gains a
    /// scale: its number may be on another scale (engineer's choice inside
    /// that decision — RC U1B-P4).
    static func detailValue(
        key: String,
        text: String,
        language: SupportedAppLanguage,
        imported: Bool
    ) -> String {
        guard key == "rpe_target", !imported,
              let effort = effortGrade(text),
              !effort.numbers.isEmpty,
              effort.numbers.allSatisfy({ (1...10).contains($0) })
        else {
            return detailValue(key: key, text: text, language: language)
        }
        return String(
            format: string("plan.draft.detail.rpe.scale-format", language: language),
            effort.grade
        ) + effort.stop
    }

    /// How a value is drawn, knowing the value: the effort stays beside its
    /// label while it is a grade ("9", "8-9", "9 de 10") and goes below it,
    /// across the card, when the server sent a phrase.
    static func detailLayout(_ key: String, text: String) -> FeatureFieldLayout {
        guard key == "rpe_target" else { return detailLayout(key) }
        return effortGrade(text) != nil || isEffortGradeWithScale(text) ? .row : .stacked
    }

    /// The numbers of a bare effort grade or range, read exactly as the
    /// server reads one (`flow-plain-training-language.ts`, GRADE and
    /// BARE_GRADE): one or two digits with one optional decimal after ","
    /// or "."; a range with "-", "–" or " a "; an optional full stop at the
    /// end. `nil` for anything else.
    static func effortGrade(_ text: String) -> (numbers: [Double], grade: String, stop: String)? {
        guard let match = text.wholeMatch(of: effortGradePattern) else { return nil }
        let written = [match.output.first, match.output.dashed, match.output.spelled].compactMap { $0 }
        let numbers = written.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        guard numbers.count == written.count else { return nil }
        return (numbers, String(match.output.grade), String(match.output.stop))
    }

    private static var effortGradePattern: Regex<(
        Substring, grade: Substring, first: Substring, dashed: Substring?, spelled: Substring?, stop: Substring
    )> {
        #/[ \t\u{A0}]*(?<grade>(?<first>[0-9]{1,2}(?:[.,][0-9])?)(?:[ \t\u{A0}]*[-\u{2013}][ \t\u{A0}]*(?<dashed>[0-9]{1,2}(?:[.,][0-9])?)|[ \t\u{A0}]+a[ \t\u{A0}]+(?<spelled>[0-9]{1,2}(?:[.,][0-9])?))?)[ \t\u{A0}]*(?<stop>\.?)\s*/#
    }

    /// A grade that already says its scale: "9 de 10", "8-9 of 10", "8/10".
    static func isEffortGradeWithScale(_ text: String) -> Bool {
        text.wholeMatch(
            of: #/[ \t\u{A0}]*[0-9]{1,2}(?:[.,][0-9])?(?:[ \t\u{A0}]*[-\u{2013}][ \t\u{A0}]*[0-9]{1,2}(?:[.,][0-9])?|[ \t\u{A0}]+a[ \t\u{A0}]+[0-9]{1,2}(?:[.,][0-9])?)?(?:[ \t\u{A0}]*/[ \t\u{A0}]*10|[ \t\u{A0}]+(?:de|of)[ \t\u{A0}]+10)[ \t\u{A0}]*\.?\s*/#
        ) != nil
    }

    static func mealTypeKey(_ value: String) -> String.LocalizationValue {
        switch value {
        case "cafe": "plan.draft.meal.cafe"
        case "lanche_manha": "plan.draft.meal.lanche-manha"
        case "almoco": "plan.draft.meal.almoco"
        case "lanche_tarde": "plan.draft.meal.lanche-tarde"
        case "jantar": "plan.draft.meal.jantar"
        case "ceia": "plan.draft.meal.ceia"
        default: "plan.draft.meal.unknown"
        }
    }

    static func uncertaintyKey(_ reason: String) -> String.LocalizationValue {
        switch reason {
        case "missing": "plan.draft.uncertain.missing"
        case "out_of_range": "plan.draft.uncertain.out-of-range"
        case "not_in_document": "plan.draft.uncertain.not-in-document"
        case "outside_domain": "plan.draft.uncertain.outside-domain"
        case "supplement": "plan.draft.uncertain.supplement"
        case "supplement_imported": "plan.draft.uncertain.supplement-imported"
        default: "plan.draft.uncertain.invalid"
        }
    }

    static func failureKey(_ failure: PlanDraftFailure) -> String.LocalizationValue {
        switch failure {
        case .offline: "registration.live.failure.offline"
        case .unavailable, .invalidInput: "registration.live.failure.unavailable"
        case .subscriptionRequired: "registration.live.failure.subscription"
        case .notFound: "plan.draft.failure.not-found"
        case .draftChanged: "plan.draft.failure.changed"
        case .planChangedDuringReview: "plan.draft.failure.plan-changed"
        case .prescribedPlanProtected: "plan.draft.failure.prescribed"
        case .incomplete: "plan.draft.failure.incomplete"
        case .notReviewable: "plan.draft.failure.not-reviewable"
        case .expired: "plan.draft.failure.expired"
        case .tooManyDrafts: "plan.draft.failure.too-many"
        case .documentAlreadyImported: "plan.import.failure.already-imported"
        case .documentAlreadyRead: "plan.import.failure.already-read"
        }
    }

    static func closedKey(
        _ status: PlanDraftStatus,
        failureCode: String?
    ) -> String.LocalizationValue {
        if status == .expired { return "plan.draft.failure.expired" }
        switch failureCode {
        case "document_without_text": return "plan.import.closed.without-text"
        case "document_too_long": return "plan.import.closed.too-long"
        case "document_unreadable": return "plan.import.closed.unreadable"
        case "nothing_recognized": return "plan.import.closed.nothing-recognized"
        default: return "plan.import.closed.failed"
        }
    }

    static func importFailureKey(_ failure: PlanImportFailure) -> String.LocalizationValue {
        switch failure {
        case let .capture(capture): MealCaptureCopy.key(for: capture)
        case let .draft(draft): failureKey(draft)
        }
    }
}
