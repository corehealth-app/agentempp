import Foundation
import SwiftUI

struct PlanField: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let value: String
}

struct NutritionPlanSection: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let fields: [PlanField]
}

struct PlanPresentation: Equatable, Sendable {
    let trainingFields: [PlanField]
    let nutritionSections: [NutritionPlanSection]

    init(
        snapshot: PlanSnapshot,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        trainingFields = snapshot.training.map {
            Self.trainingFields($0, language: language)
        } ?? []
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
            PlanField(id: "plan.training.type", title: copy("plan.training.type", language), value: training.planType),
            PlanField(id: "plan.training.days", title: copy("plan.training.days", language), value: "\(training.daysPerWeek)"),
            optionalField("plan.training.equipment", copy("plan.training.equipment", language), training.equipmentSummary),
            PlanField(id: "plan.training.generated", title: copy("plan.generated", language), value: date(training.generatedAt, language: language)),
            optionalField("plan.training.valid-until", copy("plan.valid-until", language), training.validUntil.map { date($0, language: language) }),
            optionalField("plan.training.version", copy("plan.version", language), training.version.map(String.init)),
            optionalField("plan.training.notes", copy("plan.notes", language), training.notes),
        ].compactMap { $0 }
    }

    private static func nutritionSection(
        _ prescription: NutritionPrescriptionSnapshot,
        language: SupportedAppLanguage
    ) -> NutritionPlanSection {
        NutritionPlanSection(
            id: prescription.id,
            title: copy("plan.nutrition.title", language),
            fields: [
                PlanField(id: "plan.nutrition.\(prescription.id).type", title: copy("plan.nutrition.type", language), value: prescription.type),
                PlanField(id: "plan.nutrition.\(prescription.id).generated", title: copy("plan.generated", language), value: date(prescription.generatedAt, language: language)),
                optionalField("plan.nutrition.\(prescription.id).valid-until", copy("plan.valid-until", language), prescription.validUntil.map { date($0, language: language) }),
                optionalField("plan.nutrition.\(prescription.id).version", copy("plan.version", language), prescription.version.map(String.init)),
                optionalField("plan.nutrition.\(prescription.id).notes", copy("plan.notes", language), prescription.notes),
            ].compactMap { $0 }
        )
    }

    private static func optionalField(
        _ id: String,
        _ title: String,
        _ value: String?
    ) -> PlanField? {
        value.map { PlanField(id: id, title: title, value: $0) }
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
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                ForEach(primaryFields) { field in
                    FixtureMetricRow(title: field.title, value: field.value)
                        .accessibilityIdentifier(field.id)
                    if field.id != primaryFields.last?.id { Divider() }
                }

                if !secondaryFields.isEmpty {
                    Divider()
                    Text(PlanCopy.string("plan.metadata.title", language: language))
                        .font(BodyFlowTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("plan.metadata")

                    ForEach(secondaryFields) { field in
                        FixtureMetricRow(title: field.title, value: field.value)
                            .accessibilityIdentifier(field.id)
                        if field.id != secondaryFields.last?.id { Divider() }
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

enum PlanCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }
}
