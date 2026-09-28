import Observation
import SwiftUI

/// The patient's open drafts and the way to import a plan, on the Plan tab.
/// It stays visible when there is no plan yet — that is when it matters most.
@MainActor
@Observable
final class PlanDraftsModel {
    private let provider: any PlanDraftProviding
    private var sequence = 0

    private(set) var drafts: [PlanDraftSummary] = []
    private(set) var failure: PlanDraftFailure?

    init(provider: any PlanDraftProviding) {
        self.provider = provider
    }

    func load() async {
        sequence += 1
        let current = sequence
        do {
            let loaded = try await provider.openDrafts()
            guard sequence == current, !Task.isCancelled else { return }
            drafts = loaded
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            guard sequence == current else { return }
            failure = PlanDraftFailure(error)
        }
    }

    func invalidate() {
        sequence += 1
        drafts = []
        failure = nil
    }
}

@MainActor
struct PlanDraftsSection: View {
    let model: PlanDraftsModel
    let supportsImport: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            if !model.drafts.isEmpty {
                Text(copy("plan.drafts.title"))
                    .font(BodyFlowTypography.sectionTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                ForEach(model.drafts) { draft in
                    NavigationLink(value: AppRoute.planDraft(PlanDraftRoute(
                        draftID: draft.id, origin: .plan
                    ))) {
                        BodyFlowCard {
                            FeatureActionLabel(
                                title: PlanDraftCopy.domainTitle(draft.domain, language: language),
                                detail: copy(detailKey(for: draft)),
                                systemImage: draft.domain == .training
                                    ? "figure.run" : "fork.knife"
                            )
                        }
                    }
                    .buttonStyle(.bodyFlowRow)
                    .accessibilityIdentifier("plan.drafts.item.\(draft.id)")
                }
            }
            if supportsImport {
                NavigationLink(value: AppRoute.planImport) {
                    BodyFlowCard {
                        FeatureActionLabel(
                            title: copy("plan.import.action.title"),
                            detail: copy("plan.import.action.detail"),
                            systemImage: "square.and.arrow.down"
                        )
                    }
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityIdentifier("plan.import")
            }
        }
        .padding(.horizontal, BodyFlowSpacing.md)
        .padding(.top, BodyFlowSpacing.md)
    }

    private func detailKey(for draft: PlanDraftSummary) -> String.LocalizationValue {
        switch draft.state {
        case .extracting, .generating: "plan.drafts.state.in-progress"
        case .needsCompletion: "plan.drafts.state.needs-completion"
        default: "plan.drafts.state.ready"
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        PlanDraftCopy.string(key, language: language)
    }
}
