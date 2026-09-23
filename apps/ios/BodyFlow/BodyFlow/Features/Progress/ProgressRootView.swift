import SwiftUI

@MainActor
struct ProgressRootView: View {
    let model: ProgressViewModel
    @Binding var selectedTab: AppTab
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            BodyFlowColor.background
                .ignoresSafeArea()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AppTab.progress.rootAccessibilityIdentifier)
            FeatureReadStateView(state: model.state, retryAction: retry) { snapshot in
                let presentation = ProgressPresentation(
                    snapshot: snapshot,
                    language: language
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        ProgressContentView(
                            presentation: presentation,
                            selectedTab: $selectedTab
                        )
                        NavigationLink(value: AppRoute.progress(.block7700)) {
                            BodyFlowCard(surface: .card) {
                                FeatureActionLabel(
                                    title: copy("progress.block.title"),
                                    detail: copy("progress.block.action.detail"),
                                    systemImage: "circle.hexagongrid"
                                )
                            }
                        }
                        .buttonStyle(.bodyFlowRow)
                        .accessibilityIdentifier("progress.block.detail")
                    }
                    .padding(BodyFlowSpacing.md)
                }
            }
        }
        .navigationTitle(copy("progress.navigation.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedTab) {
            guard selectedTab == .progress else { return }
            await model.load()
        }
    }

    private func retry() {
        Task { await model.retry() }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        ProgressCopy.string(key, language: language)
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
