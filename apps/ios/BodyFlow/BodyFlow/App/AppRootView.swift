import SwiftUI

@MainActor
struct AppRootView: View {
    let model: AppFlowModel
    let dependencies: AppDependencies
    let configuration: AppLaunchConfiguration

    var body: some View {
        Group {
            rootContent
        }
        .installAppDependencies(dependencies)
        .task {
            await model.start()
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
            ProgressView("Carregando onboarding")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BodyFlowColor.background)
                .accessibilityLabel("Carregando onboarding")
        case .authenticated(let userID):
            AppShellView(userID: userID)
        }
    }
}
