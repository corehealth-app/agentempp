import SwiftUI

@MainActor
struct ProfileRootView: View {
    let fixture: ProfileFixture
    let state: ScreenContentState
    private let retryAction: @MainActor () -> Void

    init(
        fixture: ProfileFixture = AppFixtures.profile,
        state: ScreenContentState = .loaded,
        retryAction: @escaping @MainActor () -> Void = {}
    ) {
        self.fixture = fixture
        self.state = state
        self.retryAction = retryAction
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()

            if let screenState = state.screenState {
                ScreenStateView(state: screenState, retryAction: retryAction)
            } else {
                loadedContent
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppTab.profile.rootAccessibilityIdentifier)
        .navigationTitle("Perfil")
    }

    private var loadedContent: some View {
        List {
            Section("Perfil") {
                Label(fixture.title, systemImage: "person.crop.circle")
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            }

            Section("Preferências") {
                FixtureMetricRow(
                    title: "Preferência de coach",
                    value: fixture.coachPreference
                )
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)

                FixtureMetricRow(
                    title: "Notificações",
                    value: fixture.notifications
                )
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)

                NavigationLink(
                    value: AppRoute.detail(
                        tab: .profile,
                        id: "profile-preferences"
                    )
                ) {
                    FeatureActionLabel(
                        title: "Ver preferências",
                        detail: "Abrir destino local de demonstração",
                        systemImage: "slider.horizontal.3",
                        showsDisclosureIndicator: false
                    )
                }
                .accessibilityIdentifier("profile.detail")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BodyFlowColor.background)
        .listRowBackground(BodyFlowColor.surface)
    }
}

#Preview("Perfil · Loaded") {
    NavigationStack {
        ProfileRootView()
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}

#Preview("Perfil · Empty") {
    NavigationStack {
        ProfileRootView(state: .empty)
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}
