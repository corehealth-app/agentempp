import SwiftUI

@MainActor
struct SplashView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: BodyFlowSpacing.lg) {
            Text("Performe AI")
                .font(BodyFlowTypography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(BodyFlowColor.color(.onPrimary))

            ProgressView()
                .controlSize(.large)
                .tint(BodyFlowColor.color(.onPrimary))
                .accessibilityLabel(PremiumPresentationCopy.string(
                    "splash.loading",
                    locale: locale,
                    fallback: "Carregando"
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.color(.brandPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.splash")
    }
}

#Preview("Splash") {
    SplashView()
}
