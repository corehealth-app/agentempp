import SwiftUI

/// A control the guided tour can point at. The screens attach these to
/// their real buttons; the shell reads the resolved frames, so a spotlight
/// follows Dynamic Type, device size and rotation instead of fixed points.
enum GuidedTourTarget: String, CaseIterable, Sendable {
    case flow, library, register, planTab, progressTab, profileTab
    case mealCommand, flowComposer
}

struct GuidedTourAnchorKey: PreferenceKey {
    static var defaultValue: [GuidedTourTarget: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [GuidedTourTarget: Anchor<CGRect>], nextValue: () -> [GuidedTourTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Publishes this control's bounds as a tour target. `enabled: false`
    /// publishes nothing (a tab bar drawn inside an inactive tab).
    func guidedTourTarget(_ target: GuidedTourTarget, enabled: Bool = true) -> some View {
        anchorPreference(key: GuidedTourAnchorKey.self, value: .bounds) { anchor in
            enabled ? [target: anchor] : [:]
        }
    }
}

private struct GuidedTourFocusKey: EnvironmentKey {
    static let defaultValue: GuidedTourTarget? = nil
}

extension EnvironmentValues {
    /// The control the tour is pointing at right now; a screen that owns
    /// it scrolls it into view.
    var guidedTourFocus: GuidedTourTarget? {
        get { self[GuidedTourFocusKey.self] }
        set { self[GuidedTourFocusKey.self] = newValue }
    }
}

/// One stop of the tour: a spotlight on a target, or a card with no target
/// (welcome, the trail). Copy lives in the catalog under `tour.*`.
struct GuidedTourStep: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case welcome
        case spotlight(GuidedTourTarget)
        case trail
    }

    let id: String
    let kind: Kind
    /// The tab the step is shown on; the tour selects it when needed.
    let tab: AppTab
    let titleKey: String
    let bodyKey: String
    var showsBlock7700: Bool = false

    var target: GuidedTourTarget? {
        if case let .spotlight(target) = kind { return target }
        return nil
    }
}

enum GuidedTourContent {
    /// The full tour: welcome, the six real controls, then the trail.
    static func steps(facts: GuidedTutorialFacts) -> [GuidedTourStep] {
        [
            GuidedTourStep(id: "welcome", kind: .welcome, tab: .today,
                           titleKey: "tour.welcome.title", bodyKey: "tour.welcome.body"),
            GuidedTourStep(id: "flow", kind: .spotlight(.flow), tab: .today,
                           titleKey: "tour.flow.title",
                           bodyKey: facts.planDrafts ? "tour.flow.body.suggestions" : "tour.flow.body"),
            GuidedTourStep(id: "library", kind: .spotlight(.library), tab: .today,
                           titleKey: "tour.library.title", bodyKey: "tour.library.body"),
            GuidedTourStep(id: "register", kind: .spotlight(.register), tab: .today,
                           titleKey: "tour.register.title",
                           bodyKey: facts.mealMedia ? "tour.register.body.media" : "tour.register.body"),
            GuidedTourStep(id: "plan", kind: .spotlight(.planTab), tab: .today,
                           titleKey: "tour.plan.title",
                           bodyKey: facts.planImport ? "tour.plan.body.import" : "tour.plan.body"),
            GuidedTourStep(id: "progress", kind: .spotlight(.progressTab), tab: .today,
                           titleKey: "tour.progress.title",
                           bodyKey: facts.showsBlock7700 ? "tour.progress.body" : "tour.progress.body.without-block"),
            GuidedTourStep(id: "profile", kind: .spotlight(.profileTab), tab: .today,
                           titleKey: "tour.profile.title",
                           bodyKey: facts.currentObjective
                               ? (facts.reminders ? "tour.profile.body.reminders.objective" : "tour.profile.body.objective")
                               : (facts.reminders ? "tour.profile.body.reminders" : "tour.profile.body")),
            GuidedTourStep(id: "trail", kind: .trail, tab: .today,
                           titleKey: "tour.trail.title",
                           bodyKey: facts.showsBlock7700 ? "tour.trail.body" : "tour.trail.body.without-block",
                           showsBlock7700: facts.showsBlock7700),
        ]
    }

    /// A single contextual tip, shown once per account on the first visit.
    static func tip(_ target: GuidedTourTarget) -> GuidedTourStep? {
        switch target {
        case .mealCommand:
            GuidedTourStep(id: "tip.meal", kind: .spotlight(.mealCommand), tab: .register,
                           titleKey: "tour.tip.meal.title", bodyKey: "tour.tip.meal.body")
        case .flowComposer:
            GuidedTourStep(id: "tip.composer", kind: .spotlight(.flowComposer), tab: .today,
                           titleKey: "tour.tip.composer.title", bodyKey: "tour.tip.composer.body")
        default:
            nil
        }
    }

    /// Contextual tips never exceed this many per app session.
    nonisolated static let tipsPerSession = 3
}

/// Where the callout goes around a spotlight: below the target when it
/// fits, otherwise above; always inside the container with a 16 pt gutter
/// and never over the target itself.
enum GuidedTourPlacement {
    nonisolated static let gutter: CGFloat = 16
    nonisolated static let spacing: CGFloat = 12
    /// Breathing room between the control and the cutout edge.
    nonisolated static let cutoutInset: CGFloat = 6
    nonisolated static let cutoutRadius: CGFloat = 16

    struct Result: Equatable {
        var origin: CGPoint
        var above: Bool
        /// The room on the chosen side: the callout scrolls inside it, so it
        /// never grows over the target.
        var maxHeight: CGFloat
    }

    /// Free height below and above the cutout, inside the gutters.
    nonisolated static func room(target: CGRect, container: CGRect) -> (below: CGFloat, above: CGFloat) {
        let cutout = cutout(for: target)
        return (
            below: max(0, container.maxY - gutter - (cutout.maxY + spacing)),
            above: max(0, cutout.minY - spacing - (container.minY + gutter))
        )
    }

    nonisolated static func callout(target: CGRect, size: CGSize, container: CGRect) -> Result {
        let cutout = cutout(for: target)
        let room = room(target: target, container: container)
        // Below when it fits there; otherwise the roomier side.
        let below = size.height <= room.below || room.below >= room.above
        let maxHeight = max(0, below ? room.below : room.above)
        let height = min(size.height, maxHeight)
        let y = below ? cutout.maxY + spacing : cutout.minY - spacing - height
        let minX = container.minX + gutter
        let maxX = max(minX, container.maxX - gutter - size.width)
        let x = min(max(target.midX - size.width / 2, minX), maxX)
        return Result(origin: CGPoint(x: x, y: y), above: !below, maxHeight: maxHeight)
    }

    nonisolated static func cutout(for target: CGRect) -> CGRect {
        target.insetBy(dx: -cutoutInset, dy: -cutoutInset)
    }
}

/// The running tour. Pure transitions, so the order of Next/Back/Skip and
/// what each answer records are locked by unit tests.
@MainActor
@Observable
final class GuidedTourModel {
    enum Origin: Equatable { case firstEntry, profile, tip }

    private(set) var steps: [GuidedTourStep]
    let origin: Origin
    let ownerKey: String
    /// Where the user was before a replay from Profile; restored at the end.
    let returnTab: AppTab
    let isSessionActive: @MainActor () -> Bool
    private(set) var progress: GuidedTutorialProgress

    init(steps: [GuidedTourStep], origin: Origin, ownerKey: String, returnTab: AppTab,
         isSessionActive: @escaping @MainActor () -> Bool = { false }) {
        precondition(!steps.isEmpty)
        self.steps = steps
        self.origin = origin
        self.ownerKey = ownerKey
        self.returnTab = returnTab
        self.isSessionActive = isSessionActive
        progress = GuidedTutorialProgress(stepCount: steps.count)
    }

    var current: GuidedTourStep { steps[progress.index] }
    var index: Int { progress.index }
    var isFirst: Bool { progress.isFirst }
    var isLast: Bool { progress.isLast }
    var isTip: Bool { origin == .tip }

    func next() { progress.next() }
    func back() { progress.back() }

    func updateFacts(_ facts: GuidedTutorialFacts, ownerKey: String) {
        guard isSessionActive(), !isTip, self.ownerKey == ownerKey else { return }
        let updated = GuidedTourContent.steps(facts: facts)
        guard updated.map(\.id) == steps.map(\.id) else { return }
        steps = updated
    }
}
