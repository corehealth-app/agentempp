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

    /// The stored type as a label ("musculacao" reads "Musculação"); nil
    /// when the record has none.
    func typeTitle(language: SupportedAppLanguage) -> String? {
        workoutType.map { RegistrationCopy.workoutTypeTitle(stored: $0, language: language) }
    }

    /// Duration and intensity; the intensity is shown as a label, never as
    /// the stored code. An absent part is left out and nothing is shown in
    /// its place.
    func detailText(language: SupportedAppLanguage) -> String {
        let parts = [
            durationMin.map { "\(TodayValueFormatter.integer($0, language: language)) min" },
            intensity.map { RegistrationCopy.workoutIntensityTitle(stored: $0, language: language) },
        ].compactMap { $0 }
        return parts.isEmpty
            ? TodayCopy.string("common.not-available", language: language)
            : parts.joined(separator: " · ")
    }
}

@MainActor
/// The day's confirmed workouts (the meals live in `TodayMealSlotsSection`).
struct TodayRecordsSection: View {
    let workouts: [TodayWorkoutDescriptor]
    let strengthTrainingWeek: TodayStrengthTrainingWeekDescriptor?
    let isRefreshing: Bool
    let refresh: (() -> Void)?
    @Environment(\.locale) private var locale

    init(
        workouts: [TodayWorkoutDescriptor],
        strengthTrainingWeek: TodayStrengthTrainingWeekDescriptor? = nil,
        isRefreshing: Bool = false,
        refresh: (() -> Void)? = nil
    ) {
        self.workouts = workouts
        self.strengthTrainingWeek = strengthTrainingWeek
        self.isRefreshing = isRefreshing
        self.refresh = refresh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            if let strengthTrainingWeek {
                TodayStrengthTrainingWeekCard(
                    descriptor: strengthTrainingWeek,
                    isRefreshing: isRefreshing,
                    refresh: refresh
                )
            }
            workoutsSection
        }
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
                        HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                        BodyFlowDomainGlyph(domain: .exercise)
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                            Text(workout.typeTitle(language: language) ?? copy("history.workout.fallback"))
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
