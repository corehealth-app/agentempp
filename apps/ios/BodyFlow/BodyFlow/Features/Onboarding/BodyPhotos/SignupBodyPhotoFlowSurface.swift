import SwiftUI

/// One scrolling route surface under the host's existing NavigationStack.
/// Parent owns route/state; the host must supply a real close operation.
@MainActor
struct SignupBodyPhotoFlowSurface: View {
    let photos: SignupBodyPhotoPresentationModel
    private let close: @MainActor () -> Void
    @Environment(\.locale) private var locale
    // These belong to the surface, above consent/capture/result replacement.
    // D1 owns the registered producer and its actual completion/drain.
    @State private var source = SignupBodyPhotoSourcePresentationModel()
    @State private var callerTask: Task<Void, Never>?
    @State private var callerID: UUID?
    @State private var callerParent: ObjectIdentifier?
    @State private var cameraOrdinal = 0

    init(photos: SignupBodyPhotoPresentationModel,
        close: @escaping @MainActor () -> Void) {
        self.photos = photos; self.close = close
    }

    var body: some View {
        Group {
            if photos.route != nil {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    Button(copy("onboarding.back"), action: closeFlow)
                        .buttonStyle(BodyFlowButtonStyle(role: .tertiary, isCompact: true))
                        .accessibilityIdentifier("onboarding.photos.flow.close")
                        .padding(.horizontal, BodyFlowSpacing.lg)
                    ScrollView {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                            if callerTask != nil, photos.route == .capture,
                               photos.capture?.phase == .idle, source.presentation == nil {
                                BodyFlowStatusLine(copy("state.loading.title"), kind: .pending)
                                    .accessibilityIdentifier("onboarding.photos.source.pending")
                            }
                            routeContent
                        }
                        .padding(BodyFlowSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("onboarding.photos.flow.scroll")
                }
            }
        }
        .fullScreenCover(item: sourcePresentation) { presentation in
            sourceContent(presentation)
                // SDK delegate/camera callbacks are the selection/cancel
                // events. Swiping the hosting cover must not invent one.
                .interactiveDismissDisabled()
        }
        .onChange(of: photos.route) { _, route in
            if route == nil { cancelCaller() }
            // capture -> result preserves the source and registered caller.
        }
        .onChange(of: ObjectIdentifier(photos)) { _, _ in cancelCaller() }
        .onChange(of: photos.isActive) { _, active in
            if !active { cancelCaller() }
        }
        // No onDisappear cancellation: a modal can cover the capture child.
    }

    @ViewBuilder
    private var routeContent: some View {
        switch photos.route {
        case .consent:
            SignupBodyPhotoConsentRouteView(photos: photos)
        case .capture:
            SignupBodyPhotoCaptureView(photos: photos,
                onCamera: { choose(pose: $0, channel: .camera) },
                onGallery: { choose(pose: $0, channel: .gallery) },
                onExit: closeFlow, isChoosingSource: callerTask != nil)
        case .result:
            SignupBodyPhotoResultView(photos: photos, onConfirmed: closeFlow, onExit: closeFlow)
        case nil:
            EmptyView()
        }
    }

    private var sourcePresentation: Binding<SignupBodyPhotoSourcePresentation?> {
        Self.presentationBinding(for: source)
    }

    // Each setter belongs to the UUID visible when this binding was created.
    // A delayed nil from an older cover cannot cancel its replacement.
    static func presentationBinding(for source: SignupBodyPhotoSourcePresentationModel)
        -> Binding<SignupBodyPhotoSourcePresentation?> {
        let expectedID = source.presentation?.id
        return Binding(get: { source.presentation }, set: { next in
            guard next == nil, let expectedID,
                  source.presentation?.id == expectedID else { return }
            source.cancel(requestID: expectedID)
        })
    }

    @ViewBuilder
    private func sourceContent(_ presentation: SignupBodyPhotoSourcePresentation) -> some View {
        switch presentation.channel {
        case .camera:
            if let camera = presentation.camera {
                MealCameraCover(camera: camera, presentation: cameraOrdinal) { data in
                    source.finishCamera(requestID: presentation.id, data: data)
                }
            }
        case .gallery:
            SignupBodyPhotoLibraryPicker(requestID: presentation.id) { id, result in
                source.finishLibrary(requestID: id, result: result)
            }
        default:
            EmptyView() // Source rejects non-photo channels before publishing.
        }
    }

    private func choose(pose: SignupBodyPhotoPose, channel: MealSourceChannel) {
        // One serial UI caller. Other poses are not canceled by another tap,
        // and manual/skip/close remain usable while the SDK is held.
        guard callerTask == nil, photos.route == .capture, channel.isPhoto else { return }
        let parent = photos, bridge = source
        let id = UUID(), parentIdentity = ObjectIdentifier(parent)
        let camera = channel == .camera ? parent.camera : nil
        if channel == .camera { cameraOrdinal += 1 }
        callerID = id; callerParent = parentIdentity
        callerTask = Task { @MainActor in
            defer {
                // An obsolete callback cannot clear a replacement caller.
                if callerID == id, callerParent == parentIdentity {
                    callerTask = nil; callerID = nil; callerParent = nil
                }
            }
            // Parent registers D1 before the loader's first SDK await and
            // supplies the revocable full-owner authorization to Source.
            await parent.producePhoto(pose: pose, channel: channel) { authorization in
                try await bridge.request(channel: channel, camera: camera,
                    authorization: authorization)
            }
        }
    }

    private func cancelCaller() {
        guard callerID != nil else { return }
        callerTask?.cancel()
        if let id = source.presentation?.id { source.cancel(requestID: id) }
        // Retain the task/identity until its real operation ends. Selection
        // can already be loading data, and Source must not fake that return.
    }

    private func closeFlow() {
        cancelCaller() // revoke this caller before changing the host route
        close()
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }
}
