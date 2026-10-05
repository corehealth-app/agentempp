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

    /// A meal type as the server sends it ("cafe", "almoco"...) in the
    /// reader's language; an unknown code is shown as sent.
    static func mealTypeTitle(
        code: String,
        language: SupportedAppLanguage
    ) -> String {
        guard let mealType = MealType(rawValue: code) else { return code }
        return mealTypeTitle(mealType, language: language)
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

    /// A stored workout intensity ("leve", "moderada", "alta") in the
    /// reader's language; any other value is tidied, never translated.
    static func workoutIntensityTitle(
        stored: String,
        language: SupportedAppLanguage
    ) -> String {
        switch storedValueKey(stored) {
        case WorkoutIntensity.light.rawValue:
            workoutIntensityTitle(.light, language: language)
        case WorkoutIntensity.moderate.rawValue:
            workoutIntensityTitle(.moderate, language: language)
        case WorkoutIntensity.high.rawValue:
            workoutIntensityTitle(.high, language: language)
        case "intensa":
            string("registration.workout-intensity.intensa", language: language)
        default:
            tidiedStoredValue(stored)
        }
    }

    /// A stored workout type in the reader's language. The server keeps the
    /// type as a code ("musculacao") or as the person typed it; a known code
    /// gets its name, anything else is tidied and otherwise left as typed.
    static func workoutTypeTitle(
        stored: String,
        language: SupportedAppLanguage
    ) -> String {
        guard let key = workoutTypeKeys[storedValueKey(stored)] else {
            return tidiedStoredValue(stored)
        }
        return string(key, language: language)
    }

    private static let workoutTypeKeys: [String: String.LocalizationValue] = [
        "musculacao": "registration.workout-type.musculacao",
        "corrida": "registration.workout-type.corrida",
        "caminhada": "registration.workout-type.caminhada",
        "natacao": "registration.workout-type.natacao",
        "ciclismo": "registration.workout-type.ciclismo",
    ]

    /// How a stored value is looked up: the way the server compares it
    /// (lower case), and with "Natação" and "natacao" being the same word.
    private static func storedValueKey(_ stored: String) -> String {
        stored
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { $0 == "_" || $0.isWhitespace }
            .joined(separator: "_")
    }

    /// "corrida_leve" reads "Corrida leve": "_" becomes a space and the first
    /// letter is upper case; nothing else of what was typed changes.
    private static func tidiedStoredValue(_ stored: String) -> String {
        let spaced = stored
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
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

            if presentsLocalDemonstration {
                BodyFlowStatusLine(copy("registration.capture.demo-notice"), kind: .info)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                        sampleButtons
                    }
                    VStack(spacing: BodyFlowSpacing.sm) {
                        sampleButtons
                    }
                }
            } else {
                BodyFlowStatusLine(
                    copy("registration.capture.media-unavailable"),
                    kind: .unavailable
                )
                .accessibilityIdentifier("registration.meal.source.media-unavailable")
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
