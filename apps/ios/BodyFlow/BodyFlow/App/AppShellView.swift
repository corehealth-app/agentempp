import SwiftUI

@MainActor
struct AppShellView: View {
    @State private var selectedTab = AppTab.today
    @State private var router = AppRouter()
    @State private var invalidationCenter: FeatureInvalidationCenter
    @State private var todayViewModel: TodayViewModel
    @State private var planViewModel: PlanViewModel
    @State private var progressViewModel: ProgressViewModel
    @State private var historyViewModel: HistoryViewModel
    @State private var historyCoordinator: HistoryFeatureCoordinator
    let userID: String
    let dependencies: AppDependencies
    let sessionOwner: Prompt14SessionOwner

    init(
        userID: String,
        dependencies: AppDependencies,
        sessionOwner: Prompt14SessionOwner
    ) {
        self.userID = userID
        self.dependencies = dependencies
        self.sessionOwner = sessionOwner
        _invalidationCenter = State(
            initialValue: FeatureInvalidationCenter()
        )
        _todayViewModel = State(
            initialValue: TodayViewModel(provider: dependencies.today)
        )
        _planViewModel = State(
            initialValue: PlanViewModel(provider: dependencies.plan)
        )
        _progressViewModel = State(
            initialValue: ProgressViewModel(provider: sessionOwner.progress)
        )
        let historyModel = HistoryViewModel(provider: dependencies.history)
        _historyViewModel = State(initialValue: historyModel)
        _historyCoordinator = State(
            initialValue: HistoryFeatureCoordinator(model: historyModel)
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    navigationStack(for: tab)
                }
                .accessibilityIdentifier(tab.accessibilityIdentifier)
            }
        }
        .tint(BodyFlowColor.accent)
        .bodyFlowBrandIdentity()
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--ui-testing-prompt13-stale-offline") else {
                return
            }
            await historyViewModel.load(revision: 0)
            await historyViewModel.retry()
        }
#endif
        .background {
            TabBarAccessibilityConfigurator(
                identifiers: AppTab.allCases.map(\.accessibilityIdentifier)
            )
            .frame(width: 0, height: 0)
        }
        .environment(router)
        .sheet(item: presentedSheetBinding) { sheet in
            RegistrationSheet(
                sheet: sheet,
                dependencies: dependencies,
                invalidationCenter: invalidationCenter
            )
                .environment(router)
        }
        .onDisappear {
            sessionOwner.invalidateSynchronously()
        }
    }

    private var presentedSheetBinding: Binding<AppSheet?> {
        Binding(
            get: { router.presentedSheet },
            set: { router.presentedSheet = $0 }
        )
    }

    @ViewBuilder
    private func navigationStack(for tab: AppTab) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
            rootView(for: tab)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
    }

    @ViewBuilder
    private func rootView(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayRootView(
                model: todayViewModel,
                invalidationCenter: invalidationCenter
            )
        case .register:
            RegisterRootView()
        case .plan:
            PlanRootView(
                model: planViewModel,
                selectedTab: $selectedTab
            )
        case .progress:
            ProgressRootView(
                model: progressViewModel,
                selectedTab: $selectedTab
            )
        case .profile:
            ProfileRootView(userID: userID)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .detail:
            FeatureDetailView(route: route)
        case .mainHistory:
            MainHistoryView(
                model: historyViewModel,
                invalidationCenter: invalidationCenter
            )
        case .historyMealLog:
            HistoryMealLogDetailView(
                row: historyCoordinator.mealLogRow(for: route)
            )
        case .historyWorkout:
            HistoryWorkoutDetailView(
                row: historyCoordinator.workoutLogRow(for: route)
            )
        case let .routine(routineRoute):
            switch routineRoute.destination {
            case .list:
                RoutineListView(
                    kind: routineRoute.kind,
                    dependencies: dependencies,
                    invalidationCenter: invalidationCenter
                )
            case .detail:
                RoutineDetailRouteView(
                    route: routineRoute,
                    dependencies: dependencies,
                    invalidationCenter: invalidationCenter
                )
            case .history:
                RoutineHistoryView(
                    kind: routineRoute.kind,
                    itemID: routineRoute.itemID ?? "",
                    dependencies: dependencies,
                    invalidationCenter: invalidationCenter
                )
            }
        case .plan:
            PlanDetailView(provider: dependencies.plan)
        case .progress:
            Block7700DetailView(today: dependencies.today)
        case let .content(contentRoute):
            switch contentRoute {
            case let .library(initialSelection):
                LibraryRootView(
                    initialSelection: initialSelection,
                    sessionOwner: sessionOwner,
                    dependencies: dependencies,
                    invalidationCenter: invalidationCenter
                )
            case .detail:
                FeatureDetailView(route: route)
            }
        case .mascot:
            FeatureDetailView(route: route)
        }
    }
}

#Preview("App Shell · Loaded") {
    let dependencies = AppDependencies.scaffold()
    AppShellView(
        userID: "fixture-user",
        dependencies: dependencies,
        sessionOwner: Prompt14SessionOwner(
            userID: "fixture-user",
            dependencies: dependencies
        )
    )
        .installAppDependencies(dependencies)
}
