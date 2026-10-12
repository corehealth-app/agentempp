import SwiftUI

@MainActor
struct AppRootView: View {
    let model: AppFlowModel
    let dependencies: AppDependencies
    let configuration: AppLaunchConfiguration
    @Namespace private var brandNamespace
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var systemDifferentiateWithoutColor
    @State private var onboardingCoordinator = OnboardingRootCoordinator()
    @State private var authenticatedShellCoordinator: Prompt14AuthenticatedShellCoordinator
    @State private var onboardingRetryTask: Task<Void, Never>?
    @State private var appearance: BodyFlowAppearanceStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    init(
        model: AppFlowModel,
        dependencies: AppDependencies,
        configuration: AppLaunchConfiguration
    ) {
        self.model = model
        self.dependencies = dependencies
        self.configuration = configuration
        _authenticatedShellCoordinator = State(
            initialValue: Prompt14AuthenticatedShellCoordinator(
                dependencies: dependencies
            )
        )
        _appearance = State(initialValue: BodyFlowAppearanceStore.make(isDemo: configuration.mode == .demo))
    }

    var body: some View {
        Group {
            rootContent
                .transition(
                    hasOutgoingSessionOwner
                        ? .identity
                        : BodyFlowMotion.stateTransition(reduceMotion: effectiveReduceMotion)
                )
        }
        // The root changes with the brand duration (400 ms) so the Signal
        // Spark mark is seen travelling from the splash into the tab bar.
        .animation(
            hasOutgoingSessionOwner
                ? nil
                : BodyFlowMotion.animation(.brand, reduceMotion: effectiveReduceMotion),
            value: rootPresentationKey
        )
        .transaction { transaction in
            if hasOutgoingSessionOwner {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .installAppDependencies(dependencies)
        .environment(
            \.performeBrandNamespace,
            hasOutgoingSessionOwner ? nil : brandNamespace
        )
        // Appearance only: the catalog AccentColor is a historical asset (its
        // dark value is the achievement gold), so every SwiftUI control that
        // is not explicitly tinted — sheets, dialogs, auth and onboarding —
        // takes the semantic brand primary from here instead.
        .tint(BodyFlowColor.color(.brandPrimary))
        .bodyFlowVisualEnvironment(
            reduceMotion: effectiveReduceMotion,
            differentiateWithoutColor: configuration.differentiateWithoutColorOverride
                ?? systemDifferentiateWithoutColor
        )
        // Light/dark: the person's choice, or the clock (day light, night
        // dark), or the system. nil leaves it to the system.
        .preferredColorScheme(appearance.colorScheme)
        .environment(appearance)
        .task { await appearance.followSchedule() }
        .onChange(of: scenePhase) { _, phase in
            model.setCleanupActive(phase == .active)
            if phase == .active { appearance.refreshClock() }
        }
        .task {
            model.setCleanupActive(scenePhase == .active)
            await model.start()
        }
        .task(id: onboardingTaskID) {
            await synchronizeOnboardingModel()
        }
        .task(id: requestedAuthenticatedUserID) {
            await authenticatedShellCoordinator.transition(
                to: requestedAuthenticatedUserID
            )
        }
        .task(id: isSignedOut) {
            // No local reminder survives without a signed-in account: this
            // also finishes a clean-up that a sign-out could not complete
            // (for example, the app ended right after the sign-out marker).
            guard isSignedOut else { return }
            await (dependencies.localReminders?.scheduler ?? LocalReminderScheduler.system).clearAll()
        }
        .onDisappear {
            model.setCleanupActive(false)
            onboardingRetryTask?.cancel()
            onboardingRetryTask = nil
        }
    }

    private var isSignedOut: Bool {
        if case .signedOut = model.state { return true }
        return false
    }

    @ViewBuilder
    private var rootContent: some View {
        if let label = splashLandscapeAccessibilityTestLabel {
            SplashView(loadingLabel: label)
        } else if authenticatedShellCoordinator.requiresNeutralRoot(
            for: requestedAuthenticatedUserID
        ) {
            authenticatedSessionLoading
        } else {
            switch model.state {
            case .launching:
                SplashView()
            case .signedOut(.signIn):
                SignInView(model: model)
            case .signedOut(.signUp):
                SignUpView(model: model)
            case .signedOut(.passwordRecovery):
                PasswordRecoveryView(model: model)
            case .awaitingEmailConfirmation(let email):
                EmailConfirmationView(
                    email: email,
                    allowsDevelopmentConfirmation: configuration.mode == .demo,
                    model: model
                )
            case .onboarding(let userID, _):
                if let onboardingFlowModel = onboardingCoordinator.flowModel,
                   onboardingCoordinator.canRender(ownerToken: model.onboardingOwnerToken),
                   OnboardingRootLoadState.canRender(
                       modelUserID: onboardingFlowModel.userID,
                       activeUserID: userID
                   ) {
                    OnboardingContainerView(model: onboardingFlowModel)
                } else if onboardingCoordinator.flowModel == nil,
                          onboardingCoordinator.loadFailed {
                    onboardingLoadError
                } else {
                    rootLoading(
                        "app.onboarding.loading",
                        fallback: "Carregando seu cadastro"
                    )
                }
            case .authenticated(let userID):
                if let owner = authenticatedShellCoordinator.renderableOwner(
                    for: userID
                ) {
                    AppShellView(
                        userID: userID,
                        dependencies: dependencies,
                        sessionOwner: owner,
                        accountEmail: dependencies.presentsRealAccountIdentity
                            ? model.currentSession?.email : nil,
                        signOut: accountSignOut
                    )
                    .id(userID)
                } else {
                    authenticatedSessionLoading
                }
            }
        }
    }

    private var splashLandscapeAccessibilityTestLabel: String? {
        #if DEBUG
        configuration.splashLandscapeAccessibilityTestLabel
        #else
        nil
        #endif
    }

    private var authenticatedSessionLoading: some View {
        rootLoading("app.session.loading", fallback: "Carregando sessão")
    }

    /// Only a real account can leave from Profile; the demo keeps its
    /// fixture identity without an account action.
    private var accountSignOut: (@MainActor () async -> Void)? {
        guard dependencies.presentsRealAccountIdentity else { return nil }
        let model = model
        return { await model.signOut() }
    }

    /// The screen the root shows, not the state's own payload: switching
    /// sign-in ↔ sign-up ↔ recovery, or entering/leaving onboarding, fades;
    /// an onboarding step change does not retrigger this fade (the
    /// container animates that on its own, keyed to `model.step`).
    private enum RootPresentationKey: Equatable {
        case neutralLoading
        case launching
        case signIn, signUp, passwordRecovery
        case awaitingEmailConfirmation
        case onboardingLoading, onboardingReady, onboardingError
        case authenticatedLoading, authenticatedReady
    }

    private var rootPresentationKey: RootPresentationKey {
        if authenticatedShellCoordinator.requiresNeutralRoot(
            for: requestedAuthenticatedUserID
        ) {
            return .neutralLoading
        }
        switch model.state {
        case .launching: return .launching
        case .signedOut(.signIn): return .signIn
        case .signedOut(.signUp): return .signUp
        case .signedOut(.passwordRecovery): return .passwordRecovery
        case .awaitingEmailConfirmation: return .awaitingEmailConfirmation
        case .onboarding(let userID, _):
            if let onboardingFlowModel = onboardingCoordinator.flowModel,
               onboardingCoordinator.canRender(ownerToken: model.onboardingOwnerToken),
               OnboardingRootLoadState.canRender(
                   modelUserID: onboardingFlowModel.userID,
                   activeUserID: userID
               ) {
                return .onboardingReady
            } else if onboardingCoordinator.flowModel == nil,
                      onboardingCoordinator.loadFailed {
                return .onboardingError
            }
            return .onboardingLoading
        case .authenticated(let userID):
            return authenticatedShellCoordinator.renderableOwner(for: userID) != nil
                ? .authenticatedReady
                : .authenticatedLoading
        }
    }

    private var effectiveReduceMotion: Bool {
        BodyFlowReduceMotionPolicy.effectiveValue(
            systemValue: systemReduceMotion,
            override: configuration.accessibilityReduceMotionOverride
        )
    }

    private var requestedAuthenticatedUserID: String? {
        guard case let .authenticated(userID) = model.state else { return nil }
        return userID
    }

    /// A removed shell or onboarding must not remain in an outgoing transition:
    /// the next root may represent a different authentication activation.
    /// After teardown, the neutral root may animate into its safe destination.
    private var hasOutgoingSessionOwner: Bool {
        if let owner = onboardingCoordinator.ownerToken,
           owner != model.onboardingOwnerToken { return true }
        if case .onboarding = model.state, model.onboardingOwnerToken == nil {
            return true
        }
        if authenticatedShellCoordinator.tearingDownOwner != nil { return true }
        guard let owner = authenticatedShellCoordinator.renderableOwner else {
            return false
        }
        return owner.isInvalidated || owner.userID != requestedAuthenticatedUserID
    }

    private var onboardingUserID: String? {
        model.onboardingOwnerToken?.userID
    }

    private var onboardingTaskID: OnboardingRootTaskID {
        OnboardingRootTaskID(
            userID: onboardingUserID,
            restoreGeneration: model.onboardingRestoreGeneration
        )
    }

    /// The sign-up could not be loaded: the screen says why as far as the
    /// model knows, and always offers a way out of the account.
    private var onboardingLoadError: some View {
        let model = model
        return OnboardingLoadErrorView(
            failure: model.onboardingLoadFailure ?? .temporary,
            retry: {
                onboardingCoordinator.prepareForRetry()
                onboardingRetryTask?.cancel()
                onboardingRetryTask = Task {
                    await model.retryOnboardingRestore()
                }
            },
            signOut: { await model.signOut() }
        )
    }

    private func rootLoading(
        _ key: String.LocalizationValue,
        fallback: String
    ) -> some View {
        SplashView(loadingLabel: rootCopy(key, fallback: fallback))
    }

    private func rootCopy(
        _ key: String.LocalizationValue,
        fallback: String
    ) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }

    private func synchronizeOnboardingModel() async {
        let activeUserID = onboardingUserID
        let ownerToken = model.onboardingOwnerToken
        onboardingCoordinator.synchronize(
            activeUserID: activeUserID,
            restoredDraft: model.restoredOnboardingDraft,
            restoreGeneration: model.onboardingRestoreGeneration,
            historicalCompletedAt: model.restoredHistoricalCompletedAt,
            requirements: model.restoredOnboardingRequirements,
            onboarding: model.onboardingRepositoryForCurrentOwner,
            persona: dependencies.coachPersona,
            developmentConsentAvailability: configuration.developmentConsentAvailability,
            idempotencyKeyProvider: dependencies.idempotencyKeyProvider,
            telemetry: dependencies.telemetry,
            onStepChanged: { step in
                guard ownerToken != nil, model.onboardingOwnerToken == ownerToken else { return }
                guard let ownerToken else { return }
                model.updateOnboardingStep(step, ownerToken: ownerToken)
            },
            onCompleted: {
                guard let userID = activeUserID,
                      onboardingUserID == userID, model.onboardingOwnerToken == ownerToken else { return }
                guard let ownerToken else { return }
                model.completeOnboarding(ownerToken: ownerToken)
            },
            onOfficialCleanupObserved: { observation in
                guard let ownerToken else { return }
                _ = await model.observeOnboardingCleanup(observation, ownerToken: ownerToken)
            }
        )
    }
}

enum BodyFlowReduceMotionPolicy {
    static func effectiveValue(
        systemValue: Bool,
        override: Bool?
    ) -> Bool {
        override ?? systemValue
    }
}

private struct BodyFlowReduceMotionEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var bodyFlowReduceMotion: Bool {
        get { self[BodyFlowReduceMotionEnvironmentKey.self] }
        set { self[BodyFlowReduceMotionEnvironmentKey.self] = newValue }
    }
}

private struct BodyFlowDifferentiateWithoutColorEnvironmentKey:
    EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var bodyFlowDifferentiateWithoutColor: Bool {
        get { self[BodyFlowDifferentiateWithoutColorEnvironmentKey.self] }
        set {
            self[BodyFlowDifferentiateWithoutColorEnvironmentKey.self] = newValue
        }
    }
}

private struct OnboardingRootTaskID: Equatable {
    let userID: String?
    let restoreGeneration: Int
}

@MainActor
struct OnboardingRootCoordinator {
    private(set) var flowModel: OnboardingFlowModel?
    private(set) var loadFailed = false
    private(set) var ownerToken: OnboardingOwnerToken?

    func canRender(ownerToken: OnboardingOwnerToken?) -> Bool {
        ownerToken != nil && self.ownerToken == ownerToken && flowModel?.isActive == true
    }

    mutating func prepareForRetry() {
        loadFailed = false
    }

    mutating func synchronize(
        activeUserID: String?,
        restoredDraft: OnboardingDraft?,
        restoreGeneration: Int = 0,
        historicalCompletedAt: String? = nil,
        requirements: OnboardingRequirements = .unavailable,
        onboarding: any OnboardingRepository,
        persona: any CoachPersonaRepository,
        developmentConsentAvailability: DevelopmentConsentAvailability,
        idempotencyKeyProvider: any IdempotencyKeyProviding = RandomIdempotencyKeyProvider(),
        telemetry: any TelemetryClient,
        onStepChanged: @escaping @MainActor (OnboardingStep) -> Void,
        onCompleted: @escaping @MainActor () -> Void,
        onOfficialCleanupObserved: @escaping @MainActor (OnboardingBodyPhotoCleanupScope?) async -> Void = { _ in }
    ) {
        guard let activeUserID else {
            flowModel?.invalidate()
            flowModel = nil
            ownerToken = nil
            loadFailed = false
            return
        }
        let requestedOwner = OnboardingOwnerToken(userID: activeUserID, restoreGeneration: restoreGeneration)
        guard ownerToken != requestedOwner || flowModel?.isActive != true else { return }

        flowModel?.invalidate()
        flowModel = nil
        ownerToken = requestedOwner
        loadFailed = false
        guard let restoredDraft else {
            loadFailed = true
            return
        }

        flowModel = OnboardingFlowModel(
            userID: activeUserID,
            initialDraft: restoredDraft,
            repository: onboarding,
            personaRepository: persona,
            developmentConsentAvailability: developmentConsentAvailability,
            requirements: requirements,
            historicalCompletedAt: historicalCompletedAt,
            idempotencyKeyProvider: idempotencyKeyProvider,
            telemetry: telemetry,
            onStepChanged: onStepChanged,
            onCompleted: onCompleted,
            onOfficialCleanupObserved: onOfficialCleanupObserved
        )
    }
}

struct OnboardingRootLoadState: Equatable {
    struct Token: Equatable {
        let userID: String
        let generation: Int
    }

    private var generation = 0
    private(set) var activeToken: Token?

    mutating func begin(for userID: String) -> Token {
        generation += 1
        let token = Token(userID: userID, generation: generation)
        activeToken = token
        return token
    }

    mutating func invalidate() {
        activeToken = nil
    }

    func canPublish(
        _ token: Token,
        activeUserID: String?,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && activeToken == token && activeUserID == token.userID
    }

    static func canRender(modelUserID: String, activeUserID: String) -> Bool {
        modelUserID == activeUserID
    }
}
