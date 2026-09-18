import SwiftUI

@MainActor
struct FeatureDetailView: View {
    let route: AppRoute
    @Environment(\.locale) private var locale

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

                        Text(route.tab.title(for: language))
                            .font(BodyFlowTypography.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(BodyFlowColor.primaryText)

                        Text(ProfileCopy.string(
                            "profile.preferences.demo-message",
                            language: language
                        ))
                            .font(BodyFlowTypography.body)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                }
                .padding(BodyFlowSpacing.md)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(route.accessibilityIdentifier)
        .navigationTitle(ProfileCopy.string(
            "profile.preferences.detail-title",
            language: language
        ))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
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
