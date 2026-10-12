import SwiftUI

/// Presentation choice only; the caller uses the existing draft/proof callbacks.
enum SignupBodyFatChoice: Equatable, Sendable { case photos, typed, skip }

@MainActor
struct SignupBodyPhotoChoiceView: View {
    let availability: SignupBodyPhotoAvailability
    let selection: SignupBodyFatChoice?
    let select: @MainActor (SignupBodyFatChoice) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: BodyFlowSpacing.sm) {
            choice(.photos, key: "onboarding.body-fat.choice.photos")
                .disabled(availability != .available)
            choice(.typed, key: "onboarding.body-fat.choice.typed")
            choice(.skip, key: "onboarding.body-fat.choice.skip")
        }
        .accessibilityElement(children: .contain)
    }

    private func choice(_ value: SignupBodyFatChoice, key: String.LocalizationValue) -> some View {
        Button { select(value) } label: {
            Text(OnboardingCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale)))
        }
        .buttonStyle(BodyFlowButtonStyle(role: value == .photos ? .primary : .secondary))
        .accessibilityAddTraits(selection == value ? .isSelected : [])
        .accessibilityIdentifier(identifier(value))
    }

    private func identifier(_ value: SignupBodyFatChoice) -> String {
        switch value {
        case .photos: "onboarding.body-fat.choice.photos"
        case .typed: "onboarding.body-fat.choice.typed"
        case .skip: "onboarding.body-fat.choice.skip"
        }
    }
}
