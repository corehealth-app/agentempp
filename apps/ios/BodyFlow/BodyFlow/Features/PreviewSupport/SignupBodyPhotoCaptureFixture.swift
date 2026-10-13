#if DEBUG
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Local synthetic scope, not Auth/JWT/Storage proof.
/// Install only from the separate DEBUG fresh-demo capture launch configuration.
actor SignupBodyPhotoCaptureFixture: SignupBodyPhotosProviding, StorageUploading {
    private let mode: AppRuntimeMode
    private let buildFlavor: AppBuildFlavor
    private let allowedOwnerID: String
    private let document: SignupBodyPhotoConsent
    private let staging: MediaStagingStore
    private let cleanup: SignupBodyPhotoCleanupStore
    private var boundOwner: String?
    private var acceptedAt: APITimestamp?
    private var consentAttempts: [String: MutationAttempt<SignupBodyPhotoConsentRequest>] = [:]
    private var createAttempts: [String: MutationAttempt<SignupBodyPhotoCreateRequest>] = [:]
    private var createResults: [String: SignupBodyPhotoCreateReceipt] = [:]
    private var completeAttempts: [String: MutationAttempt<MediaAssetCommand>] = [:]
    private var completeResults: [String: SignupBodyPhotoCompleteReceipt] = [:]
    private var deleteAttempts: [String: MutationAttempt<SignupBodyPhotoDeleteCommand>] = [:]
    private var deleteResults: [String: SignupBodyPhotoDeleteReceipt] = [:]
    private var byPose: [SignupBodyPhotoPose: SignupBodyPhotoOperationPhoto] = [:]
    private var ticketAssets: [String: String] = [:]
    private var uploaded: Set<String> = []
    private var ownedFiles: Set<URL> = []
    private var remembered: Set<UUID> = []
    private var consentCount = 0, createCount = 0, uploadCount = 0, completeCount = 0, deleteCount = 0
    private static let now = Date(timeIntervalSince1970: 1_791_849_600)

    init(mode: AppRuntimeMode, buildFlavor: AppBuildFlavor, directory: URL,
         allowedOwnerID: String, document: SignupBodyPhotoConsent) {
        self.mode = mode; self.buildFlavor = buildFlavor; self.allowedOwnerID = allowedOwnerID
        self.document = SignupBodyPhotoConsent(documentKey: document.documentKey, version: document.version,
            locale: document.locale, body: document.body, bodyHash: document.bodyHash, acceptedAt: nil)
        staging = MediaStagingStore(temporaryDirectory: directory.appendingPathComponent("media"))
        cleanup = SignupBodyPhotoCleanupStore(directory: directory.appendingPathComponent("markers"))
    }

    nonisolated var capability: SignupBodyPhotoCaptureCapability {
        .init(scoped: { userID in try await self.bind(userID) })
    }

    private func bind(_ userID: String) throws -> SignupBodyPhotoCaptureScope {
        try configurationBoundary()
        guard userID == allowedOwnerID, boundOwner == nil || boundOwner == userID else {
            throw SignupBodyPhotoFailure.sessionChanged
        }
        boundOwner = userID
        return SignupBodyPhotoCaptureScope(userID: userID, photos: self, uploader: self,
            staging: staging, camera: .synthetic,
            validateSession: { try await self.ownerBoundary(userID) },
            stagePhoto: { data, channel in try await self.stage(data, channel: channel, owner: userID) },
            performWork: { operation in try await self.perform(operation, owner: userID) },
            discardStaged: { file in try await self.discard(file, owner: userID) },
            rememberUnboundCreate: { operationID in try await self.remember(operationID, owner: userID) })
    }

    private func configurationBoundary(checkCancellation: Bool = true) throws {
        if checkCancellation { try Task.checkCancellation() }
        guard mode == .demo, buildFlavor == .debug else { throw SignupBodyPhotoFailure.unavailable }
    }
    private func ownerBoundary(_ owner: String, checkCancellation: Bool = true) throws {
        try configurationBoundary(checkCancellation: checkCancellation)
        guard boundOwner == owner, owner == allowedOwnerID else { throw SignupBodyPhotoFailure.sessionChanged }
    }
    private func currentBoundary() throws { try ownerBoundary(allowedOwnerID) }

    private func stage(_ data: Data, channel: MealSourceChannel, owner: String) throws -> StagedMedia {
        try ownerBoundary(owner)
        let media = try SignupBodyPhotoStager(staging: staging).stagePhoto(data, channel: channel)
        ownedFiles.insert(media.fileURL.standardizedFileURL)
        return media
    }
    private func perform(_ operation: @escaping @Sendable () async throws -> Void, owner: String) async throws {
        try ownerBoundary(owner)
        try await operation()
        try ownerBoundary(owner)
        // Parent/D1/Core retain and drain this task. This is a synthetic boundary,
        // not a substituted SessionLease or proof of live PatientWorkRegistry auth.
    }
    private func discard(_ file: URL, owner: String) throws {
        // Exact owned-file cleanup is permitted after caller cancellation.
        try ownerBoundary(owner, checkCancellation: false)
        let exact = file.standardizedFileURL
        guard ownedFiles.contains(exact) else { throw SignupBodyPhotoFailure.invalidInput }
        staging.remove(exact)
        guard !FileManager.default.fileExists(atPath: exact.path) else { throw SignupBodyPhotoFailure.unavailable }
        ownedFiles.remove(exact)
    }
    private func remember(_ operationID: UUID, owner: String) throws {
        try ownerBoundary(owner)
        try cleanup.mutate(for: owner) { queue in _ = queue.rememberUnbound(operationID) }
        remembered.insert(operationID)
    }

    func state() throws -> SignupBodyPhotoState { try currentBoundary(); return snapshot() }
    private func snapshot() -> SignupBodyPhotoState {
        let slots = SignupBodyPhotoPose.allCases.map { pose in
            SignupBodyPhotoSlot(pose: pose, photo: byPose[pose].map {
                SignupBodyPhoto(id: $0.id, status: $0.status, createdAt: $0.createdAt)
            })
        }
        var estimate: SignupBodyPhotoEstimate?
        if acceptedAt != nil, slots.allSatisfy({ $0.photo?.status == "read" }),
           let front = byPose[.front]?.id, let side = byPose[.side]?.id, let back = byPose[.back]?.id {
            // Declared server-shaped fixture, emitted only after the three current
            // captures completed. No client nutrition formula/AI/real reading.
            let decision = SignupBodyPhotoEstimate.Decision(usable: true, bodyFatPercent: Decimal(24), reason: nil)
            estimate = .init(isEstimate: true, bySex: .init(masculine: decision, feminine: decision),
                sourceIDs: .init(front: front, side: side, back: back),
                fingerprint: Self.digest([front, side, back, "synthetic-18-24-30"].joined(separator: "|")),
                readings: [.init(pose: .front, bodyFatPercent: Decimal(18)),
                    .init(pose: .side, bodyFatPercent: Decimal(24)), .init(pose: .back, bodyFatPercent: Decimal(30))])
        }
        return .init(available: true, unavailableReason: nil,
            consent: .init(documentKey: document.documentKey, version: document.version, locale: document.locale,
                body: document.body, bodyHash: document.bodyHash, acceptedAt: acceptedAt),
            minimumAge: 18, poses: slots, estimate: estimate, remainingUploads: max(9 - createCount, 0))
    }

    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) throws -> SignupBodyPhotoConsentReceipt {
        try currentBoundary()
        guard attempt.operation == .mediaCreate, attempt.payload.version == document.version,
              attempt.payload.bodyHash == document.bodyHash, Self.digest(document.body) == document.bodyHash
        else { throw SignupBodyPhotoFailure.consentRequired }
        if let prior = consentAttempts[attempt.key.value], prior != attempt { throw SignupBodyPhotoFailure.invalidInput }
        var ageDraft = OnboardingDraft.currentDeviceWelcome
        ageDraft.localeIdentifier = document.locale; ageDraft.timeZoneIdentifier = "UTC"
        ageDraft.birthDate = OnboardingCivilDate.date(from: attempt.payload.birthDate, timeZoneIdentifier: "UTC")
        guard SignupBodyPhotoAvailability.resolve(draft: ageDraft, state: snapshot(), hasCapability: true,
            now: Self.now) == .available else { throw SignupBodyPhotoFailure.ageNotAllowed }
        if consentAttempts[attempt.key.value] == nil { consentCount += 1; consentAttempts[attempt.key.value] = attempt }
        let timestamp = acceptedAt ?? APITimestamp(value: Self.now)
        acceptedAt = timestamp
        return .init(documentKey: document.documentKey, version: document.version, acceptedAt: timestamp)
    }

    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) throws -> SignupBodyPhotoCreateReceipt {
        try currentBoundary()
        guard acceptedAt != nil else { throw SignupBodyPhotoFailure.consentRequired }
        guard attempt.operation == .mediaCreate, attempt.payload.mimeType == "image/jpeg",
              (1...MealMediaLimits.maximumPhotoBytes).contains(attempt.payload.sizeBytes)
        else { throw SignupBodyPhotoFailure.invalidInput }
        if let old = createAttempts[attempt.key.value], let result = createResults[attempt.key.value] {
            guard old == attempt else { throw SignupBodyPhotoFailure.invalidInput }
            guard let current = byPose[result.photo.pose], current.id == result.photo.id else {
                throw SignupBodyPhotoFailure.uploadNotPending
            }
            return .init(photo: current, upload: current.status == "pending_upload" ? result.upload : nil,
                replayed: true)
        }
        guard createCount < 9 else { throw SignupBodyPhotoFailure.limitReached }
        let id = UUID().uuidString.lowercased()
        let photo = SignupBodyPhotoOperationPhoto(id: id, pose: attempt.payload.pose,
            status: "pending_upload", createdAt: APITimestamp(value: Self.now))
        // This opaque synthetic ticket is interpreted only by this local uploader.
        // It is not an HTTP URL/capability and is never handed to StorageUploadTransport.
        let ticketID = "signup-photo-local-fixture-" + id
        let ticket = MediaUploadTicket(signedURL: ticketID, method: "PUT",
            headers: ["Content-Type": "image/jpeg"], expiresAt: APITimestamp(value: .distantFuture))
        let result = SignupBodyPhotoCreateReceipt(photo: photo, upload: ticket, replayed: false)
        createAttempts[attempt.key.value] = attempt; createResults[attempt.key.value] = result
        byPose[attempt.payload.pose] = photo; ticketAssets[ticketID] = id; createCount += 1
        return result
    }

    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) throws {
        try currentBoundary()
        guard let id = ticketAssets[ticket.signedURL], ticket.method == "PUT",
              ticket.headers == ["Content-Type": "image/jpeg"], media.kind == .signupBodyPhoto,
              media.mimeType == "image/jpeg", media.channel.isPhoto, media.duration == nil,
              ownedFiles.contains(media.fileURL.standardizedFileURL),
              let create = createResults.values.first(where: { $0.photo.id == id }),
              let attempt = createAttempts.values.first(where: { $0.payload.pose == create.photo.pose
                  && createResults[$0.key.value]?.photo.id == id }),
              media.sizeBytes == attempt.payload.sizeBytes,
              byPose[create.photo.pose]?.id == id, byPose[create.photo.pose]?.status == "pending_upload"
        else { throw SignupBodyPhotoFailure.invalidInput }
        let bytes = try Data(contentsOf: media.fileURL)
        guard bytes.count == media.sizeBytes,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              (CGImageSourceGetType(source) as String?) == UTType.jpeg.identifier
        else { throw SignupBodyPhotoFailure.unreadableImage }
        if uploaded.insert(id).inserted { uploadCount += 1 }
        byPose[create.photo.pose] = .init(id: id, pose: create.photo.pose,
            status: "uploaded", createdAt: create.photo.createdAt)
    }

    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) throws -> SignupBodyPhotoCompleteReceipt {
        try currentBoundary()
        guard attempt.operation == .mediaComplete else { throw SignupBodyPhotoFailure.invalidInput }
        if let old = completeAttempts[attempt.key.value], let result = completeResults[attempt.key.value] {
            guard old == attempt else { throw SignupBodyPhotoFailure.invalidInput }; return result
        }
        guard uploaded.contains(attempt.payload.assetID),
              let photo = byPose.values.first(where: { $0.id == attempt.payload.assetID }),
              photo.status == "uploaded" else { throw SignupBodyPhotoFailure.uploadNotPending }
        let read = SignupBodyPhotoOperationPhoto(id: photo.id, pose: photo.pose, status: "read", createdAt: photo.createdAt)
        let result = SignupBodyPhotoCompleteReceipt(photo: read)
        byPose[photo.pose] = read; completeAttempts[attempt.key.value] = attempt
        completeResults[attempt.key.value] = result; completeCount += 1
        return result
    }

    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) throws -> SignupBodyPhotoDeleteReceipt {
        try currentBoundary()
        guard attempt.operation == .mediaDelete else { throw SignupBodyPhotoFailure.invalidInput }
        if let old = deleteAttempts[attempt.key.value], let result = deleteResults[attempt.key.value] {
            guard old == attempt else { throw SignupBodyPhotoFailure.invalidInput }; return result
        }
        // D1 drains Parent/Core and their exact-file cleanup before this boundary.
        guard ownedFiles.isEmpty else { throw SignupBodyPhotoFailure.cleanupPending }
        let result = SignupBodyPhotoDeleteReceipt(deleted: byPose.count)
        try cleanup.mutate(for: allowedOwnerID) { $0.unboundCreates.removeAll() }
        byPose.removeAll(); uploaded.removeAll(); ticketAssets.removeAll()
        deleteAttempts[attempt.key.value] = attempt; deleteResults[attempt.key.value] = result; deleteCount += 1
        return result
    }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) throws -> SignupBodyPhotoDeleteReceipt {
        try currentBoundary(); throw SignupBodyPhotoFailure.unavailable // no fake official generation G
    }
    func report() -> SignupBodyPhotoCaptureFixtureReport {
        .init(consents: consentCount, creates: createCount, uploads: uploadCount,
            completes: completeCount, deletes: deleteCount, rememberedCreates: remembered.count)
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
struct SignupBodyPhotoCaptureFixtureReport: Sendable {
    let consents: Int, creates: Int, uploads: Int, completes: Int, deletes: Int, rememberedCreates: Int
}
#endif
