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
            if awaitsBothInitialReads {
                BodyFlowFeatureSkeleton(kind: .progress)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        if model.state.presentation.value == nil, let weightState = model.profileWeight.state {
                            ProfileWeightCard(state: weightState, language: language, retryAction: retry)
                        }
                        // The charts sit beside the snapshot: a day with
                        // records has trends even before any gamification.
                        ProgressTrendsSection(model: model.trends)
                        FeatureReadStateView(state: model.state, retryAction: retry) { snapshot in
                            let presentation = ProgressPresentation(snapshot: snapshot, language: language)
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                                ProgressContentView(
                                    presentation: presentation,
                                    selectedTab: $selectedTab,
                                    profileWeightState: model.profileWeight.state,
                                    retryProfileWeight: retry
                                )
                                NavigationLink(value: AppRoute.progress(.block7700)) {
                                    BodyFlowCard(surface: .card) {
                                        FeatureActionLabel(
                                            title: copy("progress.block.title"),
                                            detail: copy("progress.block.action.detail"),
                                            systemImage: BodyFlowSymbol.block.systemName
                                        )
                                    }
                                }
                                .buttonStyle(.bodyFlowRow)
                                .accessibilityIdentifier("progress.block.detail")
                                .bodyFlowZoomSource(.progress(.block7700))
                            }
                        }
                    }
                    .padding(BodyFlowSpacing.md)
                }
                .refreshable { await model.retry() }
            }
        }
        .navigationTitle(copy("progress.navigation.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedTab) {
            guard selectedTab == .progress else { return }
            await model.load()
        }
    }

    /// Independently available profile data or recovery must be usable even
    /// while the progress endpoint is still pending.
    private var awaitsBothInitialReads: Bool {
        guard model.state.presentation.fullScreenState == .loading else { return false }
        switch model.profileWeight.state {
        case nil, .idle?, .loading?: return true
        default: return false
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


@MainActor
private struct ProfileWeightCard: View {
    let state: FeatureReadState<ProfileWeightSnapshot>
    let language: SupportedAppLanguage
    let retryAction: @MainActor () -> Void

    var body: some View {
        BodyFlowCard(surface: .card) {
            ProfileWeightContent(state: state, language: language, retryAction: retryAction)
        }
    }
}
