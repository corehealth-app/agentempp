import SwiftUI

/// One explicit confirmation action, plus recovery of the retained intent.
/// The parent owns transport, idempotency, receipt and session boundaries.
@MainActor
struct SignupBodyPhotoDeleteControl: View {
    let photos: SignupBodyPhotoPresentationModel
    @Environment(\.locale) private var locale
    @State private var showsConfirmation = false

    var body: some View {
        Group {
            if photos.canDeletePhotos {
                Button(copy("onboarding.photos.delete.title")) {
                    guard photos.canDeletePhotos else { return }
                    showsConfirmation = true
                }
                .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
                .accessibilityIdentifier("onboarding.photos.delete")
            } else if let phase = photos.photoDeletionPhase {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    if case .failed = phase {
                        BodyFlowStatusLine(copy("onboarding.photos.delete.error"), kind: .error)
                            .accessibilityIdentifier("onboarding.photos.delete.error")
                    } else {
                        BodyFlowStatusLine(copy("onboarding.photos.delete.pending"), kind: .pending)
                            .accessibilityIdentifier("onboarding.photos.delete.pending")
                    }
                    if photos.canRetryPhotoDeletion {
                        Button(copy("onboarding.retry")) {
                            guard photos.canRetryPhotoDeletion else { return }
                            Task { await photos.retryDeletion() }
                        }
                        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                        .accessibilityIdentifier("onboarding.photos.delete.retry")
                    }
                }
            }
        }
        .alert(copy("onboarding.photos.delete.title"), isPresented: $showsConfirmation) {
            Button(copy("onboarding.photos.delete.title"), role: .destructive) {
                guard photos.canDeletePhotos else { return }
                Task { await photos.deletePhotos() }
            }
            .accessibilityIdentifier("onboarding.photos.delete.confirm")
            Button(copy("registration.live.cancel"), role: .cancel) {}
                .accessibilityIdentifier("onboarding.photos.delete.cancel")
        } message: {
            Text(copy("onboarding.photos.delete.message"))
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }
}
