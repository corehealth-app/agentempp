import SwiftUI

@MainActor
struct AppShellView: View {
    @State private var selectedTab = AppTab.today
    @State private var router = AppRouter()
    @State private var invalidationCenter: FeatureInvalidationCenter
    @State private var todayViewModel: TodayViewModel
    @State private var planViewModel: PlanViewModel
    let userID: String
    let dependencies: AppDependencies

    init(
        userID: String,
        dependencies: AppDependencies
    ) {
        self.userID = userID
        self.dependencies = dependencies
        _invalidationCenter = State(
            initialValue: FeatureInvalidationCenter()
        )
        _todayViewModel = State(
            initialValue: TodayViewModel(provider: dependencies.today)
        )
        _planViewModel = State(
            initialValue: PlanViewModel(provider: dependencies.plan)
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
            ProgressRootView()
        case .profile:
            ProfileRootView(userID: userID)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .detail:
            FeatureDetailView(route: route)
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
        }
    }
}

#Preview("App Shell · Loaded") {
    AppShellView(
        userID: "fixture-user",
        dependencies: AppDependencies.scaffold()
    )
        .installAppDependencies(AppDependencies.scaffold())
}
