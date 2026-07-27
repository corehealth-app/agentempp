import SwiftUI

@MainActor
struct ProfileRootView: View {
    @Environment(\.appDependencies) private var dependencies

    let userID: String
    let fixture: ProfileFixture
    let state: ScreenContentState
    private let retryAction: @MainActor () -> Void

    @State private var selectedPersona: CoachPersona?
    @State private var personaEditor: CoachPersonaEditorModel?
    @State private var hasLoadedPersona = false

    init(
        userID: String = "fixture-user",
        fixture: ProfileFixture = AppFixtures.profile,
        state: ScreenContentState = .loaded,
        retryAction: @escaping @MainActor () -> Void = {}
    ) {
        self.userID = userID
        self.fixture = fixture
        self.state = state
        self.retryAction = retryAction
        _selectedPersona = State(initialValue: nil)
        _personaEditor = State(initialValue: nil)
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
        .task(id: userID) {
            await loadPersona()
        }
        .sheet(item: $personaEditor, onDismiss: refreshPersona) { editor in
            CoachPersonaPickerView(model: editor)
        }
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
                Button {
                    personaEditor = CoachPersonaEditorModel(
                        userID: userID,
                        repository: dependencies.coachPersona
                    )
                } label: {
                    FeatureActionLabel(
                        title: "Personalidade do coach",
                        detail: personaDisplayName,
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
                .buttonStyle(.plain)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .accessibilityIdentifier("profile.coach-persona")

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

    private var personaDisplayName: String {
        guard hasLoadedPersona else { return "Carregando…" }
        return selectedPersona?.displayName ?? "Não selecionada"
    }

    private func refreshPersona() {
        Task { @MainActor in
            await loadPersona()
        }
    }

    private func loadPersona() async {
        do {
            let persona = try await dependencies.coachPersona.selectedPersona(for: userID)
            guard !Task.isCancelled else { return }
            selectedPersona = persona
            hasLoadedPersona = true
        } catch {
            guard !Task.isCancelled else { return }
            hasLoadedPersona = true
        }
    }
}

#Preview("Perfil · Loaded") {
    NavigationStack {
        ProfileRootView(userID: "demo-user-v1")
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
