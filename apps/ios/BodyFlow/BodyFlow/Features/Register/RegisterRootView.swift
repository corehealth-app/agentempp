import SwiftUI

@MainActor
struct RegisterRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    mealTile(mealCommand)
                        .guidedTourTarget(.mealCommand)
                }

                if presentsLocalDemonstration {
                    BodyFlowStatusLine(
                        copy("registration.root.demo-notice"),
                        kind: .info
                    )
                }

                // The remaining kinds: three tiles in their own colors at
                // regular text sizes, one panel of rows at larger ones.
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    BodyFlowSectionHeader(copy("registration.root.other-actions"))
                    let commands = fixture.commands.filter {
                        RegistrationKind(rawValue: $0.kindID) != .meal
                    }
                    if dynamicTypeSize <= .xLarge {
                        HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                            ForEach(commands) { command in
                                otherTile(command)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        BodyFlowCard {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                                    if index > 0 { Divider() }
                                    Button {
                                        present(command)
                                    } label: {
                                        FeatureActionLabel(
                                            title: commandTitle(for: command),
                                            detail: openDetail,
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
            }
            .padding(BodyFlowSpacing.md)
            .containerRelativeFrame(.horizontal)
        }
    }

    private var openDetail: String {
        copy(presentsLocalDemonstration ? "registration.root.open-demo" : "registration.root.open")
    }

    /// The meal is the one primary action: a brand tile that names the three
    /// ways to tell the app what was eaten. The ways are a hint, not three
    /// buttons — the sheet that opens offers them.
    private func mealTile(_ command: RegistrationCommandFixture) -> some View {
        Button { present(command) } label: {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    Text(verbatim: commandTitle(for: command))
                        .font(BodyFlowTypography.screenTitle)
                    Text(verbatim: copy("registration.root.meal.detail"))
                        .font(BodyFlowTypography.callout)
                }
                .foregroundStyle(BodyFlowColor.color(.onPrimary))
                .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize <= .xLarge {
                    HStack(spacing: BodyFlowSpacing.xs) {
                        way(.camera, copy("registration.root.way.photo"))
                        way(.compose, copy("registration.root.way.text"))
                        way(.microphone, copy("registration.root.way.audio"))
                    }
                    .accessibilityHidden(true)
                }
            }
            .padding(BodyFlowSpacing.md)
            .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
            .background(
                BodyFlowColor.color(.brandPrimary),
                in: RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRowAction)
        .disabled(RegistrationKind(rawValue: command.kindID) == nil)
        .accessibilityLabel(commandTitle(for: command))
        .accessibilityHint(copy("registration.root.meal.detail"))
        .accessibilityIdentifier(identifier(for: command))
    }

    private func way(_ symbol: BodyFlowSymbol, _ title: String) -> some View {
        VStack(spacing: BodyFlowSpacing.xxs) {
            Image(symbol: symbol).font(.system(size: 17, weight: .semibold)).frame(height: 22)
            Text(verbatim: title).font(BodyFlowTypography.caption.weight(.semibold))
        }
        .foregroundStyle(BodyFlowColor.color(.brandPrimary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, BodyFlowSpacing.xs)
        .background(
            BodyFlowColor.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
        )
    }

    private func otherTile(_ command: RegistrationCommandFixture) -> some View {
        Button { present(command) } label: {
            BodyFlowCard(surface: .elevated, padding: BodyFlowSpacing.sm) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    BodyFlowDomainGlyph(domain: domain(for: command), diameter: 36)
                    Text(verbatim: commandTitle(for: command))
                        .font(BodyFlowTypography.headline)
                        .foregroundStyle(BodyFlowColor.primaryText)
                    Text(verbatim: openDetail)
                        .font(BodyFlowTypography.caption)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget,
                    maxHeight: .infinity, alignment: .topLeading
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRow)
        .disabled(RegistrationKind(rawValue: command.kindID) == nil)
        .accessibilityIdentifier(identifier(for: command))
    }

    private func domain(for command: RegistrationCommandFixture) -> BodyFlowDomain {
        switch RegistrationKind(rawValue: command.kindID) {
        case .training: .exercise
        case .hydration: .hydration
        case .weight: .progress
        case .meal, nil: .energy
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
