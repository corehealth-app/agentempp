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
        case "canonical_exact", "product_label":
            "today.provenance.confirmed"
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
    let mealType: String
    let foodName: String
    let quantityG: Decimal
    let kcal: Int
    let proteinG: Decimal
    let carbsG: Decimal
    let fatG: Decimal
    let consumedAt: APITimestamp
    let provenance: String
}

struct TodayWorkoutDescriptor: Equatable, Sendable, Identifiable {
    let id: String
    let workoutType: String
    let durationMin: Int
    let estimatedKcal: Int
    let intensity: String
    let performedAt: APITimestamp
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
            Label(copy("today.records.meals"), systemImage: "fork.knife")
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.primaryText)

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
                            Text(meal.mealType)
                                .font(BodyFlowTypography.callout)
                                .foregroundStyle(BodyFlowColor.secondaryText)
                            Text(TodayValueFormatter.kcal(meal.kcal, language: language))
                                .font(BodyFlowTypography.body)
                            Label(meal.provenance, systemImage: "info.circle")
                                .font(BodyFlowTypography.caption)
                                .foregroundStyle(BodyFlowColor.secondaryText)
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
            Label(copy("today.records.workouts"), systemImage: "figure.run")
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.primaryText)

            if workouts.isEmpty {
                Text(copy("today.records.workouts.empty"))
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            } else {
                ForEach(workouts) { workout in
                    BodyFlowCard {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                            Text(workout.workoutType)
                                .font(BodyFlowTypography.headline)
                                .foregroundStyle(BodyFlowColor.primaryText)
                            Text("\(workout.durationMin) min · \(workout.intensity)")
                                .font(BodyFlowTypography.callout)
                                .foregroundStyle(BodyFlowColor.secondaryText)
                            Text(TodayValueFormatter.kcal(workout.estimatedKcal, language: language))
                                .font(BodyFlowTypography.body)
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

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
