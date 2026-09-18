import SwiftUI

@MainActor
struct RoutineStepView: View {
    let model: OnboardingFlowModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                titleKey: "onboarding.routine.title",
                titleFallback: "Sua rotina",
                messageKey: "onboarding.routine.message",
                messageFallback: "Conte como são seus hábitos em uma semana comum."
            )

            pickerField(
                copy("onboarding.routine.activity-level.title"),
                selection: activityLevel,
                issues: [.activityLevelRequired]
            ) {
                Text(copy("onboarding.selection.placeholder"))
                    .tag(nil as ActivityLevel?)
                ForEach(ActivityLevel.allCases, id: \.self) {
                    Text($0.onboardingLabel(for: language))
                        .tag($0 as ActivityLevel?)
                }
            }
            OnboardingFieldIssue(model: model, candidates: [.activityLevelRequired])

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy("onboarding.routine.training-frequency.title"))
                    .font(BodyFlowTypography.headline)
                if model.draft.trainingFrequency != nil {
                    Stepper(value: trainingFrequency, in: 0...7) {
                        Text(OnboardingCopy.format(
                            "onboarding.routine.training-frequency.format",
                            language: language,
                            model.draft.trainingFrequency ?? 0
                        ))
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .accessibilityHint(
                        model.accessibilityHint(
                            for: [.trainingFrequencyOutOfRange]
                        )
                    )
                } else {
                    Button {
                        model.updateTrainingFrequency(0)
                    } label: {
                        Text(copy("onboarding.routine.training-frequency.set"))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: BodyFlowSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint(
                        model.accessibilityHint(
                            for: [.trainingFrequencyOutOfRange]
                        )
                    )
                }
                OnboardingFieldIssue(model: model, candidates: [.trainingFrequencyOutOfRange])
            }

            pickerField(
                copy("onboarding.routine.water-intake.title"),
                selection: waterIntake,
                issues: [.waterIntakeRequired]
            ) {
                Text(copy("onboarding.selection.placeholder"))
                    .tag(nil as WaterIntake?)
                ForEach(WaterIntake.allCases, id: \.self) {
                    Text($0.onboardingLabel(for: language))
                        .tag($0 as WaterIntake?)
                }
            }
            OnboardingFieldIssue(model: model, candidates: [.waterIntakeRequired])

            pickerField(
                copy("onboarding.routine.hunger-level.title"),
                selection: hungerLevel,
                issues: [.hungerLevelRequired]
            ) {
                Text(copy("onboarding.selection.placeholder"))
                    .tag(nil as HungerLevel?)
                ForEach(HungerLevel.allCases, id: \.self) {
                    Text($0.onboardingLabel(for: language))
                        .tag($0 as HungerLevel?)
                }
            }
            OnboardingFieldIssue(model: model, candidates: [.hungerLevelRequired])

            timeField(
                title: copy("onboarding.routine.wake-time.title"),
                value: model.draft.wakeTime,
                selection: wakeDate,
                defaultValue: LocalTime(hour: 7, minute: 0),
                issues: [.wakeTimeRequired],
                update: { model.updateWakeTime($0) }
            )
            OnboardingFieldIssue(model: model, candidates: [.wakeTimeRequired])

            timeField(
                title: copy("onboarding.routine.bedtime.title"),
                value: model.draft.bedtime,
                selection: bedtimeDate,
                defaultValue: LocalTime(hour: 23, minute: 0),
                issues: [.bedtimeRequired],
                update: { model.updateBedtime($0) }
            )
            OnboardingFieldIssue(model: model, candidates: [.bedtimeRequired])

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Toggle(
                    copy("onboarding.routine.food-organization.title"),
                    isOn: organizesFood
                )
                    .font(BodyFlowTypography.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHint(
                        model.accessibilityHint(
                            for: [.foodOrganizationRequired]
                        )
                    )
                if model.draft.foodOrganization == nil {
                    Text(copy("onboarding.routine.food-organization.unconfirmed"))
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                    Button {
                        model.updateFoodOrganization(.no)
                    } label: {
                        Text(copy("onboarding.routine.food-organization.confirm-no"))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: BodyFlowSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint(
                        model.accessibilityHint(
                            for: [.foodOrganizationRequired]
                        )
                    )
                }
                OnboardingFieldIssue(model: model, candidates: [.foodOrganizationRequired])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.routine")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: language)
    }

    private var activityLevel: Binding<ActivityLevel?> {
        Binding(get: { model.draft.activityLevel }, set: { model.updateActivityLevel($0) })
    }

    private var trainingFrequency: Binding<Int> {
        Binding(
            get: { model.draft.trainingFrequency ?? 0 },
            set: { model.updateTrainingFrequency($0) }
        )
    }

    private var waterIntake: Binding<WaterIntake?> {
        Binding(get: { model.draft.waterIntake }, set: { model.updateWaterIntake($0) })
    }

    private var hungerLevel: Binding<HungerLevel?> {
        Binding(get: { model.draft.hungerLevel }, set: { model.updateHungerLevel($0) })
    }

    private var wakeDate: Binding<Date> { timeBinding(model.draft.wakeTime, update: model.updateWakeTime) }
    private var bedtimeDate: Binding<Date> { timeBinding(model.draft.bedtime, update: model.updateBedtime) }

    private var organizesFood: Binding<Bool> {
        Binding(
            get: { model.draft.foodOrganization == .yes },
            set: { model.updateFoodOrganization($0 ? .yes : .no) }
        )
    }

    private func timeBinding(
        _ value: LocalTime?,
        update: @escaping (LocalTime?) -> Void
    ) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: value?.hour ?? 7,
                    minute: value?.minute ?? 0,
                    second: 0,
                    of: Date(timeIntervalSince1970: 946_684_800)
                ) ?? Date(timeIntervalSince1970: 946_684_800)
            },
            set: {
                let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
                update(LocalTime(hour: components.hour ?? 0, minute: components.minute ?? 0))
            }
        )
    }

    private func timeField(
        title: String,
        value: LocalTime?,
        selection: Binding<Date>,
        defaultValue: LocalTime,
        issues: [OnboardingValidationIssue],
        update: @escaping (LocalTime?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(title).font(BodyFlowTypography.headline)
            if value != nil {
                DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .accessibilityHint(model.accessibilityHint(for: issues))
            } else {
                Button {
                    update(defaultValue)
                } label: {
                    Text(copy("onboarding.routine.select-time"))
                        .frame(
                            maxWidth: .infinity,
                            minHeight: BodyFlowSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityHint(model.accessibilityHint(for: issues))
            }
        }
    }

    private func pickerField<Selection: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Selection>,
        issues: [OnboardingValidationIssue],
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(title).font(BodyFlowTypography.headline)
            Picker(title, selection: selection, content: content)
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
                .accessibilityHint(model.accessibilityHint(for: issues))
        }
    }
}

#if DEBUG
#Preview("Rotina · Válido") {
    OnboardingContainerView(model: .preview(step: .routine))
}

#Preview("Rotina · Validação") {
    OnboardingContainerView(model: .preview(
        step: .routine,
        validationIssues: [
            .activityLevelRequired, .trainingFrequencyOutOfRange,
            .waterIntakeRequired, .hungerLevelRequired,
            .wakeTimeRequired, .bedtimeRequired, .foodOrganizationRequired,
        ]
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Rotina · Erro ao salvar") {
    OnboardingContainerView(model: .preview(
        step: .routine,
        operationState: .failed(.serviceUnavailable)
    ))
}
#endif
