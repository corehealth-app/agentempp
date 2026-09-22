import SwiftUI

@MainActor
struct RegisterRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.locale) private var locale

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
        .navigationTitle(copy("registration.root.navigation-title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(copy("registration.root.eyebrow"))
                        .font(BodyFlowTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.accent)

                    Text(copy("registration.root.title"))
                        .font(BodyFlowTypography.title)
                        .fontWeight(.bold)
                        .foregroundStyle(BodyFlowColor.primaryText)

                    Text(copy("registration.root.detail"))
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }

                if let mealCommand = fixture.commands.first(where: {
                    RegistrationKind(rawValue: $0.kindID) == .meal
                }) {
                    commandButton(mealCommand, role: .primary)
                }

                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    Text(copy("registration.root.other-actions"))
                        .font(BodyFlowTypography.headline)
                        .foregroundStyle(BodyFlowColor.primaryText)
                    ForEach(fixture.commands.filter {
                        RegistrationKind(rawValue: $0.kindID) != .meal
                    }) { command in
                        Button {
                            present(command)
                        } label: {
                            BodyFlowCard {
                                FeatureActionLabel(
                                    title: commandTitle(for: command),
                                    detail: copy("registration.root.open-demo"),
                                    systemImage: command.systemImage
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(RegistrationKind(rawValue: command.kindID) == nil)
                        .accessibilityIdentifier(identifier(for: command))
                    }
                }

                Label(copy("registration.root.demo-notice"), systemImage: "info.circle")
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .padding(.horizontal, BodyFlowSpacing.xs)
            }
            .padding(BodyFlowSpacing.md)
        }
    }

    private func commandButton(
        _ command: RegistrationCommandFixture,
        role: BodyFlowButtonRole
    ) -> some View {
        Button { present(command) } label: {
            Label(commandTitle(for: command), systemImage: command.systemImage)
        }
        .buttonStyle(BodyFlowButtonStyle(role: role))
        .disabled(RegistrationKind(rawValue: command.kindID) == nil)
        .accessibilityIdentifier(identifier(for: command))
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

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func commandTitle(for command: RegistrationCommandFixture) -> String {
        guard let kind = RegistrationKind(rawValue: command.kindID) else {
            return command.title
        }
        let key: String.LocalizationValue = switch kind {
        case .meal: "registration.kind.meal"
        case .training: "registration.kind.workout"
        case .weight: "registration.kind.weight"
        case .hydration: "registration.kind.hydration"
        }
        return copy(key)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
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
