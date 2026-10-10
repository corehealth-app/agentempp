import SwiftUI

/// The sign-up of the signed-in account could not be loaded.
///
/// The screen says why as far as the app knows and always offers a way out
/// of the account. Before the first update it offered only "Tentar
/// novamente": an account the server refuses stayed here forever, because
/// the same session is restored on every launch (reported on 2026-10-10 for
/// an e-mail that administers the team's panel).
struct OnboardingLoadErrorView: View {
    let failure: OnboardingLoadFailure
    let retry: @MainActor () -> Void
    let signOut: @MainActor () async -> Void

    var body: some View {
        GeometryReader { proxy in
            // The longest message and both actions stay reachable at the
            // largest text size: the content scrolls when it has to.
            ScrollView {
                OnboardingLoadErrorContent(failure: failure, retry: retry, signOut: signOut)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(BodyFlowColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.load-error")
    }
}

/// What the screen says and offers, without the scrolling around it.
struct OnboardingLoadErrorContent: View {
    let failure: OnboardingLoadFailure
    let retry: @MainActor () -> Void
    let signOut: @MainActor () async -> Void
    @Environment(\.locale) private var locale
    @State private var isSigningOut = false

    /// The same column the shared state screen uses (`ScreenStateView`): it
    /// has the height of what it shows, so the screen scrolls it when the
    /// text is large, as that screen already does everywhere else.
    var body: some View {
        VStack(spacing: BodyFlowSpacing.md) {
            Image(symbol: .warning)
                .font(BodyFlowTypography.largeTitle)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(BodyFlowTypography.screenTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityIdentifier("onboarding.load-error.message")
            actions
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, BodyFlowSpacing.lg)
        .padding(.vertical, BodyFlowSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: BodyFlowSpacing.sm) {
            switch failure {
            case .teamPanelAccount:
                // Trying again cannot change which account this is.
                signOutButton(role: .primary)
            case .temporary:
                Button(copy("app.retry", fallback: "Tentar novamente")) {
                    retry()
                }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .disabled(isSigningOut)
                .accessibilityIdentifier("onboarding.load-error.retry")
                signOutButton(role: .secondary)
            }
        }
    }

    private func signOutButton(role: BodyFlowButtonRole) -> some View {
        Button(copy("app.sign-out", fallback: "Sair da conta")) {
            guard !isSigningOut else { return }
            isSigningOut = true
            Task {
                // A sign-out that works replaces this screen with "Entrar";
                // one that fails leaves the person here, able to try again.
                await signOut()
                isSigningOut = false
            }
        }
        .buttonStyle(BodyFlowButtonStyle(role: role, isLoading: isSigningOut))
        .disabled(isSigningOut)
        .accessibilityIdentifier("onboarding.load-error.sign-out")
    }

    private var title: String {
        switch failure {
        case .teamPanelAccount:
            copy("app.onboarding.error.team-account.title", fallback: "Use outro e-mail no app")
        case .temporary:
            copy("app.onboarding.error.title", fallback: "Não foi possível carregar")
        }
    }

    private var message: String {
        switch failure {
        case .teamPanelAccount:
            copy(
                "app.onboarding.error.team-account.message",
                fallback: "Este e-mail é do painel da equipe. O app precisa de um e-mail diferente. "
                    + "Saia desta conta e entre com outro e-mail."
            )
        case .temporary:
            copy(
                "app.onboarding.error.message",
                fallback: "Tente novamente para continuar seu cadastro."
            )
        }
    }

    private func copy(
        _ key: String.LocalizationValue,
        fallback: String
    ) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
}
