import SwiftUI

@MainActor
struct SplashView: View {
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 112

    var body: some View {
        VStack(spacing: BodyFlowSpacing.lg) {
            Image(decorative: PerformeAIBrandAsset.symbolNegative.resourceName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: symbolSize, height: symbolSize)

            Text("Performe AI")
                .font(BodyFlowTypography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(BodyFlowColor.color(.onPrimary))
                .accessibilityIdentifier("brand.product-name")

            ProgressView()
                .controlSize(.large)
                .tint(BodyFlowColor.color(.onPrimary))
                .accessibilityLabel(PremiumPresentationCopy.string(
                    "splash.loading",
                    locale: locale,
                    fallback: "Carregando"
                ))
        }
        .padding(.horizontal, BodyFlowSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.color(.brandPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.splash")
    }
}

#Preview("Splash") {
    SplashView()
}
