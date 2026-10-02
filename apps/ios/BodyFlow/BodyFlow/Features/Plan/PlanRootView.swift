import SwiftUI

@MainActor
struct PlanRootView: View {
    let model: PlanViewModel
    @Binding var selectedTab: AppTab
    var drafts: PlanDraftsModel? = nil
    var supportsImport = false
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            PlanReadContent(
                model: model, showsDetailLink: true,
                drafts: drafts, supportsImport: supportsImport
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppTab.plan.rootAccessibilityIdentifier)
        .refreshable {
            await model.retry()
            await drafts?.load()
        }
        .navigationTitle(copy("plan.navigation.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedTab) {
            guard selectedTab == .plan else { return }
            await model.load()
            await drafts?.load()
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        PlanCopy.string(key, language: language)
    }
}

@MainActor
struct PlanReadContent: View {
    let model: PlanViewModel
    var showsDetailLink = false
    var drafts: PlanDraftsModel? = nil
    var supportsImport = false
    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                    if let drafts, showsDrafts {
                        // Drafts and import remain reachable alongside every
                        // read state, even when twenty drafts fill many screens.
                        PlanDraftsSection(model: drafts, supportsImport: supportsImport)
                    }
                    readContent(availableHeight: geometry.size.height)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var showsDrafts: Bool {
        drafts.map { !$0.drafts.isEmpty || supportsImport } ?? false
    }

    @ViewBuilder
    private func readContent(availableHeight: CGFloat) -> some View {
        let presentation = model.state.presentation
        if presentation.fullScreenState == .loading {
            BodyFlowFeatureSkeleton(kind: .plan, isEmbedded: true)
        } else if let screenState = presentation.fullScreenState {
            ScreenStateView(state: screenState, retryAction: retry, isEmbedded: true)
                .frame(minHeight: showsDrafts ? 0 : availableHeight)
        } else if let snapshot = presentation.value {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                if presentation.showsStaleBanner {
                    FeatureStaleRecovery(retry: retry)
                }

                PlanContentView(presentation: PlanPresentation(
                    snapshot: snapshot,
                    language: language
                ))

                if showsDetailLink {
                    NavigationLink(value: AppRoute.plan(.detail)) {
                        BodyFlowCard {
                            FeatureActionLabel(
                                title: copy("plan.detail.action.title"),
                                detail: copy("plan.detail.action.detail"),
                                systemImage: "list.clipboard"
                            )
                        }
                    }
                    .buttonStyle(.bodyFlowRow)
                    .accessibilityIdentifier("plan.detail")
                }
            }
            .padding(BodyFlowSpacing.md)
        }
    }

    private func retry() {
        Task { await model.retry() }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        PlanCopy.string(key, language: language)
    }
}
