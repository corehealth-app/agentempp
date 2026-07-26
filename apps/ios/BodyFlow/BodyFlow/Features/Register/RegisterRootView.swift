import SwiftUI

@MainActor
struct RegisterRootView: View {
    @Environment(AppRouter.self) private var router

    let fixture: RegistrationFixture
    let state: ScreenContentState
    private let retryAction: @MainActor () -> Void

    init(
        fixture: RegistrationFixture = AppFixtures.registration,
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
        .accessibilityIdentifier(AppTab.register.rootAccessibilityIdentifier)
        .navigationTitle("Registrar")
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("REGISTRO RÁPIDO")
                        .font(BodyFlowTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.accent)

                    Text("O que você quer registrar?")
                        .font(BodyFlowTypography.title)
                        .fontWeight(.bold)
                        .foregroundStyle(BodyFlowColor.primaryText)

                    Text("Escolha uma opção para abrir uma demonstração local.")
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }

                VStack(spacing: BodyFlowSpacing.sm) {
                    ForEach(fixture.commands) { command in
                        Button {
                            present(command)
                        } label: {
                            BodyFlowCard {
                                FeatureActionLabel(
                                    title: command.title,
                                    detail: "Abrir demonstração",
                                    systemImage: command.systemImage
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(RegistrationKind(rawValue: command.kindID) == nil)
                        .accessibilityIdentifier(identifier(for: command))
                    }
                }

                Label(fixture.disclaimer, systemImage: "info.circle")
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .padding(.horizontal, BodyFlowSpacing.xs)
            }
            .padding(BodyFlowSpacing.md)
        }
    }

    private func present(_ command: RegistrationCommandFixture) {
        guard let kind = RegistrationKind(rawValue: command.kindID) else {
            return
        }
        router.presentedSheet = .registration(kind)
    }

    private func identifier(for command: RegistrationCommandFixture) -> String {
        guard let kind = RegistrationKind(rawValue: command.kindID) else {
            return "register.indisponivel"
        }
        return kind.commandAccessibilityIdentifier
    }
}

#Preview("Registrar · Loaded") {
    NavigationStack {
        RegisterRootView()
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}

#Preview("Registrar · Empty") {
    NavigationStack {
        RegisterRootView(state: .empty)
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}
