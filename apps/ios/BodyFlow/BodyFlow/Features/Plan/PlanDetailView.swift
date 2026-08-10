import SwiftUI

@MainActor
struct PlanDetailView: View {
    @State private var model: PlanViewModel

    init(provider: any PlanProviding) {
        _model = State(initialValue: PlanViewModel(provider: provider))
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            PlanReadContent(model: model)
        }
        .navigationTitle("Detalhes do plano")
        .accessibilityIdentifier("screen.plan.detail")
        .task {
            await model.load()
        }
    }
}
