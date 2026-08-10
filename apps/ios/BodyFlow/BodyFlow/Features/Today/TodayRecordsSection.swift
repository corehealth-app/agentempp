import SwiftUI

enum TodayNutritionProvenance {
    static func label(for source: String?) -> String {
        switch source {
        case "canonical_exact", "product_label":
            "Referência confirmada"
        case "llm_estimate",
             "category_mismatch",
             "protein_mismatch",
             "composite_rejected":
            "Estimativa"
        case "user_kcal", "user_correction":
            "Informado pelo paciente"
        default:
            "Origem não informada"
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            mealsSection
            workoutsSection
        }
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Label("Refeições confirmadas", systemImage: "fork.knife")
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.primaryText)

            if meals.isEmpty {
                Text("Nenhum registro confirmado.")
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
                            Text(TodayValueFormatter.kcal(meal.kcal))
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
            Label("Treinos confirmados", systemImage: "figure.run")
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.primaryText)

            if workouts.isEmpty {
                Text("Nenhum treino confirmado.")
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
                            Text(TodayValueFormatter.kcal(workout.estimatedKcal))
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
}
