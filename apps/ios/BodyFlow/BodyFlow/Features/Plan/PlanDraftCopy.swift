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

    static func detailValue(
        key: String,
        text: String,
        language: SupportedAppLanguage
    ) -> String {
        guard key == "plan_type",
              ["split", "full_body", "custom"].contains(text) else {
            return text
        }
        let localizationKey = "plan.training.type." + text
        return string(String.LocalizationValue(stringLiteral: localizationKey), language: language)
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
