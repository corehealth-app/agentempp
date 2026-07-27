import SwiftUI

@MainActor
struct AppRootView: View {
    let model: AppFlowModel
    let dependencies: AppDependencies
    let configuration: AppLaunchConfiguration
    @State private var onboardingFlowModel: OnboardingFlowModel?
    @State private var onboardingLoadFailed = false
    @State private var onboardingRetryID = 0

    var body: some View {
        Group {
            rootContent
        }
        .installAppDependencies(dependencies)
        .task {
            await model.start()
        }
        .task(id: onboardingTaskID) {
            await synchronizeOnboardingModel()
        }
    }

    @ViewBuilder
    private var rootContent: some View {
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
        case .onboarding:
            if let onboardingFlowModel {
                OnboardingContainerView(model: onboardingFlowModel)
            } else if onboardingLoadFailed {
                onboardingLoadError
            } else {
                ProgressView("Carregando onboarding")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BodyFlowColor.background)
                    .accessibilityLabel("Carregando onboarding")
            }
        case .authenticated(let userID):
            AppShellView(userID: userID)
        }
    }

    private var onboardingUserID: String? {
        guard case .onboarding(let userID, _) = model.state else { return nil }
        return userID
    }

    private var onboardingTaskID: OnboardingRootTaskID {
        OnboardingRootTaskID(userID: onboardingUserID, retryID: onboardingRetryID)
    }

    private var onboardingLoadError: some View {
        ContentUnavailableView {
            Label("Não foi possível carregar", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Tente novamente para continuar seu onboarding.")
        } actions: {
            Button("Tentar novamente") {
                onboardingRetryID += 1
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.background)
    }

    private func synchronizeOnboardingModel() async {
        guard let userID = onboardingUserID else {
            onboardingFlowModel = nil
            onboardingLoadFailed = false
            return
        }
        guard onboardingFlowModel?.userID != userID else { return }

        onboardingFlowModel = nil
        onboardingLoadFailed = false
        do {
            guard let draft = try await dependencies.onboarding.loadDraft(for: userID),
                  !Task.isCancelled,
                  onboardingUserID == userID else {
                if !Task.isCancelled, onboardingUserID == userID {
                    onboardingLoadFailed = true
                }
                return
            }
            onboardingFlowModel = OnboardingFlowModel(
                userID: userID,
                initialDraft: draft,
                repository: dependencies.onboarding,
                onStepChanged: { step in
                    guard onboardingUserID == userID else { return }
                    model.updateOnboardingStep(step)
                },
                onCompleted: {
                    // Task 6 owns final persistence and authenticated transition.
                }
            )
        } catch is CancellationError {
            return
        } catch {
            guard onboardingUserID == userID else { return }
            onboardingLoadFailed = true
        }
    }
}

private struct OnboardingRootTaskID: Equatable {
    let userID: String?
    let retryID: Int
}
