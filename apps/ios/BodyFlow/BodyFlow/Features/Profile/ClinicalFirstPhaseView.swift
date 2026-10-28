import SwiftUI

@MainActor
struct ClinicalFirstPhaseView: View {
    let model: ClinicalFirstPhaseModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                if model.confirmation != nil {
                    Text(copy("first-phase.confirmed")).accessibilityIdentifier("first-phase.confirmed")
                    Button(copy("first-phase.done")) { dismiss() }
                        .buttonStyle(BodyFlowButtonStyle(role: .primary))
                } else if let preview = model.preview {
                    previewCard(preview)
                } else if let choices = model.choices {
                    choicesCard(choices)
                } else if !model.isBusy {
                    Text(copy("first-phase.unavailable"))
                    Button(copy("first-phase.refresh")) { Task { await model.load() } }
                        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                }
                if model.isBusy { ProgressView(copy("first-phase.loading")) }
                if let error = model.error {
                    Text(copy(errorKey(error))).foregroundStyle(BodyFlowColor.secondaryText)
                        .accessibilityIdentifier("first-phase.error")
                    if model.preview == nil {
                        Button(copy("first-phase.refresh")) { Task { await model.load() } }
                            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    }
                }
            }
            .padding(BodyFlowSpacing.md)
        }
        .background(BodyFlowColor.background)
        .navigationTitle(copy(model.preview == nil ? "first-phase.title" : "first-phase.preview"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.first-phase")
        .task { await model.load() }
    }
    private func choicesCard(_ value: ClinicalFirstPhaseChoices) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("first-phase.intro"))
            if value.professionalAssessmentRecommended { Text(copy("first-phase.professional")) }
            if !value.missing.isEmpty || value.availability == .incomplete { Text(copy("first-phase.complete-profile")) }
            ForEach(value.options.filter { $0.status != .notOffered }, id: \.phase.rawValue) { option in
                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        Button(option.phase.onboardingLabel(for: language)) { Task { await model.prepare(option.phase) } }
                            .buttonStyle(BodyFlowButtonStyle(role: .primary))
                            .disabled(model.isBusy || option.status != .available)
                            .accessibilityIdentifier("first-phase.option.\(option.phase.rawValue)")
                        if option.status == .blocked { Text(copy("first-phase.restricted")).font(BodyFlowTypography.callout) }
                    }
                }
            }
        }
    }
    private func previewCard(_ value: ClinicalFirstPhasePreview) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(value.phase.onboardingLabel(for: language)).font(BodyFlowTypography.sectionTitle)
            Text(String(format: copy("first-phase.effective"), value.effectiveDate))
            BodyFlowCard {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    Text(copy("first-phase.calories"))
                    Text(TodayValueFormatter.mealKcal(Decimal(value.targets.caloriesKcal), language: language))
                        .font(BodyFlowTypography.headline).accessibilityIdentifier("first-phase.calories")
                    Text(copy("first-phase.protein"))
                    Text(TodayValueFormatter.optionalGrams(value.targets.proteinG, language: language))
                        .font(BodyFlowTypography.headline).accessibilityIdentifier("first-phase.protein")
                }
            }
            Button(copy(model.hasPendingConfirmation ? "first-phase.retry" : "first-phase.confirm")) { Task { await model.confirm() } }
                .buttonStyle(BodyFlowButtonStyle(role: .primary)).disabled(model.isBusy)
                .accessibilityIdentifier("first-phase.confirm")
            if !model.hasPendingConfirmation {
                Button(copy("first-phase.back")) { model.backToChoices() }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary)).disabled(model.isBusy)
            }
        }
    }
    private func errorKey(_ value: ClinicalFirstPhaseFailure) -> String.LocalizationValue {
        if model.hasPendingConfirmation { return "first-phase.uncertain" }
        switch value {
        case .changed: return "first-phase.changed"
        case .offline: return "first-phase.offline"
        case .busy: return "first-phase.busy"
        default: return "first-phase.unavailable"
        }
    }
    private func copy(_ key: String.LocalizationValue) -> String { TodayCopy.string(key, language: language) }
}
