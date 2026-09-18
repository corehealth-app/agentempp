import SwiftUI

@MainActor
struct PlanRootView: View {
    let model: PlanViewModel
    @Binding var selectedTab: AppTab
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            PlanReadContent(model: model, showsDetailLink: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppTab.plan.rootAccessibilityIdentifier)
        .navigationTitle(copy("plan.navigation.title"))
        .task(id: selectedTab) {
            guard selectedTab == .plan else { return }
            await model.load()
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
    @Environment(\.locale) private var locale

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
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plan.detail")
                    }

                }
                .padding(BodyFlowSpacing.md)
            }
        }
    }

    private var retryButton: some View {
        Button(copy("state.retry"), action: retry)
            .font(BodyFlowTypography.headline)
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            .accessibilityIdentifier("state.retry")
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
