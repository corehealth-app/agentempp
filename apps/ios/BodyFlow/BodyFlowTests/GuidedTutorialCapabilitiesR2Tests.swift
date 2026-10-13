// PRIVATE TEST CANDIDATE — no checkout implementation and no execution.
// Root may adopt as BodyFlowTests/GuidedTutorialCapabilitiesR2Tests.swift.
// Only production APIs already present are used, so RED must be assertion
// failures, not a missing proposed member or a deliberately uncompilable test.
// R2 selected behavior and capability provenance are documented in PLAN-R2.md.
import Foundation
import Testing

@testable import BodyFlow

@Suite("Guided tutorial capability and practical coverage")
struct GuidedTutorialCapabilitiesR2Tests {
    private func facts(drafts: Bool = true, importing: Bool = true,
                       media: Bool = true) -> GuidedTutorialFacts {
        GuidedTutorialFacts(
            mealMedia: media, planDrafts: drafts, planImport: importing,
            reminders: true, realAccount: true, showsBlock7700: false,
            currentObjective: true
        )
    }

    private func localized(_ key: String, language: SupportedAppLanguage) throws -> String {
        let result = try AppLocalization.string(String.LocalizationValue(key), for: language)
        #expect(result != key && !result.isEmpty, "Missing display text: \(key) / \(language)")
        return result
    }

    private func spotlight(_ id: String, facts: GuidedTutorialFacts,
                           language: SupportedAppLanguage) throws -> String {
        let step = try #require(GuidedTourContent.steps(facts: facts).first { $0.id == id })
        return try localized(step.bodyKey, language: language)
    }

    private func textual(_ area: GuidedTutorialStep.Area, facts: GuidedTutorialFacts,
                         language: SupportedAppLanguage) throws -> String {
        let step = try #require(GuidedTutorialContent.steps(facts: facts).first { $0.area == area })
        return try step.lineKeys.map { try localized($0, language: language) }.joined(separator: "\n")
    }

    // These expectations are independently chosen from the real controls,
    // not generated from another content builder or production copy helper.
    private func contains(_ pieces: [String], in actual: String) {
        for piece in pieces {
            #expect(actual.localizedCaseInsensitiveContains(piece),
                    "Missing practical explanation '\(piece)' in display text: \(actual)")
        }
    }

    private func excludes(_ pieces: [String], from actual: String) {
        for piece in pieces {
            #expect(!actual.localizedCaseInsensitiveContains(piece),
                    "Unavailable capability promised by '\(piece)': \(actual)")
        }
    }

    // Exact bug: planDrafts=false, planImport=false. The current visual
    // fallback says "sugestões do Flow em Para revisar" in both languages.
    @Test("No draft capability never promises suggestions, review queue or import",
          arguments: SupportedAppLanguage.allCases)
    func noDraftCapabilityDoesNotPromiseUnavailableActions(_ language: SupportedAppLanguage) throws {
        for importing in [false, true] {
            // Draft capability has precedence even for an inconsistent synthetic facts tuple.
            let unavailable = facts(drafts: false, importing: importing, media: false)
            let forbidden = language == .portugueseBrazil
                ? ["sugest", "Para revisar", "import", "foto", "PDF"]
                : ["suggest", "To review", "import", "photo", "PDF"]
            let current = language == .portugueseBrazil ? ["atuais", "treino", "alimentação"]
                : ["current", "workout", "nutrition"]
            for actual in [try spotlight("plan", facts: unavailable, language: language),
                           try textual(.plan, facts: unavailable, language: language)] {
                contains(current, in: actual)
                excludes(forbidden, from: actual)
            }
        }
    }

    // Wrong-branch regression: draft capability exists without an uploader.
    // Suggestions may be explained; import must not appear in this session.
    @Test("Draft-only sessions explain review and confirmation without import",
          arguments: SupportedAppLanguage.allCases)
    func draftOnlySessionKeepsReviewAndConfirmation(_ language: SupportedAppLanguage) throws {
        let available = facts(drafts: true, importing: false, media: false)
        let expected = language == .portugueseBrazil
            ? ["Para revisar", "confirma"] : ["To review", "confirm"]
        let forbidden = language == .portugueseBrazil
            ? ["Importar plano", "foto", "PDF"] : ["Import plan", "photo", "PDF"]
        for actual in [try spotlight("plan", facts: available, language: language),
                       try textual(.plan, facts: available, language: language)] {
            contains(expected, in: actual)
            excludes(forbidden, from: actual)
        }
    }

    // User-visible gap: the spotlight trail never explains food vs. daily
    // balance, the real refresh controls, or where confirmed records live.
    @Test("Both presentations explain Today balances, refresh and History",
          arguments: SupportedAppLanguage.allCases)
    func bothPresentationsExplainToday(_ language: SupportedAppLanguage) throws {
        let available = facts()
        let expected = language == .portugueseBrazil
            ? ["Restam para comida", "O exercício não entra nessa conta", "Balanço do dia",
               "legenda", "atualizar", "puxe", "Mais detalhes", "Histórico"]
            : ["Remaining for food", "Exercise is not part of this number", "Day balance",
               "caption", "refresh", "pull", "More details", "History"]
        for actual in [try spotlight("trail", facts: available, language: language),
                       try textual(.today, facts: available, language: language)] {
            contains(expected, in: actual)
        }
    }

    // User-visible gap: no routine explanation exists in the spotlight.
    @Test("Both presentations explain existing Routine and its timed actions",
          arguments: SupportedAppLanguage.allCases)
    func bothPresentationsExplainRoutine(_ language: SupportedAppLanguage) throws {
        let available = facts()
        let expected = language == .portugueseBrazil
            ? ["Rotina", "suplementos", "medicamentos", "horário", "marcar", "adiar", "pular"]
            : ["Routine", "supplements", "medications", "time", "mark", "snooz", "skip"]
        for actual in [try spotlight("library", facts: available, language: language),
                       try textual(.routineLibrary, facts: available, language: language)] {
            contains(expected, in: actual)
        }
    }

    // A person must distinguish proposal confirmation from direct save.
    @Test("Both presentations distinguish proposal review from direct records",
          arguments: SupportedAppLanguage.allCases)
    func bothPresentationsExplainRegistrationConfirmation(_ language: SupportedAppLanguage) throws {
        let available = facts()
        let expected = language == .portugueseBrazil
            ? ["refeição", "treino", "proposta", "revise", "confirmar",
               "Registrar peso", "Registrar hidratação"]
            : ["meal", "workout", "proposal", "review", "confirm",
               "Record weight", "Record hydration"]
        for actual in [try spotlight("register", facts: available, language: language),
                       try textual(.register, facts: available, language: language)] {
            contains(expected, in: actual)
        }
    }

    // Positive + negative capability guards use only the registration area;
    // the Plan area's photo import must never satisfy a meal-media assertion.
    @Test("Both presentations offer meal media only when actually available",
          arguments: SupportedAppLanguage.allCases)
    func mealCaptureModalitiesFollowCapability(_ language: SupportedAppLanguage) throws {
        let withMedia = facts(media: true)
        let withoutMedia = facts(media: false)
        let text = language == .portugueseBrazil ? "texto" : "text"
        let mediaTerms = language == .portugueseBrazil ? ["foto", "áudio"] : ["photo", "audio"]
        for actual in [try spotlight("register", facts: withMedia, language: language),
                       try textual(.register, facts: withMedia, language: language)] {
            contains([text] + mediaTerms, in: actual)
        }
        for actual in [try spotlight("register", facts: withoutMedia, language: language),
                       try textual(.register, facts: withoutMedia, language: language)] {
            contains([text], in: actual)
            excludes(mediaTerms, from: actual)
        }
    }

    // User-visible gap: importing is mentioned, but its domain choice and
    // draft review/edit/discard before confirmation are not explained.
    @Test("Available import is explained as a draft to review before confirmation",
          arguments: SupportedAppLanguage.allCases)
    func bothPresentationsExplainPlanImport(_ language: SupportedAppLanguage) throws {
        let available = facts()
        let expected = language == .portugueseBrazil
            ? ["Importar plano", "treino", "alimentação", "foto", "PDF", "rascunho",
               "revis", "ajust", "descart", "confirm"]
            : ["Import plan", "workout", "nutrition", "photo", "PDF", "draft",
               "review", "adjust", "discard", "confirm"]
        for actual in [try spotlight("plan", facts: available, language: language),
                       try textual(.plan, facts: available, language: language)] {
            contains(expected, in: actual)
        }
    }

    // Preservation guard: a late callback from an invalidated shell may not
    // record completion for that account or a subsequent session.
    @MainActor
    @Test("An inactive presentation cannot record a tutorial answer")
    func invalidatedSessionCannotWriteCompletion() {
        let store = InMemoryGuidedTutorialStore()
        let ownerA = LocalReminderPlanner.ownerKey(for: "tutorial-private-test-a")
        let ownerB = LocalReminderPlanner.ownerKey(for: "tutorial-private-test-b")
        store.setStatus(.deferred, ownerKey: ownerA)
        let recorded = GuidedTutorialOffer.record(.finished, ownerKey: ownerA, store: store,
                                                  sessionIsActive: false)
        #expect(!recorded)
        #expect(store.status(ownerKey: ownerA) == .deferred)
        #expect(store.status(ownerKey: ownerB) == .notOffered)
    }

    @Test("The same eight IDs, targets and order survive every capability branch")
    func existingStructuresArePreserved() {
        for drafts in [false, true] {
            for importing in [false, true] {
                for media in [false, true] {
                    let session = facts(drafts: drafts, importing: importing, media: media)
                    let visual = GuidedTourContent.steps(facts: session)
                    #expect(visual.map(\.id) == ["welcome", "flow", "library", "register", "plan", "progress", "profile", "trail"])
                    #expect(visual.map(\.target) == [nil, .flow, .library, .register, .planTab, .progressTab, .profileTab, nil])
                    #expect(visual.allSatisfy { $0.tab == .today })
                    let text = GuidedTutorialContent.steps(facts: session)
                    #expect(text.map(\.area) == [.welcome, .today, .flow, .plan, .register, .progress, .routineLibrary, .profile])
                    #expect(Set(visual.map(\.id)).count == 8)
                    #expect(Set(text.map(\.id)).count == 8)
                }
            }
        }
    }

    @Test("Flow explains fill-before-send, retry and the limit of cancelling a wait",
          arguments: SupportedAppLanguage.allCases)
    func flowExplainsTheExistingOperations(_ language: SupportedAppLanguage) throws {
        for drafts in [false, true] {
            let session = facts(drafts: drafts, importing: false, media: false)
            let expected = language == .portugueseBrazil
                ? ["preenchem", "enviar", "Envio sem confirmação", "novamente", "não garante"]
                : ["fill", "send", "Delivery unconfirmed", "again", "does not guarantee"]
            for actual in [try spotlight("flow", facts: session, language: language),
                           try textual(.flow, facts: session, language: language)] {
                contains(expected, in: actual)
                if !drafts {
                    excludes(language == .portugueseBrazil ? ["sugestão de treino", "cardápio", "Para revisar"]
                             : ["workout suggestion", "meal plan suggestion", "To review"], from: actual)
                }
            }
        }
    }

    @Test("Progress explains dates, missing values and the actual calorie-bar tap",
          arguments: SupportedAppLanguage.allCases)
    func progressDoesNotInventDataOrAControl(_ language: SupportedAppLanguage) throws {
        let session = facts()
        let expected = language == .portugueseBrazil
            ? ["datas", "não está disponível", "nunca um número inventado", "barra de calorias", "dia"]
            : ["dates", "not available", "never a made-up number", "calorie bar", "day"]
        for actual in [try spotlight("progress", facts: session, language: language),
                       try textual(.progress, facts: session, language: language)] {
            contains(expected, in: actual)
            excludes(["7.700", "7,700"], from: actual)
        }
    }
}
