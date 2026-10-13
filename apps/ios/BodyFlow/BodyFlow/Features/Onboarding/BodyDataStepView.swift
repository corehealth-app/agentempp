import SwiftUI
import UIKit

@MainActor
struct BodyDataStepView: View {
    private enum Field: Hashable {
        case height
        case weight
        case bodyFat
    }

    let model: OnboardingFlowModel
    let photos: SignupBodyPhotoPresentationModel?
    let openPhotos: @MainActor () -> Void

    init(model: OnboardingFlowModel, photos: SignupBodyPhotoPresentationModel? = nil,
         openPhotos: @escaping @MainActor () -> Void = {}) {
        self.model = model
        self.photos = photos
        self.openPhotos = openPhotos
    }
    @Environment(\.locale) private var locale
    @FocusState private var focusedField: Field?
    @State private var isReloadingPhotos = false

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                titleKey: "onboarding.body-data.title",
                titleFallback: "Dados corporais",
                messageKey: "onboarding.body-data.message",
                messageFallback: "Esses dados ajudam a personalizar sua experiência."
            )

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy("onboarding.body-data.biological-sex.title"))
                    .font(BodyFlowTypography.headline)
                Picker(copy("onboarding.body-data.biological-sex.title"), selection: biologicalSex) {
                    Text(copy("onboarding.selection.placeholder"))
                        .tag(nil as BiologicalSex?)
                    ForEach(BiologicalSex.allCases, id: \.self) { value in
                        Text(value.onboardingLabel(for: language))
                            .tag(value as BiologicalSex?)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint(
                    model.accessibilityHint(for: [.biologicalSexRequired])
                )
                OnboardingFieldIssue(model: model, candidates: [.biologicalSexRequired])
            }

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy("onboarding.body-data.birth-date.title"))
                    .font(BodyFlowTypography.headline)
                if model.draft.birthDate != nil {
                    DatePicker(
                        copy("onboarding.body-data.birth-date.title"),
                        selection: birthDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.timeZone, birthDateTimeZone)
                    .accessibilityLabel(copy("onboarding.body-data.birth-date.title"))
                    .accessibilityHint(
                        model.accessibilityHint(
                            for: [.birthDateRequired, .birthDateInFuture]
                        )
                    )
                } else {
                    Button {
                        model.updateBirthDate(
                            OnboardingCivilDate.date(
                                from: "2000-01-01",
                                timeZoneIdentifier: model.draft.timeZoneIdentifier
                            )
                        )
                    } label: {
                        Text(copy("onboarding.body-data.birth-date.select"))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: BodyFlowSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityHint(
                        model.accessibilityHint(
                            for: [.birthDateRequired, .birthDateInFuture]
                        )
                    )
                }
                OnboardingFieldIssue(
                    model: model,
                    candidates: [.birthDateRequired, .birthDateInFuture]
                )
            }

            decimalField(
                descriptor: .height(language: language),
                value: height,
                field: .height,
                identifier: "onboarding.height",
                issues: [.heightOutOfRange]
            )
            decimalField(
                descriptor: .weight(language: language),
                value: weight,
                field: .weight,
                identifier: "onboarding.weight",
                issues: [.weightOutOfRange]
            )
            if let photos {
                if photos.loadFailed || isReloadingPhotos {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        if photos.loadFailed {
                            BodyFlowStatusLine(copy("state.error.detail"), kind: .error)
                                .accessibilityIdentifier("onboarding.photos.load.error")
                        } else {
                            BodyFlowStatusLine(copy("state.loading.title"), kind: .pending)
                        }
                        Button(copy("onboarding.retry"), action: reloadPhotos)
                            .buttonStyle(BodyFlowButtonStyle(role: .secondary,
                                isLoading: isReloadingPhotos))
                            .disabled(isReloadingPhotos || !model.allowsDraftEditing
                                || model.operationState == .saving)
                            .accessibilityIdentifier("onboarding.photos.load.retry")
                    }
                }
                if model.draft.bodyFatOrigin == .photos,
                   let confirmation = model.draft.bodyPhotoConfirmation,
                   confirmation.matches(model.draft), !model.requiresBodyPhotoRevalidation {
                    let number = confirmation.value.formatted(
                        .number.locale(language.formattingLocale)
                            .precision(.fractionLength(0...2))) + "%"
                    Text(OnboardingCopy.format("onboarding.body-fat.photos.confirmed-format",
                        language: language, number))
                        .font(BodyFlowTypography.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("onboarding.body-fat.photos.confirmed")
                }
                SignupBodyPhotoChoiceView(availability: photos.availability,
                    selection: photos.choice, select: selectBodyFatChoice)
                    .disabled(!model.allowsDraftEditing || model.operationState == .saving)
            }
            if photos?.choice != .photos && photos?.choice != .skip {
                decimalField(
                    descriptor: .bodyFat(language: language),
                    value: bodyFat,
                    field: .bodyFat,
                    identifier: "onboarding.body-fat",
                    issues: [.bodyFatOutOfRange]
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.body-data")
        // The decimal pad has no return key: give it a way to close so the
        // keyboard never has to cover the step's Continue action.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(copy("keyboard.done")) {
                    focusedField = nil
                }
            }
        }
    }

    private var biologicalSex: Binding<BiologicalSex?> {
        Binding(get: { model.draft.biologicalSex }, set: { model.updateBiologicalSex($0) })
    }

    private func selectBodyFatChoice(_ choice: SignupBodyFatChoice) {
        // Commit the number still being edited before removing its field.
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
        photos?.select(choice)
        if choice == .photos, photos?.route != nil { openPhotos() }
    }

    private func reloadPhotos() {
        guard !isReloadingPhotos, let photos else { return }
        isReloadingPhotos = true
        Task {
            await photos.load()
            isReloadingPhotos = false
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: language)
    }

    private var birthDate: Binding<Date> {
        Binding(
            get: { model.draft.birthDate ?? Date(timeIntervalSince1970: 946_684_800) },
            set: { model.updateBirthDate($0) }
        )
    }

    private var birthDateTimeZone: TimeZone {
        OnboardingCivilDate.timeZone(for: model.draft.timeZoneIdentifier) ?? .gmt
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
        field: Field,
        identifier: String,
        issues: [OnboardingValidationIssue]
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(descriptor.title).font(BodyFlowTypography.headline)
            HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                TextField(
                    descriptor.accessibilityLabel,
                    value: value,
                    format: .number.locale(language.formattingLocale)
                        .precision(.fractionLength(0...2)),
                    prompt: Text(descriptor.prompt)
                )
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: field)
                    .bodyFlowField()
                    .accessibilityLabel(descriptor.accessibilityLabel)
                    .accessibilityValue(descriptor.accessibilityValue(
                        for: value.wrappedValue,
                        language: language
                    ))
                    .accessibilityHint(model.accessibilityHint(for: issues))
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

    static var height: Self { height(language: .portugueseBrazil) }
    static var weight: Self { weight(language: .portugueseBrazil) }
    static var bodyFat: Self { bodyFat(language: .portugueseBrazil) }

    static func height(language: SupportedAppLanguage) -> Self {
        Self(
            title: OnboardingCopy.string("onboarding.body-data.height.title", language: language),
            prompt: "0",
            accessibilityLabel: OnboardingCopy.string(
                "onboarding.body-data.height.title",
                language: language
            ),
            unit: "cm"
        )
    }

    static func weight(language: SupportedAppLanguage) -> Self {
        Self(
            title: OnboardingCopy.string("onboarding.body-data.weight.title", language: language),
            prompt: "0",
            accessibilityLabel: OnboardingCopy.string(
                "onboarding.body-data.weight.title",
                language: language
            ),
            unit: "kg"
        )
    }

    static func bodyFat(language: SupportedAppLanguage) -> Self {
        Self(
            title: OnboardingCopy.string("onboarding.body-data.body-fat.title", language: language),
            prompt: OnboardingCopy.string("onboarding.body-data.optional", language: language),
            accessibilityLabel: OnboardingCopy.string(
                "onboarding.body-data.body-fat.accessibility-label",
                language: language
            ),
            unit: "%"
        )
    }

    func accessibilityValue(
        for value: Double?,
        language: SupportedAppLanguage
    ) -> String {
        guard let value else {
            return OnboardingCopy.format(
                "onboarding.body-data.not-provided-format",
                language: language,
                unit
            )
        }
        let formatted = value.formatted(
            .number
                .locale(language.formattingLocale)
                .precision(.fractionLength(0...2))
        )
        return "\(formatted) \(unit)"
    }

    func accessibilityValue(for value: Double?) -> String {
        accessibilityValue(for: value, language: .portugueseBrazil)
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
