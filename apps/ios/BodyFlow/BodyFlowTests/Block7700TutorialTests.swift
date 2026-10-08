import Foundation
import Testing

@testable import BodyFlow

@Suite("Block eligibility in the guided tutorial")
struct Block7700TutorialTests {
    private let initialFacts = GuidedTutorialFacts(
        mealMedia: true, planDrafts: true, planImport: true, reminders: true, realAccount: true
    )

    @Test("unknown initial context offers all eight areas without a block promise", arguments: SupportedAppLanguage.allCases)
    func unknownInitialContext(_ language: SupportedAppLanguage) throws {
        let text = GuidedTutorialContent.steps(facts: initialFacts)
        #expect(text.map(\.id) == ["welcome", "today", "flow", "plan", "register", "progress", "routineLibrary", "profile"])
        let progress = try #require(text.first { $0.area == .progress })
        #expect(progress.lineKeys == ["tutorial.progress.body.without-block", "tutorial.progress.empty"])
        let tour = GuidedTourContent.steps(facts: initialFacts)
        #expect(tour.map(\.id) == ["welcome", "flow", "library", "register", "plan", "progress", "profile", "trail"])
        #expect(tour.first { $0.id == "progress" }?.bodyKey == "tour.progress.body.without-block")
        #expect(tour.last?.bodyKey == "tour.trail.body.without-block")
        for key in ["tutorial.progress.body.without-block", "tour.progress.body.without-block", "tour.trail.body.without-block"] {
            let copy = try AppLocalization.string(String.LocalizationValue(key), for: language)
            #expect(copy != key)
            #expect(!copy.contains("7.700") && !copy.contains("7,700"))
        }
    }

    @Test("the same running tour follows official unknown to recomposition to gain without losing position")
    @MainActor
    func activeTourUpdates() throws {
        let model = GuidedTourModel(steps: GuidedTourContent.steps(facts: initialFacts),
            origin: .profile, ownerKey: "a-current-session", returnTab: .profile, isSessionActive: { true })
        for _ in 0..<5 { model.next() }
        #expect(model.current.id == "progress")
        #expect(model.current.bodyKey == "tour.progress.body.without-block")
        var recomposition = initialFacts
        recomposition.showsBlock7700 = true
        model.updateFacts(recomposition, ownerKey: "a-current-session")
        #expect(model.current.bodyKey == "tour.progress.body")
        #expect(model.index == 5)
        model.updateFacts(initialFacts, ownerKey: "a-current-session")
        #expect(model.current.bodyKey == "tour.progress.body.without-block")
        #expect(model.steps.count == 8 && model.index == 5)
        #expect(model.ownerKey == "a-current-session" && model.returnTab == .profile)
        // Facts of another account are rejected without resetting the tour.
        model.updateFacts(recomposition, ownerKey: "b-other-account")
        #expect(model.current.bodyKey == "tour.progress.body.without-block")
        #expect(model.index == 5)
        for _ in 0..<2 { model.next() }
        #expect(model.current.id == "trail")
        #expect(model.current.bodyKey == "tour.trail.body.without-block")
    }

    @Test("block facts leave contextual tips intact")
    @MainActor
    func tipsRemainIntact() throws {
        let step = try #require(GuidedTourContent.tip(.mealCommand))
        let model = GuidedTourModel(steps: [step], origin: .tip, ownerKey: "a", returnTab: .register)
        var recomposition = initialFacts
        recomposition.showsBlock7700 = true
        model.updateFacts(recomposition, ownerKey: "a")
        #expect(model.steps == [step])
        #expect(model.isTip && model.isFirst && model.isLast)
    }

    @Test("QA A to B to A suppresses old tour facts and a late completion for the same owner hash")
    @MainActor
    func oldSessionCannotRecordForNewA() async throws {
        let coordinator = Prompt14AuthenticatedShellCoordinator(dependencies: AppDependencies.scaffold())
        let store = InMemoryGuidedTutorialStore()
        let keyA = LocalReminderPlanner.ownerKey(for: "qa-account-a")
        let keyB = LocalReminderPlanner.ownerKey(for: "qa-account-b")
        await coordinator.transition(to: "qa-account-a")
        let firstA = try #require(coordinator.renderableOwner)
        let oldTour = GuidedTourModel(steps: GuidedTourContent.steps(facts: initialFacts), origin: .profile,
            ownerKey: keyA, returnTab: .profile, isSessionActive: { [weak firstA] in
                firstA.map { !$0.isInvalidated } ?? false
            })
        for _ in 0..<5 { oldTour.next() }
        await coordinator.transition(to: "qa-account-b")
        #expect(firstA.isInvalidated)
        let ownerB = try #require(coordinator.renderableOwner)
        await coordinator.transition(to: "qa-account-a")
        let secondA = try #require(coordinator.renderableOwner)
        #expect(firstA !== secondA && ownerB.isInvalidated && !secondA.isInvalidated)
        store.setStatus(.deferred, ownerKey: keyA)
        var recomposition = initialFacts
        recomposition.showsBlock7700 = true
        oldTour.updateFacts(recomposition, ownerKey: keyA)
        #expect(oldTour.current.bodyKey == "tour.progress.body.without-block")
        #expect(oldTour.index == 5)
        #expect(!GuidedTutorialOffer.record(.finished, ownerKey: keyA, store: store,
            sessionIsActive: oldTour.isSessionActive()))
        #expect(store.status(ownerKey: keyA) == .deferred)
        #expect(store.status(ownerKey: keyB) == .notOffered)
        let currentTour = GuidedTourModel(steps: GuidedTourContent.steps(facts: initialFacts), origin: .profile,
            ownerKey: keyA, returnTab: .profile, isSessionActive: { [weak secondA] in
                secondA.map { !$0.isInvalidated } ?? false
            })
        for _ in 0..<5 { currentTour.next() }
        currentTour.updateFacts(recomposition, ownerKey: keyA)
        #expect(currentTour.current.bodyKey == "tour.progress.body")
        #expect(GuidedTutorialOffer.record(.finished, ownerKey: keyA, store: store,
            sessionIsActive: currentTour.isSessionActive()))
        #expect(store.status(ownerKey: keyA) == .completed)
        await coordinator.transition(to: nil)
        #expect(secondA.isInvalidated && coordinator.renderableOwner == nil)
    }
}
