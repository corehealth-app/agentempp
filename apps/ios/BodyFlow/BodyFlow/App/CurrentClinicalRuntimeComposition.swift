import Foundation

/// Explicit build selection. Invalid or mismatched current configuration must
/// be unavailable rather than silently selecting the legacy numerical runtime.
enum CurrentClinicalRuntimeMode: Equatable, Sendable {
    case legacy, currentV1, unavailable
}

/// Composition only: no lease, request, camera permission or Storage operation
/// starts here. These capabilities are installed or refused as one family.
struct CurrentClinicalRuntimeComposition: Sendable {
    let readers: CurrentClinicalReaderSessionFactory
    let onboarding: MobileOnboardingRepository
    let flowChat: MobileFlowChatRepository
    let firstPhase: MobileClinicalFirstPhaseRepository
    let full: MobileClinicalFullRepository
    let photos: ReevaluationPhotoCaptureCapability

    static let supabaseHost = "xitugspwfxkcluxvrdeg.supabase.co"
    static let bffHost = "performe-ai-staging-bff.vercel.app"

    static func allows(storageOrigin: URL, apiOrigin: URL, qaBinding: CurrentClinicalQABinding = .absent) -> Bool {
        func matches(_ url: URL, host: String) -> Bool {
            url.scheme == "https" && url.host?.lowercased() == host
                && (url.port == nil || url.port == 443)
                && (url.path.isEmpty || url.path == "/")
                && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
        }
        guard matches(storageOrigin, host: supabaseHost) else { return false }
        switch qaBinding {
        case .absent: return matches(apiOrigin, host: bffHost)
        case .invalid: return false
        case .candidate(let candidate):
            guard let host = candidate.origin.host?.lowercased() else { return false }
            return matches(apiOrigin, host: host)
        }
    }

    static func make(transport: MobileAPITransport?, lifecycle: (any SessionLifecycleProviding)?,
                     storageOrigin: URL?, deviceDraft: OnboardingDeviceDraftStore,
                     qaBinding: CurrentClinicalQABinding = .absent) -> Self? {
        guard let transport, transport.supportsCurrentClinicalSessionBinding, let lifecycle,
              let storageOrigin, let apiOrigin = transport.configuredOrigin,
              allows(storageOrigin: storageOrigin, apiOrigin: apiOrigin, qaBinding: qaBinding) else { return nil }
        return Self(readers: .live(transport: transport, lifecycle: lifecycle),
            onboarding: MobileOnboardingRepository(transport: transport, deviceDraft: deviceDraft,
                sessionLifecycle: lifecycle, clinicalRepresentation: .currentV1),
            flowChat: MobileFlowChatRepository(transport: transport, sessionLifecycle: lifecycle,
                clinicalRepresentation: .currentV1),
            firstPhase: MobileClinicalFirstPhaseRepository(transport: transport, lifecycle: lifecycle),
            full: MobileClinicalFullRepository(transport: transport, lifecycle: lifecycle),
            photos: .live(transport: transport, lifecycle: lifecycle,
                uploader: StorageUploadTransport(storageOrigin: storageOrigin),
                staging: MediaStagingStore(), camera: .device))
    }
}

extension CurrentClinicalReaderSessionFactory {
    static var unavailable: Self {
        Self { _ in throw BodyFlowCapabilityError.serviceUnavailable }
    }
}
