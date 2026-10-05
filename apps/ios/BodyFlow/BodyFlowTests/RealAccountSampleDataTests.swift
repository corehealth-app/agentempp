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

    @Test("the rendered form: empty fields and a disabled action on a real account")
    func realAccountWorkoutFormIsRenderedEmpty() throws {
        let form = try Self.workoutForm(presentsLocalDemonstration: false)
        #expect(form.type == "")
        #expect(form.duration == "")
        #expect(!form.proposeEnabled)
    }

    @Test("the rendered form: sample values and an enabled action in the demonstration")
    func demonstrationWorkoutFormIsRenderedPrefilled() throws {
        let form = try Self.workoutForm(presentsLocalDemonstration: true)
        #expect(form.type == "musculacao")
        #expect(form.duration == "47")
        #expect(form.proposeEnabled)
    }

    @Test("the sheet hands the form the same account kind as the rest of Register")
    func sheetThreadsTheAccountKindIntoTheWorkoutForm() throws {
        let sheet = try Self.source("BodyFlow/Features/Register/RegistrationSheet.swift")
        #expect(sheet.contains(
            "cancel: { perform(.cancel) { await workoutModel.cancel() } },\n"
                + "                        presentsLocalDemonstration: presentsLocalDemonstration\n"
        ))
        #expect(sheet.contains(
            "initialPerformedAt: model.initialPerformedAt,\n"
                + "                presentsLocalDemonstration: presentsLocalDemonstration,\n"
                + "                isSubmitting: model.isSubmitting, submit: propose"
        ))
        let form = try Self.source("BodyFlow/Features/Register/WorkoutRegistrationView.swift")
        #expect(form.contains("presentsLocalDemonstration: Bool = false"))
    }

    // MARK: Onboarding · legal documents

    @Test("a legal document is titled by its kind, in both languages", arguments: [
        SampleDataBilingualCase("terms_of_service", "Termos de uso", "Terms of use"),
        SampleDataBilingualCase("qa_terms_notice", "Termos de uso", "Terms of use"),
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
        let document = Self.document(key: "terms_of_service", purpose: "account_terms_acceptance")
        for language in SupportedAppLanguage.allCases {
            let presentation = OnboardingLegalDocumentPresentation(document: document, language: language)
            #expect(presentation.title == (language == Self.pt ? "Termos de uso" : "Terms of use"))
            #expect(presentation.body == "Corpo do documento para o teste.")
            #expect(!presentation.visibleText.contains(document.purpose))
            #expect(!presentation.visibleText.contains(document.documentKey))
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
        #expect(labels.contains { $0.contains("America/New_York") })
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
                      "fornecidos pelo serviço", "definido pelo serviço", "pelo paciente"],
            "en": ["server", "received details", "by the service", "service set",
                   "by patient"],
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

    private static func realAccountDependencies() throws -> AppDependencies {
        AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: try MobileAPIConfiguration(
                    originString: "https://mobile.example.test"
                )
            ),
            supabaseAuthConfiguration: try SupabaseAuthConfiguration(
                originString: "https://project.example.test",
                key: "sb_publishable_synthetic"
            ),
            authenticationSessionStore: AuthenticationSessionStore(
                secureStore: InMemorySecureStore()
            ),
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) }
        )
    }

    private static func document(key: String, purpose: String) -> OnboardingLegalDocument {
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

    private static func onboardingModel(
        step: OnboardingStep,
        documents: [OnboardingLegalDocument]
    ) -> OnboardingFlowModel {
        OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: step),
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

    private struct WorkoutForm {
        let type: String
        let duration: String
        let proposeEnabled: Bool
    }

    private static func workoutForm(presentsLocalDemonstration: Bool) throws -> WorkoutForm {
        let view = WorkoutRegistrationView(
            initialPerformedAt: Date(timeIntervalSince1970: 1_790_000_000),
            presentsLocalDemonstration: presentsLocalDemonstration,
            isSubmitting: false,
            submit: { _ in }
        )
        .environment(\.locale, Locale(identifier: "pt_BR"))
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

    private struct AccessibilityTree {
        var labels: [String] = []
        var identifiers: Set<String> = []
    }

    private static func accessibilityTree<V: View>(_ view: V, height: CGFloat) -> AccessibilityTree {
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

    private static func hosted<V: View, Result>(
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
