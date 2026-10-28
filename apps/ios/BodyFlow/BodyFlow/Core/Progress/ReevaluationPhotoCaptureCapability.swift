import Foundation

struct ReevaluationPhotoCaptureScope: Sendable {
    let userID:String
    let cycleID:String
    let photos:any ReevaluationPhotosProviding
    let camera:MealCameraAccess
    let validateSession:@Sendable () async throws -> Void
    let stagePhoto:@Sendable (Data,MealSourceChannel) async throws -> StagedMedia
    let upload:@Sendable (StagedMedia,ReevaluationPhotoUpload) async throws -> Void
    let discardStaged:@Sendable (URL) async throws -> Void
    let loadData:@Sendable (@escaping @Sendable () async throws -> Data) async throws -> Data
    init(userID:String,cycleID:String,photos:any ReevaluationPhotosProviding,camera:MealCameraAccess,
         validateSession:@escaping @Sendable () async throws -> Void,
         stagePhoto:@escaping @Sendable (Data,MealSourceChannel) async throws -> StagedMedia,
         upload:@escaping @Sendable (StagedMedia,ReevaluationPhotoUpload) async throws -> Void,
         discardStaged:@escaping @Sendable (URL) async throws -> Void,
         loadData:@escaping @Sendable (@escaping @Sendable () async throws -> Data) async throws -> Data = { load in try await load() }) {
        self.userID = userID; self.cycleID = cycleID; self.photos = photos; self.camera = camera
        self.validateSession = validateSession; self.stagePhoto = stagePhoto; self.upload = upload; self.discardStaged = discardStaged; self.loadData = loadData
    }
}
struct ReevaluationPhotoCaptureCapability: Sendable {
    let scoped:@Sendable (String,String) async throws -> ReevaluationPhotoCaptureScope
    static func live(transport:any MobileAPIExecuting,lifecycle:any SessionLifecycleProviding,uploader:any StorageUploading,
                     staging:MediaStagingStore,camera:MealCameraAccess) -> Self {
        Self { userID,cycleID in
            guard ReevaluationPhotoValidation.id(cycleID) else { throw ReevaluationPhotoFailure.invalidInput }
            try Task.checkCancellation()
            let lease = try await lifecycle.leaseForRequest()
            guard lease.userID == userID else { throw ReevaluationPhotoFailure.sessionEnded }
            let photos = try await MobileReevaluationPhotoRepository(transport:transport,lifecycle:lifecycle).scoped(to:lease,cycleID:cycleID)
            let work = ReevaluationPhotoSessionWork(lifecycle:lifecycle,lease:lease)
            return ReevaluationPhotoCaptureScope(userID:userID,cycleID:cycleID.lowercased(),photos:photos,camera:camera,
                validateSession:{ try Task.checkCancellation(); try await lifecycle.validate(lease) },
                stagePhoto:{ data,channel in
                    try await lifecycle.performPatientStateOperation(lease:lease) {
                        guard channel.isPhoto else { throw ReevaluationPhotoFailure.invalidInput }
                        let bytes = try MealPhotoNormalizer.normalizedJPEG(from:data)
                        guard (1...MealMediaLimits.maximumPhotoBytes).contains(bytes.count) else { throw MealCaptureFailure.fileTooLarge }
                        let url = try staging.stage(bytes,fileExtension:"jpg")
                        // body_checkin_photo is the shared media KIND only.
                        // All allocation/consent/cycle authority is recurring.
                        return StagedMedia(fileURL:url,kind:.signupBodyPhoto,mimeType:"image/jpeg",sizeBytes:bytes.count,duration:nil,channel:channel)
                    }
                }, upload:{ media,ticket in
                    _ = try ticket.validated(cycleID:cycleID,assetID:ticket.asset.id,acceptanceID:ticket.asset.acceptanceID)
                    guard media.kind == .signupBodyPhoto, media.mimeType == "image/jpeg", media.channel.isPhoto, media.duration == nil,
                          media.sizeBytes == ticket.asset.sizeBytes, media.mimeType == ticket.asset.mimeType else { throw ReevaluationPhotoFailure.invalidInput }
                    try await work.run { try await uploader.upload(media,with:ticket.upload) }
                }, discardStaged:{ url in
                    // Local cleanup outlives caller cancellation, but not the
                    // original filesystem authority. Session purge handles end.
                    let cleanup = Task {
                        try await lifecycle.performPatientStateOperation(lease:lease) {
                            staging.remove(url)
                            guard !FileManager.default.fileExists(atPath:url.path) else { throw ReevaluationPhotoFailure.unavailable }
                        }
                    }
                    try await cleanup.value
                },loadData:{ load in try await work.run(load) })
        }
    }
}
