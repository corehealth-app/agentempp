import SwiftUI

@MainActor
struct PlanRootView: View {
    let model: PlanViewModel
    @Binding var selectedTab: AppTab

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            PlanReadContent(model: model, showsDetailLink: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppTab.plan.rootAccessibilityIdentifier)
        .navigationTitle("Plano")
        .task(id: selectedTab) {
            guard selectedTab == .plan else { return }
            await model.load()
        }
    }
}

@MainActor
struct PlanReadContent: View {
    let model: PlanViewModel
    var showsDetailLink = false

    var body: some View {
        let presentation = model.state.presentation
        if let screenState = presentation.fullScreenState {
            ScreenStateView(state: screenState, retryAction: retry)
        } else if let snapshot = presentation.value {
            ScrollView {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                    if presentation.showsStaleBanner {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                            StaleDataBanner()
                            retryButton
                        }
                    }

                    PlanContentView(presentation: PlanPresentation(snapshot: snapshot))

                    if showsDetailLink {
                        NavigationLink(value: AppRoute.plan(.detail)) {
                            BodyFlowCard {
                                FeatureActionLabel(
                                    title: "Ver detalhes do plano",
                                    detail: "Recarregar os dados atuais do plano",
                                    systemImage: "list.clipboard"
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plan.detail")
                    }

                }
                .padding(BodyFlowSpacing.md)
            }
        }
    }

    private var retryButton: some View {
        Button("Tentar novamente", action: retry)
            .font(BodyFlowTypography.headline)
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            .accessibilityIdentifier("state.retry")
    }

    private func retry() {
        Task { await model.retry() }
    }
}
