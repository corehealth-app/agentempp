#if DEBUG
import SwiftUI

@MainActor
enum Prompt13PreviewSupport {
    static func dependencies(
        for scenario: DemoBodyFlowScenario
    ) -> AppDependencies {
        AppDependencies.make(
            configuration: AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", launchArgument(for: scenario)],
                buildFlavor: .debug
            )
        )
    }

    private static func launchArgument(
        for scenario: DemoBodyFlowScenario
    ) -> String {
        switch scenario {
        case .loaded: "--ui-testing-prompt13-loaded"
        case .loadingDelay: "--ui-testing-prompt13-loading"
        case .empty: "--ui-testing-prompt13-empty"
        case .initialOffline: "--ui-testing-prompt13-offline"
        case .staleOffline: "--ui-testing-prompt13-stale-offline"
        case .initialError: "--ui-testing-prompt13-error"
        case .staleError: "--ui-testing-prompt13-stale-error"
        case .incompleteDay: "--ui-testing-prompt13-incomplete"
        case .unavailablePresentation: "--ui-testing-prompt13-unavailable"
        case .registrationFailureOnce:
            "--ui-testing-prompt13-registration-error-once"
        case .routineConflictOnce:
            "--ui-testing-prompt13-routine-conflict-once"
        case .routineActionUnavailable:
            "--ui-testing-prompt13-routine-action-unavailable"
        case .reduceMotionVerification:
            "--ui-testing-prompt13-reduce-motion"
        }
    }
}

private actor Prompt13PreviewLoadingTodayProvider: TodayProviding {
    func today() async throws -> TodayResponse {
        try await Task.sleep(for: .seconds(86_400))
        return DemoBodyFlowFixtures.loadedToday
    }
}

@MainActor
private struct Prompt13TodayStatePreview: View {
    private let dependencies: AppDependencies
    @State private var model: TodayViewModel
    @State private var invalidationCenter = FeatureInvalidationCenter()

    init(scenario: DemoBodyFlowScenario) {
        let dependencies = Prompt13PreviewSupport.dependencies(for: scenario)
        self.dependencies = dependencies
        let provider: any TodayProviding = scenario == .loadingDelay
            ? Prompt13PreviewLoadingTodayProvider()
            : dependencies.today
        _model = State(initialValue: TodayViewModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            TodayRootView(
                model: model,
                invalidationCenter: invalidationCenter
            )
        }
        .environment(AppRouter())
        .installAppDependencies(dependencies)
    }
}

@MainActor
private struct Prompt13MealJourneyPreview: View {
    let source: MealCaptureChoice
    @State private var text = "Refeição textual de demonstração"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                sourceView
                Divider()
                MealProposalView(
                    proposal: MealProposalPresentation(
                        registration: DemoBodyFlowFixtures.pendingMealRegistration.data
                    ),
                    isSubmitting: false,
                    edit: {},
                    confirm: {},
                    cancel: {}
                )
            }
            .padding(BodyFlowSpacing.lg)
        }
        .background(BodyFlowColor.background)
    }

    @ViewBuilder
    private var sourceView: some View {
        switch source {
        case .text:
            MealTextDraftView(draft: $text, isSubmitting: false, detect: {})
        case .photo, .audio:
            MealDemonstrationSourceView(
                choice: source,
                isSubmitting: false,
                detect: {}
            )
        }
    }
}

@MainActor
private struct Prompt13MealEditPreview: View {
    var body: some View {
        NavigationStack {
            MealProposalEditorView(
                registration: DemoBodyFlowFixtures.editedMealRegistration.data,
                initialConsumedAt: Date(timeIntervalSince1970: 1_784_589_300),
                isSubmitting: false,
                save: { _ in }
            )
        }
    }
}

@MainActor
private struct Prompt13WorkoutProposalPreview: View {
    var body: some View {
        ScrollView {
            WorkoutProposalView(
                proposal: WorkoutProposalPresentation(
                    registration: DemoBodyFlowFixtures.pendingWorkoutRegistration.data
                ),
                isSubmitting: false,
                edit: {},
                confirm: {},
                cancel: {}
            )
            .padding(BodyFlowSpacing.lg)
        }
        .background(BodyFlowColor.background)
    }
}

@MainActor
private struct Prompt13RoutineSnoozePreview: View {
    @State private var model: RoutineActionModel

    init() {
        let dependencies = Prompt13PreviewSupport.dependencies(for: .loaded)
        let item = DemoBodyFlowFixtures.loadedSupplementList.data.items[0]
        let context = RoutineOccurrenceContext.actionContext(
            kind: .supplement,
            itemID: item.id,
            schedules: item.schedules
        ) ?? RoutineOccurrenceContext(
            kind: .supplement,
            itemID: item.id,
            reminderRuleID: "rule-20",
            scheduledFor: APITimestamp(
                value: Date(timeIntervalSince1970: 1_784_588_400)
            )
        )
        _model = State(initialValue: RoutineActionModel(
            provider: dependencies.routine,
            timeProvider: dependencies.timeProvider,
            keyProvider: dependencies.idempotencyKeyProvider,
            invalidationCenter: FeatureInvalidationCenter(),
            patientTimeZone: dependencies.patientTimeZone,
            context: context
        ))
    }

    var body: some View {
        RoutineSnoozeView(model: model, submit: { _ in })
            .background(BodyFlowColor.background)
    }
}

@MainActor
private struct Prompt13RoutineHistoryPreview: View {
    private let dependencies = Prompt13PreviewSupport.dependencies(for: .loaded)
    @State private var invalidationCenter = FeatureInvalidationCenter()

    var body: some View {
        NavigationStack {
            RoutineHistoryView(
                kind: .supplement,
                itemID: "supplement-1",
                dependencies: dependencies,
                invalidationCenter: invalidationCenter
            )
        }
        .environment(AppRouter())
        .installAppDependencies(dependencies)
    }
}

@MainActor
private struct Prompt13PlanPreview: View {
    private let dependencies = Prompt13PreviewSupport.dependencies(for: .loaded)
    @State private var selectedTab = AppTab.plan

    var body: some View {
        NavigationStack {
            PlanRootView(
                model: PlanViewModel(provider: dependencies.plan),
                selectedTab: $selectedTab
            )
        }
        .environment(AppRouter())
        .installAppDependencies(dependencies)
    }
}

@MainActor
private struct Prompt13ProgressPreview: View {
    private let dependencies = Prompt13PreviewSupport.dependencies(for: .loaded)
    @State private var selectedTab = AppTab.progress

    var body: some View {
        NavigationStack {
            ProgressRootView(
                model: ProgressViewModel(provider: dependencies.progress),
                selectedTab: $selectedTab
            )
        }
        .environment(AppRouter())
        .installAppDependencies(dependencies)
    }
}

@MainActor
private struct Prompt13BlockPreview: View {
    private let dependencies = Prompt13PreviewSupport.dependencies(for: .loaded)

    var body: some View {
        NavigationStack {
            Block7700DetailView(today: dependencies.today)
        }
        .installAppDependencies(dependencies)
    }
}

@MainActor
private struct Prompt13HistoryPreview: View {
    private let dependencies: AppDependencies
    @State private var model: HistoryViewModel
    @State private var invalidationCenter = FeatureInvalidationCenter()

    init() {
        let dependencies = Prompt13PreviewSupport.dependencies(for: .loaded)
        self.dependencies = dependencies
        _model = State(initialValue: HistoryViewModel(provider: dependencies.history))
    }

    var body: some View {
        NavigationStack {
            MainHistoryView(
                model: model,
                invalidationCenter: invalidationCenter
            )
        }
        .environment(AppRouter())
        .installAppDependencies(dependencies)
    }
}

#Preview("Prompt 13 · Loaded") {
    Prompt13TodayStatePreview(scenario: .loaded)
}

#Preview("Prompt 13 · Loading") {
    Prompt13TodayStatePreview(scenario: .loadingDelay)
}

#Preview("Prompt 13 · Empty") {
    Prompt13TodayStatePreview(scenario: .empty)
}

#Preview("Prompt 13 · Offline") {
    Prompt13TodayStatePreview(scenario: .initialOffline)
}

#Preview("Prompt 13 · Recoverable Error") {
    Prompt13TodayStatePreview(scenario: .initialError)
}

#Preview("Prompt 13 · Incomplete") {
    Prompt13TodayStatePreview(scenario: .incompleteDay)
}

#Preview("Prompt 13 · Unavailable") {
    Prompt13TodayStatePreview(scenario: .unavailablePresentation)
}

#Preview("Prompt 13 · Dark Mode") {
    Prompt13TodayStatePreview(scenario: .loaded)
        .preferredColorScheme(.dark)
}

#Preview("Prompt 13 · Accessibility XXXL") {
    Prompt13TodayStatePreview(scenario: .loaded)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Prompt 13 · Text Proposal") {
    Prompt13MealJourneyPreview(source: .text)
}

#Preview("Prompt 13 · Photo Proposal") {
    Prompt13MealJourneyPreview(source: .photo)
}

#Preview("Prompt 13 · Audio Proposal") {
    Prompt13MealJourneyPreview(source: .audio)
}

#Preview("Prompt 13 · Meal Edit") {
    Prompt13MealEditPreview()
}

#Preview("Prompt 13 · Workout Proposal") {
    Prompt13WorkoutProposalPreview()
}

#Preview("Prompt 13 · Weight Receipt") {
    Prompt13RegistrationReceiptPreview(kind: .weight)
}

#Preview("Prompt 13 · Hydration Receipt") {
    Prompt13RegistrationReceiptPreview(kind: .hydration)
}

#Preview("Prompt 13 · Routine Snooze") {
    Prompt13RoutineSnoozePreview()
}

#Preview("Prompt 13 · Routine History") {
    Prompt13RoutineHistoryPreview()
}

#Preview("Prompt 13 · Plan") {
    Prompt13PlanPreview()
}

#Preview("Prompt 13 · Progress") {
    Prompt13ProgressPreview()
}

#Preview("Prompt 13 · Block 7700") {
    Prompt13BlockPreview()
}

#Preview("Prompt 13 · Main History") {
    Prompt13HistoryPreview()
}
#endif
