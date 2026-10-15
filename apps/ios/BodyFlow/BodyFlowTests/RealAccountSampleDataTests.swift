import Foundation
import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

/// A real account never meets demonstration, placeholder or developer-facing
/// content. Each rule is checked for the real account and, next to it, the
/// local demonstration is checked to be exactly what it was.
@Suite("A real account sees no sample data")
@MainActor
struct RealAccountSampleDataTests {
    private static let pt = SupportedAppLanguage.portugueseBrazil
    private static let en = SupportedAppLanguage.englishUnitedStates

    // MARK: Today · "Resumo do dia"

    @Test("the demonstration-only summary card is decided by the account kind")
    func summaryCardFollowsTheAccountKind() throws {
        #expect(!TodayRootView.showsDemonstrationSummaryLink(presentsRealAccountIdentity: true))
        #expect(TodayRootView.showsDemonstrationSummaryLink(presentsRealAccountIdentity: false))

        let demo = AppDependencies.scaffold()
        #expect(TodayRootView.showsDemonstrationSummaryLink(
            presentsRealAccountIdentity: demo.presentsRealAccountIdentity
        ))
        let real = try Self.realAccountDependencies()
        #expect(!TodayRootView.showsDemonstrationSummaryLink(
            presentsRealAccountIdentity: real.presentsRealAccountIdentity
        ))

        // Previews and every caller that says nothing keep the card.
        let untouched = TodayRootView(
            model: TodayViewModel(provider: FixedTodayProvider()),
            invalidationCenter: FeatureInvalidationCenter()
        )
        #expect(untouched.showsDemonstrationSummaryLink)
    }

    @Test("the shell hands Today the account kind, and the card is drawn only behind it")
    func shellThreadsTheAccountKindIntoToday() throws {
        let shell = try Self.source("BodyFlow/App/AppShellView.swift")
        #expect(shell.contains("showsDemonstrationSummaryLink: TodayRootView.showsDemonstrationSummaryLink("))
        #expect(shell.contains("presentsRealAccountIdentity: dependencies.presentsRealAccountIdentity"))

        let today = try Self.source("BodyFlow/Features/Today/TodayRootView.swift")
        let gate = try #require(today.range(of: "if showsDemonstrationSummaryLink {"))
        let link = try #require(today.range(of: "AppRoute.detail(tab: .today, id: \"daily-summary\")"))
        #expect(gate.upperBound < link.lowerBound)
        #expect(today.components(separatedBy: "\"today.next-action\"").count == 2)
    }

    @Test("a real account's Today is drawn shorter by the summary card; the demonstration keeps it")
    func summaryCardIsRenderedOnlyInTheDemonstration() async throws {
        let demonstration = try await Self.todayContentHeight(showsDemonstrationSummaryLink: true)
        let realAccount = try await Self.todayContentHeight(showsDemonstrationSummaryLink: false)
        let untouched = try await Self.todayContentHeight(showsDemonstrationSummaryLink: nil)

        // The same day, drawn twice: the only difference is the closing card
        // (a tappable row and the spacing above it).
        let heights: Comment = "demonstration \(demonstration), real account \(realAccount), default \(untouched)"
        #expect(realAccount > 400, heights)
        #expect(demonstration - realAccount >= BodyFlowSpacing.minimumTapTarget + BodyFlowSpacing.lg, heights)
        #expect(demonstration - realAccount < 200, heights)
        #expect(untouched == demonstration, heights)
    }

    // MARK: Register · workout form

    @Test("a real account opens the workout form empty and cannot propose it")
    func realAccountWorkoutFormStartsEmpty() {
        let seed = WorkoutRegistrationFormSeed(
            initialProposal: nil,
            presentsLocalDemonstration: false
        )
        #expect(seed.workoutType == "")
        #expect(seed.duration == "")
        #expect(!seed.canPropose)
    }

    @Test("the demonstration keeps its sample workout ready to propose")
    func demonstrationWorkoutFormStaysPrefilled() {
        let seed = WorkoutRegistrationFormSeed(
            initialProposal: nil,
            presentsLocalDemonstration: true
        )
        #expect(seed.workoutType == "musculacao")
        #expect(seed.duration == "47")
        #expect(seed.canPropose)
    }

    @Test("editing a proposal shows its own values on either kind of account", arguments: [true, false])
    func editedProposalKeepsItsValues(presentsLocalDemonstration: Bool) {
        let proposal = WorkoutProposalRequest(
            workoutType: "corrida",
            durationMin: 32,
            intensity: .high,
            performedAt: APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_000))
        )
        let seed = WorkoutRegistrationFormSeed(
            initialProposal: proposal,
            presentsLocalDemonstration: presentsLocalDemonstration
        )
        #expect(seed.workoutType == "corrida")
        #expect(seed.duration == "32")
        #expect(seed.canPropose)
    }

    @Test("the proposal action needs a typed type and a whole number of minutes")
    func proposalValidation() {
        #expect(!WorkoutRegistrationFormSeed.canPropose(workoutType: "", duration: ""))
        #expect(!WorkoutRegistrationFormSeed.canPropose(workoutType: "corrida", duration: ""))
        #expect(!WorkoutRegistrationFormSeed.canPropose(workoutType: "", duration: "30"))
        #expect(!WorkoutRegistrationFormSeed.canPropose(workoutType: "corrida", duration: "trinta"))
        #expect(WorkoutRegistrationFormSeed.canPropose(workoutType: "corrida", duration: "30"))
    }

    // The server's contract for a workout proposal: `workout_type` trimmed,
    // 1 to 80 characters; `duration_min` a positive integer up to 1440.
    @Test("the proposal action follows the server's limits for type and duration")
    func proposalValidationMatchesTheServerContract() {
        func canPropose(_ workoutType: String, _ duration: String) -> Bool {
            WorkoutRegistrationFormSeed.canPropose(workoutType: workoutType, duration: duration)
        }
        #expect(!canPropose(" ", "30"))
        #expect(!canPropose(" \n\t ", "30"))
        #expect(canPropose("  corrida  ", "30"))
        #expect(canPropose(String(repeating: "a", count: 80), "30"))
        #expect(!canPropose(String(repeating: "a", count: 81), "30"))
        // Surrounding spaces are not part of the 80.
        #expect(canPropose(" " + String(repeating: "a", count: 80) + " ", "30"))
        #expect(!canPropose("corrida", "0"))
        #expect(!canPropose("corrida", "-30"))
        #expect(canPropose("corrida", "1"))
        #expect(canPropose("corrida", "1440"))
        #expect(!canPropose("corrida", "1441"))
        #expect(!canPropose("corrida", "2000"))
        #expect(!canPropose("corrida", "30.5"))
        #expect(!canPropose("corrida", "30 "))
    }

    @Test("the rendered action is disabled outside the server's limits", arguments: [
        WorkoutFormCase(" ", 30, false),
        WorkoutFormCase("corrida", 0, false),
        WorkoutFormCase("corrida", -30, false),
        WorkoutFormCase("corrida", 2_000, false),
        WorkoutFormCase("corrida", 1_441, false),
        WorkoutFormCase(String(repeating: "a", count: 81), 30, false),
        WorkoutFormCase("corrida", 1_440, true),
        WorkoutFormCase(String(repeating: "a", count: 80), 1, true),
    ])
    func renderedActionFollowsTheServerContract(_ form: WorkoutFormCase) throws {
        let rendered = try Self.workoutForm(
            presentsLocalDemonstration: false,
            initialProposal: WorkoutProposalRequest(
                workoutType: form.workoutType,
                durationMin: form.durationMin,
                intensity: .moderate,
                performedAt: nil
            )
        )
        #expect(rendered.type == form.workoutType)
        #expect(rendered.duration == String(form.durationMin))
        #expect(rendered.proposeEnabled == form.canPropose)
    }

    @Test("the rendered form: empty fields and a disabled action on a real account")
    func realAccountWorkoutFormIsRenderedEmpty() throws {
        let form = try Self.workoutForm(presentsLocalDemonstration: false)
        #expect(form.type == "")
        #expect(form.duration == "")
        #expect(!form.proposeEnabled)
    }

    // Review 2026-10-04: no test drew the form the way a caller that leaves
    // the account kind out gets it, so the default could turn to the
    // demonstration's unnoticed.
    @Test("the rendered form with no account kind given is the real account's: empty and disabled")
    func workoutFormDefaultsToTheRealAccount() throws {
        let form = try Self.workoutForm(in: WorkoutRegistrationView(
            initialPerformedAt: Date(timeIntervalSince1970: 1_790_000_000),
            isSubmitting: false,
            submit: { _ in }
        ))
        #expect(form.type == "")
        #expect(form.duration == "")
        #expect(!form.proposeEnabled)
    }

    // Review 2026-10-04: outside the server's limits the action was disabled
    // and nothing on the screen said why.
    @Test("a filled field outside the server's limits says what it accepts", arguments: [
        WorkoutHelpCase("corrida", 0, duration: true),
        WorkoutHelpCase("corrida", 1_441, duration: true),
        WorkoutHelpCase("corrida", -30, duration: true),
        WorkoutHelpCase(String(repeating: "a", count: 81), 30, type: true),
        WorkoutHelpCase(String(repeating: "a", count: 81), 1_441, type: true, duration: true),
        WorkoutHelpCase("corrida", 1, duration: false),
        WorkoutHelpCase("corrida", 1_440, duration: false),
        WorkoutHelpCase(String(repeating: "a", count: 80), 30, type: false),
    ])
    func workoutFormExplainsALimit(_ form: WorkoutHelpCase) {
        for language in SupportedAppLanguage.allCases {
            let tree = Self.workoutFormTree(
                language: language,
                initialProposal: WorkoutProposalRequest(
                    workoutType: form.workoutType,
                    durationMin: form.durationMin,
                    intensity: .moderate,
                    performedAt: nil
                )
            )
            let seen: Comment = "\(tree.labels)"
            let typeHelp = language == Self.pt ? "Use até 80 caracteres." : "Use up to 80 characters."
            let durationHelp = language == Self.pt
                ? "Informe de 1 a 1.440 minutos." : "Enter 1 to 1,440 minutes."
            // The form itself was drawn, so an absent line is not a blank screen.
            #expect(tree.labels.contains(language == Self.pt ? "Duração (min)" : "Duration (min)"), seen)
            #expect(tree.labels.contains(typeHelp) == form.showsTypeHelp, seen)
            #expect(tree.identifiers.contains("registration.workout.type.help") == form.showsTypeHelp)
            #expect(tree.labels.contains(durationHelp) == form.showsDurationHelp, seen)
            #expect(tree.identifiers.contains("registration.workout.duration.help") == form.showsDurationHelp)
        }
    }

    @Test("an empty form shows no help line")
    func emptyWorkoutFormShowsNoHelp() {
        for language in SupportedAppLanguage.allCases {
            let tree = Self.workoutFormTree(language: language, initialProposal: nil)
            let seen: Comment = "\(tree.labels)"
            #expect(tree.labels.contains(language == Self.pt ? "Duração (min)" : "Duration (min)"), seen)
            #expect(Set(tree.labels).isDisjoint(with: [
                "Informe de 1 a 1.440 minutos.", "Enter 1 to 1,440 minutes.",
                "Use até 80 caracteres.", "Use up to 80 characters.",
            ]), seen)
            #expect(!tree.identifiers.contains("registration.workout.type.help"))
            #expect(!tree.identifiers.contains("registration.workout.duration.help"))
        }
    }

    @Test("a help line is for a filled field only, and for anything that is not 1 to 1440 whole minutes")
    func workoutHelpRules() {
        func duration(_ typed: String) -> Bool { WorkoutRegistrationFormSeed.durationIsOutsideRange(typed) }
        func type(_ typed: String) -> Bool { WorkoutRegistrationFormSeed.typeExceedsLimit(typed) }
        #expect(!duration("") && !duration("  "))
        #expect(!duration("1") && !duration("47") && !duration("1440"))
        #expect(duration("0") && duration("1441") && duration("-30") && duration("2000"))
        #expect(duration("30.5") && duration("trinta") && duration("30 "))
        #expect(!type("") && !type("   ") && !type("corrida"))
        #expect(!type(String(repeating: "a", count: 80)))
        #expect(type(String(repeating: "a", count: 81)))
        // Surrounding spaces are not part of the 80, as in `canPropose`.
        #expect(!type(" " + String(repeating: "a", count: 80) + " "))
    }

    @Test("the help lines exist in both languages", arguments: [
        SampleDataBilingualCase("registration.workout.duration.help",
         "Informe de 1 a 1.440 minutos.", "Enter 1 to 1,440 minutes."),
        SampleDataBilingualCase("registration.workout.type.help",
         "Use até 80 caracteres.", "Use up to 80 characters."),
    ])
    func workoutHelpCopy(_ wording: SampleDataBilingualCase) throws {
        let key = String.LocalizationValue(wording.subject)
        #expect(try AppLocalization.string(key, for: Self.pt) == wording.portuguese)
        #expect(try AppLocalization.string(key, for: Self.en) == wording.english)
    }

    @Test("the rendered form: sample values and an enabled action in the demonstration")
    func demonstrationWorkoutFormIsRenderedPrefilled() throws {
        let form = try Self.workoutForm(presentsLocalDemonstration: true)
        #expect(form.type == "musculacao")
        #expect(form.duration == "47")
        #expect(form.proposeEnabled)
    }

    @Test("the sheet hands the form the same account kind as the rest of Register")
    func sheetThreadsTheAccountKindIntoTheWorkoutForm() async throws {
        // The whole Register sheet, drawn with each kind of dependencies.
        let realAccount = try await Self.readyRealAccountWorkoutForm()
        #expect(realAccount.type == "")
        #expect(realAccount.duration == "")
        #expect(!realAccount.proposeEnabled)

        let demonstration = try Self.workoutForm(inSheetWith: AppDependencies.scaffold())
        #expect(demonstration.type == "musculacao")
        #expect(demonstration.duration == "47")
        #expect(demonstration.proposeEnabled)
    }

    // MARK: Onboarding · legal documents

    @Test("a legal document is titled by its kind, in both languages", arguments: [
        SampleDataBilingualCase("terms_of_service", "Termos de uso", "Terms of use"),
        // The four keys published on staging on 2026-10-04, as published.
        SampleDataBilingualCase("qa_terms_notice", "Termos de uso", "Terms of use"),
        SampleDataBilingualCase("qa_privacy_notice", "Política de privacidade", "Privacy policy"),
        SampleDataBilingualCase("qa_health_ai_notice", "Saúde e inteligência artificial", "Health and AI"),
        SampleDataBilingualCase("qa_sensitive_data_consent", "Dados sensíveis de saúde", "Sensitive health data"),
        // The four that replace them.
        SampleDataBilingualCase("evaluation_1_terms_notice", "Termos de uso", "Terms of use"),
        SampleDataBilingualCase("evaluation_2_privacy_notice", "Política de privacidade", "Privacy policy"),
        SampleDataBilingualCase("evaluation_3_health_ai_notice", "Saúde e inteligência artificial", "Health and AI"),
        SampleDataBilingualCase("evaluation_4_sensitive_data_consent", "Dados sensíveis de saúde", "Sensitive health data"),
        SampleDataBilingualCase("privacy_policy", "Política de privacidade", "Privacy policy"),
        SampleDataBilingualCase("health_ai_consent", "Saúde e inteligência artificial", "Health and AI"),
        SampleDataBilingualCase("consent_ai_processing", "Saúde e inteligência artificial", "Health and AI"),
        SampleDataBilingualCase("sensitive_health_data_consent", "Dados sensíveis de saúde", "Sensitive health data"),
        SampleDataBilingualCase("medication_reminder_disclaimer", "Lembretes de medicamentos", "Medication reminders"),
        SampleDataBilingualCase("qa_onboarding_required", "Documento", "Document"),
        SampleDataBilingualCase("qa_onboarding_notice", "Documento", "Document"),
        SampleDataBilingualCase("qa_onboarding_consent", "Documento", "Document"),
        SampleDataBilingualCase("anything_else_v2", "Documento", "Document"),
        SampleDataBilingualCase("", "Documento", "Document"),
    ])
    func legalDocumentTitle(_ wording: SampleDataBilingualCase) {
        #expect(OnboardingLegalDocumentKind.title(
            forDocumentKey: wording.subject, language: Self.pt
        ) == wording.portuguese)
        #expect(OnboardingLegalDocumentKind.title(
            forDocumentKey: wording.subject, language: Self.en
        ) == wording.english)
    }

    @Test("the kind is read by substring, in the stated order")
    func legalDocumentKindOrder() {
        #expect(OnboardingLegalDocumentKind(documentKey: "terms_of_service") == .terms)
        #expect(OnboardingLegalDocumentKind(documentKey: "privacy_policy") == .privacy)
        #expect(OnboardingLegalDocumentKind(documentKey: "health_ai") == .healthAI)
        #expect(OnboardingLegalDocumentKind(documentKey: "use_ai_notice") == .healthAI)
        #expect(OnboardingLegalDocumentKind(documentKey: "sensitive_data") == .sensitiveData)
        #expect(OnboardingLegalDocumentKind(documentKey: "medication_reminders") == .medication)
        #expect(OnboardingLegalDocumentKind(documentKey: "maintenance") == .other)
        // A key of two kinds takes the first one listed.
        #expect(OnboardingLegalDocumentKind(documentKey: "privacy_terms") == .terms)
        #expect(OnboardingLegalDocumentKind(documentKey: "sensitive_privacy") == .privacy)
        #expect(OnboardingLegalDocumentKind(documentKey: "medication_health_ai") == .healthAI)
        #expect(OnboardingLegalDocumentKind(documentKey: "TERMS_OF_SERVICE") == .terms)
    }

    @Test("every kind has a title of its own in both languages")
    func everyLegalKindIsInTheCatalog() throws {
        let keys = [
            "onboarding.legal.title.terms", "onboarding.legal.title.privacy",
            "onboarding.legal.title.health-ai", "onboarding.legal.title.sensitive-data",
            "onboarding.legal.title.medication", "onboarding.legal.title.document",
        ]
        for language in SupportedAppLanguage.allCases {
            let titles = try keys.map {
                try AppLocalization.string(String.LocalizationValue($0), for: language)
            }
            #expect(Set(titles).count == keys.count)
            #expect(OnboardingLegalDocumentKind.allCases.map { $0.title(for: language) } == titles)
        }
    }

    @Test("the consent card shows the title and the body, never the key or the purpose")
    func consentCardHidesTheRawKeyAndPurpose() {
        let document = Self.document(key: "qa_terms_notice", purpose: "account_terms_acceptance")
        let model = Self.onboardingModel(step: .consent, documents: [document])
        for language in SupportedAppLanguage.allCases {
            // The card as drawn: everything VoiceOver can read on it.
            let labels = Self.accessibilityTree(
                ConsentStepView(model: model).environment(\.locale, language.formattingLocale),
                height: 2_400
            ).labels
            #expect(labels.contains(language == Self.pt ? "Termos de uso" : "Terms of use"))
            #expect(labels.contains("Corpo do documento para o teste."))
            #expect(!labels.contains { $0.contains(document.purpose) })
            #expect(!labels.contains { $0.contains(document.documentKey) })
        }
    }

    @Test("the rendered consent step names each document and keeps its action identifiers")
    func consentStepIsRenderedWithHumanTitles() throws {
        let documents = [
            Self.document(key: "terms_of_service", purpose: "account_terms_acceptance"),
            Self.document(key: "privacy_policy", purpose: "privacy_notice_acknowledgement"),
            Self.document(key: "qa_onboarding_consent", purpose: "qa_local_consent_validation"),
        ]
        let model = Self.onboardingModel(step: .consent, documents: documents)
        let tree = Self.accessibilityTree(
            ConsentStepView(model: model).environment(\.locale, Locale(identifier: "pt_BR")),
            height: 2_400
        )

        for title in ["Termos de uso", "Política de privacidade", "Documento"] {
            #expect(tree.labels.contains(title), "missing title \(title)")
        }
        #expect(tree.labels.contains("Corpo do documento para o teste."))
        #expect(tree.labels.contains("Versão 2026-10-01.1"))
        for document in documents {
            #expect(!tree.labels.contains { $0.contains(document.documentKey) })
            #expect(!tree.labels.contains { $0.contains(document.purpose) })
            #expect(tree.identifiers.contains("onboarding.legal-action.\(document.documentKey)"))
        }
        #expect(
            OnboardingConsentAccessibilityID.officialAction("terms_of_service")
                == "onboarding.legal-action.terms_of_service"
        )
    }

    // MARK: Onboarding · review

    @Test("the country is shown by name in the app's language", arguments: [
        SampleDataBilingualCase("BR", "Brasil", "Brazil"),
        SampleDataBilingualCase("US", "Estados Unidos", "United States"),
        SampleDataBilingualCase("PT", "Portugal", "Portugal"),
    ])
    func countryName(_ wording: SampleDataBilingualCase) {
        #expect(OnboardingCountryPresentation.name(for: wording.subject, language: Self.pt) == wording.portuguese)
        #expect(OnboardingCountryPresentation.name(for: wording.subject, language: Self.en) == wording.english)
    }

    @Test("the rendered review shows the country name and the documents' titles, not codes")
    func reviewIsRenderedWithNamesAndTitles() throws {
        let documents = [
            Self.document(key: "terms_of_service", purpose: "account_terms_acceptance"),
            Self.document(key: "medication_reminder_disclaimer", purpose: "medication_notice"),
        ]
        let model = Self.onboardingModel(step: .completion, documents: documents)
        for document in documents {
            model.updateDocumentAction(document.explicitAction, selected: true)
        }
        #expect(model.draft.countryCode == "US")

        let portuguese = Self.accessibilityTree(
            OnboardingCompletionView(model: model, onComplete: {})
                .environment(\.locale, Locale(identifier: "pt_BR")),
            height: 2_400
        ).labels
        #expect(portuguese.contains("País"))
        #expect(portuguese.contains("Estados Unidos"))
        #expect(!portuguese.contains("US"))
        #expect(portuguese.contains("Termos de uso"))
        #expect(portuguese.contains("Lembretes de medicamentos"))
        #expect(!portuguese.contains { label in documents.contains { label.contains($0.documentKey) } })

        let english = Self.accessibilityTree(
            OnboardingCompletionView(model: model, onComplete: {})
                .environment(\.locale, Locale(identifier: "en_US")),
            height: 2_400
        ).labels
        #expect(english.contains("United States"))
        #expect(!english.contains("US"))
        #expect(english.contains("Terms of use"))
        #expect(english.contains("Medication reminders"))
    }

    @Test("the welcome step shows the timezone without the technical tag")
    func welcomeStepDropsTheTechnicalTimeZoneTag() throws {
        let model = Self.onboardingModel(step: .welcome, documents: [])
        let labels = Self.accessibilityTree(
            NavigationStack { WelcomeStepView(model: model) }
                .environment(\.locale, Locale(identifier: "pt_BR")),
            height: 2_400
        ).labels
        // The zone is named by its city, in the app's language; the
        // identifier is only stored.
        #expect(labels.contains { $0.contains("Nova York") })
        #expect(!labels.contains { $0.contains("America/New_York") || $0.contains("New_York") })
        #expect(!labels.contains { $0.contains("IANA") })

        for language in SupportedAppLanguage.allCases {
            let search = try AppLocalization.string(
                "onboarding.welcome.time-zone-picker.search", for: language
            )
            #expect(search == (language == Self.pt ? "Buscar cidade ou região" : "Search city or region"))
        }
    }

    // MARK: Today · date line

    @Test("the day is written the way a person reads it, in the app's language", arguments: [
        SampleDataBilingualCase("2026-10-04", "domingo, 4 de outubro", "Sunday, October 4"),
        SampleDataBilingualCase("2026-07-20", "segunda-feira, 20 de julho", "Monday, July 20"),
        SampleDataBilingualCase("2026-11-01", "domingo, 1 de novembro", "Sunday, November 1"),
        SampleDataBilingualCase("2027-01-01", "sexta-feira, 1 de janeiro", "Friday, January 1"),
        SampleDataBilingualCase("2026-12-31", "quinta-feira, 31 de dezembro", "Thursday, December 31"),
        SampleDataBilingualCase("2028-02-29", "terça-feira, 29 de fevereiro", "Tuesday, February 29"),
    ])
    func readableLocalDate(_ wording: SampleDataBilingualCase) {
        let header = TodayHeaderDescriptor(localDate: wording.subject, protocolName: nil, updatedAt: nil)
        #expect(header.readableLocalDate(for: Self.pt) == wording.portuguese)
        #expect(header.readableLocalDate(for: Self.en) == wording.english)
    }

    @Test("a value that is not a calendar date is shown as received", arguments: [
        "", "hoje", "2026-10", "2026-02-30", "2026-13-01",
    ])
    func unreadableLocalDateIsShownAsReceived(localDate: String) {
        let header = TodayHeaderDescriptor(localDate: localDate, protocolName: nil, updatedAt: nil)
        for language in SupportedAppLanguage.allCases {
            #expect(header.readableLocalDate(for: language) == localDate)
        }
    }

    @Test("the rendered date line has no technical prefix and keeps its identifier")
    func dateLineIsRenderedForReading() {
        let section = TodayHeaderSection(descriptor: TodayHeaderDescriptor(
            localDate: "2026-10-04", protocolName: "Recomposição corporal", updatedAt: nil
        ))
        let portuguese = Self.accessibilityTree(
            section.environment(\.locale, Locale(identifier: "pt_BR")), height: 400
        )
        #expect(portuguese.labels.contains("domingo, 4 de outubro"))
        #expect(!portuguese.labels.contains { $0.contains("Data local") || $0.contains("2026-10-04") })
        #expect(portuguese.identifiers.contains("today.header.local-date"))

        let english = Self.accessibilityTree(
            section.environment(\.locale, Locale(identifier: "en_US")), height: 400
        )
        #expect(english.labels.contains("Sunday, October 4"))
        #expect(!english.labels.contains { $0.contains("Local date") || $0.contains("2026-10-04") })
    }

    // MARK: Progress · Block 7.700

    @Test("the block detail no longer lists the storage origin")
    func blockDetailHasNoOriginRow() throws {
        let detail = try Self.source("BodyFlow/Features/Progress/Block7700DetailView.swift")
        #expect(!detail.contains("progress.block.source"))
        #expect(!detail.contains("descriptor.source"))
        #expect(detail.contains("copy(\"progress.block.availability\")"))
    }

    // MARK: Today · a new account's presumed meal pattern

    @Test("a presumed meal pattern is offered as open slots, never as something pending")
    func presumedMealPatternIsNotPresentedAsPending() throws {
        let original = try BodyFlowTestFixtures.decodeInconsistentToday()
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        var data = try #require(object["data"] as? [String: Any])
        data["meals"] = [[String: Any]]()
        data["pending_actions"] = [
            "registrations": [[String: Any]](),
            "meal_gaps": [
                "expected": ["cafe", "almoco", "jantar"],
                "registered": [String](),
                "skipped": [String](),
                "open": ["cafe", "almoco", "jantar"],
                "reliable": false,
                "source": "new_user_fallback",
                "active_days": 0,
            ] as [String: Any],
        ] as [String: Any]
        object["data"] = data
        let snapshot = try JSONDecoder().decode(
            TodayResponse.self,
            from: JSONSerialization.data(withJSONObject: object)
        ).data
        #expect(!snapshot.pendingActions.mealGaps.reliable)
        #expect(snapshot.pendingActions.mealGaps.source == "new_user_fallback")

        let presentation = TodayPresentation(snapshot: snapshot, language: Self.pt)
        // "Precisa da sua atenção" lists proposals awaiting an answer only.
        #expect(presentation.attention.pending.isEmpty)
        // The three presumed meals are slots that invite a record.
        #expect(presentation.mealSlots.slots.map(\.type) == ["cafe", "almoco", "jantar"])
        #expect(presentation.mealSlots.slots.allSatisfy { $0.state == .open })
        #expect(presentation.mealSlots.registeredCount == 0)
        #expect(try AppLocalization.string("today.meals.open", for: Self.pt) == "Ainda não registrada")
        #expect(try AppLocalization.string("today.meals.open", for: Self.en) == "Not logged yet")
    }

    // MARK: Catalog

    @Test("the reworded texts read plainly in both languages", arguments: [
        SampleDataBilingualCase("registration.root.detail.live",
         "Registre refeições, treinos e hidratação. Os valores são calculados para você.",
         "Log meals, workouts and hydration. Every figure is calculated for you."),
        SampleDataBilingualCase("registration.proposal.service-values",
         "Valores calculados pelo Performe AI", "Values calculated by Performe AI"),
        SampleDataBilingualCase("registration.editor.kcal.calculated",
         "Calorias calculadas pelo Performe AI", "Calories calculated by Performe AI"),
        SampleDataBilingualCase("registration.editor.official-kcal.unavailable", "Sem valor calculado", "No calculated value"),
        SampleDataBilingualCase("registration.editor.use-server-calculation",
         "Usar o cálculo do Performe AI", "Use the Performe AI calculation"),
        SampleDataBilingualCase("registration.editor.user-kcal.cleared",
         "Para voltar ao cálculo do Performe AI, toque em “Usar o cálculo do Performe AI”.",
         "To go back to the Performe AI calculation, tap “Use the Performe AI calculation”."),
        SampleDataBilingualCase("onboarding.welcome.app-language.detail",
         "Idioma definido para esta conta.", "Language set for this account."),
        SampleDataBilingualCase("onboarding.welcome.time-zone-picker.search", "Buscar cidade ou região", "Search city or region"),
        SampleDataBilingualCase("progress.block.action.detail", "Ver o andamento do bloco", "See the block's progress"),
        SampleDataBilingualCase("metric.reported-percentage", "Percentual do bloco", "Block percentage"),
        SampleDataBilingualCase("progress.block.percentage", "Percentual do bloco", "Block percentage"),
        SampleDataBilingualCase("metric.reported-progress", "Progresso", "Progress"),
        SampleDataBilingualCase("progress.metric.reported-deficit", "Déficit do bloco", "Block deficit"),
        SampleDataBilingualCase("today.summary.detail", "Ver os detalhes do dia", "View the day's details"),
        SampleDataBilingualCase("today.provenance.user-provided", "Informado por você", "Provided by you"),
        SampleDataBilingualCase("app.onboarding.loading", "Carregando seu cadastro", "Loading your setup"),
        SampleDataBilingualCase("app.onboarding.error.message",
         "Tente novamente para continuar seu cadastro.", "Try again to continue your setup."),
        SampleDataBilingualCase("onboarding.completion.message",
         "Confira suas escolhas antes de concluir seu cadastro.",
         "Review your choices before finishing your setup."),
        SampleDataBilingualCase("onboarding.documents-unavailable.message",
         "Não é possível concluir o cadastro sem os documentos oficiais atuais.",
         "Setup cannot be completed without the current official documents."),
        SampleDataBilingualCase("mascot.provenance",
         "O mascote acompanha o estado e a personalidade do seu Flow.",
         "The mascot follows your Flow's state and personality."),
        SampleDataBilingualCase("plan.draft.notice.edits-dropped",
         "O rascunho foi atualizado e o que você tinha digitado não foi aplicado. Revise a versão atual.",
         "The draft was updated and what you had typed was not applied. Review the current version."),
        SampleDataBilingualCase("auth.error.service-unavailable",
         "Não foi possível conectar agora. Tente novamente.", "Could not connect right now. Try again."),
        SampleDataBilingualCase("reminders.skipped.beyond_budget",
         "Depois do último horário coberto (agendados quando você abrir o app depois dos lembretes anteriores)",
         "After the last covered time (scheduled when you open the app after the earlier reminders)"),
        SampleDataBilingualCase("onboarding.welcome.country-picker.search", "Buscar país", "Search country"),
        SampleDataBilingualCase("profile.account.sign-out.confirm",
         "Sair desta conta neste iPhone? Seus dados continuam salvos na sua conta.",
         "Sign out of this account on this iPhone? Your data stays saved in your account."),
    ])
    func rewordedCopy(_ wording: SampleDataBilingualCase) throws {
        let key = String.LocalizationValue(wording.subject)
        #expect(try AppLocalization.string(key, for: Self.pt) == wording.portuguese)
        #expect(try AppLocalization.string(key, for: Self.en) == wording.english)
    }

    @Test("no catalog text speaks of servers, persistence or raw identifiers")
    func catalogHasNoDeveloperWording() throws {
        let data = try Data(contentsOf: Self.projectRoot.appendingPathComponent(
            "BodyFlow/Resources/Localizable.xcstrings"
        ))
        let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(strings.count > 900)

        let banned: [String: [String]] = [
            "pt-BR": ["servidor", "persistid", "detalhes recebidos", "onboarding",
                      "fornecidos pelo serviço", "definido pelo serviço", "pelo paciente",
                      "o serviço está", "próxima sincronização", "ou código"],
            "en": ["server", "received details", "by the service", "service set",
                   "by patient", "the service is", "later sync", "or code"],
        ]
        var offenders: [String] = []
        for (key, entry) in strings {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
            for (language, words) in banned {
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = try #require(unit?["value"] as? String, "\(key) has no \(language) text")
                for word in words where value.localizedCaseInsensitiveContains(word) {
                    offenders.append("\(key) [\(language)]: \(word)")
                }
                if value.contains("IANA") { offenders.append("\(key) [\(language)]: IANA") }
            }
        }
        #expect(offenders.isEmpty, "Developer wording in patient copy: \(offenders.sorted())")
    }

    // MARK: Support

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
    }

    static func realAccountDependencies(
        mobileAPISession: URLSession = .shared,
        sessionLifecycle: (any SessionLifecycleProviding)? = nil
    ) throws -> AppDependencies {
        AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: try MobileAPIConfiguration(
                    originString: "https://mobile.example.test"
                )
            ),
            mobileAPISession: mobileAPISession,
            supabaseAuthConfiguration: try SupabaseAuthConfiguration(
                originString: "https://project.example.test",
                key: "sb_publishable_synthetic"
            ),
            authenticationSessionStore: AuthenticationSessionStore(
                secureStore: InMemorySecureStore()
            ),
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) },
            sessionLifecycleOverride: sessionLifecycle
        )
    }

    /// The real sheet is drawn only after the same original lease has read Me.
    /// Protocol absence keeps this M1 fixture on the authenticated legacy path.
    private static func readyRealAccountWorkoutForm() async throws -> WorkoutForm {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let userID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let store = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(), now: { now }
        )
        // Unsigned synthetic subject-bearing fixture; never sent to an auth server.
        let payload = Data(#"{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let record = AuthenticationSessionRecord(
            userID: userID, email: "sample-data@example.invalid", isEmailConfirmed: true,
            isOnboardingCompleted: true, accessToken: "e30.\(payload).synthetic",
            refreshToken: "sample-data-synthetic-refresh", expiresAt: now.addingTimeInterval(3_600)
        )
        try await store.replace(with: record)
        let remote = SupabaseAuthRemoteClient(
            configuration: try SupabaseAuthConfiguration(
                originString: "https://project.example.test", key: "sb_publishable_synthetic"
            ),
            fetch: { _ in throw URLError(.notConnectedToInternet) }
        )
        let registry = PatientWorkRegistry()
        let lifecycle = SessionLifecycleCoordinator(
            store: store, remote: remote, patientWorkRegistry: registry,
            refreshPolicy: SessionRefreshPolicy(now: { now }, leeway: 60)
        )
        let originalLease = try await lifecycle.leaseForRequest()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [SampleDataWorkoutMeURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let dependencies = try realAccountDependencies(
            mobileAPISession: session, sessionLifecycle: lifecycle
        )
        #expect(dependencies.presentsRealAccountIdentity)
        #expect(dependencies.workoutRegistrationSessionSource != nil)
        let owner = Prompt14SessionOwner(userID: userID, dependencies: dependencies)
        let lifetime = MealRecordAuthenticationLifetime()
        do {
            let ticket = lifetime.beginAuthenticationBoundary()
            let published = lifetime.publishAuthenticated(userID: userID, ticket: ticket)
            let activation = try #require(published)
            let reservation = owner.reserveWorkoutRegistrationBinding(
                activation: activation, lifetime: lifetime,
                currentActivation: { lifetime.currentActivation }
            )
            let binding = try #require(reservation)
            #expect(owner.workoutRegistrationContext == nil)
            await owner.resolveWorkoutRegistration(binding)
            let publishedContext = owner.workoutRegistrationContext
            let context = try #require(publishedContext)
            #expect(context.isActive)
            #expect(context.activation == activation)
            #expect(context.registrationProtocol == nil)
            let captured = binding.capturedLease
            let capturedLease = try #require(captured)
            #expect(capturedLease == originalLease)
            try await lifecycle.validate(capturedLease)
            let admittedWork = await registry.activeCount
            #expect(admittedWork == 1)

            let form = try workoutForm(inSheetWith: dependencies, workoutOwner: owner)
            await lifetime.endSession()
            await owner.endSession()
            #expect(!context.isActive)
            let remainingWork = await registry.activeCount
            #expect(remainingWork == 0)
            return form
        } catch {
            // Join the same teardown before propagating; never launch detached cleanup.
            await lifetime.endSession()
            await owner.endSession()
            let remainingWork = await registry.activeCount
            #expect(remainingWork == 0)
            throw error
        }
    }

    static func document(key: String, purpose: String) -> OnboardingLegalDocument {
        OnboardingLegalDocument(
            documentKey: key,
            version: "2026-10-01.1",
            locale: "pt-BR",
            body: "Corpo do documento para o teste.",
            contentURL: nil,
            contentHash: String(repeating: "a", count: 64),
            purpose: purpose,
            action: .acceptance,
            required: true,
            effectiveAt: "2026-10-01T15:00:00.000Z"
        )
    }

    static func onboardingModel(
        step: OnboardingStep,
        documents: [OnboardingLegalDocument],
        countryCode: String? = nil,
        timeZoneIdentifier: String? = nil
    ) -> OnboardingFlowModel {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: step)
        if let countryCode { draft.countryCode = countryCode }
        if let timeZoneIdentifier { draft.timeZoneIdentifier = timeZoneIdentifier }
        return OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: draft,
            repository: InertOnboardingRepository(),
            personaRepository: InertPersonaRepository(),
            developmentConsentAvailability: .unavailable,
            requirements: documents.isEmpty
                ? .unavailable
                : OnboardingRequirements(available: true, blockingReason: nil, documents: documents),
            onStepChanged: { _ in },
            onCompleted: {}
        )
    }

    /// Height of the loaded day's scrolling content. `nil` leaves the view's
    /// own default in place.
    private static func todayContentHeight(showsDemonstrationSummaryLink: Bool?) async throws -> CGFloat {
        let model = TodayViewModel(provider: FixedTodayProvider())
        await model.load(revision: 0)
        #expect(model.state == .loaded(DemoBodyFlowFixtures.loadedToday.data))
        let center = FeatureInvalidationCenter()
        let today = showsDemonstrationSummaryLink.map {
            TodayRootView(model: model, invalidationCenter: center, showsDemonstrationSummaryLink: $0)
        } ?? TodayRootView(model: model, invalidationCenter: center)
        // Without a navigation container the links are inert but drawn, and
        // the whole day sits in one hosting view.
        let view = today
            .environment(AppRouter())
            .installAppDependencies(AppDependencies.scaffold())
            .environment(\.bodyFlowReduceMotion, true)
            .environment(\.locale, Locale(identifier: "pt_BR"))
        return try hosted(view, height: 800) { root in
            var heights: [CGFloat] = []
            @MainActor func collect(_ view: UIView) {
                if let scroll = view as? UIScrollView { heights.append(scroll.contentSize.height) }
                view.subviews.forEach(collect)
            }
            collect(root)
            return try #require(heights.max())
        }
    }

    struct WorkoutForm {
        let type: String
        let duration: String
        let proposeEnabled: Bool
    }

    private static func workoutForm(
        presentsLocalDemonstration: Bool,
        initialProposal: WorkoutProposalRequest? = nil
    ) throws -> WorkoutForm {
        try workoutForm(in: WorkoutRegistrationView(
            initialPerformedAt: Date(timeIntervalSince1970: 1_790_000_000),
            initialProposal: initialProposal,
            presentsLocalDemonstration: presentsLocalDemonstration,
            isSubmitting: false,
            submit: { _ in }
        ))
    }

    /// What the real account's workout form reads as, in one language.
    private static func workoutFormTree(
        language: SupportedAppLanguage,
        initialProposal: WorkoutProposalRequest?
    ) -> AccessibilityTree {
        accessibilityTree(
            WorkoutRegistrationView(
                initialPerformedAt: Date(timeIntervalSince1970: 1_790_000_000),
                initialProposal: initialProposal,
                presentsLocalDemonstration: false,
                isSubmitting: false,
                submit: { _ in }
            )
            .environment(\.locale, language.formattingLocale),
            height: 800
        )
    }

    /// The workout form as the Register sheet itself draws it.
    private static func workoutForm(
        inSheetWith dependencies: AppDependencies,
        workoutOwner: Prompt14SessionOwner? = nil
    ) throws -> WorkoutForm {
        if dependencies.presentsRealAccountIdentity {
            let owner = try #require(workoutOwner)
            return try workoutForm(in: WorkoutRegistrationSessionSheet(
                sheet: .registration(.training), owner: owner, dependencies: dependencies,
                invalidationCenter: FeatureInvalidationCenter()
            )
            .environment(AppRouter())
            .installAppDependencies(dependencies))
        }
        return try workoutForm(in: RegistrationSheet(
            sheet: .registration(.training),
            dependencies: dependencies,
            invalidationCenter: FeatureInvalidationCenter()
        )
        .environment(AppRouter())
        .installAppDependencies(dependencies))
    }

    private static func workoutForm<V: View>(in view: V) throws -> WorkoutForm {
        let view = view.environment(\.locale, Locale(identifier: "pt_BR"))
        return try hosted(view, height: 800) { root in
            var fields: [String: String] = [:]
            var proposeEnabled: Bool?
            @MainActor func collect(_ view: UIView) {
                if let field = view as? UITextField, let identifier = field.accessibilityIdentifier {
                    fields[identifier] = field.text ?? ""
                }
                if let button = view as? UIButton,
                   button.accessibilityIdentifier == "registration.workout.propose" {
                    proposeEnabled = button.isEnabled
                }
                view.subviews.forEach(collect)
            }
            collect(root)
            let type = try #require(fields["registration.workout.type"])
            let duration = try #require(fields["registration.workout.duration"])
            let isEnabled = try #require(proposeEnabled as Bool?)
            return WorkoutForm(type: type, duration: duration, proposeEnabled: isEnabled)
        }
    }

    struct AccessibilityTree {
        var labels: [String] = []
        var identifiers: Set<String> = []
    }

    static func accessibilityTree<V: View>(_ view: V, height: CGFloat) -> AccessibilityTree {
        let result: AccessibilityTree? = try? hosted(
            view.environment(\.accessibilityEnabled, true),
            height: height
        ) { root in
            UIAccessibility.post(notification: .screenChanged, argument: root)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            var tree = AccessibilityTree()
            var visited: Set<ObjectIdentifier> = []
            @MainActor func collect(_ object: NSObject, depth: Int = 0) {
                guard depth < 48, visited.insert(ObjectIdentifier(object)).inserted else { return }
                let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
                if object.responds(to: identifierSelector),
                   let identifier = object.perform(identifierSelector)?.takeUnretainedValue() as? String,
                   !identifier.isEmpty {
                    tree.identifiers.insert(identifier)
                }
                if object.isAccessibilityElement, let label = object.accessibilityLabel, !label.isEmpty {
                    tree.labels.append(label)
                }
                if let elements = object.accessibilityElements {
                    for case let element as NSObject in elements { collect(element, depth: depth + 1) }
                } else {
                    let count = object.accessibilityElementCount()
                    if count > 0 && count < 2_000 {
                        for index in 0..<count {
                            if let element = object.accessibilityElement(at: index) as? NSObject {
                                collect(element, depth: depth + 1)
                            }
                        }
                    }
                }
                if let nativeView = object as? UIView {
                    nativeView.subviews.forEach { collect($0, depth: depth + 1) }
                }
            }
            collect(root)
            return tree
        }
        return result ?? AccessibilityTree()
    }

    static func hosted<V: View, Result>(
        _ view: V,
        height: CGFloat,
        _ read: @MainActor (UIView) throws -> Result
    ) throws -> Result {
        let width: CGFloat = 390
        let host = UIHostingController(rootView: view.frame(width: width).ignoresSafeArea())
        host.traitOverrides.preferredContentSizeCategory = .large
        host.traitOverrides.userInterfaceStyle = .light
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first { $0.isKeyWindow }
        let window = try #require(keyWindow)
        window.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        defer { host.view.removeFromSuperview() }
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        return try read(host.view)
    }
}

/// One subject with what it reads as in pt-BR and in en.
struct SampleDataBilingualCase: Sendable, CustomTestStringConvertible {
    let subject: String
    let portuguese: String
    let english: String

    init(_ subject: String, _ portuguese: String, _ english: String) {
        self.subject = subject
        self.portuguese = portuguese
        self.english = english
    }

    var testDescription: String { subject.isEmpty ? "(empty)" : subject }
}

/// A workout proposal opened in the form, and whether it may be proposed.
struct WorkoutFormCase: Sendable, CustomTestStringConvertible {
    let workoutType: String
    let durationMin: Int
    let canPropose: Bool

    init(_ workoutType: String, _ durationMin: Int, _ canPropose: Bool) {
        self.workoutType = workoutType
        self.durationMin = durationMin
        self.canPropose = canPropose
    }

    var testDescription: String { "\(workoutType.count) characters, \(durationMin) min" }
}

/// A workout proposal opened in the form, and the help lines it must show.
struct WorkoutHelpCase: Sendable, CustomTestStringConvertible {
    let workoutType: String
    let durationMin: Int
    let showsTypeHelp: Bool
    let showsDurationHelp: Bool

    init(_ workoutType: String, _ durationMin: Int, type: Bool = false, duration: Bool = false) {
        self.workoutType = workoutType
        self.durationMin = durationMin
        showsTypeHelp = type
        showsDurationHelp = duration
    }

    var testDescription: String { "\(workoutType.count) characters, \(durationMin) min" }
}

private struct FixedTodayProvider: TodayProviding {
    func today() async throws -> TodayResponse { DemoBodyFlowFixtures.loadedToday }
}

private actor InertOnboardingRepository: OnboardingRepository {
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

private actor InertPersonaRepository: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }
    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}

/// Local URLSession boundary only. No global URLProtocol registration or mutable handler.
private final class SampleDataWorkoutMeURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.scheme == "https", url.host == "mobile.example.test",
              url.path == "/api/mobile/v1/me", request.httpMethod == "GET",
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        // Exact absence of workout_registration_protocol: authenticated M1 legacy, not demo.
        let body = Data(#"{"data":{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","timezone":"America/Sao_Paulo"},"meta":{"api_version":"v1","request_id":"sample-data-workout-me"}}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
