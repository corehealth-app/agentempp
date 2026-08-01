import SwiftUI

@MainActor
struct AppShellView: View {
    @State private var selectedTab = AppTab.today
    @State private var router = AppRouter()
    @State private var invalidationCenter: FeatureInvalidationCenter
    @State private var todayViewModel: TodayViewModel
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
                    FeatureDetailView(route: route)
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
            PlanRootView()
        case .progress:
            ProgressRootView()
        case .profile:
            ProfileRootView(userID: userID)
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
