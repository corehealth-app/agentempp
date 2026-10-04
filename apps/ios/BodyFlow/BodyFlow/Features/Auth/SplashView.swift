import SwiftUI

/// The first frame after the static launch screen is that screen (the mark
/// at the same place and size, so the handoff is seamless); then the name
/// fades in and the mark breathes while the session is restored, before it
/// travels to the brand action of the tab bar (`performeBrandContinuity`).
/// Under the name a ball climbs an endless staircase while the session is
/// restored (Eduardo, 2026-10-04: a more animated, more elaborate opening);
/// the loading line only appears when the wait is long enough to need one.
/// Reduce Motion, Low Power and a hot device keep everything still.
@MainActor
struct SplashView: View {
    @Environment(\.locale) private var locale
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy
    @State private var entered = false
    @State private var breathing = false
    @State private var showsLoadingText = false
    /// The mesh starts flat (identical to the launch screen) and drifts
    /// into its colors once, over `meshDuration`; then it is still.
    @State private var meshLive = false
    var loadingLabel: String? = nil
    nonisolated static let meshDuration: TimeInterval = 1.5

    /// Shown only after this wait: a fast restore never reads "Carregando".
    nonisolated static let loadingTextDelay: Duration = .milliseconds(1200)
    /// The breath is a slow 3% swell around the launch-screen size, for a
    /// few cycles only: a restore that takes longer shows the loading line
    /// and a still mark, never an endless animation.
    nonisolated static let breathScale: CGFloat = 1.03
    nonisolated static let breathCycles = 3
    nonisolated static let breathDuration: TimeInterval = 1.6

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
        .background { meshBackground.ignoresSafeArea() }
        .foregroundStyle(BodyFlowColor.color(.onHero))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(loadingText)
        .accessibilityIdentifier("screen.splash")
        .onAppear {
            withAnimation(BodyFlowMotion.animation(.brand, reduceMotion: motionReduced)) {
                entered = true
            }
        }
        .task {
            // The breath starts once the mark has settled and ends after a
            // few cycles, back at the launch-screen size.
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, !motionReduced else { return }
            withAnimation(
                .easeInOut(duration: Self.breathDuration)
                    .repeatCount(Self.breathCycles * 2 - 1, autoreverses: true)
            ) {
                breathing = true
            }
            try? await Task.sleep(for: .seconds(Self.breathDuration * Double(Self.breathCycles * 2 - 1)))
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { breathing = false }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, !motionReduced else { return }
            withAnimation(.easeInOut(duration: Self.meshDuration)) { meshLive = true }
        }
        .task {
            guard loadingLabel == nil else { return }
            try? await Task.sleep(for: Self.loadingTextDelay)
            guard !Task.isCancelled else { return }
            withAnimation(BodyFlowMotion.animation(.content, reduceMotion: motionReduced)) {
                showsLoadingText = true
            }
        }
    }

    private var motionReduced: Bool { reduceMotion || !visualPolicy.allowsMotion }

    /// Nine control points; only the colors animate, from the flat hero
    /// teal to a soft sweep toward the brand aqua at the top-left.
    private var meshBackground: some View {
        let base = BodyFlowColor.color(.heroBackground)
        let end = BodyFlowColor.color(.heroGradientEnd)
        let glow = BodyFlowColor.color(.brandPrimary)
        let colors: [Color] = meshLive
            ? [glow, end, base, end, base, base, base, base, end]
            : Array(repeating: base, count: 9)
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.45, 0.55], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: colors
        )
    }

    private var mark: some View {
        Image(decorative: PerformeAIBrandAsset.symbolNegative.resourceName)
            .resizable().renderingMode(.original).scaledToFit()
            .frame(width: 112, height: 112)
            .scaleEffect(breathing && !motionReduced ? Self.breathScale : 1)
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
                .opacity(reservesOnly || entered || motionReduced ? 1 : 0)
                // The name rises into place as it fades in.
                .offset(y: reservesOnly || entered || motionReduced ? 0 : BodyFlowSpacing.sm)
                .accessibilityIdentifier(reservesOnly ? "" : "brand.product-name")
            // The mirrored reservation above the mark only keeps the space:
            // one loader, one set of layers.
            Group {
                if reservesOnly {
                    Color.clear
                } else {
                    BodyFlowStairLoader()
                        .opacity(entered || motionReduced ? 1 : 0)
                }
            }
            .frame(
                width: BodyFlowStairLoaderMetrics.size.width,
                height: BodyFlowStairLoaderMetrics.size.height
            )
            .accessibilityHidden(true)
            // The line is always reserved so the mark never jumps when it
            // appears; a caller-provided label (a long restore) shows at once.
            Text(loadingText)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(reservesOnly ? 0 : (loadingLabel != nil || showsLoadingText ? 1 : 0))
                .accessibilityHidden(reservesOnly || (loadingLabel == nil && !showsLoadingText))
        }
        .font(BodyFlowTypography.callout)
        .multilineTextAlignment(.center)
    }
}

#Preview("Splash") { SplashView() }
