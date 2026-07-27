import SwiftUI

@MainActor
struct BodyDataStepView: View {
    let model: OnboardingFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                title: "Dados corporais",
                message: "Esses dados ajudam a personalizar sua experiência."
            )

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text("Sexo biológico").font(BodyFlowTypography.headline)
                Picker("Sexo biológico", selection: biologicalSex) {
                    Text("Selecione").tag(nil as BiologicalSex?)
                    ForEach(BiologicalSex.allCases, id: \.self) { value in
                        Text(value.onboardingLabel).tag(value as BiologicalSex?)
                    }
                }
                .pickerStyle(.segmented)
                OnboardingFieldIssue(model: model, candidates: [.biologicalSexRequired])
            }

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text("Data de nascimento").font(BodyFlowTypography.headline)
                if model.draft.birthDate != nil {
                    DatePicker(
                        "Data de nascimento",
                        selection: birthDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                } else {
                    Button("Selecionar data") {
                        model.updateBirthDate(Date(timeIntervalSince1970: 946_684_800))
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                }
                OnboardingFieldIssue(
                    model: model,
                    candidates: [.birthDateRequired, .birthDateInFuture]
                )
            }

            decimalField(
                descriptor: .height,
                value: height,
                identifier: "onboarding.height",
                issues: [.heightOutOfRange]
            )
            decimalField(
                descriptor: .weight,
                value: weight,
                identifier: "onboarding.weight",
                issues: [.weightOutOfRange]
            )
            decimalField(
                descriptor: .bodyFat,
                value: bodyFat,
                identifier: "onboarding.body-fat",
                issues: [.bodyFatOutOfRange]
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.body-data")
    }

    private var biologicalSex: Binding<BiologicalSex?> {
        Binding(get: { model.draft.biologicalSex }, set: { model.updateBiologicalSex($0) })
    }

    private var birthDate: Binding<Date> {
        Binding(
            get: { model.draft.birthDate ?? Date(timeIntervalSince1970: 946_684_800) },
            set: { model.updateBirthDate($0) }
        )
    }

    private var height: Binding<Double?> {
        Binding(get: { model.draft.heightCM }, set: { model.updateHeightCM($0) })
    }

    private var weight: Binding<Double?> {
        Binding(get: { model.draft.weightKG }, set: { model.updateWeightKG($0) })
    }

    private var bodyFat: Binding<Double?> {
        Binding(get: { model.draft.bodyFatPercent }, set: { model.updateBodyFatPercent($0) })
    }

    private func decimalField(
        descriptor: OnboardingDecimalFieldDescriptor,
        value: Binding<Double?>,
        identifier: String,
        issues: [OnboardingValidationIssue]
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(descriptor.title).font(BodyFlowTypography.headline)
            HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                TextField(
                    descriptor.accessibilityLabel,
                    value: value,
                    format: .number.precision(.fractionLength(0...2)),
                    prompt: Text(descriptor.prompt)
                )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(descriptor.accessibilityLabel)
                    .accessibilityValue(descriptor.accessibilityValue(for: value.wrappedValue))
                    .accessibilityIdentifier(identifier)
                Text(descriptor.unit)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .accessibilityHidden(true)
            }
            OnboardingFieldIssue(model: model, candidates: issues)
        }
    }
}

struct OnboardingDecimalFieldDescriptor: Equatable {
    let title: String
    let prompt: String
    let accessibilityLabel: String
    let unit: String

    static let height = OnboardingDecimalFieldDescriptor(
        title: "Altura",
        prompt: "0",
        accessibilityLabel: "Altura",
        unit: "cm"
    )
    static let weight = OnboardingDecimalFieldDescriptor(
        title: "Peso",
        prompt: "0",
        accessibilityLabel: "Peso",
        unit: "kg"
    )
    static let bodyFat = OnboardingDecimalFieldDescriptor(
        title: "Gordura corporal (opcional)",
        prompt: "Opcional",
        accessibilityLabel: "Gordura corporal",
        unit: "%"
    )

    func accessibilityValue(for value: Double?) -> String {
        guard let value else { return "Não informado, \(unit)" }
        let formatted = value.formatted(
            .number
                .locale(Locale(identifier: "pt_BR"))
                .precision(.fractionLength(0...2))
        )
        return "\(formatted) \(unit)"
    }
}

#if DEBUG
#Preview("Dados corporais · Válido") {
    OnboardingContainerView(model: .preview(step: .bodyData))
}

#Preview("Dados corporais · Validação") {
    OnboardingContainerView(model: .preview(
        step: .bodyData,
        validationIssues: [
            .biologicalSexRequired, .birthDateRequired,
            .heightOutOfRange, .weightOutOfRange, .bodyFatOutOfRange,
        ]
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Dados corporais · Erro ao salvar") {
    OnboardingContainerView(model: .preview(
        step: .bodyData,
        operationState: .failed(.storageUnavailable)
    ))
}
#endif
