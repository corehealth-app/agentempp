import SwiftUI

#if DEBUG
/// The camera of a UI test (Debug builds only): a cover with the two ways
/// out the system's camera has, so a test can see the capture ask for the
/// camera, cancel it, and take a photo — without the system's camera, its
/// permission prompt or a real picture.
struct MealCameraStandIn: View {
    /// Which presentation of the camera this is on its sheet; shown as a
    /// line of its own, which the test reads.
    let presentation: Int
    let finish: @MainActor (Data?) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: BodyFlowSpacing.md) {
            Text(verbatim: "\(presentation)")
                .font(BodyFlowTypography.headline)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityIdentifier("registration.meal.camera.presentation")

            Button {
                finish(DemoMealCamera.samplePhoto())
            } label: {
                label("registration.live.capture.camera")
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary))
            .accessibilityIdentifier("registration.meal.camera.take")

            Button {
                finish(nil)
            } label: {
                label("registration.live.cancel")
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
            .accessibilityIdentifier("registration.meal.camera.cancel")
        }
        .padding(BodyFlowSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BodyFlowColor.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.meal.camera")
    }

    private func label(_ key: String.LocalizationValue) -> some View {
        Text(RegistrationCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale)))
            .frame(maxWidth: .infinity)
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
    }
}
#endif
