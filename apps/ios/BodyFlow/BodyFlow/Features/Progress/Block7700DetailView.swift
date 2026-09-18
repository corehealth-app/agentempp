import SwiftUI

struct Block7700DetailPresentation: Equatable, Sendable {
    let descriptor: Block7700Descriptor?
    let fullScreenState: ScreenState?
    let showsStaleBanner: Bool
    let showsRetry: Bool

    init(state: FeatureReadState<Block7700Descriptor>) {
        let presentation = state.presentation
        descriptor = presentation.value
        fullScreenState = presentation.fullScreenState
        showsStaleBanner = presentation.showsStaleBanner
        showsRetry = presentation.value != nil && presentation.showsStaleBanner
    }
}

@MainActor
struct Block7700DetailView: View {
    @State private var model: Block7700ViewModel
    @Environment(\.locale) private var locale

    init(today: any TodayProviding) {
        _model = State(initialValue: Block7700ViewModel(today: today))
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            content
        }
        .navigationTitle(copy("progress.block.title"))
        .accessibilityIdentifier("screen.block7700.detail")
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        let presentation = Block7700DetailPresentation(state: model.state)
        if let fullScreenState = presentation.fullScreenState {
            ScreenStateView(state: fullScreenState, retryAction: retry)
                .accessibilityIdentifier(
                    fullScreenState == .unavailable
                        ? "block7700.unavailable"
                        : fullScreenState.accessibilityIdentifier
                )
        } else if let descriptor = presentation.descriptor {
            FeatureStateContentStack(
                showsStaleBanner: presentation.showsStaleBanner
            ) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    if presentation.showsRetry {
                        Button(copy("state.retry"), action: retry)
                            .font(BodyFlowTypography.headline)
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                            .accessibilityIdentifier("state.retry")
                    }

                    ScrollView {
                        BodyFlowCard(surface: .card) {
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                                Text(copy("progress.block.title"))
                                    .font(BodyFlowTypography.title)
                                    .fontWeight(.semibold)
                                FixtureMetricRow(
                                    title: copy("progress.block.target"),
                                    value: TodayValueFormatter.optionalKcal(
                                        descriptor.targetKcal,
                                        language: language
                                    )
                                )
                                Divider()
                                FixtureMetricRow(
                                    title: copy("progress.block.current"),
                                    value: TodayValueFormatter.optionalKcal(
                                        descriptor.currentKcal,
                                        language: language
                                    )
                                )
                                optionalRow(
                                    copy("progress.block.percentage"),
                                    descriptor.percentage.map { "\($0)%" }
                                )
                                optionalRow(
                                    copy("progress.block.completed"),
                                    descriptor.completedBlocks.map {
                                        TodayValueFormatter.integer($0, language: language)
                                    }
                                )
                                optionalRow(
                                    copy("progress.block.credited"),
                                    descriptor.totalCreditedKcal.map {
                                        TodayValueFormatter.kcal($0, language: language)
                                    }
                                )
                                FixtureMetricRow(
                                    title: copy("progress.block.availability"),
                                    value: descriptor.availability
                                )
                                FixtureMetricRow(
                                    title: copy("progress.block.source"),
                                    value: descriptor.source
                                )
                            }
                        }
                        .accessibilityIdentifier("block7700.summary")
                        .padding(BodyFlowSpacing.md)
                    }
                    .accessibilityIdentifier("block7700.today-snapshot")
                }
            }
        }
    }

    @ViewBuilder
    private func optionalRow(
        _ title: String,
        _ value: String?
    ) -> some View {
        if let value {
            Divider()
            FixtureMetricRow(title: title, value: value)
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
