import SwiftUI

@MainActor
struct ProgressRootView: View {
    let model: ProgressViewModel
    @Binding var selectedTab: AppTab

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            FeatureReadStateView(state: model.state, retryAction: retry) { snapshot in
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        ProgressContentView(
                            presentation: ProgressPresentation(snapshot: snapshot)
                        )
                        NavigationLink(value: AppRoute.progress(.block7700)) {
                            BodyFlowCard {
                                FeatureActionLabel(
                                    title: "Bloco 7.700 kcal",
                                    detail: "Ver o bloco persistido no resumo de hoje",
                                    systemImage: "circle.hexagongrid"
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progress.block.detail")
                    }
                    .padding(BodyFlowSpacing.md)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppTab.progress.rootAccessibilityIdentifier)
        .navigationTitle("Progresso")
        .task(id: selectedTab) {
            guard selectedTab == .progress else { return }
            await model.load()
        }
    }

    private func retry() {
        Task { await model.retry() }
    }
}

#Preview("Progresso · Loaded") {
    NavigationStack {
        ProgressRootView(
            model: ProgressViewModel(provider: AppDependencies.scaffold().progress),
            selectedTab: .constant(.progress)
        )
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}
