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
    /// The local demonstration offers its photo/audio samples; a real
    /// account says plainly that those captures are not available yet.
    var presentsLocalDemonstration: Bool = true
    let select: @MainActor (MealCaptureChoice) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("registration.capture.title"))
                .font(BodyFlowTypography.cardTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)

            // Text is the real capture path and leads; the two local samples
            // follow, under the notice that says what they are.
            sourceButton(
                copy("registration.capture.text"),
                symbol: .compose,
                role: .primary,
                identifier: "registration.meal.source.text"
            ) { select(.text) }

            BodyFlowStatusLine(copy("registration.capture.demo-notice"), kind: .info)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                    sampleButtons
                }
                VStack(spacing: BodyFlowSpacing.sm) {
                    sampleButtons
                }
            }
        }
    }

    @ViewBuilder
    private var sampleButtons: some View {
        sourceButton(
            copy("registration.capture.photo-sample"),
            symbol: .photo,
            role: .secondary,
            identifier: "registration.meal.source.photo"
        ) { select(.photo) }
        sourceButton(
            copy("registration.capture.audio-sample"),
            symbol: .audio,
            role: .secondary,
            identifier: "registration.meal.source.audio"
        ) { select(.audio) }
    }

    private func sourceButton(
        _ title: String,
        symbol: BodyFlowSymbol,
        role: BodyFlowButtonRole,
        identifier: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Label(verbatim: title, symbol: symbol)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
        }
        .buttonStyle(BodyFlowButtonStyle(role: role))
        .accessibilityIdentifier(identifier)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }
}
