import SwiftUI

@MainActor
struct RegisterRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.locale) private var locale

    let fixture: RegistrationFixture
    let state: ScreenContentState
    /// True for the local demonstration (demo authentication); false on a
    /// real account, where the copy describes the real server-backed flow.
    let presentsLocalDemonstration: Bool
    private let retryAction: @MainActor () -> Void

    init(
        fixture: RegistrationFixture = AppFixtures.registration,
        state: ScreenContentState = .loaded,
        presentsLocalDemonstration: Bool = true,
        retryAction: @escaping @MainActor () -> Void = {}
    ) {
        self.fixture = fixture
        self.state = state
        self.presentsLocalDemonstration = presentsLocalDemonstration
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
                // The screen asks one question and answers it with one
                // primary action; the eyebrow that repeated the tab name is
                // gone.
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(copy("registration.root.title"))
                        .font(BodyFlowTypography.screenTitle)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(copy(presentsLocalDemonstration
                        ? "registration.root.detail"
                        : "registration.root.detail.live"))
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let mealCommand = fixture.commands.first(where: {
                    RegistrationKind(rawValue: $0.kindID) == .meal
                }) {
                    commandButton(mealCommand, role: .primary)
                        .guidedTourTarget(.mealCommand)
                }

                if presentsLocalDemonstration {
                    BodyFlowStatusLine(
                        copy("registration.root.demo-notice"),
                        kind: .info
                    )
                }

                // The remaining kinds share one panel of rows instead of one
                // card each, so the primary action keeps its weight.
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    BodyFlowSectionHeader(copy("registration.root.other-actions"))

                    BodyFlowCard {
                        VStack(alignment: .leading, spacing: 0) {
                            let commands = fixture.commands.filter {
                                RegistrationKind(rawValue: $0.kindID) != .meal
                            }
                            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                                if index > 0 { Divider() }
                                Button {
                                    present(command)
                                } label: {
                                    FeatureActionLabel(
                                        title: commandTitle(for: command),
                                        detail: copy(presentsLocalDemonstration
                                            ? "registration.root.open-demo"
                                            : "registration.root.open"),
                                        systemImage: command.systemImage
                                    )
                                    .padding(.vertical, BodyFlowSpacing.xs)
                                }
                                .buttonStyle(.bodyFlowRow)
                                .disabled(RegistrationKind(rawValue: command.kindID) == nil)
                                .accessibilityIdentifier(identifier(for: command))
                            }
                        }
                    }
                }
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
