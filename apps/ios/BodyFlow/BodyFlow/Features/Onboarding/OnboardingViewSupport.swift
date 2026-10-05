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
        return OnboardingCountryPolicy.regions
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

    /// The folded words of a text. Punctuation only separates them, so
    /// "Port-au-Prince" is found by "prince" and "Knox, Indiana" by
    /// "knox indiana".
    static func words(_ text: String) -> [String] {
        folded(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Whether the typed words are found where a word of the text starts:
    /// each one whole, the last as far as it was typed. A match in the
    /// middle of a word is not one: "rio" is inside "horário", and every
    /// zone name in Portuguese starts with that word.
    ///
    /// A run made only of `commonWords` is not a match either, since those
    /// words tell no row apart.
    static func starts(
        _ typed: [String],
        in text: [String],
        ignoring commonWords: Set<String> = []
    ) -> Bool {
        guard let last = typed.last, typed.count <= text.count else { return false }
        return (0...(text.count - typed.count)).contains { start in
            let run = text[start..<(start + typed.count)]
            return run.dropLast().elementsEqual(typed.dropLast())
                && run.last?.hasPrefix(last) == true
                && !run.allSatisfy(commonWords.contains)
        }
    }
}

/// The system's city for a time zone, in one language ("São Paulo",
/// "Lisboa", "Nova York"). The identifier's last part is the same place
/// without accents and in English.
private struct OnboardingTimeZoneCities: Sendable {
    private let locale: Locale
    /// What the system answers for a zone it has no city for ("Cidade
    /// desconhecida"). Read from the system, so no wording is assumed.
    private let noCity: String
    private let cityByIdentifier: [String: String]
    /// A city the system gives to a zone and to its older aliases (Toronto
    /// for Montreal, Nipigon and Thunder Bay) tells none of them apart.
    private let sharedCities: Set<String>

    private init(language: SupportedAppLanguage) {
        let locale = language.formattingLocale
        let formatter = Self.formatter(locale: locale)
        let noCity = TimeZone(identifier: "GMT").flatMap { Self.answer(for: $0, formatter) } ?? ""
        var cityByIdentifier: [String: String] = [:]
        var zonesByCity: [String: Int] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let zone = TimeZone(identifier: identifier),
                  let city = Self.answer(for: zone, formatter), city != noCity else { continue }
            cityByIdentifier[identifier] = city
            zonesByCity[city, default: 0] += 1
        }
        self.locale = locale
        self.noCity = noCity
        self.cityByIdentifier = cityByIdentifier
        sharedCities = Set(zonesByCity.filter { $0.value > 1 }.keys)
    }

    /// The system's city for the zone, and whether it is that zone's alone.
    /// nil when the system has none.
    func city(for zone: TimeZone) -> (name: String, isShared: Bool)? {
        let known = cityByIdentifier[zone.identifier]
            // A valid zone outside the system's list is asked for directly.
            ?? Self.answer(for: zone, Self.formatter(locale: locale))
        guard let known, known != noCity else { return nil }
        return (known, sharedCities.contains(known))
    }

    static func cities(for language: SupportedAppLanguage) -> OnboardingTimeZoneCities {
        byLanguage[language] ?? OnboardingTimeZoneCities(language: language)
    }

    /// Asking the system costs a formatter, so every known zone is asked once.
    private static let byLanguage = Dictionary(
        uniqueKeysWithValues: SupportedAppLanguage.allCases.map {
            ($0, OnboardingTimeZoneCities(language: $0))
        }
    )

    private static func formatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        // "VVV" is the zone's exemplar city.
        formatter.dateFormat = "VVV"
        return formatter
    }

    private static func answer(for zone: TimeZone, _ formatter: DateFormatter) -> String? {
        formatter.timeZone = zone
        // The city does not depend on the date.
        let city = formatter.string(from: Date(timeIntervalSinceReferenceDate: 0))
        return city.isEmpty ? nil : city
    }
}

/// A time zone is shown by its city and by the system's name for the zone in
/// the app's language; the identifier is only the stored value.
struct OnboardingTimeZonePresentation: Equatable, Identifiable, Sendable {
    let identifier: String
    /// "America/Sao_Paulo" reads "São Paulo": the system's city for the zone
    /// in the app's language. Where the system has none, or gives the same
    /// one to several zones, it is the identifier's last part ("Montreal").
    let city: String
    /// The system's name for the zone; nil for an identifier it does not know.
    let zoneName: String?
    /// The words a search reads of the place: the city as shown, the
    /// identifier (so "sao paulo" and "new york" are found in any language)
    /// and the system's city even where it is shared.
    private let placeWords: [[String]]
    /// The words a search reads of the zone's names. The system's short name
    /// is never drawn: in some languages it is the only one that carries the
    /// city as the person writes it.
    private let nameWords: [[String]]

    var id: String { identifier }

    init(identifier: String, language: SupportedAppLanguage) {
        self.identifier = identifier
        let zone = TimeZone(identifier: identifier)
        let systemCity = zone.flatMap { OnboardingTimeZoneCities.cities(for: language).city(for: $0) }
        let identifierCity = identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
        if let systemCity, !systemCity.isShared {
            city = systemCity.name
        } else {
            city = identifierCity
        }
        let locale = language.formattingLocale
        zoneName = zone?.localizedName(for: .generic, locale: locale)
        placeWords = [city, identifier, systemCity?.name]
            .compactMap { $0 }.map(OnboardingSearchText.words)
        nameWords = [zoneName, zone?.localizedName(for: .shortGeneric, locale: locale)]
            .compactMap { $0 }.map(OnboardingSearchText.words)
    }

    /// The review's single line.
    var summary: String {
        zoneName.map { "\(city) · \($0)" } ?? city
    }

    private func matches(_ typed: [String], ignoring commonWords: Set<String>) -> Bool {
        placeWords.contains { OnboardingSearchText.starts(typed, in: $0) }
            || nameWords.contains {
                OnboardingSearchText.starts(typed, in: $0, ignoring: commonWords)
            }
    }

    /// Every zone the system knows, by city. Naming them asks the system once
    /// per zone, so the list is built once per language and kept.
    @MainActor
    static func all(for language: SupportedAppLanguage) -> [OnboardingTimeZonePresentation] {
        catalogue(for: language).zones
    }

    /// A blank search, or one with no letter or digit, lists every zone.
    @MainActor
    static func zones(
        matching query: String,
        language: SupportedAppLanguage
    ) -> [OnboardingTimeZonePresentation] {
        let catalogue = catalogue(for: language)
        let typed = OnboardingSearchText.words(query)
        guard !typed.isEmpty else { return catalogue.zones }
        return catalogue.zones.filter { $0.matches(typed, ignoring: catalogue.commonNameWords) }
    }

    private struct Catalogue {
        let zones: [OnboardingTimeZonePresentation]
        /// Words in the names of more than a fifth of the zones ("Horário",
        /// "Padrão", "de"; "Time", "Standard"). Typing one, or its start,
        /// would list hundreds of zones, so alone they find nothing; a whole
        /// name that contains them still does. Counted from the system's
        /// names, so no vocabulary is assumed for a language.
        let commonNameWords: Set<String>
    }

    @MainActor
    private static func catalogue(for language: SupportedAppLanguage) -> Catalogue {
        if let known = cache[language] { return known }
        let locale = language.formattingLocale
        let zones = TimeZone.knownTimeZoneIdentifiers
            .map { OnboardingTimeZonePresentation(identifier: $0, language: language) }
            .sorted { first, second in
                // In the language's order, so "São Paulo" sits with the "Sa…"
                // cities instead of after every unaccented one.
                switch first.city.compare(second.city, options: .caseInsensitive, range: nil, locale: locale) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: first.identifier < second.identifier
                }
            }
        var zonesByWord: [String: Int] = [:]
        for zone in zones {
            for word in Set(zone.nameWords.joined()) { zonesByWord[word, default: 0] += 1 }
        }
        let catalogue = Catalogue(
            zones: zones,
            commonNameWords: Set(zonesByWord.filter { $0.value * 5 > zones.count }.keys)
        )
        cache[language] = catalogue
        return catalogue
    }

    @MainActor private static var cache: [SupportedAppLanguage: Catalogue] = [:]
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
