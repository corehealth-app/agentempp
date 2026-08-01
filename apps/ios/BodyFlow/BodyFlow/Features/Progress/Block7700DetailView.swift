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

    init(today: any TodayProviding) {
        _model = State(initialValue: Block7700ViewModel(today: today))
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Bloco 7.700 kcal")
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
                        Button("Tentar novamente", action: retry)
                            .font(BodyFlowTypography.headline)
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                            .accessibilityIdentifier("state.retry")
                    }

                    ScrollView {
                        BodyFlowCard {
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                                Text("Bloco 7.700 kcal")
                                    .font(BodyFlowTypography.title)
                                    .fontWeight(.semibold)
                                FixtureMetricRow(title: "Meta", value: descriptor.targetText)
                                Divider()
                                FixtureMetricRow(title: "Atual", value: descriptor.currentText)
                                optionalRow("Percentual informado", descriptor.percentage.map { "\($0)%" })
                                optionalRow("Blocos concluídos", descriptor.completedBlocks.map(String.init))
                                optionalRow(
                                    "Total creditado",
                                    descriptor.creditedText
                                )
                                FixtureMetricRow(title: "Disponibilidade", value: descriptor.availability)
                                FixtureMetricRow(title: "Origem", value: descriptor.source)
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
    private func optionalRow(_ title: String, _ value: String?) -> some View {
        if let value {
            Divider()
            FixtureMetricRow(title: title, value: value)
        }
    }

    private func retry() {
        Task { await model.retry() }
    }
}
