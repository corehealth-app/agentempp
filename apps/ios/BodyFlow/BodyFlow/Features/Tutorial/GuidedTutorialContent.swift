import Foundation

/// One stop of the guided tour: an area of the app and what can really be
/// done there in this build and session.
struct GuidedTutorialStep: Identifiable, Equatable, Sendable {
    enum Area: String, CaseIterable, Sendable {
        case welcome, today, flow, plan, register, progress, routineLibrary, profile
    }

    let area: Area
    let titleKey: String
    let lineKeys: [String]
    let symbol: BodyFlowSymbol

    var id: String { area.rawValue }
}

enum GuidedTutorialContent {
    /// The tour, shortest that still covers the five areas and what lives
    /// inside Today. Lines that depend on a capability appear only with it.
    static func steps(facts: GuidedTutorialFacts) -> [GuidedTutorialStep] {
        [
            GuidedTutorialStep(
                area: .welcome,
                titleKey: "tutorial.welcome.title",
                lineKeys: ["tutorial.welcome.body", "tutorial.welcome.safety"],
                symbol: .info
            ),
            GuidedTutorialStep(
                area: .today,
                titleKey: "tutorial.today.title",
                lineKeys: [
                    "tutorial.today.food",
                    "tutorial.today.balance",
                    "tutorial.today.refresh",
                    "tutorial.today.details",
                ],
                symbol: .energy
            ),
            GuidedTutorialStep(
                area: .flow,
                titleKey: "tutorial.flow.title",
                lineKeys: [
                    "tutorial.flow.open",
                    facts.planDrafts ? "tutorial.flow.suggestions" : nil,
                    "tutorial.flow.pending",
                    "tutorial.flow.cancel",
                ].compactMap { $0 },
                symbol: .flow
            ),
            // Same order as the tab bar: Plano before Registrar.
            GuidedTutorialStep(
                area: .plan,
                titleKey: "tutorial.plan.title",
                lineKeys: [
                    "tutorial.plan.current",
                    facts.planDrafts
                        ? (facts.planImport ? "tutorial.plan.review.import" : "tutorial.plan.review")
                        : nil,
                    facts.planDrafts ? "tutorial.plan.confirm" : nil,
                ].compactMap { $0 },
                symbol: .protocolDocument
            ),
            GuidedTutorialStep(
                area: .register,
                titleKey: "tutorial.register.title",
                lineKeys: [
                    "tutorial.register.open",
                    facts.mealMedia ? "tutorial.register.meal.capture" : "tutorial.register.meal.text",
                    "tutorial.register.review",
                    "tutorial.register.direct",
                ],
                symbol: .meals
            ),
            GuidedTutorialStep(
                area: .progress,
                titleKey: "tutorial.progress.title",
                lineKeys: [facts.showsBlock7700 ? "tutorial.progress.body" : "tutorial.progress.body.without-block",
                    "tutorial.progress.empty"],
                symbol: .weight
            ),
            GuidedTutorialStep(
                area: .routineLibrary,
                titleKey: "tutorial.more.title",
                lineKeys: ["tutorial.more.routine", "tutorial.more.library"],
                symbol: .routine
            ),
            GuidedTutorialStep(
                area: .profile,
                titleKey: "tutorial.profile.title",
                lineKeys: [
                    "tutorial.profile.persona",
                    facts.reminders ? "tutorial.profile.reminders" : nil,
                    "tutorial.profile.replay",
                    facts.realAccount ? "tutorial.profile.sign-out" : nil,
                ].compactMap { $0 },
                symbol: .person
            ),
        ]
    }
}

/// The tour's position. Pure, so the order of Next/Back/close is locked by
/// unit tests, not by the view.
struct GuidedTutorialProgress: Equatable, Sendable {
    let stepCount: Int
    private(set) var index = 0

    init(stepCount: Int) {
        precondition(stepCount > 0)
        self.stepCount = stepCount
    }

    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == stepCount - 1 }

    mutating func next() {
        index = min(index + 1, stepCount - 1)
    }

    mutating func back() {
        index = max(index - 1, 0)
    }

    /// The replay from Profile can open one area directly.
    mutating func jump(to position: Int) {
        index = min(max(position, 0), stepCount - 1)
    }
}

enum GuidedTutorialCopy {
    static func string(_ key: String, language: SupportedAppLanguage) -> String {
        let value = String.LocalizationValue(key)
        return (try? AppLocalization.string(value, for: language)) ?? String(localized: value)
    }

    static func stepPosition(_ position: Int, of count: Int, language: SupportedAppLanguage) -> String {
        String(format: string("tutorial.position", language: language), position, count)
    }
}
