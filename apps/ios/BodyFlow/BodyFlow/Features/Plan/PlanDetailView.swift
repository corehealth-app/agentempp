import SwiftUI

@MainActor
struct PlanDetailView: View {
    @State private var model: PlanViewModel
    @Environment(\.locale) private var locale

    init(provider: any PlanProviding) {
        _model = State(initialValue: PlanViewModel(provider: provider))
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            PlanReadContent(model: model)
        }
        .navigationTitle(
            PlanCopy.string(
                "plan.detail.navigation.title",
                language: BodyFlowPresentationLanguage.resolve(locale)
            )
        )
        .accessibilityIdentifier("screen.plan.detail")
        .task {
            await model.load()
        }
    }
}
