import SwiftUI

@MainActor
struct MascotDetailView: View {
    @State private var model: MascotExperienceViewModel
    let invalidationCenter: FeatureInvalidationCenter
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion

    init(
        provider: any CoachExperienceProviding,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        _model = State(
            initialValue: MascotExperienceViewModel(provider: provider)
        )
        self.invalidationCenter = invalidationCenter
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            stateContent
        }
        .navigationTitle("Mascote BodyFlow")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.mascot.detail")
        .task(id: invalidationCenter.revision(for: .coachExperience)) {
            await model.load(
                revision: invalidationCenter.revision(for: .coachExperience)
            )
        }
        .toolbar {
            if model.state.presentation.value != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        retry()
                    } label: {
                        Label("Atualizar", systemImage: "arrow.clockwise")
                            .frame(
                                width: BodyFlowSpacing.minimumTapTarget,
                                height: BodyFlowSpacing.minimumTapTarget
                            )
                    }
                    .accessibilityIdentifier("mascot.refresh")
                }
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        let presentation = model.state.presentation
        if let fullScreenState = presentation.fullScreenState {
            ScreenStateView(state: fullScreenState, retryAction: retry)
        } else if let value = presentation.value {
            loadedContent(
                value,
                showsStaleBanner: presentation.showsStaleBanner
            )
        }
    }

    private func loadedContent(
        _ presentation: MascotExperiencePresentation,
        showsStaleBanner: Bool
    ) -> some View {
        let descriptor = MascotViewCompositionDescriptor(
            presentation: presentation,
            surface: .detail,
            reduceMotion: reduceMotion
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                if showsStaleBanner {
                    StaleDataBanner()
                }

                BodyFlowCard {
                    MascotSemanticContent(descriptor: descriptor)
                }

                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        Text("Sobre este estado")
                            .font(BodyFlowTypography.headline)
                            .foregroundStyle(BodyFlowColor.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(descriptor.stateText)
                            .font(BodyFlowTypography.body)
                            .foregroundStyle(BodyFlowColor.primaryText)
                        Text("Atualizado em \(descriptor.changedAtText)")
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                        Text("O estado e a personalidade vêm do seu coach BodyFlow.")
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                }
            }
            .padding(BodyFlowSpacing.md)
        }
        .refreshable {
            await model.retry()
        }
    }

    private func retry() {
        Task { await model.retry() }
    }
}
