import SwiftUI

@MainActor
struct SplashView: View {
    @Environment(\.locale) private var locale
    var loadingLabel: String? = nil

    var body: some View {
        GeometryReader { geometry in
            ViewThatFits(in: .vertical) {
                // Match the static launch center whenever the whole content
                // fits. The hidden reservation is never allowed to fill a
                // short viewport with an empty first frame.
                VStack(spacing: BodyFlowSpacing.lg) {
                    status(reservesOnly: true).hidden().accessibilityHidden(true)
                    mark
                    status(reservesOnly: false)
                }
                .padding(BodyFlowSpacing.xl)
                .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(spacing: BodyFlowSpacing.lg) {
                        mark
                        status(reservesOnly: false)
                    }
                    .padding(BodyFlowSpacing.xl)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .background(BodyFlowColor.color(.heroBackground))
        .foregroundStyle(BodyFlowColor.color(.onHero))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.splash")
    }

    private var mark: some View {
        Image(decorative: PerformeAIBrandAsset.symbolNegative.resourceName)
            .resizable().renderingMode(.original).scaledToFit()
            .frame(width: 112, height: 112)
            .performeBrandContinuity(source: true)
    }

    private var loadingText: String {
        loadingLabel ?? PremiumPresentationCopy.string(
            "splash.loading", locale: locale, fallback: "Carregando"
        )
    }

    private func status(reservesOnly: Bool) -> some View {
        VStack(spacing: BodyFlowSpacing.sm) {
            Text(BrandIdentity.productName)
                .font(BodyFlowTypography.title.weight(.bold))
                .accessibilityIdentifier(reservesOnly ? "" : "brand.product-name")
            if reservesOnly {
                HStack(spacing: BodyFlowSpacing.sm) {
                    Color.clear.frame(width: 20, height: 20)
                    Text(loadingText).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                BodyFlowDelayedProgress(label: loadingText, tint: BodyFlowColor.color(.onHero))
            }
        }
        .font(BodyFlowTypography.callout)
        .multilineTextAlignment(.center)
    }
}

#Preview("Splash") { SplashView() }
