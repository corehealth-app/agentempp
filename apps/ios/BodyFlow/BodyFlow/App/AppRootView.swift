import SwiftUI

@MainActor
struct AppRootView: View {
    let model: AppFlowModel
    let dependencies: AppDependencies
    let configuration: AppLaunchConfiguration
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var systemDifferentiateWithoutColor
    @State private var onboardingCoordinator = OnboardingRootCoordinator()
    @State private var authenticatedShellCoordinator: Prompt14AuthenticatedShellCoordinator
    @State private var onboardingRetryTask: Task<Void, Never>?

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
    }

    var body: some View {
        Group {
            rootContent
        }
        .installAppDependencies(dependencies)
        .environment(
            \.bodyFlowReduceMotion,
            BodyFlowReduceMotionPolicy.effectiveValue(
                systemValue: systemReduceMotion,
                override: configuration.accessibilityReduceMotionOverride
            )
        )
        .environment(
            \.bodyFlowDifferentiateWithoutColor,
            configuration.differentiateWithoutColorOverride
                ?? systemDifferentiateWithoutColor
        )
        .task {
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
        .onDisappear {
            onboardingRetryTask?.cancel()
            onboardingRetryTask = nil
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if authenticatedShellCoordinator.requiresNeutralRoot(
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
                   OnboardingRootLoadState.canRender(
                       modelUserID: onboardingFlowModel.userID,
                       activeUserID: userID
                   ) {
                    OnboardingContainerView(model: onboardingFlowModel)
                } else if onboardingCoordinator.flowModel == nil,
                          onboardingCoordinator.loadFailed {
                    onboardingLoadError
                } else {
                    ProgressView("Carregando onboarding")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(BodyFlowColor.background)
                        .accessibilityLabel("Carregando onboarding")
                }
            case .authenticated(let userID):
                if let owner = authenticatedShellCoordinator.renderableOwner(
                    for: userID
                ) {
                    AppShellView(
                        userID: userID,
                        dependencies: dependencies,
                        sessionOwner: owner
                    )
                    .id(userID)
                } else {
                    authenticatedSessionLoading
                }
            }
        }
    }

    private var authenticatedSessionLoading: some View {
        ProgressView("Carregando sessão")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BodyFlowColor.background)
            .accessibilityLabel("Carregando sessão")
    }

    private var requestedAuthenticatedUserID: String? {
        guard case let .authenticated(userID) = model.state else { return nil }
        return userID
    }

    private var onboardingUserID: String? {
        guard case .onboarding(let userID, _) = model.state else { return nil }
        return userID
    }

    private var onboardingTaskID: OnboardingRootTaskID {
        OnboardingRootTaskID(
            userID: onboardingUserID,
            restoreGeneration: model.onboardingRestoreGeneration
        )
    }

    private var onboardingLoadError: some View {
        ContentUnavailableView {
            Label("Não foi possível carregar", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Tente novamente para continuar seu onboarding.")
        } actions: {
            Button("Tentar novamente") {
                onboardingCoordinator.prepareForRetry()
                onboardingRetryTask?.cancel()
                onboardingRetryTask = Task {
                    await model.retryOnboardingRestore()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.background)
    }

    private func synchronizeOnboardingModel() async {
        let activeUserID = onboardingUserID
        onboardingCoordinator.synchronize(
            activeUserID: activeUserID,
            restoredDraft: model.restoredOnboardingDraft,
            onboarding: dependencies.onboarding,
            persona: dependencies.coachPersona,
            developmentConsentAvailability: configuration.developmentConsentAvailability,
            telemetry: dependencies.telemetry,
            onStepChanged: { step in
                guard onboardingUserID == activeUserID else { return }
                model.updateOnboardingStep(step)
            },
            onCompleted: {
                guard let userID = activeUserID,
                      onboardingUserID == userID else { return }
                model.completeOnboarding(for: userID)
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

    mutating func prepareForRetry() {
        loadFailed = false
    }

    mutating func synchronize(
        activeUserID: String?,
        restoredDraft: OnboardingDraft?,
        onboarding: any OnboardingRepository,
        persona: any CoachPersonaRepository,
        developmentConsentAvailability: DevelopmentConsentAvailability,
        telemetry: any TelemetryClient,
        onStepChanged: @escaping @MainActor (OnboardingStep) -> Void,
        onCompleted: @escaping @MainActor () -> Void
    ) {
        guard let activeUserID else {
            flowModel = nil
            loadFailed = false
            return
        }
        guard flowModel?.userID != activeUserID else { return }

        flowModel = nil
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
            telemetry: telemetry,
            onStepChanged: onStepChanged,
            onCompleted: onCompleted
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
