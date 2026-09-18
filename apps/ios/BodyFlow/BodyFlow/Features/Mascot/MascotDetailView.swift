import SwiftUI

@MainActor
struct MascotDetailView: View {
    @State private var model: MascotExperienceViewModel
    let invalidationCenter: FeatureInvalidationCenter
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

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
        .navigationTitle(copy("mascot.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.mascot.detail")
        .task(id: invalidationCenter.revision(for: .coachExperience)) {
            await model.load(
                revision: invalidationCenter.revision(for: .coachExperience)
            )
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
            reduceMotion: reduceMotion,
            language: language
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                if showsStaleBanner {
                    StaleDataBanner()
                }

                Button(action: retry) {
                    Label(copy("mascot.action.refresh"), systemImage: "arrow.clockwise")
                        .font(BodyFlowTypography.headline)
                        .foregroundStyle(BodyFlowColor.accent)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: BodyFlowSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mascot.refresh")

                BodyFlowCard {
                    MascotSemanticContent(descriptor: descriptor)
                }

                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        Text(copy("mascot.about.title"))
                            .font(BodyFlowTypography.headline)
                            .foregroundStyle(BodyFlowColor.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(descriptor.stateText)
                            .font(BodyFlowTypography.body)
                            .foregroundStyle(BodyFlowColor.primaryText)
                        Text(String(
                            format: copy("mascot.updated-format"),
                            locale: language.formattingLocale,
                            descriptor.changedAtText
                        ))
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                        Text(copy("mascot.provenance"))
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

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        MascotCopy.string(key, language: language)
    }
}
