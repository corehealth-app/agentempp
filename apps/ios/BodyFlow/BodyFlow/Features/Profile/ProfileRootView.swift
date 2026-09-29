import SwiftUI

@MainActor
struct ProfileRootView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.locale) private var locale

    let userID: String
    /// The signed-in account on a real backend; nil keeps the fixture
    /// identity of the local demonstration.
    let accountEmail: String?
    let fixture: ProfileFixture
    let state: ScreenContentState
    private let coachExperienceProvider: (any CoachExperienceProviding)?
    private let invalidationCenter: FeatureInvalidationCenter
    private let retryAction: @MainActor () -> Void
    /// Leaves the signed-in account; only a real account offers it, so the
    /// locked demonstration never shows an account section.
    private let signOut: (@MainActor () async -> Void)?
    /// This session's local reminders; nil where no reminder source exists.
    private let localReminders: LocalReminderModel?

    @State private var selectedPersona: CoachPersona?
    @State private var personaEditor: CoachPersonaEditorModel?
    @State private var serverOptions: [CoachPersonaOption]?
    @State private var hasLoadedPersona = false
    @State private var loadController = ProfilePersonaLoadController()
    @State private var isConfirmingSignOut = false
    @State private var isSigningOut = false

    init(
        userID: String = "fixture-user",
        accountEmail: String? = nil,
        fixture: ProfileFixture = AppFixtures.profile,
        state: ScreenContentState = .loaded,
        coachExperienceProvider: (any CoachExperienceProviding)? = nil,
        invalidationCenter: FeatureInvalidationCenter? = nil,
        retryAction: @escaping @MainActor () -> Void = {},
        localReminders: LocalReminderModel? = nil,
        signOut: (@MainActor () async -> Void)? = nil
    ) {
        self.userID = userID
        self.accountEmail = accountEmail
        self.fixture = fixture
        self.state = state
        self.coachExperienceProvider = coachExperienceProvider
        self.invalidationCenter = invalidationCenter ?? FeatureInvalidationCenter()
        self.retryAction = retryAction
        self.signOut = signOut
        self.localReminders = localReminders
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
        .navigationTitle(copy("profile.navigation.title"))
        .navigationBarTitleDisplayMode(.inline)
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
            Section {
                identityRow
                    .frame(
                        maxWidth: .infinity,
                        minHeight: BodyFlowSpacing.minimumTapTarget,
                        alignment: .leading
                    )
            } header: {
                Text(copy("profile.identity.section"))
                    .foregroundStyle(BodyFlowColor.primaryText)
            }
            .bodyFlowListRow()

            Section {
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
                        title: copy("profile.persona.title"),
                        detail: personaDisplayName,
                        systemImage: BodyFlowSymbol.flow.systemName
                    )
                }
                .buttonStyle(.bodyFlowRow)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .accessibilityIdentifier("profile.coach-persona")

                if let localReminders {
                    NavigationLink(value: AppRoute.localReminders) {
                        FeatureActionLabel(
                            title: copy("profile.reminders.title"),
                            detail: LocalReminderPresentation.summary(
                                localReminders.status,
                                language: BodyFlowPresentationLanguage.resolve(locale)
                            ),
                            systemImage: BodyFlowSymbol.reminders.systemName,
                            // The list row already draws its own chevron.
                            showsDisclosureIndicator: false
                        )
                    }
                    .buttonStyle(.bodyFlowRow)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .accessibilityIdentifier("profile.reminders")
                }

                // Demonstration-only rows: a real account has no local
                // notification fixture or demo preferences destination.
                if accountEmail == nil {
                    FixtureMetricRow(
                        title: copy("profile.fixture.notifications"),
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
                            title: copy("profile.preferences.action"),
                            detail: copy("profile.preferences.demo-detail"),
                            systemImage: BodyFlowSymbol.preferences.systemName,
                            showsDisclosureIndicator: false
                        )
                    }
                    .accessibilityIdentifier("profile.detail")
                }
            } header: {
                Text(copy("profile.preferences.section"))
                    .foregroundStyle(BodyFlowColor.primaryText)
            }
            .bodyFlowListRow()

            if accountEmail != nil, let signOut {
                Section {
                    Button(role: .destructive) {
                        isConfirmingSignOut = true
                    } label: {
                        Text(copy("profile.account.sign-out"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .destructive))
                    .disabled(isSigningOut)
                    .accessibilityIdentifier("profile.account.sign-out")
                    .confirmationDialog(
                        copy("profile.account.sign-out.confirm"),
                        isPresented: $isConfirmingSignOut,
                        titleVisibility: .visible
                    ) {
                        Button(copy("profile.account.sign-out"), role: .destructive) {
                            isSigningOut = true
                            Task {
                                await signOut()
                                isSigningOut = false
                            }
                        }
                    }
                } header: {
                    Text(copy("profile.account.section"))
                        .foregroundStyle(BodyFlowColor.primaryText)
                }
                .bodyFlowListRow()
            }
        }
        .bodyFlowList()
    }

    /// Identity as one row: the person glyph inline with the title, the
    /// provenance line under it. One structure for every Dynamic Type size
    /// (the automated audit reads the title across sizes, and a layout
    /// switch at the accessibility boundary registers as a font-size
    /// discontinuity) and the same width the section had before, so the
    /// persona row below stays within tap reach at AXXXL.
    private var identityRow: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Label(verbatim: accountEmail ?? fixture.title, symbol: .person)
                .font(BodyFlowTypography.headline)
                .foregroundStyle(BodyFlowColor.primaryText)

            identityDisclosure
        }
    }

    private var identityDisclosure: some View {
        Text(copy(accountEmail == nil
            ? "profile.fixture.disclosure"
            : "profile.identity.account-disclosure"))
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var personaDisplayName: String {
        guard hasLoadedPersona else { return copy("profile.persona.loading") }
        guard let selectedPersona else {
            return copy("profile.persona.not-selected")
        }
        guard let options = serverOptions,
              let pickerOptions = CoachPersonaEditorModel
                .validatedPickerOptions(options)
        else {
            return copy("profile.persona.unavailable")
        }
        return pickerOptions.first(where: { $0.persona == selectedPersona })?.name
            ?? copy("profile.persona.unavailable")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        ProfileCopy.string(key, language: language)
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

enum ProfileCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
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
