import Foundation
import Testing

@testable import BodyFlow

@Suite
struct LocalizationContractTests {
    @Test(arguments: SupportedAppLanguage.allCases)
    func reviewedE3CatalogCopyIsExact(_ language: SupportedAppLanguage) throws {
        let expected: [(String, String, String)] = [
            ("onboarding.objective.assigned.title", "Seu objetivo inicial", "Your starting objective"),
            ("onboarding.objective.about-gain", "Sobre o ganho de massa muscular", "About muscle gain"),
            ("onboarding.objective.unavailable", "Indisponível", "Unavailable"),
            ("onboarding.objective.checking", "Conferindo os objetivos disponíveis…", "Checking available objectives…"),
            ("onboarding.objective.retry", "Conferir novamente", "Check again"),
            ("onboarding.protocol-welcome.title", "Mensagem do Flow", "Message from Flow"),
            ("onboarding.protocol-welcome.continue", "Ir para Hoje", "Go to Today"),
            ("onboarding.objective.body-recomposition.detail", "Perder gordura com preservação ou ganho de massa muscular.", "Lose fat while preserving or gaining muscle."),
            ("onboarding.objective.maintenance.detail", "Manter o corpo atual.", "Maintain your current body."),
            ("onboarding.completion.unresolved", "O envio anterior ainda precisa ser confirmado. Tente novamente para conferir o resultado.", "Your previous submission still needs confirmation. Try again to check the result."),
            ("onboarding.completion.finish", "Concluir cadastro", "Finish sign-up"),
        ]
        for (key, pt, en) in expected {
            #expect(try AppLocalization.string(String.LocalizationValue(key), for: language) ==
                (language == .portugueseBrazil ? pt : en))
        }
    }

    /// First update after build 1.0 (3). The fallback accessor is used on
    /// purpose: a missing key reads as "" and fails the comparison, where
    /// `AppLocalization.string` would throw before any expectation ran.
    private func expectExactCopy(
        _ expected: [(String, String, String)],
        _ language: SupportedAppLanguage
    ) {
        for (key, pt, en) in expected {
            let localized = PremiumPresentationCopy.string(
                String.LocalizationValue(key),
                locale: language.formattingLocale,
                fallback: ""
            )
            #expect(
                localized == (language == .portugueseBrazil ? pt : en),
                "\(key) / \(language)"
            )
        }
    }

    /// The way out of the sign-up load error (reported on 2026-10-10 11:55).
    @Test(arguments: SupportedAppLanguage.allCases)
    func firstUpdateLoadErrorCopyIsExact(_ language: SupportedAppLanguage) {
        expectExactCopy([
            ("app.onboarding.error.team-account.title",
             "Use outro e-mail no app", "Use a different email in the app"),
            ("app.onboarding.error.team-account.message",
             "Este e-mail é do painel da equipe. O app precisa de um e-mail diferente. Saia desta conta e entre com outro e-mail.",
             "This email belongs to the team's panel. The app needs a different email. Sign out of this account and sign in with another email."),
            ("app.sign-out", "Sair da conta", "Sign out"),
        ], language)
    }

    /// The three ways of the meal card are buttons now: each says what it
    /// does, and "Foto" opens a step of its own.
    @Test(arguments: SupportedAppLanguage.allCases)
    func firstUpdateMealWaysCopyIsExact(_ language: SupportedAppLanguage) {
        expectExactCopy([
            ("registration.root.way.photo.hint",
             "Registrar a refeição por foto. Você confirma antes de salvar.",
             "Log the meal with a photo. You confirm before it is saved."),
            ("registration.root.way.text.hint",
             "Registrar a refeição por texto. Você confirma antes de salvar.",
             "Log the meal by writing. You confirm before it is saved."),
            ("registration.root.way.audio.hint",
             "Registrar a refeição por áudio. Você confirma antes de salvar.",
             "Log the meal by voice. You confirm before it is saved."),
            ("registration.live.photo.title", "Foto da refeição", "Meal photo"),
        ], language)
    }

    /// The one loading block of the meal analysis: a fixed title, the five
    /// stage lines that already existed (locks: their reviewed wording does
    /// not change) and the line of the calculation.
    @Test(arguments: SupportedAppLanguage.allCases)
    func firstUpdateMealAnalysisCopyIsExact(_ language: SupportedAppLanguage) {
        expectExactCopy([
            ("registration.live.analysis.title", "Analisando sua refeição", "Analyzing your meal"),
            ("registration.live.phase.calculating", "Calculando os valores…", "Calculating the values…"),
            // Locks.
            ("registration.live.phase.preparing", "Preparando o arquivo…", "Preparing the file…"),
            ("registration.live.phase.uploading", "Enviando…", "Uploading…"),
            ("registration.live.phase.analyzing", "Analisando a foto…", "Analyzing the photo…"),
            ("registration.live.phase.transcribing", "Transcrevendo o áudio…", "Transcribing the audio…"),
            ("registration.live.phase.reading", "Lendo os alimentos…", "Reading the foods…"),
            ("registration.live.cancel", "Cancelar", "Cancel"),
            ("brand.processing", "Processando", "Processing"),
        ], language)
    }

    // MARK: Second update (2026-10-10)

    /// A refused sign-up says why (reported by the physician on build
    /// 1.0 (3): an e-mail that already has an account read as "Não foi
    /// possível conectar agora. Tente novamente.").
    @Test(arguments: SupportedAppLanguage.allCases)
    func secondUpdateSignUpRefusalCopyIsExact(_ language: SupportedAppLanguage) {
        let refusals: [(String, AppPresentationError, String, String)] = [
            ("auth.error.email-already-registered", .emailAlreadyRegistered,
             "Este e-mail já tem uma conta. Use outro e-mail ou toque em “Já tenho uma conta”.",
             "This email already has an account. Use a different email or tap “I already have an account”."),
            ("auth.error.weak-password", .weakPassword,
             "Essa senha é fraca demais. Escolha uma senha mais longa e difícil de adivinhar.",
             "That password is too weak. Choose a longer one that is harder to guess."),
            ("auth.error.sign-up-rejected", .signUpRejected,
             "Não foi possível criar a conta. Confira o e-mail e a senha e tente novamente.",
             "Could not create the account. Check the email and password and try again."),
            ("auth.error.too-many-attempts", .tooManyAttempts,
             "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.",
             "Too many attempts in a short time. Wait a few minutes and try again."),
        ]
        expectExactCopy(refusals.map { ($0.0, $0.2, $0.3) }, language)
        let connection = language == .portugueseBrazil
            ? "Não foi possível conectar agora. Tente novamente."
            : "Could not connect right now. Try again."
        for (key, error, pt, en) in refusals {
            // What the banner reads is the catalog's text...
            #expect(error.authMessage(for: language) == (language == .portugueseBrazil ? pt : en), "\(key)")
            // ...its fallback is the same Portuguese sentence...
            #expect(error.authMessage == pt, "\(key)")
            // ...and it is never the connection message.
            #expect(error.authMessage(for: language) != connection, "\(key)")
        }
        // Lock: the connection message itself is unchanged.
        expectExactCopy([
            ("auth.error.service-unavailable",
             "Não foi possível conectar agora. Tente novamente.",
             "Could not connect right now. Try again."),
        ], language)
        #expect(AppPresentationError.serviceUnavailable.authMessage(for: language) == connection)
    }

    /// The banner points at a button: it must name it exactly as the button
    /// is written on the same screen.
    @Test(arguments: SupportedAppLanguage.allCases)
    func signUpTakenEmailCopyNamesTheRealButton(_ language: SupportedAppLanguage) {
        func catalog(_ key: String) -> String {
            PremiumPresentationCopy.string(
                String.LocalizationValue(key),
                locale: language.formattingLocale,
                fallback: ""
            )
        }
        let button = catalog("auth.sign-up.existing-account")
        #expect(button == (language == .portugueseBrazil ? "Já tenho uma conta" : "I already have an account"))
        let banner = catalog("auth.error.email-already-registered")
        #expect(
            banner.contains("“\(button)”"),
            "The banner must quote the button's own label: «\(banner)» / «\(button)»"
        )
    }

    /// The "eye" of the password fields: what its control says.
    @Test(arguments: SupportedAppLanguage.allCases)
    func secondUpdatePasswordVisibilityCopyIsExact(_ language: SupportedAppLanguage) {
        expectExactCopy([
            ("auth.password.show", "Mostrar senha", "Show password"),
            ("auth.password.hide", "Ocultar senha", "Hide password"),
            ("auth.password-confirmation.show",
             "Mostrar confirmação da senha", "Show password confirmation"),
            ("auth.password-confirmation.hide",
             "Ocultar confirmação da senha", "Hide password confirmation"),
        ], language)
    }

    /// The effort of a plan draft: its label, and the scale the app writes
    /// after a bare grade of a Flow suggestion (decisão do orquestrador,
    /// anunciada ao dono em 2026-10-10, que pode riscar qualquer uma).
    @Test(arguments: SupportedAppLanguage.allCases)
    func secondUpdateEffortCopyIsExact(_ language: SupportedAppLanguage) {
        expectExactCopy([
            ("plan.draft.detail.rpe", "Esforço", "Effort"),
            ("plan.draft.detail.rpe.scale-format", "%@ de 10", "%@ of 10"),
        ], language)
    }

    @Test(arguments: SupportedAppLanguage.allCases)
    func testEveryReviewedPublicCatalogKeyHasBothLanguages(
        _ language: SupportedAppLanguage
    ) throws {
        let reviewedKeys = [
            "onboarding.objective.assigned.title",
            "onboarding.objective.about-gain",
            "onboarding.objective.unavailable",
            "onboarding.objective.checking",
            "onboarding.objective.retry",
            "onboarding.protocol-welcome.title",
            "onboarding.protocol-welcome.continue",
            "onboarding.objective.body-recomposition.detail",
            "onboarding.objective.maintenance.detail",
            "onboarding.completion.unresolved",
            "onboarding.completion.finish",
            "onboarding.selection.placeholder",
            "onboarding.selection.selected",
            "onboarding.selection.not-selected",
            "onboarding.welcome.display-name.title",
            "onboarding.welcome.display-name.placeholder",
            "onboarding.welcome.app-language.title",
            "onboarding.welcome.app-language.detail",
            "onboarding.welcome.country.title",
            "onboarding.welcome.country-picker.title",
            "onboarding.welcome.country-picker.search",
            "onboarding.welcome.time-zone.title",
            "onboarding.welcome.time-zone-picker.title",
            "onboarding.welcome.time-zone-picker.search",
            "onboarding.body-data.biological-sex.title",
            "onboarding.body-data.birth-date.title",
            "onboarding.body-data.birth-date.select",
            "onboarding.body-data.height.title",
            "onboarding.body-data.weight.title",
            "onboarding.body-data.body-fat.title",
            "onboarding.body-data.body-fat.accessibility-label",
            "onboarding.body-data.optional",
            "onboarding.body-data.not-provided-format",
            "onboarding.biological-sex.masculine",
            "onboarding.biological-sex.feminine",
            "onboarding.objective.body-recomposition.title",
            "onboarding.objective.body-recomposition.detail",
            "onboarding.objective.muscle-gain.title",
            "onboarding.objective.muscle-gain.detail",
            "onboarding.objective.maintenance.title",
            "onboarding.objective.maintenance.detail",
            "onboarding.routine.activity-level.title",
            "onboarding.routine.activity-level.sedentary",
            "onboarding.routine.activity-level.light",
            "onboarding.routine.activity-level.moderate",
            "onboarding.routine.activity-level.high",
            "onboarding.routine.activity-level.athlete",
            "onboarding.routine.training-frequency.title",
            "onboarding.routine.training-frequency.set",
            "onboarding.routine.training-frequency.format",
            "onboarding.routine.water-intake.title",
            "onboarding.routine.water-intake.low",
            "onboarding.routine.water-intake.moderate",
            "onboarding.routine.water-intake.high",
            "onboarding.routine.hunger-level.title",
            "onboarding.routine.hunger-level.low",
            "onboarding.routine.hunger-level.moderate",
            "onboarding.routine.hunger-level.high",
            "onboarding.routine.wake-time.title",
            "onboarding.routine.bedtime.title",
            "onboarding.routine.select-time",
            "onboarding.routine.food-organization.title",
            "onboarding.routine.food-organization.unconfirmed",
            "onboarding.routine.food-organization.confirm-no",
            "onboarding.persona.focus.title",
            "onboarding.persona.focus.detail",
            "onboarding.persona.impulse.title",
            "onboarding.persona.impulse.detail",
            "onboarding.persona.zen.title",
            "onboarding.persona.zen.detail",
            "onboarding.consent.development.terms",
            "onboarding.consent.development.privacy",
            "onboarding.completion.name",
            "onboarding.completion.country",
            "onboarding.completion.time-zone",
            "onboarding.completion.objective",
            "onboarding.completion.training",
            "onboarding.completion.flow-style",
            "onboarding.completion.official-documents",
            "onboarding.completion.development-consent",
            "onboarding.completion.not-provided",
            "onboarding.completion.not-selected",
            "onboarding.completion.pending",
            "onboarding.completion.confirmed",
            "onboarding.completion.action-count.one",
            "onboarding.completion.action-count.other",
            "onboarding.completion.version-action-format",
            "onboarding.completion.action.acceptance",
            "onboarding.completion.action.acknowledgement",
            "onboarding.completion.action.consent",
            "today.energy.net-balance",
            "today.energy.net-balance.detail",
            "today.energy.net-balance.detail.activity-level",
            "today.energy.net-balance.value.deficit",
            "today.energy.net-balance.value.surplus",
            "today.energy.net-balance.accessibility",
            "today.energy.net-balance.accessibility.activity-level",
            "today.energy.net-balance.accessibility.deficit",
            "today.energy.net-balance.accessibility.surplus",
            "tutorial.today.balance",
            "registration.operation.already-confirmed",
            "today.recommendations.heading",
            "today.recommendations.library",
            "today.recommendations.empty",
            "today.recommendations.offline",
            "today.recommendations.error",
            "today.recommendations.unavailable",
            "today.provenance.confirmed",
            "today.provenance.estimate",
            "today.provenance.user-provided",
            "today.provenance.unknown",
            "mascot.persona.balanced",
            "markdown.list.ordered",
            "markdown.list.unordered",
            "markdown.list.item-format",
            "markdown.list.position-format",
            "markdown.link.external",
            "content.bounded.not-found",
            "content.bounded.subscription-required",
            "content.mutation.updating",
            "content.mutation.saved",
            "content.mutation.unsaved",
            "content.mutation.completed",
            "content.mutation.reloading",
            "content.mutation.error",
            "content.mutation.unavailable",
            "content.action.back",
            "content.action.library",
            "reminders.action.activate",
            "reminders.action.deactivate",
            "reminders.action.open-settings",
            "reminders.action.refresh",
            "reminders.coverage.sync-note",
            "reminders.coverage.until",
            "reminders.notification.category.content",
            "reminders.notification.category.hydration",
            "reminders.notification.category.meal",
            "reminders.notification.category.reengagement",
            "reminders.notification.category.reevaluation",
            "reminders.notification.category.workout",
            "reminders.notification.generic.body",
            "reminders.notification.generic.title",
            "reminders.notification.name.body",
            "reminders.notification.renewal.body",
            "reminders.notification.renewal.title",
            "reminders.privacy.name",
            "reminders.privacy.name_and_dose",
            "reminders.privacy.private",
            "reminders.screen.title",
            "reminders.silenced.note",
            "reminders.skipped.beyond_budget",
            "reminders.skipped.daily_limit",
            "reminders.skipped.no_reevaluation_date",
            "reminders.skipped.nonexistent_local_time",
            "reminders.skipped.not_accepted",
            "reminders.skipped.quiet_hours",
            "reminders.skipped.section",
            "reminders.status.loading",
            "reminders.status.none",
            "reminders.status.not-enabled",
            "reminders.status.permission-denied",
            "reminders.status.preferences-off",
            "reminders.status.scheduled",
            "reminders.status.time-zone-missing",
            "reminders.status.unavailable",
            "reminders.summary.attention",
            "reminders.summary.checking",
            "reminders.summary.denied",
            "reminders.summary.none",
            "reminders.summary.off",
            "reminders.summary.on",
            "profile.reminders.title",
            "profile.tutorial.title",
            "profile.tutorial.detail",
            // Second update (2026-10-10): a refused sign-up says why.
            "auth.error.email-already-registered",
            "auth.error.weak-password",
            "auth.error.sign-up-rejected",
            "auth.error.too-many-attempts",
            // Second update (2026-10-10): the eye of the password fields.
            "auth.password.show",
            "auth.password.hide",
            "auth.password-confirmation.show",
            "auth.password-confirmation.hide",
            // Second update (2026-10-10): the effort of a plan draft.
            "plan.draft.detail.rpe",
            "plan.draft.detail.rpe.scale-format",
        ]

        for key in reviewedKeys {
            let localized = try AppLocalization.string(
                String.LocalizationValue(key),
                for: language
            )
            #expect(localized != key, "Missing reviewed public copy: \(key) / \(language)")
        }
    }

    @Test(arguments: SupportedAppLanguage.allCases)
    func sharedStateCatalogIsCompleteAndReviewed(_ language: SupportedAppLanguage) throws {
        let keys = [
            "state.loading.title", "state.loading.detail",
            "state.empty.title", "state.empty.detail",
            "state.error.title", "state.error.detail",
            "state.offline.title", "state.offline.detail",
            "state.unavailable.title", "state.retry", "state.stale.detail",
        ]
        for key in keys {
            #expect(try AppLocalization.string(String.LocalizationValue(key), for: language) != key)
        }
        #expect(try AppLocalization.string("state.retry", for: language) ==
            (language == .portugueseBrazil ? "Tentar novamente" : "Try again"))
        #expect(try AppLocalization.string("state.stale.detail", for: language) ==
            (language == .portugueseBrazil
                ? "As informações podem estar desatualizadas."
                : "This information may be out of date."))
    }

    @Test
    func supportedLocaleSetsStayAligned() {
        let languageIdentifiers = Set(
            SupportedAppLanguage.allCases.map(\.rawValue)
        )

        #expect(languageIdentifiers == OnboardingLocalePolicy.supportedIdentifiers)
        #expect(languageIdentifiers == Set(ContentLocale.allCases.map(\.rawValue)))
    }

    @Test
    func reviewedConvergenceCopyIsNaturalAndPresentationAware() throws {
        #expect(TodayRecommendationsPresentation.heading(for: .portugueseBrazil) ==
            "Conteúdos para hoje")
        #expect(TodayRecommendationsPresentation.heading(for: .englishUnitedStates) ==
            "Today's content")
        #expect(TodayRecommendationsLibraryAction(language: .englishUnitedStates).title ==
            "View library")
        #expect(TodayNutritionProvenance.label(
            for: "canonical_exact",
            language: .englishUnitedStates
        ) == "Confirmed reference")
        #expect(TodayNutritionProvenance.label(
            for: "user_correction",
            language: .portugueseBrazil
        ) == "Informado por você")
        #expect(BodyFlowMarkdownLinkPolicy.accessibilityAnnouncement(
            for: .englishUnitedStates
        ) == "External link")
        #expect(BodyFlowMarkdownInlinePresentation.make(
            [.link(destination: "https://example.com", children: [.text("Guide")])],
            language: .englishUnitedStates
        ).accessibilityHint == "External link")
    }

    @Test
    func supportedLanguagesMapToCatalogFormattingAndContentLocales() {
        #expect(SupportedAppLanguage.portugueseBrazil.catalogLocalization == "pt-BR")
        #expect(SupportedAppLanguage.portugueseBrazil.formattingLocale.identifier == "pt_BR")
        #expect(SupportedAppLanguage.portugueseBrazil.contentLocale == .ptBR)

        #expect(SupportedAppLanguage.englishUnitedStates.catalogLocalization == "en")
        #expect(SupportedAppLanguage.englishUnitedStates.formattingLocale.identifier == "en_US")
        #expect(SupportedAppLanguage.englishUnitedStates.contentLocale == .enUS)
    }

    @Test(arguments: SupportedAppLanguage.allCases)
    func localizedBundleUsesTheRequestedCatalog(_ language: SupportedAppLanguage) throws {
        let localizedBundle = try AppLocalization.localizedBundle(for: language)

        #expect(localizedBundle.bundleURL.lastPathComponent == "\(language.catalogLocalization).lproj")
    }

    @Test(arguments: SupportedAppLanguage.allCases)
    func reviewedBrandCatalogIsComplete(_ language: SupportedAppLanguage) throws {
        switch language {
        case .portugueseBrazil:
            #expect(try AppLocalization.string(
                "brand.slogan",
                for: language
            ) == "Melhor a cada dia.")
            #expect(try AppLocalization.string(
                "brand.descriptor",
                for: language
            ) == "Sua jornada personalizada para uma vida mais saudável.")
            #expect(try AppLocalization.string(
                "brand.flow.role-line",
                for: language
            ) == "Flow, seu guia em cada etapa.")
            #expect(try AppLocalization.string(
                "brand.logo.accessibility-label",
                for: language
            ) == "Logo da Performe AI")
            #expect(try AppLocalization.string(
                "brand.logo.fallback.accessibility-label",
                for: language
            ) == "Performe AI")

        case .englishUnitedStates:
            #expect(try AppLocalization.string(
                "brand.slogan",
                for: language
            ) == "Better every day.")
            #expect(try AppLocalization.string(
                "brand.descriptor",
                for: language
            ) == "Your personalized journey to a healthier life.")
            #expect(try AppLocalization.string(
                "brand.flow.role-line",
                for: language
            ) == "Flow, your guide every step of the way.")
            #expect(try AppLocalization.string(
                "brand.logo.accessibility-label",
                for: language
            ) == "Performe AI logo")
            #expect(try AppLocalization.string(
                "brand.logo.fallback.accessibility-label",
                for: language
            ) == "Performe AI")
        }
    }

    @Test(arguments: SupportedAppLanguage.allCases)
    func reviewedAccessibilityCopyIsAvailable(_ language: SupportedAppLanguage) throws {
        let label = try AppLocalization.string(
            "brand.logo.accessibility-label",
            for: language
        )
        let fallbackLabel = try AppLocalization.string(
            "brand.logo.fallback.accessibility-label",
            for: language
        )

        #expect(label.contains("Performe AI"))
        #expect(fallbackLabel.contains("Performe AI"))
        #expect(!label.contains("BodyFlow"))
        #expect(!fallbackLabel.contains("BodyFlow"))
    }

    @Test(arguments: SupportedAppLanguage.allCases)
    func flowChatCatalogIsComplete(_ language: SupportedAppLanguage) throws {
        let keys = [
            "flow.open", "flow.title", "flow.empty.title", "flow.empty.detail",
            "flow.composer", "flow.send", "flow.cancel", "flow.retry",
            "flow.guidance", "flow.loading", "flow.responding",
            "flow.message.processing", "flow.message.failed",
            "flow.error.cancelled",
            "flow.error.offline", "flow.error.rate-limited",
            "flow.error.session", "flow.error.forbidden", "flow.error.generic",
            "flow.suggestions.title", "flow.suggestion.day", "flow.suggestion.dinner",
            "flow.suggestion.workout", "flow.suggestion.hint", "flow.suggestion.filled",
        ]

        for key in keys {
            let value = try AppLocalization.string(
                String.LocalizationValue(key),
                for: language
            )
            #expect(value != key)
        }
    }

    @Test
    func requestedLanguageOverridesTheOppositeProcessLanguage() throws {
        let fixture = try LocalizationFixture()
        defer { fixture.remove() }

        let processPrefersPortuguese = Locale.preferredLanguages.first?
            .hasPrefix("pt") == true
        let requestedLanguage: SupportedAppLanguage = processPrefersPortuguese
            ? .englishUnitedStates
            : .portugueseBrazil
        let expected = processPrefersPortuguese
            ? "Explicit English"
            : "Português explícito"
        let processLanguageOutput = processPrefersPortuguese
            ? "Português explícito"
            : "Explicit English"

        let output = try AppLocalization.string(
            "fixture.opposite-language",
            for: requestedLanguage,
            in: fixture.bundle
        )

        #expect(output == expected)
        #expect(output != processLanguageOutput)
    }

    @Test
    func dynamicPresentationStringsPreserveInterpolation() throws {
        let fixture = try LocalizationFixture()
        defer { fixture.remove() }
        let name = "Lia"
        let key: String.LocalizationValue = "presentation.greeting \(name)"

        #expect(try AppLocalization.string(
            key,
            for: .portugueseBrazil,
            in: fixture.bundle
        ) == "Olá, Lia!")
        #expect(try AppLocalization.string(
            key,
            for: .englishUnitedStates,
            in: fixture.bundle
        ) == "Hello, Lia!")
    }

    @Test
    func missingBrandKeyIsReportedByTheLocalizationContract() throws {
        let fixture = try LocalizationFixture()
        defer { fixture.remove() }

        #expect(throws: AppLocalizationError.missingLocalizedString(
            key: "brand.missing",
            language: .englishUnitedStates
        )) {
            try AppLocalization.string(
                "brand.missing",
                for: .englishUnitedStates,
                in: fixture.bundle
            )
        }
    }

    @Test
    func brandFallbackIsTheCompleteApprovedPortugueseCopy() throws {
        let fixture = try LocalizationFixture()
        defer { fixture.remove() }

        let output = BrandIdentity.copy(
            for: .englishUnitedStates,
            bundle: fixture.bundle
        )
        let combined = [output.slogan, output.descriptor, output.flowRoleLine]
            .joined(separator: " ")

        #expect(output == BrandCopy(
            slogan: "Melhor a cada dia.",
            descriptor: "Sua jornada personalizada para uma vida mais saudável.",
            flowRoleLine: "Flow, seu guia em cada etapa."
        ))
        #expect(combined.contains("Flow"))
        #expect(!combined.contains("BodyFlow"))
        #expect(!combined.contains("Coach"))
    }
}

private struct LocalizationFixture {
    let bundle: Bundle
    private let rootURL: URL

    init() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "BetterAheadLocalization-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "pt-BR",
            "CFBundleIdentifier": "com.betterahead.localization-fixture.\(UUID().uuidString)",
            "CFBundleLocalizations": ["pt-BR", "en"],
            "CFBundleName": "BetterAheadLocalizationFixture",
            "CFBundlePackageType": "BNDL",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: rootURL.appending(path: "Info.plist"))

        try Self.writeStrings(
            """
            "fixture.opposite-language" = "Português explícito";
            "presentation.greeting %@" = "Olá, %@!";
            """,
            localization: "pt-BR",
            rootURL: rootURL
        )
        try Self.writeStrings(
            """
            "fixture.opposite-language" = "Explicit English";
            "presentation.greeting %@" = "Hello, %@!";
            """,
            localization: "en",
            rootURL: rootURL
        )

        guard let bundle = Bundle(url: rootURL) else {
            throw LocalizationFixtureError.couldNotCreateBundle
        }

        self.bundle = bundle
        self.rootURL = rootURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func writeStrings(
        _ contents: String,
        localization: String,
        rootURL: URL
    ) throws {
        let localizationURL = rootURL.appending(
            path: "\(localization).lproj",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: localizationURL,
            withIntermediateDirectories: true
        )
        try contents.write(
            to: localizationURL.appending(path: "Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private enum LocalizationFixtureError: Error {
    case couldNotCreateBundle
}
