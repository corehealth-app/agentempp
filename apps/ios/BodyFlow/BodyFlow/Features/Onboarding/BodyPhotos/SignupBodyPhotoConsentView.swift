import SwiftUI

/// Presents only the current server document. No private-text/locale fallback.
/// Consent callbacks do not apply a body-fat estimate to the onboarding draft.
@MainActor
struct SignupBodyPhotoConsentView: View {
    let document: SignupBodyPhotoConsent
    let isAccepting: Bool
    let consent: @MainActor () -> Void
    let decline: @MainActor () -> Void
    @Environment(\.locale) private var locale

    // Like the existing onboarding steps, this is content for the route's
    // scrolling surface. Keeping scrolling at the route avoids nested columns.
    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            Text(verbatim: document.body)
                .font(BodyFlowTypography.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.photos.consent.body")
            Button(copy("onboarding.photos.consent.accept"), action: consent)
                .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: isAccepting))
                .disabled(isAccepting)
                .accessibilityIdentifier("onboarding.photos.consent.accept")
            Button(copy("onboarding.body-fat.choice.skip"), action: decline)
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .accessibilityIdentifier("onboarding.photos.consent.decline")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.photos.consent")
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }
}
