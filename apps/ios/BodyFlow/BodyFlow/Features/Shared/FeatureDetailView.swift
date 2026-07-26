import SwiftUI

@MainActor
struct FeatureDetailView: View {
    let route: AppRoute

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()

            ScrollView {
                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                        Image(systemName: route.tab.systemImage)
                            .font(BodyFlowTypography.largeTitle)
                            .foregroundStyle(BodyFlowColor.accent)
                            .accessibilityHidden(true)

                        Text(route.tab.title)
                            .font(BodyFlowTypography.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(BodyFlowColor.primaryText)

                        Text("Conteúdo local de demonstração. Nenhuma operação foi executada.")
                            .font(BodyFlowTypography.body)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                }
                .padding(BodyFlowSpacing.md)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(route.accessibilityIdentifier)
        .navigationTitle("Detalhes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Detalhe · Hoje") {
    NavigationStack {
        FeatureDetailView(
            route: .detail(tab: .today, id: "daily-summary")
        )
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}
