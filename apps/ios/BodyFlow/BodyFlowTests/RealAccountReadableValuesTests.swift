import Foundation
import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

/// What is stored as a code (a country, a time zone, a workout type, an
/// intensity, a calorie origin) reaches the person as a name. Each rule is
/// read from the drawn screen, on the values the reviews reported.
@Suite("Stored values are shown as names")
@MainActor
struct RealAccountReadableValuesTests {
    private static let pt = SupportedAppLanguage.portugueseBrazil
    private static let en = SupportedAppLanguage.englishUnitedStates
    private typealias Support = RealAccountSampleDataTests

    // MARK: Onboarding · country

    // Review 2026-10-04: the first step showed "Brasil    BR" and every row
    // of the picker ended in its ISO code.
    @Test("the welcome step names the country and the time zone, in both languages")
    func welcomeStepShowsNamesOnly() throws {
        let model = Support.onboardingModel(
            step: .welcome, documents: [],
            countryCode: "BR", timeZoneIdentifier: "America/Sao_Paulo"
        )
        for language in SupportedAppLanguage.allCases {
            let labels = Support.accessibilityTree(
                NavigationStack { WelcomeStepView(model: model) }
                    .environment(\.locale, language.formattingLocale),
                height: 2_400
            ).labels
            let seen: Comment = "\(labels)"
            #expect(labels.contains(language == Self.pt ? "Brasil" : "Brazil"), seen)
            #expect(!labels.contains { Self.parts(of: $0).contains("BR") }, seen)

            let zone = try #require(Self.systemZoneName("America/Sao_Paulo", language))
            #expect(labels.contains { $0.contains("Sao Paulo") && $0.contains(zone) }, seen)
            #expect(!labels.contains { $0.contains("America/") || $0.contains("Sao_Paulo") }, seen)
        }
    }

    @Test("the country picker lists names without any ISO code")
    func countryPickerShowsNoCode() {
        let codes = Set(Locale.Region.isoRegions.map(\.identifier))
        #expect(codes.contains("BR"))

        for query in ["", "alemanha", "DE"] {
            let labels = Support.accessibilityTree(
                NavigationStack {
                    CountrySelectionView(
                        selectedCode: "BR", language: Self.pt, initialQuery: query
                    ) { _ in }
                }
                .environment(\.locale, Self.pt.formattingLocale),
                height: 2_400
            ).labels
            let seen: Comment = "query “\(query)”: \(labels)"
            #expect(labels.contains { $0.hasPrefix(query.isEmpty ? "Afeganistão" : "Alemanha") }, seen)
            #expect(!labels.contains { !codes.isDisjoint(with: Self.parts(of: $0)) }, seen)
        }
    }

    @Test("a country is still found by its code, and by its name without accents")
    func countrySearch() {
        func found(_ query: String, _ language: SupportedAppLanguage) -> [String] {
            OnboardingCountryPresentation.regions(matching: query, language: language).map(\.identifier)
        }
        // "Alemanha" has no "de" in it: only the code can have matched.
        #expect(found("de", Self.pt).contains("DE"))
        #expect(found("BR", Self.pt).contains("BR"))
        #expect(found("mexico", Self.pt).contains("MX"))
        #expect(found("MÉXICO", Self.pt).contains("MX"))
        #expect(found("estados unidos", Self.pt).first == "US")
        #expect(found("", Self.pt).count == Locale.Region.isoRegions.count)
        #expect(found("xyzzy", Self.pt).isEmpty)
    }

    @Test("a country search with no result says so")
    func countryPickerEmptyMessage() {
        for language in SupportedAppLanguage.allCases {
            let tree = Support.accessibilityTree(
                NavigationStack {
                    CountrySelectionView(
                        selectedCode: "BR", language: language, initialQuery: "xyzzy"
                    ) { _ in }
                }
                .environment(\.locale, language.formattingLocale),
                height: 800
            )
            #expect(
                tree.labels.contains(language == Self.pt ? "Nenhum país encontrado" : "No country found"),
                "\(tree.labels)"
            )
            #expect(tree.identifiers.contains("onboarding.country-picker.empty"))
        }
    }

    // MARK: Onboarding · time zone

    @Test("a zone is its city plus the system's name for it; the identifier is only stored")
    func timeZonePresentation() throws {
        for language in SupportedAppLanguage.allCases {
            let zone = OnboardingTimeZonePresentation(identifier: "America/Sao_Paulo", language: language)
            let name = try #require(Self.systemZoneName("America/Sao_Paulo", language))
            #expect(zone.identifier == "America/Sao_Paulo")
            #expect(zone.city == "Sao Paulo")
            #expect(zone.zoneName == name)
            #expect(OnboardingSearchText.folded(name).contains("brasilia"))
            #expect(zone.summary == "Sao Paulo · \(name)")
            #expect(!zone.summary.contains("/") && !zone.summary.contains("_"))
        }
        let nested = OnboardingTimeZonePresentation(
            identifier: "America/Argentina/Buenos_Aires", language: Self.pt
        )
        #expect(nested.city == "Buenos Aires")

        // A value the system does not know is shown without a made-up name.
        let unknown = OnboardingTimeZonePresentation(identifier: "Mars/Olympus_Mons", language: Self.pt)
        #expect(unknown.city == "Olympus Mons")
        #expect(unknown.zoneName == nil)
        #expect(unknown.summary == "Olympus Mons")
    }

    // Review 2026-10-04: "São Paulo", "Sao Paulo" and "Belém" found nothing.
    @Test("the search reads a city the way a person types it", arguments: [
        TimeZoneSearchCase("são paulo", "America/Sao_Paulo"),
        TimeZoneSearchCase("sao paulo", "America/Sao_Paulo"),
        TimeZoneSearchCase("São Paulo", "America/Sao_Paulo"),
        TimeZoneSearchCase("SAO_PAULO", "America/Sao_Paulo"),
        TimeZoneSearchCase("America/Sao_Paulo", "America/Sao_Paulo"),
        TimeZoneSearchCase("america sao paulo", "America/Sao_Paulo"),
        TimeZoneSearchCase("Belém", "America/Belem"),
        TimeZoneSearchCase("belem", "America/Belem"),
        TimeZoneSearchCase("  Cuiabá ", "America/Cuiaba"),
        TimeZoneSearchCase("Porto Velho", "America/Porto_Velho"),
        TimeZoneSearchCase("buenos aires", "America/Argentina/Buenos_Aires"),
        TimeZoneSearchCase("new york", "America/New_York"),
    ])
    func timeZoneSearch(_ search: TimeZoneSearchCase) {
        for language in SupportedAppLanguage.allCases {
            let found = OnboardingTimeZonePresentation.zones(matching: search.query, language: language)
            #expect(found.map(\.identifier).contains(search.identifier), "\(found.map(\.identifier))")
            #expect(found.count < 40, "the search narrowed nothing: \(found.count) zones")
        }
    }

    @Test("the search also reads the system's name for the zone")
    func timeZoneSearchReadsTheZoneName() throws {
        for language in SupportedAppLanguage.allCases {
            let name = try #require(Self.systemZoneName("America/Sao_Paulo", language))
            let found = OnboardingTimeZonePresentation.zones(matching: name.uppercased(), language: language)
            #expect(found.map(\.identifier).contains("America/Sao_Paulo"))
        }
    }

    @Test("an empty search lists every zone; an unknown word lists none")
    func timeZoneSearchBounds() {
        for language in SupportedAppLanguage.allCases {
            let all = OnboardingTimeZonePresentation.all(for: language)
            #expect(all.count == TimeZone.knownTimeZoneIdentifiers.count)
            #expect(all.allSatisfy { !$0.city.isEmpty && !$0.city.contains("_") && !$0.city.contains("/") })
            #expect(all.allSatisfy { $0.zoneName?.isEmpty == false })
            #expect(OnboardingTimeZonePresentation.zones(matching: "", language: language) == all)
            #expect(OnboardingTimeZonePresentation.zones(matching: "   ", language: language) == all)
            #expect(OnboardingTimeZonePresentation.zones(matching: "xyzzy", language: language).isEmpty)
        }
    }

    @Test("the time zone picker lists cities and zone names, never identifiers")
    func timeZonePickerShowsNoIdentifier() throws {
        for language in SupportedAppLanguage.allCases {
            for query in ["", "são paulo"] {
                let labels = Support.accessibilityTree(
                    NavigationStack {
                        TimeZoneSelectionView(
                            selectedIdentifier: "America/Sao_Paulo",
                            language: language,
                            initialQuery: query
                        ) { _ in }
                    }
                    .environment(\.locale, language.formattingLocale),
                    height: 2_400
                ).labels
                let seen: Comment = "query “\(query)”: \(labels)"
                #expect(labels.contains { $0.hasPrefix(query.isEmpty ? "Abidjan" : "Sao Paulo") }, seen)
                #expect(!labels.contains { $0.contains("/") || $0.contains("_") }, seen)
            }
        }
    }

    @Test("a time zone search with no result says so")
    func timeZonePickerEmptyMessage() {
        for language in SupportedAppLanguage.allCases {
            let tree = Support.accessibilityTree(
                NavigationStack {
                    TimeZoneSelectionView(
                        selectedIdentifier: "America/Sao_Paulo",
                        language: language,
                        initialQuery: "xyzzy"
                    ) { _ in }
                }
                .environment(\.locale, language.formattingLocale),
                height: 800
            )
            #expect(
                tree.labels.contains(language == Self.pt ? "Nenhum fuso encontrado" : "No time zone found"),
                "\(tree.labels)"
            )
            #expect(tree.identifiers.contains("onboarding.timezone-picker.empty"))
        }
    }

    // Review 2026-10-04: the review showed "Fuso: America/Sao_Paulo".
    @Test("the rendered review names the time zone and shows no identifier")
    func reviewShowsNoTimeZoneIdentifier() throws {
        let model = Support.onboardingModel(
            step: .completion, documents: [],
            countryCode: "BR", timeZoneIdentifier: "America/Sao_Paulo"
        )
        for language in SupportedAppLanguage.allCases {
            let labels = Support.accessibilityTree(
                OnboardingCompletionView(model: model, onComplete: {})
                    .environment(\.locale, language.formattingLocale),
                height: 2_400
            ).labels
            let seen: Comment = "\(labels)"
            let zone = try #require(Self.systemZoneName("America/Sao_Paulo", language))
            #expect(labels.contains(language == Self.pt ? "Fuso" : "Time zone"), seen)
            #expect(labels.contains("Sao Paulo · \(zone)"), seen)
            #expect(labels.contains(language == Self.pt ? "Brasil" : "Brazil"), seen)
            #expect(!labels.contains { $0.contains("America/") || $0.contains("Sao_Paulo") }, seen)
            #expect(!labels.contains { Self.parts(of: $0).contains("BR") }, seen)
        }
    }

    @Test("the picker texts exist in both languages", arguments: [
        SampleDataBilingualCase("onboarding.welcome.country-picker.search", "Buscar país", "Search country"),
        SampleDataBilingualCase("onboarding.welcome.country-picker.empty", "Nenhum país encontrado", "No country found"),
        SampleDataBilingualCase("onboarding.welcome.time-zone-picker.search", "Buscar cidade ou região", "Search city or region"),
        SampleDataBilingualCase("onboarding.welcome.time-zone-picker.empty", "Nenhum fuso encontrado", "No time zone found"),
    ])
    func pickerCopy(_ wording: SampleDataBilingualCase) throws {
        try Self.expectCopy(wording)
    }

    // MARK: Register · meal proposal note

    // Review 2026-10-04: after typing 350 kcal for an item, the proposal came
    // back with "Valores calculados pelo Performe AI" under it.
    @Test("every item calculated: the proposal says the values were calculated")
    func proposalNoteWhenEveryItemIsCalculated() throws {
        let proposal = try Self.mealProposal(items: [try Self.calculatedItem, try Self.calculatedItem])
        #expect(proposal.kcalProvenance == .calculated)
        let portuguese = Self.proposalLabels(proposal, Self.pt)
        #expect(portuguese.contains("Valores calculados pelo Performe AI"), "\(portuguese)")
        #expect(!portuguese.contains("Inclui calorias informadas por você"))
        let english = Self.proposalLabels(proposal, Self.en)
        #expect(english.contains("Values calculated by Performe AI"), "\(english)")
        #expect(!english.contains("Includes calories you provided"))
    }

    @Test("one item typed by the person: the proposal says so and does not claim a calculation")
    func proposalNoteWhenAnItemWasTyped() throws {
        let proposal = try Self.mealProposal(items: [try Self.calculatedItem, try Self.typedItem])
        #expect(proposal.kcalProvenance == .includesPatientReported)
        let portuguese = Self.proposalLabels(proposal, Self.pt)
        #expect(portuguese.contains("350 kcal"), "\(portuguese)")
        #expect(portuguese.contains("Inclui calorias informadas por você"), "\(portuguese)")
        #expect(!portuguese.contains("Valores calculados pelo Performe AI"))
        let english = Self.proposalLabels(proposal, Self.en)
        #expect(english.contains("Includes calories you provided"), "\(english)")
        #expect(!english.contains("Values calculated by Performe AI"))
    }

    @Test("an unknown origin: the proposal says neither")
    func proposalNoteWhenTheOriginIsUnknown() throws {
        let proposal = try Self.mealProposal(items: [try Self.calculatedItem, try Self.itemOfUnknownOrigin])
        #expect(proposal.kcalProvenance == .unstated)
        for language in SupportedAppLanguage.allCases {
            let labels = Self.proposalLabels(proposal, language)
            // The proposal itself is drawn; only the note is absent.
            #expect(labels.contains("Arroz branco cozido"), "\(labels)")
            #expect(!labels.contains { $0.contains("Performe AI") }, "\(labels)")
            #expect(!labels.contains { $0.contains("informadas por você") || $0.contains("you provided") })
        }
    }

    @Test("the note is decided by the whole proposal")
    func proposalNoteRule() throws {
        let calculated = try Self.calculatedItem
        let typed = try Self.typedItem
        let unknown = try Self.itemOfUnknownOrigin
        let unresolved = try Self.unresolvedItem
        func provenance(_ items: [MealProposalItemSnapshot]) -> MealProposalKcalProvenance {
            MealProposalKcalProvenance(items: items)
        }
        #expect(provenance([calculated]) == .calculated)
        #expect(provenance([typed]) == .includesPatientReported)
        // A typed value is said even next to an item of unknown origin.
        #expect(provenance([typed, unknown]) == .includesPatientReported)
        #expect(provenance([unknown]) == .unstated)
        // An item still waiting for its calculation is not "calculated".
        #expect(provenance([calculated, unresolved]) == .unstated)
        #expect(provenance([]) == .unstated)

        let workout = MealProposalPresentation(registration: DemoBodyFlowFixtures.pendingWorkoutRegistration.data)
        #expect(workout.kcalProvenance == .unstated)
    }

    @Test("the two notes exist in both languages", arguments: [
        SampleDataBilingualCase("registration.proposal.service-values",
         "Valores calculados pelo Performe AI", "Values calculated by Performe AI"),
        SampleDataBilingualCase("registration.proposal.includes-user-kcal",
         "Inclui calorias informadas por você", "Includes calories you provided"),
    ])
    func proposalNoteCopy(_ wording: SampleDataBilingualCase) throws {
        try Self.expectCopy(wording)
    }

    // MARK: Workout · stored type and intensity

    @Test("a known workout type has its name in both languages", arguments: [
        SampleDataBilingualCase("musculacao", "Musculação", "Strength training"),
        SampleDataBilingualCase("corrida", "Corrida", "Running"),
        SampleDataBilingualCase("caminhada", "Caminhada", "Walking"),
        SampleDataBilingualCase("natacao", "Natação", "Swimming"),
        SampleDataBilingualCase("ciclismo", "Ciclismo", "Cycling"),
        // The same word as a person writes it.
        SampleDataBilingualCase("Musculação", "Musculação", "Strength training"),
        SampleDataBilingualCase("NATACAO", "Natação", "Swimming"),
        SampleDataBilingualCase(" Corrida ", "Corrida", "Running"),
    ])
    func knownWorkoutType(_ wording: SampleDataBilingualCase) {
        #expect(RegistrationCopy.workoutTypeTitle(stored: wording.subject, language: Self.pt) == wording.portuguese)
        #expect(RegistrationCopy.workoutTypeTitle(stored: wording.subject, language: Self.en) == wording.english)
    }

    @Test("any other workout type is tidied and otherwise left as typed", arguments: [
        ["corrida_leve", "Corrida leve"],
        ["muay_thai", "Muay thai"],
        ["corrida intervalada", "Corrida intervalada"],
        ["caminhada inclinada", "Caminhada inclinada"],
        ["HIIT", "HIIT"],
        ["Beach Tennis", "Beach Tennis"],
        ["élan", "Élan"],
        ["Treino de corrida intervalada em terreno inclinado com recuperação ativa entre séries",
         "Treino de corrida intervalada em terreno inclinado com recuperação ativa entre séries"],
        ["", ""],
    ])
    func otherWorkoutType(_ pair: [String]) {
        for language in SupportedAppLanguage.allCases {
            #expect(RegistrationCopy.workoutTypeTitle(stored: pair[0], language: language) == pair[1])
        }
    }

    @Test("a stored intensity has its name in both languages", arguments: [
        SampleDataBilingualCase("leve", "Leve", "Light"),
        SampleDataBilingualCase("moderada", "Moderada", "Moderate"),
        // What the server stores for the form's third option, named as the form names it.
        SampleDataBilingualCase("alta", "Alta", "High"),
        SampleDataBilingualCase("intensa", "Intensa", "Intense"),
        SampleDataBilingualCase("Moderada", "Moderada", "Moderate"),
        SampleDataBilingualCase("muito_alta", "Muito alta", "Muito alta"),
    ])
    func storedIntensity(_ wording: SampleDataBilingualCase) {
        #expect(RegistrationCopy.workoutIntensityTitle(stored: wording.subject, language: Self.pt) == wording.portuguese)
        #expect(RegistrationCopy.workoutIntensityTitle(stored: wording.subject, language: Self.en) == wording.english)
    }

    @Test("every intensity the form sends is one the labels know")
    func formIntensitiesAreLabelled() {
        for intensity in WorkoutIntensity.allCases {
            for language in SupportedAppLanguage.allCases {
                #expect(
                    RegistrationCopy.workoutIntensityTitle(stored: intensity.rawValue, language: language)
                        == RegistrationCopy.workoutIntensityTitle(intensity, language: language)
                )
            }
        }
    }

    @Test("Today draws the fixture's workouts by name")
    func todayWorkoutsAreNamed() {
        let snapshot = DemoBodyFlowFixtures.loadedToday.data
        #expect(snapshot.workouts.map(\.workoutType) == ["musculacao", "caminhada"])
        #expect(snapshot.workouts.map(\.intensity) == ["moderada", "leve"])

        let portuguese = Self.todayWorkoutLabels(snapshot, Self.pt)
        #expect(portuguese.contains { $0.contains("Musculação") && $0.contains("40 min · Moderada") }, "\(portuguese)")
        #expect(portuguese.contains { $0.contains("Caminhada") && $0.contains("25 min · Leve") }, "\(portuguese)")
        #expect(!portuguese.contains { Self.showsStoredCode($0) }, "\(portuguese)")

        let english = Self.todayWorkoutLabels(snapshot, Self.en)
        #expect(english.contains { $0.contains("Strength training") && $0.contains("40 min · Moderate") }, "\(english)")
        #expect(english.contains { $0.contains("Walking") && $0.contains("25 min · Light") }, "\(english)")
        #expect(!english.contains { Self.showsStoredCode($0) }, "\(english)")

        let edited = DemoBodyFlowFixtures.postEditedWorkoutConfirmationToday.data
        #expect(edited.workouts.contains { $0.workoutType == "ciclismo" && $0.intensity == "alta" })
        let editedLabels = Self.todayWorkoutLabels(edited, Self.en)
        #expect(editedLabels.contains { $0.contains("Cycling") && $0.contains("61 min · High") }, "\(editedLabels)")
    }

    // The test host exposes no accessibility elements under a SwiftUI
    // `ScrollView` (the hosting scroll view answers none), so History's list
    // and detail cannot be read from the drawn screen here. The label both
    // draw is checked on the fixtures' values; the drawn screens are read by
    // `Prompt13RegistrationUITests.testConfirmedWorkoutIsNamedEverywhere`.
    @Test("History names the fixtures' workouts")
    func historyWorkoutsAreNamed() throws {
        let rows = DemoBodyFlowFixtures.postWorkoutConfirmationHistory.data.workouts
        let typed = "Treino de corrida intervalada em terreno inclinado com recuperação ativa entre séries"
        #expect(rows.map(\.workoutType) == ["musculacao", typed])

        let portuguese = HistoryValuePresentation(language: Self.pt)
        let english = HistoryValuePresentation(language: Self.en)
        #expect(rows.map { portuguese.workoutType($0.workoutType) } == ["Musculação", typed])
        #expect(rows.map { english.workoutType($0.workoutType) } == ["Strength training", typed])

        let edited = try #require(
            DemoBodyFlowFixtures.postEditedWorkoutConfirmationHistory.data.workouts.first
        )
        #expect(edited.workoutType == "ciclismo")
        #expect(portuguese.workoutType(edited.workoutType) == "Ciclismo")
        #expect(english.workoutType(edited.workoutType) == "Cycling")

        // A record without a type keeps the views' own fallback ("Treino").
        #expect(portuguese.workoutType(nil) == nil)
    }

    @Test("the workout proposal draws its type and intensity by name")
    func workoutProposalIsNamed() {
        let pending = DemoBodyFlowFixtures.pendingWorkoutRegistration.data
        let edited = DemoBodyFlowFixtures.editedWorkoutRegistration.data
        #expect(WorkoutProposalPresentation(registration: pending).workoutType == "musculacao")
        #expect(WorkoutProposalPresentation(registration: pending).intensity == "moderada")
        #expect(WorkoutProposalPresentation(registration: edited).workoutType == "ciclismo")
        #expect(WorkoutProposalPresentation(registration: edited).intensity == "alta")

        let portuguese = Self.workoutProposalLabels(pending, Self.pt)
        #expect(portuguese.contains("Musculação"), "\(portuguese)")
        #expect(portuguese.contains("Moderada"), "\(portuguese)")
        #expect(portuguese.contains("47 min"), "\(portuguese)")
        #expect(!portuguese.contains { Self.showsStoredCode($0) }, "\(portuguese)")

        let english = Self.workoutProposalLabels(pending, Self.en)
        #expect(english.contains("Strength training"), "\(english)")
        #expect(english.contains("Moderate"), "\(english)")
        #expect(!english.contains { Self.showsStoredCode($0) }, "\(english)")

        let editedPortuguese = Self.workoutProposalLabels(edited, Self.pt)
        #expect(editedPortuguese.contains("Ciclismo"), "\(editedPortuguese)")
        #expect(editedPortuguese.contains("Alta"), "\(editedPortuguese)")
        let editedEnglish = Self.workoutProposalLabels(edited, Self.en)
        #expect(editedEnglish.contains("Cycling"), "\(editedEnglish)")
        #expect(editedEnglish.contains("High"), "\(editedEnglish)")
        #expect(!editedEnglish.contains { Self.showsStoredCode($0) }, "\(editedEnglish)")
    }

    @Test("what the form sends is what was typed and chosen, not a label")
    func whatIsSentIsUnchanged() throws {
        let sent = try Self.proposalSent(byFormOpenedWith: WorkoutProposalRequest(
            workoutType: " Natação ", durationMin: 40, intensity: .high, performedAt: nil
        ))
        #expect(sent.workoutType == " Natação ")
        #expect(sent.durationMin == 40)
        #expect(sent.intensity == .high)
        #expect(sent.intensity?.rawValue == "alta")
    }

    @Test("the new workout labels exist in both languages", arguments: [
        SampleDataBilingualCase("registration.workout-type.musculacao", "Musculação", "Strength training"),
        SampleDataBilingualCase("registration.workout-type.corrida", "Corrida", "Running"),
        SampleDataBilingualCase("registration.workout-type.caminhada", "Caminhada", "Walking"),
        SampleDataBilingualCase("registration.workout-type.natacao", "Natação", "Swimming"),
        SampleDataBilingualCase("registration.workout-type.ciclismo", "Ciclismo", "Cycling"),
        SampleDataBilingualCase("registration.workout-intensity.intensa", "Intensa", "Intense"),
    ])
    func workoutLabelCopy(_ wording: SampleDataBilingualCase) throws {
        try Self.expectCopy(wording)
    }

    // MARK: Register · bridged submit buttons

    // The previous lot found that SwiftUI writes the environment's enabled
    // state into a bridged UIButton after `updateUIView`, so `isEnabled` set
    // there alone never disables it. Each form is drawn idle and then told a
    // request is in flight: the state a second tap meets.
    @Test("hydration: once a request is in flight every button is disabled and a second tap does nothing")
    func hydrationButtonsWhileSubmitting() throws {
        let flag = SubmittingFlag()
        let submissions = Counter()
        let identifiers = [
            "registration.hydration.submit", "registration.hydration.quick.250",
            "registration.hydration.quick.500", "registration.hydration.quick.750",
        ]
        try Self.withButtons(of: SubmittingHarness(flag: flag) { isSubmitting in
            HydrationRegistrationView(
                initialOccurredAt: Self.instant,
                isSubmitting: isSubmitting,
                submit: { _, _, _ in submissions.value += 1 }
            )
        }) { buttons in
            try Self.expect(identifiers, in: buttons(), enabled: true)
            // By design the form does not judge the amount: with nothing
            // typed the tap still reaches the model, which answers with
            // "registration.hydration.validation".
            try Self.tap("registration.hydration.submit", in: buttons())
            #expect(submissions.value == 1)

            flag.isSubmitting = true
            Self.settle()
            try Self.expect(identifiers, in: buttons(), enabled: false)
            try Self.tap("registration.hydration.submit", in: buttons())
            #expect(submissions.value == 1)

            flag.isSubmitting = false
            Self.settle()
            try Self.expect(identifiers, in: buttons(), enabled: true)
        }
    }

    @Test("weight: once a request is in flight the button is disabled and a second tap does nothing")
    func weightButtonWhileSubmitting() throws {
        let flag = SubmittingFlag()
        let submissions = Counter()
        let identifiers = ["registration.weight.submit"]
        try Self.withButtons(of: SubmittingHarness(flag: flag) { isSubmitting in
            WeightRegistrationView(
                initialRecordedAt: Self.instant,
                isSubmitting: isSubmitting,
                submit: { _, _ in submissions.value += 1 }
            )
        }) { buttons in
            try Self.expect(identifiers, in: buttons(), enabled: true)
            // As with hydration: "registration.weight.validation" is the
            // answer to an invalid value, so the idle button stays enabled.
            try Self.tap("registration.weight.submit", in: buttons())
            #expect(submissions.value == 1)

            flag.isSubmitting = true
            Self.settle()
            try Self.expect(identifiers, in: buttons(), enabled: false)
            try Self.tap("registration.weight.submit", in: buttons())
            #expect(submissions.value == 1)

            flag.isSubmitting = false
            Self.settle()
            try Self.expect(identifiers, in: buttons(), enabled: true)
        }
    }

    @Test("workout form: once a request is in flight the action is disabled and a second tap does nothing")
    func workoutFormButtonWhileSubmitting() throws {
        let flag = SubmittingFlag()
        let submissions = Counter()
        let identifiers = ["registration.workout.propose"]
        try Self.withButtons(of: SubmittingHarness(flag: flag) { isSubmitting in
            WorkoutRegistrationView(
                initialPerformedAt: Self.instant,
                presentsLocalDemonstration: true,
                isSubmitting: isSubmitting,
                submit: { _ in submissions.value += 1 }
            )
        }) { buttons in
            try Self.expect(identifiers, in: buttons(), enabled: true)
            try Self.tap("registration.workout.propose", in: buttons())
            #expect(submissions.value == 1)

            flag.isSubmitting = true
            Self.settle()
            try Self.expect(identifiers, in: buttons(), enabled: false)
            try Self.tap("registration.workout.propose", in: buttons())
            #expect(submissions.value == 1)
        }
    }

    @Test("workout proposal: once a request is in flight its actions are disabled and a second tap does nothing")
    func workoutProposalButtonsWhileSubmitting() throws {
        let flag = SubmittingFlag()
        let taps = Counter()
        let identifiers = [
            "registration.proposal.confirm", "registration.proposal.edit", "registration.proposal.cancel",
        ]
        let pending = WorkoutProposalPresentation(
            registration: DemoBodyFlowFixtures.pendingWorkoutRegistration.data
        )
        try Self.withButtons(of: SubmittingHarness(flag: flag) { isSubmitting in
            WorkoutProposalView(
                proposal: pending, isSubmitting: isSubmitting,
                edit: { taps.value += 1 },
                confirm: { taps.value += 1 },
                cancel: { taps.value += 1 }
            )
        }) { buttons in
            try Self.expect(identifiers, in: buttons(), enabled: true)
            for identifier in identifiers { try Self.tap(identifier, in: buttons()) }
            #expect(taps.value == identifiers.count)

            flag.isSubmitting = true
            Self.settle()
            try Self.expect(identifiers, in: buttons(), enabled: false)
            for identifier in identifiers { try Self.tap(identifier, in: buttons()) }
            #expect(taps.value == identifiers.count)
        }
    }

    // MARK: Wording

    @Test("the connection error reads the same from the catalog and from the fallback")
    func connectionErrorWording() throws {
        let portuguese = "Não foi possível conectar agora. Tente novamente."
        #expect(try AppLocalization.string("auth.error.service-unavailable", for: Self.pt) == portuguese)
        #expect(
            try AppLocalization.string("auth.error.service-unavailable", for: Self.en)
                == "Could not connect right now. Try again."
        )
        #expect(AppPresentationError.serviceUnavailable.authMessage == portuguese)
        #expect(AppPresentationError.serviceUnavailable.authMessage(for: Self.pt) == portuguese)
        #expect(
            AppPresentationError.serviceUnavailable.authMessage(for: Self.en)
                == "Could not connect right now. Try again."
        )
    }

    // MARK: Support

    private static let instant = Date(timeIntervalSince1970: 1_790_000_000)

    private static func expectCopy(_ wording: SampleDataBilingualCase) throws {
        let key = String.LocalizationValue(wording.subject)
        #expect(try AppLocalization.string(key, for: pt) == wording.portuguese)
        #expect(try AppLocalization.string(key, for: en) == wording.english)
    }

    /// The parts VoiceOver joins into one label ("Brasil, BR").
    private static func parts(of label: String) -> Set<String> {
        Set(label.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private static func systemZoneName(_ identifier: String, _ language: SupportedAppLanguage) -> String? {
        TimeZone(identifier: identifier)?.localizedName(for: .generic, locale: language.formattingLocale)
    }

    /// True when a label still carries one of the fixtures' stored codes.
    private static func showsStoredCode(_ label: String) -> Bool {
        ["musculacao", "caminhada", "ciclismo", "moderada", "leve", "alta"].contains { code in
            label.range(of: "\\b\(code)\\b", options: .regularExpression) != nil
        }
    }

    /// An item as the server sends it, so the origin is read from the same
    /// keys the app reads.
    private static func item(_ json: String) throws -> MealProposalItemSnapshot {
        try JSONDecoder().decode(MealProposalItemSnapshot.self, from: Data(json.utf8))
    }

    /// The server's calculation: both provenance keys sent, no typed value.
    private static var calculatedItem: MealProposalItemSnapshot {
        get throws {
            try item("""
            {"name":"Arroz branco cozido","quantity_g":150,"kcal":195,"protein_g":4,"carbs_g":42,"fat_g":0,
             "user_kcal":null,"nutrition_source":"canonical_exact"}
            """)
        }
    }

    /// The review's case: the person typed 350 kcal and the server applied it.
    private static var typedItem: MealProposalItemSnapshot {
        get throws {
            try item("""
            {"name":"Frango grelhado","quantity_g":120,"kcal":350,"protein_g":36,"carbs_g":0,"fat_g":4,
             "user_kcal":350,"nutrition_source":"user_kcal"}
            """)
        }
    }

    /// An earlier server: neither provenance key in the response.
    private static var itemOfUnknownOrigin: MealProposalItemSnapshot {
        get throws {
            try item("""
            {"name":"Feijão carioca","quantity_g":100,"kcal":76,"protein_g":5,"carbs_g":14,"fat_g":1}
            """)
        }
    }

    private static var unresolvedItem: MealProposalItemSnapshot {
        get throws {
            try item("""
            {"name":"Ovo","quantity_g":50,"kcal":null,"protein_g":null,"carbs_g":null,"fat_g":null,
             "user_kcal":null,"nutrition_source":null,"resolution":"needs_clarification"}
            """)
        }
    }

    private static func mealProposal(items: [MealProposalItemSnapshot]) throws -> MealProposalPresentation {
        #expect(try calculatedItem.kcalOrigin == .official)
        #expect(try typedItem.kcalOrigin == .patientReported(350))
        #expect(try itemOfUnknownOrigin.kcalOrigin == .unknown)
        #expect(try unresolvedItem.needsClarification)
        return MealProposalPresentation(registration: RegistrationSnapshot(
            id: "proposal-note-1",
            status: "pending",
            createdAt: APITimestamp(value: instant),
            expiresAt: APITimestamp(value: instant.addingTimeInterval(3_600)),
            resolvedAt: nil,
            proposal: .meal(MealProposalSnapshot(
                mealType: "almoco", items: items, totals: nil, warnings: []
            ))
        ))
    }

    private static func proposalLabels(
        _ proposal: MealProposalPresentation,
        _ language: SupportedAppLanguage
    ) -> [String] {
        Support.accessibilityTree(
            MealProposalView(proposal: proposal, isSubmitting: false, edit: {}, confirm: {}, cancel: {})
                .environment(\.locale, language.formattingLocale),
            height: 2_400
        ).labels
    }

    private static func todayWorkoutLabels(
        _ snapshot: TodaySnapshot,
        _ language: SupportedAppLanguage
    ) -> [String] {
        Support.accessibilityTree(
            TodayRecordsSection(workouts: TodayPresentation(snapshot: snapshot, language: language).workouts)
                .environment(\.locale, language.formattingLocale),
            height: 1_200
        ).labels
    }

    private static func workoutProposalLabels(
        _ registration: RegistrationSnapshot,
        _ language: SupportedAppLanguage
    ) -> [String] {
        Support.accessibilityTree(
            WorkoutProposalView(
                proposal: WorkoutProposalPresentation(registration: registration),
                isSubmitting: false, edit: {}, confirm: {}, cancel: {}
            )
            .environment(\.locale, language.formattingLocale),
            height: 1_200
        ).labels
    }

    /// Every bridged button under a view, by accessibility identifier.
    private static func bridgedButtons(under root: UIView) -> [String: [UIButton]] {
        var buttons: [String: [UIButton]] = [:]
        @MainActor func collect(_ view: UIView) {
            if let button = view as? UIButton, let identifier = button.accessibilityIdentifier {
                buttons[identifier, default: []].append(button)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return buttons
    }

    /// Draws the view and hands over a way to read its buttons again after
    /// each change of state.
    private static func withButtons<V: View>(
        of view: V,
        _ body: @MainActor (@MainActor () -> [String: [UIButton]]) throws -> Void
    ) throws {
        try Support.hosted(view.environment(\.locale, pt.formattingLocale), height: 800) { root in
            try body { bridgedButtons(under: root) }
        }
    }

    private static func expect(
        _ identifiers: [String],
        in buttons: [String: [UIButton]],
        enabled: Bool
    ) throws {
        for identifier in identifiers {
            let found = try #require(buttons[identifier], "\(identifier) was not drawn")
            #expect(!found.isEmpty)
            #expect(
                found.allSatisfy { $0.isEnabled == enabled },
                "\(identifier) should be \(enabled ? "enabled" : "disabled")"
            )
        }
    }

    /// A touch delivered to the control itself, as one already on its way
    /// when the state changed would be.
    private static func tap(_ identifier: String, in buttons: [String: [UIButton]]) throws {
        try #require(buttons[identifier]?.first).sendActions(for: .touchUpInside)
    }

    /// Lets SwiftUI apply a change of state to the drawn controls.
    private static func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    /// Opens the form on a proposal and taps its action, returning what the
    /// form hands over to be sent.
    private static func proposalSent(
        byFormOpenedWith proposal: WorkoutProposalRequest
    ) throws -> WorkoutProposalRequest {
        let sent = Box<WorkoutProposalRequest?>(nil)
        let view = WorkoutRegistrationView(
            initialPerformedAt: instant,
            initialProposal: proposal,
            isSubmitting: false,
            submit: { sent.value = $0 }
        )
        .environment(\.locale, pt.formattingLocale)
        try Support.hosted(view, height: 800) { root in
            var action: UIButton?
            @MainActor func collect(_ view: UIView) {
                if let button = view as? UIButton,
                   button.accessibilityIdentifier == "registration.workout.propose" {
                    action = button
                }
                view.subviews.forEach(collect)
            }
            collect(root)
            try #require(action).sendActions(for: .touchUpInside)
        }
        return try #require(sent.value)
    }
}

/// What a person types in the time zone search, and the zone it must find.
struct TimeZoneSearchCase: Sendable, CustomTestStringConvertible {
    let query: String
    let identifier: String

    init(_ query: String, _ identifier: String) {
        self.query = query
        self.identifier = identifier
    }

    var testDescription: String { "“\(query)” finds \(identifier)" }
}

@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor
private final class Counter {
    var value = 0
}

/// Whether a request is in flight, changed by the test while the form stays
/// on screen.
@MainActor
@Observable
private final class SubmittingFlag {
    var isSubmitting = false
}

private struct SubmittingHarness<Content: View>: View {
    let flag: SubmittingFlag
    @ViewBuilder let content: (Bool) -> Content

    var body: some View { content(flag.isSubmitting) }
}
