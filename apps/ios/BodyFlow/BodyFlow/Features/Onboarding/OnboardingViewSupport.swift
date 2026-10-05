import Foundation
import SwiftUI

enum OnboardingCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }

    static func format(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, language: language),
            locale: language.formattingLocale,
            arguments: arguments
        )
    }
}

/// A legal document is named for the person by its kind, never by the
/// server's key. The kind is read from the key by substring, so today's keys
/// and the ones published later resolve alike; a key of no known kind reads
/// as a plain document.
enum OnboardingLegalDocumentKind: CaseIterable, Equatable, Sendable {
    case terms
    case privacy
    case healthAI
    case sensitiveData
    case medication
    case other

    init(documentKey: String) {
        let key = documentKey.lowercased()
        if key.contains("terms") {
            self = .terms
        } else if key.contains("privacy") {
            self = .privacy
        } else if key.contains("health_ai") || key.contains("_ai_") {
            self = .healthAI
        } else if key.contains("sensitive") {
            self = .sensitiveData
        } else if key.contains("medication") {
            self = .medication
        } else {
            self = .other
        }
    }

    func title(for language: SupportedAppLanguage) -> String {
        switch self {
        case .terms:
            OnboardingCopy.string("onboarding.legal.title.terms", language: language)
        case .privacy:
            OnboardingCopy.string("onboarding.legal.title.privacy", language: language)
        case .healthAI:
            OnboardingCopy.string("onboarding.legal.title.health-ai", language: language)
        case .sensitiveData:
            OnboardingCopy.string("onboarding.legal.title.sensitive-data", language: language)
        case .medication:
            OnboardingCopy.string("onboarding.legal.title.medication", language: language)
        case .other:
            OnboardingCopy.string("onboarding.legal.title.document", language: language)
        }
    }

    /// The title the consent step and the review show for a document key.
    static func title(
        forDocumentKey documentKey: String,
        language: SupportedAppLanguage
    ) -> String {
        OnboardingLegalDocumentKind(documentKey: documentKey).title(for: language)
    }
}

/// What the consent card shows for one legal document. The server's purpose
/// code is a storage value and is not part of it.
struct OnboardingLegalDocumentPresentation: Equatable, Sendable {
    let title: String
    let body: String

    init(document: OnboardingLegalDocument, language: SupportedAppLanguage) {
        title = OnboardingLegalDocumentKind.title(
            forDocumentKey: document.documentKey,
            language: language
        )
        body = document.body ?? ""
    }

    /// Every text of the card that comes from the document itself.
    var visibleText: [String] { [title, body] }
}

/// The country is shown by its name in the app's language; the ISO code is
/// only the stored value.
enum OnboardingCountryPresentation {
    static func name(for code: String, language: SupportedAppLanguage) -> String {
        language.formattingLocale.localizedString(forRegionCode: code) ?? code
    }

    /// The picker's rows for a search. The code is never drawn, but typing it
    /// still finds its country.
    static func regions(
        matching query: String,
        language: SupportedAppLanguage
    ) -> [Locale.Region] {
        let needle = OnboardingSearchText.folded(query)
        return Locale.Region.isoRegions
            .filter { region in
                needle.isEmpty
                    || OnboardingSearchText.folded(region.identifier).contains(needle)
                    || OnboardingSearchText.folded(name(for: region.identifier, language: language))
                        .contains(needle)
            }
            .sorted {
                name(for: $0.identifier, language: language)
                    < name(for: $1.identifier, language: language)
            }
    }
}

/// A search is read the way a person types it: case and accents do not
/// matter, and a space, "_" and "/" are one and the same separator.
enum OnboardingSearchText {
    static func folded(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { $0 == "_" || $0 == "/" || $0.isWhitespace }
            .joined(separator: " ")
    }
}

/// A time zone is shown by its city and by the system's name for the zone in
/// the app's language; the identifier is only the stored value.
struct OnboardingTimeZonePresentation: Equatable, Identifiable, Sendable {
    let identifier: String
    /// "America/Sao_Paulo" reads "Sao Paulo".
    let city: String
    /// The system's name for the zone; nil for an identifier it does not know.
    let zoneName: String?
    /// Everything a search reads, already folded. The system's short name is
    /// never drawn: in some languages it is the only one that carries the
    /// city as the person writes it.
    private let searchText: [String]

    var id: String { identifier }

    init(identifier: String, language: SupportedAppLanguage) {
        self.identifier = identifier
        city = identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
        let zone = TimeZone(identifier: identifier)
        let locale = language.formattingLocale
        zoneName = zone?.localizedName(for: .generic, locale: locale)
        searchText = [
            city,
            identifier,
            zoneName,
            zone?.localizedName(for: .shortGeneric, locale: locale),
        ].compactMap { $0 }.map(OnboardingSearchText.folded)
    }

    /// The review's single line.
    var summary: String {
        zoneName.map { "\(city) · \($0)" } ?? city
    }

    func matches(_ query: String) -> Bool {
        let needle = OnboardingSearchText.folded(query)
        return needle.isEmpty || searchText.contains { $0.contains(needle) }
    }

    /// Every zone the system knows, by city. Naming them asks the system once
    /// per zone, so the list is built once per language and kept.
    @MainActor
    static func all(for language: SupportedAppLanguage) -> [OnboardingTimeZonePresentation] {
        if let known = cache[language] { return known }
        let named: [OnboardingTimeZonePresentation] = TimeZone.knownTimeZoneIdentifiers.map {
            OnboardingTimeZonePresentation(identifier: $0, language: language)
        }
        let zones = named.sorted { first, second in
            (first.city, first.identifier) < (second.city, second.identifier)
        }
        cache[language] = zones
        return zones
    }

    @MainActor
    static func zones(
        matching query: String,
        language: SupportedAppLanguage
    ) -> [OnboardingTimeZonePresentation] {
        all(for: language).filter { $0.matches(query) }
    }

    @MainActor private static var cache: [SupportedAppLanguage: [OnboardingTimeZonePresentation]] = [:]
}

@MainActor
struct OnboardingStepHeader: View {
    let titleKey: String.LocalizationValue
    let titleFallback: String
    let messageKey: String.LocalizationValue
    let messageFallback: String
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(PremiumPresentationCopy.string(
                titleKey,
                locale: locale,
                fallback: titleFallback
            ))
                .font(BodyFlowTypography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(BodyFlowColor.primaryText)
            Text(PremiumPresentationCopy.string(
                messageKey,
                locale: locale,
                fallback: messageFallback
            ))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.step-header")
    }
}

@MainActor
struct OnboardingFieldIssue: View {
    let model: OnboardingFlowModel
    let candidates: [OnboardingValidationIssue]
    @Environment(\.locale) private var locale

    var body: some View {
        if let issue = candidates.first(where: model.validationIssues.contains) {
            BodyFlowStatusLine(
                issue.message(for: BodyFlowPresentationLanguage.resolve(locale)),
                kind: .error,
                font: BodyFlowTypography.callout
            )
        }
    }
}

extension OnboardingFlowModel {
    func accessibilityHint(
        for candidates: [OnboardingValidationIssue]
    ) -> String {
        let language = BodyFlowPresentationLanguage.resolve(.current)
        return FormAccessibilityText.hint(
            for: candidates.first(where: validationIssues.contains)?.message(
                for: language
            ),
            language: language
        )
    }
}

extension BiologicalSex {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .masculine:
            OnboardingCopy.string("onboarding.biological-sex.masculine", language: language)
        case .feminine:
            OnboardingCopy.string("onboarding.biological-sex.feminine", language: language)
        }
    }
}

extension BodyFlowObjective {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .bodyRecomposition:
            OnboardingCopy.string("onboarding.objective.body-recomposition.title", language: language)
        case .muscleGain:
            OnboardingCopy.string("onboarding.objective.muscle-gain.title", language: language)
        case .maintenance:
            OnboardingCopy.string("onboarding.objective.maintenance.title", language: language)
        }
    }

    func onboardingDescription(for language: SupportedAppLanguage) -> String {
        switch self {
        case .bodyRecomposition:
            OnboardingCopy.string("onboarding.objective.body-recomposition.detail", language: language)
        case .muscleGain:
            OnboardingCopy.string("onboarding.objective.muscle-gain.detail", language: language)
        case .maintenance:
            OnboardingCopy.string("onboarding.objective.maintenance.detail", language: language)
        }
    }
}

extension ActivityLevel {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .sedentary:
            OnboardingCopy.string("onboarding.routine.activity-level.sedentary", language: language)
        case .light:
            OnboardingCopy.string("onboarding.routine.activity-level.light", language: language)
        case .moderate:
            OnboardingCopy.string("onboarding.routine.activity-level.moderate", language: language)
        case .high:
            OnboardingCopy.string("onboarding.routine.activity-level.high", language: language)
        case .athlete:
            OnboardingCopy.string("onboarding.routine.activity-level.athlete", language: language)
        }
    }
}

extension WaterIntake {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .low:
            OnboardingCopy.string("onboarding.routine.water-intake.low", language: language)
        case .moderate:
            OnboardingCopy.string("onboarding.routine.water-intake.moderate", language: language)
        case .high:
            OnboardingCopy.string("onboarding.routine.water-intake.high", language: language)
        }
    }
}

extension HungerLevel {
    func onboardingLabel(for language: SupportedAppLanguage) -> String {
        switch self {
        case .low:
            OnboardingCopy.string("onboarding.routine.hunger-level.low", language: language)
        case .moderate:
            OnboardingCopy.string("onboarding.routine.hunger-level.moderate", language: language)
        case .high:
            OnboardingCopy.string("onboarding.routine.hunger-level.high", language: language)
        }
    }
}

#if DEBUG
private actor PreviewOnboardingRepository: OnboardingRepository {
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

private actor PreviewCoachPersonaRepository: CoachPersonaRepository {
    private var selected: CoachPersona?

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        selected
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        selected = persona
    }
}

extension OnboardingFlowModel {
    static func preview(
        step: OnboardingStep,
        operationState: OnboardingOperationState = .idle,
        validationIssues: [OnboardingValidationIssue] = []
    ) -> OnboardingFlowModel {
        OnboardingFlowModel(
            userID: "preview-user",
            initialDraft: OnboardingDraft(
                displayName: "Pessoa de exemplo",
                localeIdentifier: "pt-BR",
                countryCode: "BR",
                timeZoneIdentifier: "America/Sao_Paulo",
                biologicalSex: .feminine,
                birthDate: Date(timeIntervalSince1970: 946_684_800),
                heightCM: 170,
                weightKG: 65,
                bodyFatPercent: 25,
                objective: .bodyRecomposition,
                activityLevel: .moderate,
                trainingFrequency: 3,
                waterIntake: .moderate,
                hungerLevel: .moderate,
                wakeTime: LocalTime(hour: 7, minute: 0),
                bedtime: LocalTime(hour: 23, minute: 0),
                foodOrganization: .yes,
                persona: .focus,
                consent: DevelopmentConsentAcceptance(
                    documentIDs: [.terms, .privacy],
                    acceptedAt: Date(timeIntervalSince1970: 946_684_800)
                ),
                currentStep: step
            ),
            repository: PreviewOnboardingRepository(),
            personaRepository: PreviewCoachPersonaRepository(),
            developmentConsentAvailability: .syntheticDevelopment,
            onStepChanged: { _ in },
            onCompleted: {},
            initialOperationState: operationState,
            initialValidationIssues: validationIssues
        )
    }
}
#endif
