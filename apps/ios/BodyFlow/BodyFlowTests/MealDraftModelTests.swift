import Foundation
import Testing

@testable import BodyFlow

@Suite("Meal draft model")
@MainActor
struct MealDraftModelTests {
    private static let assetID = "0a0a0a0a-1111-4222-8333-444455556666"
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static let draft = MealDraftSnapshot(
        source: "text", mediaAssetID: nil, transcript: nil, contextNote: nil,
        items: [MealDraftCandidate(
            candidateID: "c1-0a1b2c3d", name: "ovos mexidos", quantityG: 100,
            quantityBasis: "portion_reference", count: 2, unitLabel: "unidade",
            confidence: nil, needsReview: true, reviewReason: "estimated_quantity"
        )],
        nutritionLabel: nil
    )

    private struct Harness {
        let model: MealDraftModel
        let server: CaptureServerFake
        let staging: MediaStagingStore
        let base: URL

        func stagedPhoto() throws -> StagedMedia {
            let url = try staging.stage(Data([0xFF, 0xD8, 1, 2]), fileExtension: "jpg")
            return StagedMedia(
                fileURL: url, kind: .mealPhoto, mimeType: "image/jpeg",
                sizeBytes: 4, duration: nil, channel: .camera
            )
        }

        func stagedAudio(duration: TimeInterval = 20) throws -> StagedMedia {
            let url = try staging.stage(Data([1, 2, 3]), fileExtension: "m4a")
            return StagedMedia(
                fileURL: url, kind: .audioNote, mimeType: "audio/mp4",
                sizeBytes: 3, duration: duration, channel: .audioRecording
            )
        }
    }

    private func makeHarness(
        withMedia: Bool = true,
        maximumPolls: Int = 5
    ) -> Harness {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-model-\(UUID().uuidString)", isDirectory: true)
        let staging = MediaStagingStore(temporaryDirectory: base)
        let server = CaptureServerFake(assetID: Self.assetID, draft: Self.draft)
        let model = MealDraftModel(
            media: withMedia ? server : nil,
            drafts: server,
            uploader: withMedia ? server : nil,
            staging: staging,
            timeProvider: FixedTimeProvider(value: Self.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "capture-key"),
            pollInterval: .milliseconds(1),
            maximumPolls: maximumPolls,
            calendar: Calendar(identifier: .gregorian)
        )
        return Harness(model: model, server: server, staging: staging, base: base)
    }

    @Test("Free text becomes candidates for review, with no media call")
    func textToReview() async throws {
        let harness = makeHarness()

        await harness.model.submitText("  2 ovos mexidos  ")

        #expect(await harness.server.calls == [.draft(.text("2 ovos mexidos"))])
        #expect(harness.model.phase == .review)
        #expect(harness.model.channel == .text)
        #expect(harness.model.review?.items.map(\.name) == ["ovos mexidos"])
        #expect(harness.model.review?.source
            == MealProposalSource(channel: .text, mediaAssetID: nil))
    }

    @Test("Empty or oversized text never leaves the phone")
    func textLimits() async {
        let harness = makeHarness()

        await harness.model.submitText("   ")
        #expect(harness.model.phase == .failed(.invalidInput))
        await harness.model.submitText(String(repeating: "a", count: 2_001))
        #expect(harness.model.phase == .failed(.invalidInput))

        #expect(await harness.server.calls.isEmpty)
        #expect(!harness.model.canRetry)
    }

    @Test("A photo is created, uploaded, completed, processed and only then read")
    func photoPipeline() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPhoto()
        await harness.server.setStates(["processing", "processing", "processed"])

        await harness.model.submitMedia(staged)

        #expect(await harness.server.calls == [
            .create, .upload, .complete, .process, .read, .read, .read,
            .draft(.media(assetID: Self.assetID)),
        ])
        #expect(harness.model.phase == .review)
        #expect(harness.model.review?.source
            == MealProposalSource(channel: .camera, mediaAssetID: Self.assetID))
        // The staged file leaves the phone's temporary folder once the server
        // confirmed the upload.
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test("A failed upload resumes with the same asset and a fresh ticket")
    func resumesAfterUploadFailure() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPhoto()
        await harness.server.failNext(.upload, with: .offline)

        await harness.model.submitMedia(staged)

        #expect(harness.model.phase == .failed(.offline))
        #expect(harness.model.canRetry)
        #expect(FileManager.default.fileExists(atPath: staged.fileURL.path))

        await harness.model.retry()

        #expect(harness.model.phase == .review)
        #expect(await harness.server.calls == [
            .create, .upload, .create, .upload, .complete, .process, .read,
            .draft(.media(assetID: Self.assetID)),
        ])
        let keys = await harness.server.createKeys
        #expect(keys.count == 2)
        #expect(Set(keys).count == 1)
    }

    @Test("After the upload was accepted the file is not sent again")
    func resumesAfterProcessingFailure() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.server.setStates(["failed"])

        await harness.model.submitMedia(try harness.stagedPhoto())
        #expect(harness.model.phase == .failed(.processingFailed))
        #expect(harness.model.canRetry)

        await harness.server.setStates(["processed"])
        await harness.model.retry()

        #expect(harness.model.phase == .review)
        #expect(await harness.server.calls == [
            .create, .upload, .complete, .process, .read,
            .process, .read, .draft(.media(assetID: Self.assetID)),
        ])
        // A new processing request needs a new key.
        let keys = await harness.server.processKeys
        #expect(Set(keys).count == 2)
    }

    @Test("The server's refusal of a long recording is final")
    func audioTooLongFromWorker() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.server.setStates(["failed"], failureCode: "audio_too_long")

        await harness.model.submitMedia(try harness.stagedAudio())

        #expect(harness.model.phase == .failed(.audioTooLong))
        #expect(!harness.model.canRetry)
        #expect(!(await harness.server.calls.contains(.draft(.media(assetID: Self.assetID)))))
    }

    @Test("A recording over 180 seconds never reaches the server and leaves no file")
    func audioTooLongOnPhone() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedAudio(duration: 181)

        await harness.model.submitMedia(staged)

        #expect(harness.model.phase == .failed(.audioTooLong))
        #expect(await harness.server.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test("Processing that never ends stops with a retry that only reads again")
    func processingTimeout() async throws {
        let harness = makeHarness(maximumPolls: 2)
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.server.setStates(["processing", "processing", "processed"])

        await harness.model.submitMedia(try harness.stagedPhoto())
        #expect(harness.model.phase == .failed(.processingTimedOut))

        await harness.model.retry()
        #expect(harness.model.phase == .review)
        #expect(await harness.server.calls == [
            .create, .upload, .complete, .process, .read, .read,
            .read, .draft(.media(assetID: Self.assetID)),
        ])
    }

    @Test("Nothing recognized is said as such and reading again uses a new key")
    func nothingRecognized() async throws {
        let harness = makeHarness()
        await harness.server.failNext(.draft(.text("xyz")), with: .nothingRecognized)

        await harness.model.submitText("xyz")
        #expect(harness.model.phase == .failed(.nothingRecognized))
        #expect(!harness.model.canRetry)

        await harness.server.failNext(.draft(.text("2 ovos")), with: .unavailable)
        await harness.model.submitText("2 ovos")
        #expect(harness.model.canRetry)
        await harness.model.retry()
        #expect(harness.model.phase == .review)
        let keys = await harness.server.draftKeys
        #expect(Set(keys).count == keys.count)
    }

    @Test("Without storage access media is refused and the file removed")
    func mediaUnavailable() async throws {
        let harness = makeHarness(withMedia: false)
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPhoto()

        #expect(harness.model.isAvailable)
        #expect(!harness.model.supportsMedia)
        await harness.model.submitMedia(staged)

        #expect(harness.model.phase == .failed(.captureUnavailable))
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test("Dropping a capture removes the file and the server's copy")
    func startOverDeletesAsset() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.model.submitMedia(try harness.stagedPhoto())
        #expect(harness.model.phase == .review)

        harness.model.startOver()
        try await harness.server.waitForDelete()

        #expect(harness.model.phase == .idle)
        #expect(harness.model.review == nil)
        #expect(harness.model.channel == nil)
        #expect(await harness.server.calls.last == .delete)
    }

    @Test("Once the review became a proposal its media stays with it")
    func proposedMediaIsKept() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.model.submitMedia(try harness.stagedPhoto())

        #expect(harness.model.reviewedRequest(language: .portugueseBrazil) == nil)
        harness.model.review?.items[0].isConfirmed = true
        let request = try #require(harness.model.reviewedRequest(language: .portugueseBrazil))
        harness.model.proposalCreated()
        harness.model.discardSheet()
        try await Task.sleep(for: .milliseconds(30))

        #expect(request.source?.mediaAssetID == Self.assetID)
        #expect(request.items.first?.candidateID == "c1-0a1b2c3d")
        #expect(!(await harness.server.calls.contains(.delete)))
    }

    @Test("A reviewed meal whose proposal was never created does not keep its media")
    func failedProposalDoesNotKeepMedia() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.model.submitMedia(try harness.stagedPhoto())
        harness.model.review?.items[0].isConfirmed = true
        // The request was handed over, and the proposal failed.
        _ = try #require(harness.model.reviewedRequest(language: .portugueseBrazil))

        harness.model.startOver()
        try await harness.server.waitForDelete()

        #expect(await harness.server.calls.last == .delete)
    }

    @Test("A capture that finishes preparing after the sheet was closed is not sent")
    func lateSubmitAfterClose() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPhoto()

        harness.model.discardSheet()
        await harness.model.submitMedia(staged)
        await harness.model.submitText("2 ovos")

        #expect(await harness.server.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
        #expect(harness.model.review == nil)
    }

    @Test("The server's copy is deleted only after the upload has stopped")
    func deleteWaitsForUpload() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPhoto()
        await harness.server.suspendUploads()

        let task = Task { await harness.model.submitMedia(staged) }
        try await harness.server.waitForUploadStart()
        harness.model.startOver()
        try await Task.sleep(for: .milliseconds(30))
        #expect(await harness.server.calls == [.create, .upload])

        await harness.server.resumeUploads()
        await task.value
        try await harness.server.waitForDelete()

        #expect(await harness.server.calls == [.create, .upload, .delete])
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
        #expect(harness.model.phase == .idle)
    }

    @Test("Closing the sheet in the middle of an upload leaves nothing behind")
    func discardDuringUpload() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPhoto()
        await harness.server.suspendUploads()

        let task = Task { await harness.model.submitMedia(staged) }
        try await harness.server.waitForUploadStart()
        #expect(harness.model.phase == .uploading)

        harness.model.discardSheet()
        await harness.server.resumeUploads()
        await task.value
        try await harness.server.waitForDelete()

        #expect(harness.model.phase == .idle)
        #expect(harness.model.review == nil)
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
        #expect(!(await harness.server.calls.contains(.complete)))
    }

    @Test("A capture failure from the phone is shown with its cause")
    func reportedFailure() {
        let harness = makeHarness()
        harness.model.reportCaptureFailure(.permissionDenied)
        #expect(harness.model.phase == .failed(.permissionDenied))
        #expect(!harness.model.canRetry)
    }
}

private actor CaptureServerFake: MealMediaProviding, MealDraftProviding, StorageUploading {
    enum Call: Equatable, Sendable {
        case create, upload, complete, process, read, delete
        case draft(MealDraftRequest)
    }

    private let assetID: String
    private let draft: MealDraftSnapshot
    private var states = ["processed"]
    private var failureCode: String?
    private var failures: [(Call, MealCaptureFailure)] = []
    private var uploaded = false
    private var uploadsSuspended = false
    private var uploadWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var calls: [Call] = []
    private(set) var createKeys: [String] = []
    private(set) var processKeys: [String] = []
    private(set) var draftKeys: [String] = []

    init(assetID: String, draft: MealDraftSnapshot) {
        self.assetID = assetID
        self.draft = draft
    }

    func setStates(_ states: [String], failureCode: String? = nil) {
        self.states = states
        self.failureCode = failureCode
    }

    func failNext(_ call: Call, with failure: MealCaptureFailure) {
        failures.append((call, failure))
    }

    func suspendUploads() { uploadsSuspended = true }

    func resumeUploads() {
        uploadsSuspended = false
        let waiters = uploadWaiters
        uploadWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForUploadStart() async throws {
        for _ in 0..<500 where !calls.contains(.upload) {
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    func waitForDelete() async throws {
        for _ in 0..<500 where !calls.contains(.delete) {
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    private func record(_ call: Call) throws {
        calls.append(call)
        if let index = failures.firstIndex(where: { $0.0 == call }) {
            throw failures.remove(at: index).1
        }
    }

    private func asset(_ status: String) -> MediaAssetSnapshot {
        MediaAssetSnapshot(
            id: assetID, kind: "meal_photo", status: status,
            failureStage: status == "failed" ? "processing" : nil,
            failureCode: status == "failed" ? failureCode : nil
        )
    }

    func create(
        _ attempt: MutationAttempt<MediaUploadRequest>
    ) async throws -> MediaCreateSnapshot {
        createKeys.append(attempt.key.value)
        try record(.create)
        return MediaCreateSnapshot(
            asset: asset(uploaded ? "uploaded" : "pending_upload"),
            upload: uploaded ? nil : MediaUploadTicket(
                signedURL: "https://project.supabase.co/storage/v1/object/upload/sign/b/u/a?token=t\(createKeys.count)",
                method: "PUT",
                headers: ["Content-Type": attempt.payload.mimeType],
                expiresAt: APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_600))
            ),
            replayed: createKeys.count > 1
        )
    }

    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        try record(.upload)
        if uploadsSuspended {
            await withCheckedContinuation { uploadWaiters.append($0) }
        }
        guard FileManager.default.fileExists(atPath: media.fileURL.path) else {
            throw MealCaptureFailure.unreadableMedia
        }
        uploaded = true
    }

    func complete(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot {
        try record(.complete)
        return asset("uploaded")
    }

    func requestProcessing(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot {
        processKeys.append(attempt.key.value)
        try record(.process)
        return asset("uploaded")
    }

    func asset(id: String) async throws -> MediaAssetSnapshot {
        try record(.read)
        let status = states.count > 1 ? states.removeFirst() : (states.first ?? "processed")
        return asset(status)
    }

    func delete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws {
        try record(.delete)
    }

    func draft(
        _ attempt: MutationAttempt<MealDraftRequest>
    ) async throws -> MealDraftSnapshot {
        draftKeys.append(attempt.key.value)
        try record(.draft(attempt.payload))
        return draft
    }
}
