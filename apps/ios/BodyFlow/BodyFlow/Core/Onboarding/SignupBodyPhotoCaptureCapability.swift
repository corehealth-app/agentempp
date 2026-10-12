import Foundation

/// One retained signup owner for all reads, mutations, staging and PUTs.
/// A new account must ask the factory for a new scope; an old scope cannot renew.
struct SignupBodyPhotoCaptureScope: Sendable {
    let userID: String
    let photos: any SignupBodyPhotosProviding
    let uploader: any StorageUploading
    let staging: MediaStagingStore
    let camera: MealCameraAccess
    let validateSession: @Sendable () async throws -> Void
    let stagePhoto: @Sendable (Data, MealSourceChannel) async throws -> StagedMedia
    let performWork: @Sendable (@escaping @Sendable () async throws -> Void) async throws -> Void
    let discardStaged: @Sendable (URL) async throws -> Void

    init(
        userID: String, photos: any SignupBodyPhotosProviding, uploader: any StorageUploading,
        staging: MediaStagingStore, camera: MealCameraAccess,
        validateSession: @escaping @Sendable () async throws -> Void,
        stagePhoto: @escaping @Sendable (Data, MealSourceChannel) async throws -> StagedMedia,
        performWork: @escaping @Sendable (@escaping @Sendable () async throws -> Void) async throws -> Void = { _ in throw SignupBodyPhotoFailure.unavailable },
        discardStaged: @escaping @Sendable (URL) async throws -> Void = { _ in throw SignupBodyPhotoFailure.unavailable }
    ) {
        self.userID = userID
        self.photos = photos
        self.uploader = uploader
        self.staging = staging
        self.camera = camera
        self.validateSession = validateSession
        self.stagePhoto = stagePhoto
        self.performWork = performWork
        self.discardStaged = discardStaged
    }
}

struct SignupBodyPhotoCaptureCapability: Sendable {
    let scoped: @Sendable (String) async throws -> SignupBodyPhotoCaptureScope

    static func live(
        transport: MobileAPITransport,
        lifecycle: any SessionLifecycleProviding,
        uploader: any StorageUploading,
        staging: MediaStagingStore,
        camera: MealCameraAccess
    ) -> Self {
        Self { userID in
            try Task.checkCancellation()
            let lease = try await lifecycle.leaseForRequest()
            guard lease.userID == userID else { throw SessionLifecycleError.sessionSuperseded }
            try await lifecycle.validate(lease)
            return SignupBodyPhotoCaptureScope(
                userID: userID,
                photos: MobileSignupBodyPhotoRepository(transport: transport.scoped(to: lease)),
                uploader: SignupSessionBoundUploader(uploader: uploader, lifecycle: lifecycle, lease: lease),
                staging: staging,
                camera: camera,
                validateSession: {
                    try Task.checkCancellation()
                    try await lifecycle.validate(lease)
                },
                stagePhoto: { data, channel in
                    try await lifecycle.performPatientStateOperation(lease: lease) {
                        try SignupBodyPhotoStager(staging: staging).stagePhoto(data, channel: channel)
                    }
                },
                performWork: { operation in
                    try await SignupSessionBoundWork(lifecycle: lifecycle, lease: lease).run(operation)
                },
                discardStaged: { url in
                    // Local cleanup must finish even if its caller cancelled.
                    // The retained lease still owns every filesystem effect.
                    let cleanup = Task {
                        try await lifecycle.performPatientStateOperation(lease: lease) {
                            staging.remove(url)
                        }
                    }
                    try await cleanup.value
                }
            )
        }
    }
}

/// Local cancellation requests stopping the PUT; it does not revoke a ticket
/// or prove that no bytes reached Storage. The server owns disposition/retry.
struct SignupSessionBoundUploader: StorageUploading {
    let uploader: any StorageUploading
    let lifecycle: any SessionLifecycleProviding
    let lease: SessionLease

    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        guard media.kind == .signupBodyPhoto, media.mimeType == "image/jpeg",
              media.channel.isPhoto, media.duration == nil,
              (1...MealMediaLimits.maximumPhotoBytes).contains(media.sizeBytes)
        else { throw SignupBodyPhotoFailure.invalidInput }
        try await SignupSessionBoundWork(lifecycle: lifecycle, lease: lease).run {
            try await uploader.upload(media, with: ticket)
        }
    }
}

/// Shares the already guarded PUT registration with the whole capture task.
/// Completing the registry is a suspension and cannot renew the retained lease.
struct SignupSessionBoundWork: Sendable {
    let lifecycle: any SessionLifecycleProviding
    let lease: SessionLease

    func run(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try Task.checkCancellation()
        let cancellation = SignupUploadCancellation()
        let id = try await lifecycle.beginPatientWork(lease: lease, cancel: { cancellation.cancel() })
        do {
            try Task.checkCancellation()
            let task = Task {
                try await lifecycle.validate(lease)
                try Task.checkCancellation()
                try await operation()
                try await lifecycle.validate(lease)
                try Task.checkCancellation()
            }
            cancellation.install(task)
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                cancellation.cancel()
            }
            cancellation.clear()
        } catch {
            cancellation.cancel()
            cancellation.clear()
            await lifecycle.finishPatientWork(id)
            throw error
        }
        await lifecycle.finishPatientWork(id)
        // Finishing the registry can suspend too. Refuse a session switch or
        // cancellation that occurred there before handing success to the model.
        try await lifecycle.validate(lease)
        try Task.checkCancellation()
    }
}

/// `beginPatientWork` may cancel before the child task has been installed.
/// The lock retains that cancellation and applies it when installation occurs.
private final class SignupUploadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: Task<Void, Error>?

    func install(_ value: Task<Void, Error>) {
        let cancelNow = lock.withLock { task = value; return cancelled }
        if cancelNow { value.cancel() }
    }
    func cancel() {
        let value = lock.withLock { cancelled = true; return task }
        value?.cancel()
    }
    func clear() { lock.withLock { task = nil } }
}
