import Foundation
import SwiftUI

struct PlanField: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let value: String
    /// How the card draws the field. Marked here, where the field is built:
    /// the notes are free text and go below their label; everything else is
    /// a short value beside it.
    var layout: FeatureFieldLayout = .row
}

struct NutritionPlanSection: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let fields: [PlanField]
}

/// One day of the training plan, as the server stored it. Nothing here is
/// computed: a value the plan does not carry is simply not shown.
struct PlanTrainingDay: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let exercises: [PlanField]
}

struct PlanPresentation: Equatable, Sendable {
    let trainingFields: [PlanField]
    let trainingDays: [PlanTrainingDay]
    let nutritionSections: [NutritionPlanSection]

    init(
        snapshot: PlanSnapshot,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        trainingFields = snapshot.training.map {
            Self.trainingFields($0, language: language)
        } ?? []
        trainingDays = Self.trainingDays(
            snapshot.training?.weeklySchedule ?? [],
            language: language
        )
        nutritionSections = snapshot.nutrition.map {
            Self.nutritionSection($0, language: language)
        }
    }

    var isEmpty: Bool {
        trainingFields.isEmpty && nutritionSections.isEmpty
    }

    private static func trainingFields(
        _ training: TrainingPlanSnapshot,
        language: SupportedAppLanguage
    ) -> [PlanField] {
        [
            PlanField(
                id: "plan.training.type",
                title: copy("plan.training.type", language),
                value: label(for: training.planType, among: Self.trainingPlanTypes, prefix: "plan.training.type", language: language)
            ),
            PlanField(id: "plan.training.days", title: copy("plan.training.days", language), value: "\(training.daysPerWeek)"),
            optionalField("plan.training.equipment", copy("plan.training.equipment", language), training.equipmentSummary),
            PlanField(id: "plan.training.generated", title: copy("plan.generated", language), value: date(training.generatedAt, language: language)),
            optionalField("plan.training.valid-until", copy("plan.valid-until", language), training.validUntil.map { date($0, language: language) }),
            optionalField("plan.training.version", copy("plan.version", language), training.version.map(String.init)),
            optionalField("plan.training.notes", copy("plan.notes", language), training.notes, layout: .stacked),
        ].compactMap { $0 }
    }

    private static func trainingDays(
        _ schedule: [TrainingDaySnapshot],
        language: SupportedAppLanguage
    ) -> [PlanTrainingDay] {
        schedule.enumerated().compactMap { index, day in
            let heading = [
                day.day,
                day.focus,
                day.durationMin.map {
                    "\(number($0, language)) \(copy("plan.training.schedule.minutes", language))"
                },
            ].compactMap { value in
                value.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            }
            let exercises = day.exercises.enumerated().compactMap { position, exercise -> PlanField? in
                guard let name = exercise.name, !name.isEmpty else { return nil }
                let volume = [exercise.sets.map { number($0, language) }, exercise.repsRange]
                    .compactMap { $0 }
                    .joined(separator: " × ")
                let rest = exercise.restSeconds.map {
                    "\(copy("plan.training.schedule.rest", language)) \(number($0, language)) s"
                }
                return PlanField(
                    id: "plan.training.day.\(index).exercise.\(position)",
                    title: name,
                    value: [volume.isEmpty ? nil : volume, rest]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
            }
            guard !heading.isEmpty || !exercises.isEmpty else { return nil }
            return PlanTrainingDay(
                id: "plan.training.day.\(index)",
                title: heading.joined(separator: " · "),
                exercises: exercises
            )
        }
    }

    private static func number(_ value: Decimal, _ language: SupportedAppLanguage) -> String {
        MealProposalNumberParser.format(value, language: language)
    }

    private static func nutritionSection(
        _ prescription: NutritionPrescriptionSnapshot,
        language: SupportedAppLanguage
    ) -> NutritionPlanSection {
        NutritionPlanSection(
            id: prescription.id,
            title: copy("plan.nutrition.title", language),
            fields: [
                PlanField(
                    id: "plan.nutrition.\(prescription.id).type",
                    title: copy("plan.nutrition.type", language),
                    value: label(for: prescription.type, among: Self.prescriptionTypes, prefix: "plan.nutrition.type", language: language)
                ),
                PlanField(id: "plan.nutrition.\(prescription.id).generated", title: copy("plan.generated", language), value: date(prescription.generatedAt, language: language)),
                optionalField("plan.nutrition.\(prescription.id).valid-until", copy("plan.valid-until", language), prescription.validUntil.map { date($0, language: language) }),
                optionalField("plan.nutrition.\(prescription.id).version", copy("plan.version", language), prescription.version.map(String.init)),
                optionalField("plan.nutrition.\(prescription.id).notes", copy("plan.notes", language), prescription.notes, layout: .stacked),
            ].compactMap { $0 }
        )
    }

    private static func optionalField(
        _ id: String,
        _ title: String,
        _ value: String?,
        layout: FeatureFieldLayout = .row
    ) -> PlanField? {
        value.map { PlanField(id: id, title: title, value: $0, layout: layout) }
    }

    private static func date(
        _ timestamp: APITimestamp,
        language: SupportedAppLanguage
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.formattingLocale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = language == .englishUnitedStates
            ? "MM/dd/yyyy" : "dd/MM/yyyy"
        return formatter.string(from: timestamp.value)
    }

    private static func copy(
        _ key: String.LocalizationValue,
        _ language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }

    /// The closed enums the database enforces (`training_plans.plan_type`
    /// and `prescriptions.type` CHECK constraints). Only these get a display
    /// label; anything else is official server data and stays as received.
    private static let trainingPlanTypes: Set<String> = ["split", "full_body", "custom"]
    private static let prescriptionTypes: Set<String> = ["diet", "shopping_list", "combined"]

    private static func label(
        for value: String,
        among known: Set<String>,
        prefix: String,
        language: SupportedAppLanguage
    ) -> String {
        guard known.contains(value) else { return value }
        // Build the key as a plain string first: interpolating straight into
        // a LocalizationValue turns the pieces into format arguments.
        let key = prefix + "." + value
        return copy(String.LocalizationValue(stringLiteral: key), language)
    }
}

@MainActor
struct PlanContentView: View {
    let presentation: PlanPresentation
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            if !presentation.trainingFields.isEmpty {
                PlanMetadataCard(
                    title: PlanCopy.string("plan.training.title", language: language),
                    fields: presentation.trainingFields,
                    accessibilityIdentifier: "plan.training"
                )
            }

            ForEach(presentation.trainingDays) { day in
                BodyFlowCard(surface: .card) {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        Text(verbatim: day.title)
                            .font(BodyFlowTypography.cardTitle)
                            .foregroundStyle(BodyFlowColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(day.exercises) { exercise in
                            FixtureMetricRow(title: exercise.title, value: exercise.value, layout: exercise.layout)
                                .accessibilityIdentifier(exercise.id)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(day.id)
            }

            ForEach(presentation.nutritionSections) { section in
                PlanMetadataCard(
                    title: section.title,
                    fields: section.fields,
                    accessibilityIdentifier: "plan.nutrition.\(section.id)"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }
}

@MainActor
private struct PlanMetadataCard: View {
    let title: String
    let fields: [PlanField]
    let accessibilityIdentifier: String
    @Environment(\.locale) private var locale

    var body: some View {
        BodyFlowCard(surface: .card) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Text(title)
                    .font(BodyFlowTypography.cardTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)

                ForEach(primaryFields) { field in
                    FixtureMetricRow(title: field.title, value: field.value, layout: field.layout)
                        .accessibilityIdentifier(field.id)
                    if field.id != primaryFields.last?.id { Divider() }
                }

                // Provenance (generated / valid until / version) is real plan
                // data but not what the patient reads first: it keeps its own
                // heading and a quieter row, still fully expanded.
                if !secondaryFields.isEmpty {
                    Divider()
                    Text(PlanCopy.string("plan.metadata.title", language: language))
                        .font(BodyFlowTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("plan.metadata")

                    ForEach(secondaryFields) { field in
                        PlanProvenanceRow(title: field.title, value: field.value)
                            .accessibilityIdentifier(field.id)
                    }
                }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var primaryFields: [PlanField] {
        fields.filter { !isSecondary($0) }
    }

    private var secondaryFields: [PlanField] {
        fields.filter(isSecondary)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func isSecondary(_ field: PlanField) -> Bool {
        field.id.hasSuffix(".generated")
            || field.id.hasSuffix(".valid-until")
            || field.id.hasSuffix(".version")
    }
}

/// A provenance row: same received values, one step quieter than the plan's
/// own fields, and read as a single element.
@MainActor
private struct PlanProvenanceRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let value: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    titleText
                    valueText
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                    titleText
                    Spacer(minLength: BodyFlowSpacing.sm)
                    valueText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(verbatim: title)
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(verbatim: value)
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum PlanCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }
}
