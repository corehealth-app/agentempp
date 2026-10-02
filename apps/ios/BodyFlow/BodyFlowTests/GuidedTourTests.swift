import CoreGraphics
import Foundation
import Testing

@testable import BodyFlow

@Suite("Guided tour (spotlight)")
struct GuidedTourTests {
    private let allFacts = GuidedTutorialFacts(
        mealMedia: true, planDrafts: true, planImport: true, reminders: true, realAccount: true
    )
    private let noFacts = GuidedTutorialFacts(
        mealMedia: false, planDrafts: false, planImport: false, reminders: false, realAccount: false
    )

    @Test("Welcome, the six real controls in tab-bar order, then the trail")
    func stepOrder() {
        let steps = GuidedTourContent.steps(facts: allFacts)
        #expect(steps.map(\.id) == ["welcome", "flow", "library", "register", "plan", "progress", "profile", "trail"])
        #expect(steps.map(\.target) == [nil, .flow, .library, .register, .planTab, .progressTab, .profileTab, nil])
        #expect(steps.allSatisfy { $0.tab == .today })
        #expect(steps.first?.kind == .welcome)
        #expect(steps.last?.kind == .trail)
    }

    @Test("Bodies follow the session's real capabilities")
    func bodiesFollowFacts() {
        func body(_ id: String, _ facts: GuidedTutorialFacts) -> String {
            GuidedTourContent.steps(facts: facts).first { $0.id == id }!.bodyKey
        }
        #expect(body("flow", allFacts) == "tour.flow.body.suggestions")
        #expect(body("flow", noFacts) == "tour.flow.body")
        #expect(body("register", allFacts) == "tour.register.body.media")
        #expect(body("register", noFacts) == "tour.register.body")
        #expect(body("plan", allFacts) == "tour.plan.body.import")
        #expect(body("plan", noFacts) == "tour.plan.body")
        #expect(body("profile", allFacts) == "tour.profile.body.reminders")
        #expect(body("profile", noFacts) == "tour.profile.body")
    }

    @Test("Every tour text exists in both languages with the public names only",
          arguments: SupportedAppLanguage.allCases)
    func textsAreReviewed(_ language: SupportedAppLanguage) throws {
        var keys: Set<String> = ["tour.skip", "tour.got-it", "tour.trail.plan",
                                 "tour.trail.node.register", "tour.trail.node.today",
                                 "tour.trail.node.block", "tour.trail.node.progress"]
        for facts in [allFacts, noFacts] {
            for step in GuidedTourContent.steps(facts: facts) {
                keys.insert(step.titleKey); keys.insert(step.bodyKey)
            }
        }
        for target in [GuidedTourTarget.mealCommand, .flowComposer] {
            let tip = try #require(GuidedTourContent.tip(target))
            keys.insert(tip.titleKey); keys.insert(tip.bodyKey)
        }
        for key in keys {
            let text = try AppLocalization.string(String.LocalizationValue(key), for: language)
            #expect(text != key && !text.isEmpty, "\(key) / \(language)")
            #expect(!text.localizedCaseInsensitiveContains("BodyFlow") && !text.contains("MPP"), "\(key)")
        }
    }

    @Test("The trail names both balances correctly and keeps the plan as the protocol",
          arguments: SupportedAppLanguage.allCases)
    func trailIsHonest(_ language: SupportedAppLanguage) throws {
        let body = try AppLocalization.string("tour.trail.body", for: language)
        let plan = try AppLocalization.string("tour.trail.plan", for: language)
        // CALCULO-MPP §3: the block is credited at day close from the day's
        // deficit, exercise speeds it, going over the target subtracts.
        if language == .portugueseBrazil {
            #expect(body.contains("Ao fechar o dia") && body.contains("credita o déficit no Bloco 7.700 kcal"))
            #expect(body.contains("o exercício acelera") && body.contains("passar da meta desconta"))
            #expect(plan.contains("protocolo") && plan.contains("só você confirma"))
        } else {
            #expect(body.contains("When the day closes") && body.contains("credits the deficit to the 7,700 kcal Block"))
            #expect(body.contains("exercise speeds it up") && body.contains("going over subtracts"))
            #expect(plan.contains("protocol") && plan.contains("only you confirm"))
        }
    }

    @Test("Tips exist only for the two first-visit controls")
    func tips() {
        #expect(GuidedTourContent.tip(.mealCommand)?.tab == .register)
        #expect(GuidedTourContent.tip(.flowComposer)?.tab == .today)
        for target in [GuidedTourTarget.flow, .library, .register, .planTab, .progressTab, .profileTab] {
            #expect(GuidedTourContent.tip(target) == nil)
        }
        #expect(GuidedTourContent.tipsPerSession == 3)
    }

    @Test("The callout sits below the target when it fits, above otherwise, and never leaves the container")
    func placement() {
        let container = CGRect(x: 0, y: 60, width: 402, height: 760)
        let size = CGSize(width: 360, height: 180)
        let high = GuidedTourPlacement.callout(target: CGRect(x: 24, y: 140, width: 250, height: 64), size: size, container: container)
        #expect(!high.above)
        #expect(high.origin.y == CGFloat(140 + 64 + 6 + 12))
        #expect(high.origin.x == 16) // clamped to the gutter, not centred off-screen
        let low = GuidedTourPlacement.callout(target: CGRect(x: 300, y: 760, width: 80, height: 44), size: size, container: container)
        #expect(low.above)
        #expect(low.origin.y == CGFloat(760 - 6 - 12 - 180))
        #expect(low.origin.x == CGFloat(402 - 16 - 360))
        #expect(GuidedTourPlacement.cutout(for: CGRect(x: 10, y: 10, width: 44, height: 44)) == CGRect(x: 4, y: 4, width: 56, height: 56))
    }

    @Test("A callout taller than the room never covers the target: it takes the roomier side and scrolls inside it")
    func placementNeverCoversTheTarget() {
        let container = CGRect(x: 0, y: 0, width: 402, height: 400)
        let target = CGRect(x: 0, y: 380, width: 402, height: 20)
        let result = GuidedTourPlacement.callout(target: target, size: CGSize(width: 360, height: 500), container: container)
        #expect(result.above)
        // room above = 380 − 6 − 12 − 16 = 346; the callout is capped to it.
        #expect(result.maxHeight == 346)
        #expect(result.origin.y == CGFloat(380 - 6 - 12 - 346))
        #expect(result.origin.y >= GuidedTourPlacement.gutter)
        #expect(result.origin.y + result.maxHeight <= GuidedTourPlacement.cutout(for: target).minY)

        // A target near the top with a tall callout goes below, capped.
        let high = CGRect(x: 0, y: 30, width: 402, height: 44)
        let down = GuidedTourPlacement.callout(target: high, size: CGSize(width: 360, height: 900), container: container)
        #expect(!down.above)
        #expect(down.maxHeight == CGFloat(400 - 16 - (74 + 6 + 12)))
        #expect(down.origin.y == CGFloat(74 + 6 + 12))
    }

    @MainActor
    @Test("Next, Back and the first/last flags")
    func modelTransitions() {
        let model = GuidedTourModel(
            steps: GuidedTourContent.steps(facts: noFacts), origin: .profile,
            ownerKey: "k", returnTab: .profile
        )
        #expect(model.isFirst && !model.isLast && !model.isTip)
        model.back()
        #expect(model.index == 0)
        for _ in 0..<10 { model.next() }
        #expect(model.isLast && model.current.id == "trail")
        model.back()
        #expect(model.current.id == "profile")
        let tip = GuidedTourModel(steps: [GuidedTourContent.tip(.mealCommand)!], origin: .tip, ownerKey: "k", returnTab: .register)
        #expect(tip.isTip && tip.isFirst && tip.isLast)
    }

    @Test("Each tip is remembered per account")
    func tipStoreIsolation() {
        let store = InMemoryGuidedTutorialStore()
        store.markTipShown(.mealCommand, ownerKey: "a")
        #expect(store.hasShownTip(.mealCommand, ownerKey: "a"))
        #expect(!store.hasShownTip(.flowComposer, ownerKey: "a"))
        #expect(!store.hasShownTip(.mealCommand, ownerKey: "b"))
        #expect(UserDefaultsGuidedTutorialStore.tipKey(.mealCommand, "abcd") == "pai.tutorial.v1.tip.mealCommand.abcd")
    }

    @Test("Only the bar of each tab publishes a target, and Today has none of its own")
    func barTargets() {
        // A second `.flow` anchor from the Today label would steal the spotlight.
        #expect(PerformeTabBar.tourTarget(for: .today) == nil)
        #expect(PerformeTabBar.tourTarget(for: .register) == .register)
        #expect(PerformeTabBar.tourTarget(for: .plan) == .planTab)
        #expect(PerformeTabBar.tourTarget(for: .progress) == .progressTab)
        #expect(PerformeTabBar.tourTarget(for: .profile) == .profileTab)
    }
}
