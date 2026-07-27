import SwiftUI

@MainActor
struct SplashView: View {
    var body: some View {
        VStack(spacing: BodyFlowSpacing.lg) {
            Text("BodyFlow")
                .font(BodyFlowTypography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(BodyFlowColor.primaryText)

            ProgressView()
                .controlSize(.large)
                .tint(BodyFlowColor.accent)
                .accessibilityLabel("Carregando")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.splash")
    }
}

#Preview("Splash") {
    SplashView()
}
