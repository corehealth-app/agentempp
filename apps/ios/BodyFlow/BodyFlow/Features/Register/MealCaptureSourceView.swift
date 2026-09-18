import SwiftUI

enum RegistrationCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }

    static func mealTypeTitle(
        _ mealType: MealType,
        language: SupportedAppLanguage
    ) -> String {
        switch mealType {
        case .breakfast: string("registration.meal-type.cafe", language: language)
        case .lunch: string("registration.meal-type.almoco", language: language)
        case .snack: string("registration.meal-type.lanche", language: language)
        case .dinner: string("registration.meal-type.jantar", language: language)
        case .supper: string("registration.meal-type.ceia", language: language)
        case .other: string("registration.meal-type.outro", language: language)
        }
    }

    static func workoutIntensityTitle(
        _ intensity: WorkoutIntensity,
        language: SupportedAppLanguage
    ) -> String {
        switch intensity {
        case .light:
            string("registration.workout-intensity.leve", language: language)
        case .moderate:
            string("registration.workout-intensity.moderada", language: language)
        case .high:
            string("registration.workout-intensity.alta", language: language)
        }
    }
}

enum MealCaptureChoice: Equatable {
    case text
    case photo
    case audio
}

struct MealCaptureSourceView: View {
    let select: @MainActor (MealCaptureChoice) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("registration.capture.title"))
                .font(BodyFlowTypography.headline)
                .foregroundStyle(BodyFlowColor.primaryText)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                    sourceButtons
                }
                VStack(spacing: BodyFlowSpacing.sm) {
                    sourceButtons
                }
            }

            Label(copy("registration.capture.demo-notice"), systemImage: "info.circle")
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sourceButtons: some View {
        sourceButton(
            copy("registration.capture.photo-sample"),
            systemImage: "photo",
            identifier: "registration.meal.source.photo"
        ) { select(.photo) }
        sourceButton(
            copy("registration.capture.audio-sample"),
            systemImage: "waveform",
            identifier: "registration.meal.source.audio"
        ) { select(.audio) }
        sourceButton(
            copy("registration.capture.text"),
            systemImage: "text.alignleft",
            identifier: "registration.meal.source.text"
        ) { select(.text) }
    }

    private func sourceButton(
        _ title: String,
        systemImage: String,
        identifier: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
        }
        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
        .accessibilityIdentifier(identifier)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }
}
