import SwiftUI

@MainActor
struct ProfileRootView: View {
    @Environment(\.appDependencies) private var dependencies

    let userID: String
    let fixture: ProfileFixture
    let state: ScreenContentState
    private let coachExperienceProvider: (any CoachExperienceProviding)?
    private let invalidationCenter: FeatureInvalidationCenter
    private let retryAction: @MainActor () -> Void

    @State private var selectedPersona: CoachPersona?
    @State private var personaEditor: CoachPersonaEditorModel?
    @State private var serverOptions: [CoachPersonaOption]?
    @State private var hasLoadedPersona = false
    @State private var loadController = ProfilePersonaLoadController()

    init(
        userID: String = "fixture-user",
        fixture: ProfileFixture = AppFixtures.profile,
        state: ScreenContentState = .loaded,
        coachExperienceProvider: (any CoachExperienceProviding)? = nil,
        invalidationCenter: FeatureInvalidationCenter? = nil,
        retryAction: @escaping @MainActor () -> Void = {}
    ) {
        self.userID = userID
        self.fixture = fixture
        self.state = state
        self.coachExperienceProvider = coachExperienceProvider
        self.invalidationCenter = invalidationCenter ?? FeatureInvalidationCenter()
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
        .task(id: ProfilePersonaLoadKey(
            userID: userID,
            coachRevision: invalidationCenter.revision(for: .coachExperience)
        )) {
            await loadPersona()
        }
        .sheet(item: $personaEditor) { editor in
            CoachPersonaPickerView(model: editor)
        }
        .onDisappear {
            loadController.invalidate()
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
                        repository: dependencies.coachPersona,
                        telemetry: dependencies.telemetry,
                        serverOptions: serverOptions ?? [],
                        initialSelected: selectedPersona,
                        initialPersisted: selectedPersona,
                        initialOperationState: .idle,
                        onPersistedPersonaChanged: {
                            invalidationCenter.record(.coachPersonaChanged)
                        }
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
        guard let selectedPersona else { return "Não selecionada" }
        guard let options = serverOptions,
              let pickerOptions = CoachPersonaEditorModel
                .validatedPickerOptions(options)
        else {
            return "Indisponível nesta versão"
        }
        return pickerOptions.first(where: { $0.persona == selectedPersona })?.name
            ?? "Indisponível nesta versão"
    }

    private func loadPersona() async {
        await loadController.load(
            userID: userID,
            previous: ProfilePersonaLoadController.Publication(
                selectedPersona: selectedPersona,
                serverOptions: serverOptions
            ),
            repository: dependencies.coachPersona,
            provider: coachExperienceProvider
        ) { publication in
            selectedPersona = publication.selectedPersona
            serverOptions = publication.serverOptions
            personaEditor?.updateServerOptions(publication.serverOptions ?? [])
            hasLoadedPersona = true
        }
    }
}

private struct ProfilePersonaLoadKey: Hashable {
    let userID: String
    let coachRevision: Int
}

@MainActor
final class ProfilePersonaLoadController {
    struct Publication: Equatable {
        let selectedPersona: CoachPersona?
        let serverOptions: [CoachPersonaOption]?
    }

    private var ownership = ProfilePersonaLoadOwnership()

    func load(
        userID: String,
        previous: Publication,
        repository: any CoachPersonaRepository,
        provider: (any CoachExperienceProviding)?,
        publish: @escaping @MainActor (Publication) -> Void
    ) async {
        let token = ownership.begin(for: userID)
        guard canPublish(token, userID: userID) else { return }

        var selectedPersona = previous.selectedPersona
        var serverOptions: [CoachPersonaOption]?

        do {
            selectedPersona = try await repository.selectedPersona(for: userID)
        } catch {
            guard canPublish(token, userID: userID) else { return }
        }

        guard canPublish(token, userID: userID) else { return }

        if let provider {
            do {
                let response = try await provider.coachExperience()
                if let snapshot = CoachExperienceV1PresentationContract
                    .validatedSnapshot(from: response),
                   CoachPersonaEditorModel
                    .validatedPickerOptions(snapshot.options) != nil {
                    selectedPersona = Self.persona(from: snapshot.selected)
                    serverOptions = snapshot.options
                } else {
                    serverOptions = nil
                }
            } catch {
                serverOptions = nil
            }
        }

        guard canPublish(token, userID: userID) else { return }
        publish(Publication(
            selectedPersona: selectedPersona,
            serverOptions: serverOptions
        ))
    }

    func invalidate() {
        ownership.invalidate()
    }

    private func canPublish(
        _ token: ProfilePersonaLoadOwnership.Token,
        userID: String
    ) -> Bool {
        ownership.canPublish(
            token,
            activeUserID: userID,
            isCancelled: Task.isCancelled
        )
    }

    private static func persona(
        from selectable: SelectableCoachPersona?
    ) -> CoachPersona? {
        switch selectable {
        case .focus: .focus
        case .impulse: .impulse
        case .zen: .zen
        case nil: nil
        }
    }
}

struct ProfilePersonaLoadOwnership {
    struct Token: Equatable {
        fileprivate let userID: String
        fileprivate let generation: UInt64
    }

    private var generation: UInt64 = 0
    private var activeToken: Token?

    mutating func begin(for userID: String) -> Token {
        generation &+= 1
        let token = Token(userID: userID, generation: generation)
        activeToken = token
        return token
    }

    mutating func invalidate() {
        generation &+= 1
        activeToken = nil
    }

    func canPublish(
        _ token: Token,
        activeUserID: String,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled
            && activeToken == token
            && token.userID == activeUserID
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
