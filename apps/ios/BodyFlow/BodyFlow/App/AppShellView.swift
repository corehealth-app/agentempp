import SwiftUI

@MainActor
struct AppShellView: View {
    @Environment(\.appDependencies) private var dependencies
    @State private var selectedTab = AppTab.today
    @State private var router = AppRouter()
    let userID: String

    init(userID: String = "fixture-user") {
        self.userID = userID
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
        .background {
            TabBarAccessibilityConfigurator(
                identifiers: AppTab.allCases.map(\.accessibilityIdentifier)
            )
            .frame(width: 0, height: 0)
        }
        .environment(router)
        .sheet(item: presentedSheetBinding) { sheet in
            RegistrationSheet(sheet: sheet)
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
            TodayRootView()
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
    AppShellView()
        .installAppDependencies(AppDependencies.scaffold())
}
