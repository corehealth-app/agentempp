import SwiftUI

struct BodyFlowBrandIdentityView: View {
    var body: some View {
        Text("BodyFlow")
            .font(BodyFlowTypography.headline)
            .fontWeight(.bold)
            .foregroundStyle(BodyFlowColor.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, BodyFlowSpacing.lg)
            .padding(.vertical, BodyFlowSpacing.xs)
            .background(BodyFlowColor.background)
            .overlay(alignment: .bottom) {
                Divider()
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("brand.product-name")
    }
}

extension View {
    func bodyFlowBrandIdentity() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            BodyFlowBrandIdentityView()
        }
    }
}

enum ScreenContentState: Equatable, Sendable {
    case loaded
    case loading
    case empty
    case recoverableError
    case offline

    var screenState: ScreenState? {
        switch self {
        case .loaded:
            nil
        case .loading:
            .loading
        case .empty:
            .empty
        case .recoverableError:
            .recoverableError
        case .offline:
            .offline
        }
    }
}

enum ScreenState: Equatable, Sendable {
    case loading
    case empty
    case recoverableError
    case offline

    struct Descriptor: Equatable, Sendable {
        let title: String
        let message: String
        let systemImage: String
        let showsRetry: Bool
    }

    var descriptor: Descriptor {
        switch self {
        case .loading:
            Descriptor(
                title: "Carregando",
                message: "Preparando suas informações.",
                systemImage: "hourglass",
                showsRetry: false
            )
        case .empty:
            Descriptor(
                title: "Nada por aqui",
                message: "Ainda não há conteúdo para mostrar.",
                systemImage: "tray",
                showsRetry: false
            )
        case .recoverableError:
            Descriptor(
                title: "Não foi possível carregar",
                message: "Ocorreu um problema temporário. Tente novamente.",
                systemImage: "arrow.clockwise",
                showsRetry: true
            )
        case .offline:
            Descriptor(
                title: "Você está offline",
                message: "Confira sua conexão e tente novamente.",
                systemImage: "wifi.slash",
                showsRetry: true
            )
        }
    }
}

struct ScreenStateView: View {
    let state: ScreenState
    private let retryAction: @MainActor () -> Void

    init(
        state: ScreenState,
        retryAction: @escaping @MainActor () -> Void
    ) {
        self.state = state
        self.retryAction = retryAction
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: BodyFlowSpacing.md) {
                    stateGraphic

                    Text(state.descriptor.title)
                        .font(BodyFlowTypography.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.primaryText)

                    Text(state.descriptor.message)
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)

                    if state.descriptor.showsRetry {
                        Button("Tentar novamente", action: triggerRetry)
                            .font(BodyFlowTypography.headline)
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                            .accessibilityIdentifier("state.retry")
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, BodyFlowSpacing.lg)
                .padding(.vertical, BodyFlowSpacing.xl)
                .frame(
                    maxWidth: .infinity,
                    minHeight: geometry.size.height
                )
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.background)
    }

    @MainActor
    func triggerRetry() {
        retryAction()
    }

    @ViewBuilder
    private var stateGraphic: some View {
        if state == .loading {
            ProgressView()
                .controlSize(.large)
                .tint(BodyFlowColor.accent)
                .accessibilityHidden(true)
        } else {
            Image(systemName: state.descriptor.systemImage)
                .font(BodyFlowTypography.largeTitle)
                .foregroundStyle(graphicColor)
                .accessibilityHidden(true)
        }
    }

    private var graphicColor: Color {
        state == .recoverableError ? BodyFlowColor.warning : BodyFlowColor.accent
    }
}

#if DEBUG
private struct ScreenContentStatePreviewHost: View {
    let state: ScreenContentState

    var body: some View {
        if state == .loaded {
            VStack(spacing: BodyFlowSpacing.md) {
                Image(systemName: "checkmark.circle")
                    .font(BodyFlowTypography.largeTitle)
                    .foregroundStyle(BodyFlowColor.accent)
                Text("Conteúdo carregado")
                    .font(BodyFlowTypography.title)
                    .foregroundStyle(BodyFlowColor.primaryText)
                Text("O conteúdo carregado permanece sob responsabilidade da funcionalidade.")
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(BodyFlowSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BodyFlowColor.background)
        } else if let screenState = state.screenState {
            ScreenStateView(state: screenState, retryAction: {})
        }
    }
}

#Preview("Loaded") {
    ScreenContentStatePreviewHost(state: .loaded)
}

#Preview("Loading") {
    ScreenContentStatePreviewHost(state: .loading)
}

#Preview("Empty") {
    ScreenContentStatePreviewHost(state: .empty)
}

#Preview("Error") {
    ScreenContentStatePreviewHost(state: .recoverableError)
}

#Preview("Offline") {
    ScreenContentStatePreviewHost(state: .offline)
}
#endif
