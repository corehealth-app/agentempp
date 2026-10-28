import SwiftUI

@MainActor
struct CurrentObjectiveView: View {
    private enum Presentation: Identifiable {
        case message(ProtocolWelcome)
        case firstPhase(ClinicalFirstPhaseModel)
        var id: String { switch self { case .message: "message"; case .firstPhase: "first-phase" } }
    }
    let model: CurrentObjectiveModel
    @Environment(\.locale) private var locale
    @State private var presentation: Presentation?

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            FeatureReadStateView(state: model.state, retryAction: { Task { await model.load() } }) { snapshot in
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        if snapshot.clinicalPolicy?.professionalAssessmentRecommended == true {
                            Text(copy("first-phase.professional"))
                        }
                        if snapshot.clinicalPolicy?.phaseSelectionPending == true, let firstPhase = model.firstPhase {
                            Button(copy("first-phase.choose")) { presentation = .firstPhase(firstPhase) }
                                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                                .accessibilityIdentifier("current-objective.choose-first-phase")
                        }
                        BodyFlowCard {
                            Text(snapshot.currentProtocol?.onboardingLabel(for: language) ?? unavailable)
                                .font(BodyFlowTypography.screenTitle)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("current-objective.value")
                        }
                        BodyFlowCard {
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                                Text(copy("current-objective.targets"))
                                    .font(BodyFlowTypography.sectionTitle)
                                    .accessibilityAddTraits(.isHeader)
                                metric("current-objective.calories", identifier: "current-objective.calories", value: TodayValueFormatter.mealKcal(snapshot.targets?.calories, language: language))
                                metric("current-objective.protein", identifier: "current-objective.protein", value: TodayValueFormatter.optionalGrams(snapshot.targets?.proteinG, language: language))
                            }
                        }
                        if let welcome = snapshot.welcome {
                            Button {
                                presentation = .message(welcome)
                            } label: {
                                Text(copy("current-objective.message"))
                            }
                            .buttonStyle(BodyFlowButtonStyle(role: .primary))
                            .accessibilityIdentifier("current-objective.message")
                        }
                    }
                    .padding(BodyFlowSpacing.md)
                }
            }
        }
        .bodyFlowScreenChrome(title: copy("current-objective.title"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.current-objective")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.load() } } label: {
                    Label(verbatim: copy(model.isLoading ? "current-objective.refreshing" : "current-objective.refresh"), symbol: .refresh)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: BodyFlowSpacing.minimumTapTarget, minHeight: BodyFlowSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
                .accessibilityIdentifier("current-objective.refresh")
            }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
        .onDisappear { model.cancelRead() }
        .sheet(item: $presentation, onDismiss: { Task { await model.load() } }) { selected in
            NavigationStack {
                switch selected {
                case let .firstPhase(firstPhase):
                    ClinicalFirstPhaseView(model: firstPhase)
                case let .message(welcome):
                    ScrollView {
                        ProtocolMessageView(welcome: welcome, context: .currentObjective) {
                            presentation = nil
                        }
                        .padding(BodyFlowSpacing.md)
                    }
                    .accessibilityIdentifier("current-objective.welcome.scroll")
                    .background(BodyFlowColor.background)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private func metric(_ key: String.LocalizationValue, identifier: String, value: String) -> some View {
        let title = copy(key)
        return VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            Text(title).font(BodyFlowTypography.callout).foregroundStyle(BodyFlowColor.secondaryText)
            Text(verbatim: value).font(BodyFlowTypography.headline)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(title): \(value)"))
        .accessibilityIdentifier(identifier)
    }

    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    private var unavailable: String { copy("common.not-available") }
    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
