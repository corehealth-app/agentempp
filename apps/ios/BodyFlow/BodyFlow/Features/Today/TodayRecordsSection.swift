import SwiftUI

enum TodayNutritionProvenance {
    static func label(for source: String?) -> String {
        label(for: source, language: .portugueseBrazil)
    }

    static func label(
        for source: String?,
        language: SupportedAppLanguage
    ) -> String {
        let key: String.LocalizationValue = switch source {
        case "canonical_exact", "product_label", "taco":
            "today.provenance.confirmed"
        // A reference-table value reached by an approximate match, a
        // composition or the patient's own history (`MealNutritionSource`).
        case "canonical_fuzzy",
             "canonical_composite",
             "canonical_composite_partial",
             "rule_based",
             "history",
             "pending_approved":
            "today.provenance.reference"
        case "llm_estimate",
             "category_mismatch",
             "protein_mismatch",
             "composite_rejected":
            "today.provenance.estimate"
        case "user_kcal", "user_correction":
            "today.provenance.user-provided"
        default:
            "today.provenance.unknown"
        }
        return TodayCopy.string(key, language: language)
    }
}

struct TodayMealDescriptor: Equatable, Sendable, Identifiable {
    let id: String
    let mealType: String?
    let foodName: String
    let quantityG: Decimal?
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?
    let consumedAt: APITimestamp
    let provenance: String
}

struct TodayWorkoutDescriptor: Equatable, Sendable, Identifiable {
    let id: String
    let workoutType: String?
    let durationMin: Int?
    let estimatedKcal: Int?
    let intensity: String?
    let performedAt: APITimestamp

    /// Duration and intensity as received; an absent part is left out and
    /// nothing is shown in its place.
    func detailText(language: SupportedAppLanguage) -> String {
        let parts = [
            durationMin.map { "\(TodayValueFormatter.integer($0, language: language)) min" },
            intensity,
        ].compactMap { $0 }
        return parts.isEmpty
            ? TodayCopy.string("common.not-available", language: language)
            : parts.joined(separator: " · ")
    }
}

@MainActor
struct TodayRecordsSection: View {
    let meals: [TodayMealDescriptor]
    let workouts: [TodayWorkoutDescriptor]
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            mealsSection
            workoutsSection
        }
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            BodyFlowSectionHeader(copy("today.records.meals"), symbol: .meals)

            if meals.isEmpty {
                Text(copy("today.records.meals.empty"))
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            } else {
                ForEach(meals) { meal in
                    BodyFlowCard {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                            Text(meal.foodName)
                                .font(BodyFlowTypography.headline)
                                .foregroundStyle(BodyFlowColor.primaryText)
                            // Received type and energy on one line while
                            // they fit; stacked at accessibility sizes.
                            recordLine(
                                detail: meal.mealType.map {
                                    RegistrationCopy.mealTypeTitle(code: $0, language: language)
                                } ?? TodayCopy.string("common.not-available", language: language),
                                value: TodayValueFormatter.mealKcal(meal.kcal, language: language)
                            )
                            BodyFlowStatusLine(
                                meal.provenance,
                                kind: .info,
                                font: BodyFlowTypography.caption
                            )
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.meal.\(meal.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.meals")
    }

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            BodyFlowSectionHeader(copy("today.records.workouts"), symbol: .workouts)

            if workouts.isEmpty {
                Text(copy("today.records.workouts.empty"))
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            } else {
                ForEach(workouts) { workout in
                    BodyFlowCard {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                            Text(workout.workoutType ?? copy("history.workout.fallback"))
                                .font(BodyFlowTypography.headline)
                                .foregroundStyle(BodyFlowColor.primaryText)
                            recordLine(
                                detail: workout.detailText(language: language),
                                value: TodayValueFormatter.optionalKcal(
                                    workout.estimatedKcal,
                                    language: language
                                )
                            )
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.workout.\(workout.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.workouts")
    }

    private func recordLine(detail: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                detailText(detail)
                Spacer(minLength: BodyFlowSpacing.sm)
                valueText(value)
            }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                detailText(detail)
                valueText(value)
            }
        }
    }

    private func detailText(_ detail: String) -> some View {
        Text(detail)
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(BodyFlowTypography.body)
            .foregroundStyle(BodyFlowColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
