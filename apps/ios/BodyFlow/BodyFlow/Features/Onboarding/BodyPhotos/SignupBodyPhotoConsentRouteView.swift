import SwiftUI

/// Content for the existing signup navigation surface. The retained parent
/// supplies the current document and owns its consent operation.
@MainActor
struct SignupBodyPhotoConsentRouteView: View {
    let photos: SignupBodyPhotoPresentationModel
    @State private var isAccepting = false
    @Environment(\.locale) private var locale

    var body: some View {
        if photos.route == .consent, let document = photos.capture?.state?.consent {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                if let phase = photos.capture?.phase, case .failed = phase {
                    BodyFlowStatusLine(OnboardingCopy.string("state.error.detail",
                        language: BodyFlowPresentationLanguage.resolve(locale)), kind: .error)
                        .accessibilityIdentifier("onboarding.photos.consent.error")
                }
                SignupBodyPhotoConsentView(document: document, isAccepting: isAccepting,
                    consent: accept, decline: photos.declineConsent)
                SignupBodyPhotoDeleteControl(photos: photos)
            }
        }
    }

    private func accept() {
        guard !isAccepting else { return }
        isAccepting = true
        Task {
            await photos.acceptConsent()
            isAccepting = false
        }
    }
}
