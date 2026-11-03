import SwiftUI

/// Existing official plan reads, split by domain. Execution, day/week and
/// sharing controls are not fabricated while their server contracts are absent.
@MainActor
struct ConversationalPlanRootView: View {
    let model: PlanViewModel
    let tab: AppTab
    let scope: PlanContentScope
    @Binding var selectedTab: AppTab
    @Environment(\.locale) private var locale

    var body: some View {
        PlanReadContent(model: model, scope: scope)
            .background(BodyFlowColor.background)
            .navigationTitle(AppNavigationLayout.conversationalPreview.title(for: tab,
                language: BodyFlowPresentationLanguage.resolve(locale)))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(scope == .nutrition ? "screen.alimentacao" : "screen.treino")
            .task(id: selectedTab) {
                guard selectedTab == tab else { return }
                await model.load()
            }
            .refreshable { await model.retry() }
    }
}
