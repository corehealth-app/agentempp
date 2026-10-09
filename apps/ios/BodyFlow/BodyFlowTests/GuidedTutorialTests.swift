import Foundation
import Testing

@testable import BodyFlow

@Suite("Guided tutorial")
struct GuidedTutorialTests {
    private let allFacts = GuidedTutorialFacts(
        mealMedia: true, planDrafts: true, planImport: true, reminders: true, realAccount: true
    )
    private let noFacts = GuidedTutorialFacts(
        mealMedia: false, planDrafts: false, planImport: false, reminders: false, realAccount: false
    )

    private var chromeKeys: [String] {
        [
            "tutorial.navigation.title", "tutorial.close", "tutorial.later",
            "tutorial.start", "tutorial.back", "tutorial.next", "tutorial.finish",
            "tutorial.areas.title",
            "profile.tutorial.title", "profile.tutorial.detail",
        ]
    }

    private func everyKey() -> Set<String> {
        var keys = Set(chromeKeys)
        for base in [allFacts, noFacts] {
            for objective in [false, true] {
                for reminders in [false, true] {
                    var facts = base
                    facts.currentObjective = objective
                    facts.reminders = reminders
                    for step in GuidedTutorialContent.steps(facts: facts) {
                        keys.insert(step.titleKey)
                        keys.formUnion(step.lineKeys)
                    }
                }
            }
        }
        return keys
    }

    @Test("Every tour text exists in Portuguese and English, with the public names only",
          arguments: SupportedAppLanguage.allCases)
    func everyTextIsReviewed(_ language: SupportedAppLanguage) throws {
        for key in everyKey() {
            let text = try AppLocalization.string(String.LocalizationValue(key), for: language)
            #expect(text != key, "Missing \(key) / \(language)")
            #expect(!text.isEmpty)
            #expect(!text.localizedCaseInsensitiveContains("BodyFlow"), "\(key)")
            #expect(!text.localizedCaseInsensitiveContains("Body Flow"), "\(key)")
            #expect(!text.contains("MPP"), "\(key)")
        }
        let position = GuidedTutorialCopy.stepPosition(2, of: 8, language: language)
        #expect(position == (language == .portugueseBrazil ? "Etapa 2 de 8" : "Step 2 of 8"))
    }

    @Test("Profile explains the available current objective in both tutorial presentations",
          arguments: [
            TutorialObjectiveCase(false, false, .portugueseBrazil, .textual),
            TutorialObjectiveCase(false, false, .portugueseBrazil, .spotlight, "tour.profile.body"),
            TutorialObjectiveCase(false, false, .englishUnitedStates, .textual),
            TutorialObjectiveCase(false, false, .englishUnitedStates, .spotlight, "tour.profile.body"),
            TutorialObjectiveCase(false, true, .portugueseBrazil, .textual),
            TutorialObjectiveCase(false, true, .portugueseBrazil, .spotlight, "tour.profile.body.reminders"),
            TutorialObjectiveCase(false, true, .englishUnitedStates, .textual),
            TutorialObjectiveCase(false, true, .englishUnitedStates, .spotlight, "tour.profile.body.reminders"),
            TutorialObjectiveCase(true, false, .portugueseBrazil, .textual),
            TutorialObjectiveCase(true, false, .portugueseBrazil, .spotlight, "tour.profile.body.objective"),
            TutorialObjectiveCase(true, false, .englishUnitedStates, .textual),
            TutorialObjectiveCase(true, false, .englishUnitedStates, .spotlight, "tour.profile.body.objective"),
            TutorialObjectiveCase(true, true, .portugueseBrazil, .textual),
            TutorialObjectiveCase(true, true, .portugueseBrazil, .spotlight, "tour.profile.body.reminders.objective"),
            TutorialObjectiveCase(true, true, .englishUnitedStates, .textual),
            TutorialObjectiveCase(true, true, .englishUnitedStates, .spotlight, "tour.profile.body.reminders.objective"),
          ])
    func profileObjectiveFollowsCapability(_ scenario: TutorialObjectiveCase) throws {
        let facts = GuidedTutorialFacts(
            mealMedia: true, planDrafts: true, planImport: true,
            reminders: scenario.reminders, realAccount: true,
            currentObjective: scenario.objective
        )
        let language = scenario.language
        let title = try AppLocalization.string("current-objective.title", for: language)
        #expect(title == (language == .portugueseBrazil ? "Seu objetivo" : "Your objective"))
        let consultation = language == .portugueseBrazil
            ? "Em “Seu objetivo” você consulta o objetivo e as metas disponíveis para esta conta."
            : "In “Your objective” you can view the objective and targets available for this account."
        let rendered: String

        switch scenario.presentation {
        case .textual:
            let steps = GuidedTutorialContent.steps(facts: facts)
            #expect(steps.map(\.area) == [.welcome, .today, .flow, .plan, .register, .progress, .routineLibrary, .profile])
            #expect(Set(steps.map(\.id)).count == 8)
            let profile = try #require(steps.first { $0.area == .profile })
            let objectiveKeys = profile.lineKeys.filter { $0 == "tutorial.profile.objective" }
            #expect(objectiveKeys.count == (scenario.objective ? 1 : 0))
            var expectedKeys = ["tutorial.profile.persona"]
            if scenario.objective { expectedKeys.append("tutorial.profile.objective") }
            if scenario.reminders { expectedKeys.append("tutorial.profile.reminders") }
            expectedKeys += ["tutorial.profile.replay", "tutorial.profile.sign-out"]
            #expect(profile.lineKeys == expectedKeys)
            let texts = try profile.lineKeys.map { key in
                let value = try AppLocalization.string(String.LocalizationValue(key), for: language)
                #expect(value != key && !value.isEmpty, "\(key) / \(language)")
                return value
            }
            rendered = texts.joined(separator: " ")
            #expect(profile.lineKeys.contains("tutorial.profile.reminders") == scenario.reminders)
            #expect(profile.lineKeys.contains("tutorial.profile.replay"))
            #expect(profile.lineKeys.contains("tutorial.profile.sign-out"))
        case .spotlight:
            let steps = GuidedTourContent.steps(facts: facts)
            #expect(steps.map(\.id) == ["welcome", "flow", "library", "register", "plan", "progress", "profile", "trail"])
            #expect(steps.map(\.target) == [nil, .flow, .library, .register, .planTab, .progressTab, .profileTab, nil])
            #expect(steps.allSatisfy { $0.tab == .today })
            let profile = try #require(steps.first { $0.id == "profile" })
            #expect(profile.target == .profileTab)
            #expect(profile.kind == .spotlight(.profileTab))
            let expectedBodyKey = try #require(scenario.expectedBodyKey)
            #expect(profile.bodyKey == expectedBodyKey)
            rendered = try AppLocalization.string(String.LocalizationValue(profile.bodyKey), for: language)
            #expect(rendered != profile.bodyKey && !rendered.isEmpty)
            let originalBody: String
            if language == .portugueseBrazil {
                originalBody = scenario.reminders
                    ? "O estilo do Flow, os lembretes neste iPhone, a sua conta e “Conhecer o app” para rever este passeio."
                    : "O estilo do Flow, a sua conta e “Conhecer o app” para rever este passeio."
            } else {
                originalBody = scenario.reminders
                    ? "Flow’s style, reminders on this iPhone, your account and “Get to know the app” to see this tour again."
                    : "Flow’s style, your account and “Get to know the app” to see this tour again."
            }
            #expect(rendered == originalBody + (scenario.objective ? " " + consultation : ""))
        }

        #expect(rendered.components(separatedBy: title).count - 1 == (scenario.objective ? 1 : 0))
        #expect(rendered.contains(consultation) == scenario.objective)
        let reminderMention = language == .portugueseBrazil ? "lembretes neste iPhone" : "reminders on this iPhone"
        #expect(rendered.localizedCaseInsensitiveContains(reminderMention) == scenario.reminders)
    }

    @Test("The tour covers the five areas and what lives inside Today, in a short order")
    func coversTheAreas() {
        let areas = GuidedTutorialContent.steps(facts: allFacts).map(\.area)
        // Flow lives in Today; the rest follows the tab bar (Plano before Registrar).
        #expect(areas == [.welcome, .today, .flow, .plan, .register, .progress, .routineLibrary, .profile])
        #expect(Set(GuidedTutorialContent.steps(facts: noFacts).map(\.id)).count == areas.count)
    }

    @Test("Lines that depend on a capability appear only with it")
    func linesFollowCapabilities() {
        func lines(_ facts: GuidedTutorialFacts) -> [String] {
            GuidedTutorialContent.steps(facts: facts).flatMap(\.lineKeys)
        }
        #expect(lines(allFacts).contains("tutorial.register.meal.capture"))
        #expect(!lines(allFacts).contains("tutorial.register.meal.text"))
        #expect(lines(noFacts).contains("tutorial.register.meal.text"))
        #expect(!lines(noFacts).contains("tutorial.register.meal.capture"))
        #expect(lines(allFacts).contains("tutorial.plan.review.import"))
        var draftsWithoutImport = allFacts
        draftsWithoutImport.planImport = false
        #expect(lines(draftsWithoutImport).contains("tutorial.plan.review"))
        #expect(!lines(draftsWithoutImport).contains("tutorial.plan.review.import"))
        // No drafts in this session: no suggestion, review or confirm lines.
        for key in ["tutorial.flow.suggestions", "tutorial.plan.review", "tutorial.plan.review.import",
                    "tutorial.plan.confirm"] {
            #expect(!lines(noFacts).contains(key), "\(key)")
        }
        // Weight and hydration are explained as saved on tap, always.
        #expect(lines(noFacts).contains("tutorial.register.direct"))
        #expect(lines(allFacts).contains("tutorial.profile.reminders"))
        #expect(!lines(noFacts).contains("tutorial.profile.reminders"))
        #expect(lines(allFacts).contains("tutorial.profile.sign-out"))
        #expect(!lines(noFacts).contains("tutorial.profile.sign-out"))
        // Replay is always explained: it is how the user comes back.
        #expect(lines(noFacts).contains("tutorial.profile.replay"))
    }

    @Test("The food line keeps exercise out; the day balance points to its caption instead of stating a rule per goal",
          arguments: SupportedAppLanguage.allCases)
    func balancesAreNotMixed(_ language: SupportedAppLanguage) throws {
        let food = try AppLocalization.string("tutorial.today.food", for: language)
        let net = try AppLocalization.string("tutorial.today.balance", for: language)
        let foodLabel = try AppLocalization.string("today.energy.food-remaining", for: language)
        let netLabel = try AppLocalization.string("today.energy.net-balance", for: language)
        #expect(food.contains(foodLabel))
        #expect(net.contains(netLabel))
        if language == .portugueseBrazil {
            #expect(food.contains("O exercício não entra"))
            #expect(netLabel == "Balanço do dia")
            #expect(net == "“Balanço do dia” mostra o balanço do dia inteiro. A legenda embaixo diz se o exercício entrou na conta.")
            #expect(!net.contains("Déficit líquido"))
            // The caption follows the server field; the client states no
            // rule per protocol.
            #expect(!net.contains("recomposição") && !net.contains("objetivos"))
        } else {
            #expect(food.contains("Exercise is not part"))
            #expect(netLabel == "Day balance")
            #expect(net == "“Day balance” shows the balance of the whole day. The caption below says whether exercise is counted.")
            #expect(!net.contains("Net deficit"))
            #expect(!net.contains("recomposition") && !net.contains("goals"))
        }
    }

    @Test("Offered on its own only on the first eligible entry")
    func offerRules() {
        #expect(GuidedTutorialOffer.shouldOffer(
            status: .notOffered, offersOnFirstEntry: true, isPresentingSheet: false, hasPendingRoute: false))
        #expect(!GuidedTutorialOffer.shouldOffer(
            status: .deferred, offersOnFirstEntry: true, isPresentingSheet: false, hasPendingRoute: false))
        #expect(!GuidedTutorialOffer.shouldOffer(
            status: .completed, offersOnFirstEntry: true, isPresentingSheet: false, hasPendingRoute: false))
        #expect(!GuidedTutorialOffer.shouldOffer(
            status: .notOffered, offersOnFirstEntry: false, isPresentingSheet: false, hasPendingRoute: false))
        #expect(!GuidedTutorialOffer.shouldOffer(
            status: .notOffered, offersOnFirstEntry: true, isPresentingSheet: true, hasPendingRoute: false))
        #expect(!GuidedTutorialOffer.shouldOffer(
            status: .notOffered, offersOnFirstEntry: true, isPresentingSheet: false, hasPendingRoute: true))
    }

    @Test("Closing is never finishing, and a replay closed early keeps an earlier completion")
    func statusAfterAnswers() {
        #expect(GuidedTutorialOffer.status(after: .finished, from: .notOffered) == .completed)
        #expect(GuidedTutorialOffer.status(after: .finished, from: .deferred) == .completed)
        #expect(GuidedTutorialOffer.status(after: .closedEarly, from: .notOffered) == .deferred)
        #expect(GuidedTutorialOffer.status(after: .closedEarly, from: .deferred) == .deferred)
        #expect(GuidedTutorialOffer.status(after: .closedEarly, from: .completed) == .completed)
    }

    @Test("A reminder closing the tour is not an answer: it is offered again")
    func interruptionKeepsStatus() {
        for status in [GuidedTutorialStatus.notOffered, .deferred, .completed] {
            #expect(GuidedTutorialOffer.status(after: .interrupted, from: status) == status)
        }
        #expect(GuidedTutorialOffer.shouldOffer(
            status: GuidedTutorialOffer.status(after: .interrupted, from: .notOffered),
            offersOnFirstEntry: true, isPresentingSheet: false, hasPendingRoute: false))
    }

    @Test("Each account keeps its own answer on the same iPhone")
    func storeIsolatesAccounts() {
        let store = InMemoryGuidedTutorialStore()
        let accountA = LocalReminderPlanner.ownerKey(for: "qa-account-a")
        let accountB = LocalReminderPlanner.ownerKey(for: "qa-account-b")
        #expect(accountA != accountB)
        store.setStatus(.completed, ownerKey: accountA)
        #expect(store.status(ownerKey: accountA) == .completed)
        #expect(store.status(ownerKey: accountB) == .notOffered)
    }

    @Test("The persisted key holds only the owner hash, never the account id")
    func persistedKeyHasNoAccountID() {
        let ownerKey = LocalReminderPlanner.ownerKey(for: "user-123@example.com")
        let key = UserDefaultsGuidedTutorialStore.key(ownerKey)
        #expect(key == "pai.tutorial.v1.\(ownerKey)")
        #expect(!key.contains("user-123"))
    }

    @Test("Next and Back stay within the tour")
    func progressBounds() {
        var progress = GuidedTutorialProgress(stepCount: 3)
        #expect(progress.isFirst && !progress.isLast)
        progress.back()
        #expect(progress.index == 0)
        progress.next(); progress.next(); progress.next()
        #expect(progress.index == 2 && progress.isLast)
        progress.back()
        #expect(progress.index == 1)
        progress.jump(to: 9)
        #expect(progress.index == 2)
        progress.jump(to: -1)
        #expect(progress.index == 0)
    }
}

/// Explicit cases keep the contract oracle independent from both content builders.
enum TutorialObjectivePresentation: String, Sendable {
    case textual, spotlight
}

struct TutorialObjectiveCase: Sendable, CustomTestStringConvertible {
    let objective: Bool
    let reminders: Bool
    let language: SupportedAppLanguage
    let presentation: TutorialObjectivePresentation
    let expectedBodyKey: String?

    init(_ objective: Bool, _ reminders: Bool, _ language: SupportedAppLanguage,
         _ presentation: TutorialObjectivePresentation, _ expectedBodyKey: String? = nil) {
        self.objective = objective
        self.reminders = reminders
        self.language = language
        self.presentation = presentation
        self.expectedBodyKey = expectedBodyKey
    }

    var testDescription: String {
        "objective-\(objective ? 1 : 0)_reminders-\(reminders ? 1 : 0)_\(language.rawValue)_\(presentation.rawValue)"
    }
}
