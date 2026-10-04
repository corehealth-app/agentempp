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
        for facts in [allFacts, noFacts] {
            for step in GuidedTutorialContent.steps(facts: facts) {
                keys.insert(step.titleKey)
                keys.formUnion(step.lineKeys)
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
