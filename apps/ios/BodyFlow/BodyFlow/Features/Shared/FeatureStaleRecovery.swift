import SwiftUI

/// Stale data recovery: the stale banner plus the standard retry — one
/// secondary-role button with the shared `state.retry` identifier and 44 pt
/// target — instead of a hand-rolled headline button on every screen. Pass
/// `retry: nil` when the screen has no retry for this state.
@MainActor
struct FeatureStaleRecovery<Banner: View>: View {
    private let retry: (@MainActor () -> Void)?
    private let banner: Banner

    init(
        retry: (@MainActor () -> Void)?,
        @ViewBuilder banner: () -> Banner
    ) {
        self.retry = retry
        self.banner = banner()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            banner

            if let retry {
                FeatureRetryButton(action: retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The standard inline retry: secondary role, shared `state.retry`
/// identifier, 44 pt target. Full-screen states keep their primary retry in
/// `ScreenStateView`.
@MainActor
struct FeatureRetryButton: View {
    @Environment(\.locale) private var locale
    let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
        .accessibilityIdentifier("state.retry")
    }

    private var title: String {
        (try? AppLocalization.string(
            "state.retry",
            for: BodyFlowPresentationLanguage.resolve(locale)
        )) ?? "Tentar novamente"
    }
}

extension FeatureStaleRecovery where Banner == StaleDataBanner {
    init(retry: (@MainActor () -> Void)?) {
        self.init(retry: retry) { StaleDataBanner() }
    }
}
