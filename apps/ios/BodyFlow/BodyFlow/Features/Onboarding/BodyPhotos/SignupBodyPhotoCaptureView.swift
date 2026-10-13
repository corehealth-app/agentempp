import SwiftUI

/// Content only. The route owns navigation/scrolling and the producer host
/// supplies real camera/gallery actions. Missing handlers expose no button.
@MainActor
struct SignupBodyPhotoCaptureView: View {
    let photos: SignupBodyPhotoPresentationModel
    private let onCamera: (@MainActor (SignupBodyPhotoPose) -> Void)?
    private let onGallery: (@MainActor (SignupBodyPhotoPose) -> Void)?
    private let onExit: (@MainActor () -> Void)?
    private let isChoosingSource: Bool
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    init(photos: SignupBodyPhotoPresentationModel,
        onCamera: (@MainActor (SignupBodyPhotoPose) -> Void)? = nil,
        onGallery: (@MainActor (SignupBodyPhotoPose) -> Void)? = nil,
        onExit: (@MainActor () -> Void)? = nil,
        isChoosingSource: Bool = false) {
        self.photos = photos
        self.onCamera = onCamera; self.onGallery = onGallery; self.onExit = onExit
        self.isChoosingSource = isChoosingSource
    }

    var body: some View {
        if photos.route == .capture, let core = photos.capture,
           core.isActive, core.hasAcceptedConsent, let state = core.state {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                Text(copy("onboarding.photos.capture.title"))
                    .font(BodyFlowTypography.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if let key = pendingKey(core.phase) {
                    BodyFlowStatusLine(copy(key), kind: .pending)
                        .accessibilityIdentifier("onboarding.photos.capture.pending")
                }
                if hasFailure(core) {
                    BodyFlowStatusLine(copy("state.error.detail"), kind: .error)
                        .accessibilityIdentifier("onboarding.photos.capture.error")
                }
                if onCamera != nil, !cameraAvailable || cameraDenied {
                    BodyFlowStatusLine(copy(cameraAvailable
                        ? "onboarding.photos.capture.camera-denied"
                        : "onboarding.photos.capture.camera-unavailable"), kind: .unavailable)
                        .accessibilityIdentifier("onboarding.photos.capture.camera-help")
                }
                ForEach(SignupBodyPhotoPose.allCases, id: \.self) { pose in
                    poseRow(pose, photo: state.poses.first { $0.pose == pose }?.photo)
                }
                Button(copy("onboarding.photos.change-percentage")) { select(.typed) }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("onboarding.photos.capture.manual")
                Button(copy("onboarding.body-fat.choice.skip")) { select(.skip) }
                    .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
                    .accessibilityIdentifier("onboarding.photos.capture.skip")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    private func poseRow(_ pose: SignupBodyPhotoPose, photo: SignupBodyPhoto?) -> some View {
        let code = statusCode(photo)
        return VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(poseTitle(pose))
                .font(BodyFlowTypography.sectionTitle)
                .accessibilityIdentifier("onboarding.photos.capture.pose." + pose.rawValue)
            Text(copy(statusKey(code)))
                .font(BodyFlowTypography.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.photos.capture.status." + pose.rawValue + "." + code)
            if let onCamera, cameraAvailable {
                Button(OnboardingCopy.format("onboarding.photos.capture.camera-format",
                    language: language, poseTitle(pose))) {
                    guard photos.route == .capture, !isChoosingSource,
                          !cameraDenied, scenePhase == .active else { return }
                    onCamera(pose)
                }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .disabled(isChoosingSource || cameraDenied || scenePhase != .active)
                .accessibilityIdentifier("onboarding.photos.capture.camera." + pose.rawValue)
            }
            if let onGallery {
                Button(OnboardingCopy.format("onboarding.photos.capture.gallery-format",
                    language: language, poseTitle(pose))) {
                    guard photos.route == .capture, !isChoosingSource else { return }
                    onGallery(pose)
                }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .disabled(isChoosingSource)
                .accessibilityIdentifier("onboarding.photos.capture.gallery." + pose.rawValue)
            }
            // GET-only status does not prove a retained retry pipeline. A
            // retry action requires a separate Core eligibility/action seam.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func statusCode(_ photo: SignupBodyPhoto?) -> String {
        guard let photo else { return "empty" }
        switch photo.status {
        case "pending_upload", "uploaded", "reading", "read", "unreadable", "reading_failed":
            return photo.status
        default: return "unknown"
        }
    }

    private var cameraAvailable: Bool {
        guard let camera = photos.camera, camera.origin != .none else { return false }
        return camera.isAvailable()
    }

    private var cameraDenied: Bool {
        cameraAvailable && photos.camera?.permission() == .denied
    }

    private func statusKey(_ code: String) -> String.LocalizationValue {
        switch code {
        case "empty": "onboarding.photos.capture.status.empty"
        case "pending_upload": "onboarding.photos.capture.status.pending-upload"
        case "uploaded": "onboarding.photos.capture.status.uploaded"
        case "reading": "onboarding.photos.capture.status.reading"
        case "read": "onboarding.photos.capture.status.read"
        case "unreadable": "onboarding.photos.capture.status.unreadable"
        case "reading_failed": "onboarding.photos.capture.status.reading-failed"
        default: "onboarding.photos.capture.status.unknown"
        }
    }

    private func pendingKey(_ phase: SignupBodyPhotoCapturePhase) -> String.LocalizationValue? {
        switch phase {
        case .preparing: "onboarding.photos.capture.phase.preparing"
        case .sending: "onboarding.photos.capture.phase.sending"
        default: nil
        }
    }

    private func hasFailure(_ core: SignupBodyPhotoCaptureModel) -> Bool {
        if case .failed = core.phase { return true }
        return photos.deletion?.producerFailure != nil
    }

    private func select(_ choice: SignupBodyFatChoice) {
        guard photos.route == .capture else { return }
        photos.select(choice)
        onExit?()
    }

    private func poseTitle(_ pose: SignupBodyPhotoPose) -> String {
        switch pose {
        case .front: copy("onboarding.photos.pose.front")
        case .side: copy("onboarding.photos.pose.side")
        case .back: copy("onboarding.photos.pose.back")
        }
    }
    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    private func copy(_ key: String.LocalizationValue) -> String { OnboardingCopy.string(key, language: language) }
}
