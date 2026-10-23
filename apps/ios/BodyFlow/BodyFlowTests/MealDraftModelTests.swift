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
        maximumPolls: Int = 5,
        now: Date = Self.now,
        selectedMealType: MealType? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
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
            timeProvider: FixedTimeProvider(value: now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "capture-key"),
            pollInterval: .milliseconds(1),
            maximumPolls: maximumPolls,
            calendar: calendar,
            selectedMealType: selectedMealType
        )
        return Harness(model: model, server: server, staging: staging, base: base)
    }

    // Roberto selected the still-empty breakfast slot at lunch and at night.
    // Hours and foods below are synthetic; the reported timing/selection is exact.
    @Test("Breakfast selected in Today stays breakfast at lunch and at night, for every capture",
          arguments: [13, 20], ["text", "photo", "audio"])
    func selectedBreakfastSurvivesCapture(hour: Int, capture: String) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: hour)))
        let harness = makeHarness(now: now, selectedMealType: .breakfast, calendar: calendar)
        defer { try? FileManager.default.removeItem(at: harness.base) }

        switch capture {
        case "photo": await harness.model.submitMedia(try harness.stagedPhoto())
        case "audio": await harness.model.submitMedia(try harness.stagedAudio())
        default: await harness.model.submitText("2 ovos mexidos")
        }

        #expect(harness.model.phase == .review)
        #expect(harness.model.review?.mealType == .breakfast)
        let request = try #require(harness.model.reviewedRequest(language: .portugueseBrazil))
        #expect(request.mealType == .breakfast)
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(payload["meal_type"] as? String == "cafe")
    }

    @Test("An explicitly selected slot survives reading retry and remains editable")
    func selectedSlotSurvivesRetryAndManualCorrection() async throws {
        let harness = makeHarness(selectedMealType: .breakfast)
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.server.failNext(.draft(.text("2 ovos mexidos")), with: .unavailable)
        await harness.model.submitText("2 ovos mexidos")
        #expect(harness.model.canRetry)
        await harness.model.retry()
        #expect(harness.model.review?.mealType == .breakfast)
        harness.model.review?.mealType = .dinner
        #expect(harness.model.reviewedRequest(language: .portugueseBrazil)?.mealType == .dinner)
    }

    @Test("Without a selected slot the named meal still wins over the clock")
    func genericEntryKeepsNamedMeal() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.model.submitText("No café da manhã comi 2 ovos mexidos")
        #expect(harness.model.review?.mealType == .breakfast)
    }

    @Test("An explicit Today selection wins over an automatic interpretation of the text")
    func selectedSlotWinsOverDetectedMealName() async throws {
        let harness = makeHarness(selectedMealType: .breakfast)
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.model.submitText("Os mesmos alimentos do almoço: 2 ovos mexidos")
        #expect(harness.model.review?.mealType == .breakfast)
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

    // MARK: First update (2026-10-10) — one continuous analysis
    //
    // Reported by the owner on build 1.0 (3), real account, PHOTO: while the
    // plate was analysed, several loading indicators followed one another
    // ("Preparando o arquivo…" owned by the screen, then a new one for
    // "Enviando…" onwards owned by this model).

    @Test("A photo is one continuous analysis from preparing to the review")
    func photoIsOneContinuousAnalysisFromPreparingToReview() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPhoto()
        await harness.server.setStates(["processing", "processed"])
        let model = harness.model
        await harness.server.observePhases { model.phase }

        // The photo was taken: the wait starts before anything is sent.
        model.beginPreparing()
        #expect(model.phase == .preparing)
        #expect(model.isAnalysing)
        #expect(!model.isWorking, "Nothing travels yet: the prepared file is still accepted")
        #expect(MealAnalysisStage.resolve(phase: model.phase, channel: model.channel, isProposing: false)
            == .preparing)

        await model.submitMedia(staged)

        let calls = await harness.server.calls
        let phases = await harness.server.phases
        #expect(calls == [
            .create, .upload, .complete, .process, .read, .read,
            .draft(.media(assetID: Self.assetID)),
        ])
        try #require(phases.count == calls.count)
        try #require(phases.count >= 6)
        #expect(phases == [
            .uploading, .uploading, .uploading, .processing, .processing, .processing, .reading,
        ])
        // The choice of ways can never show through in the middle.
        #expect(!phases.contains(.idle))
        let stages = phases.map {
            MealAnalysisStage.resolve(phase: $0, channel: .camera, isProposing: false)
        }
        #expect(stages == [.sending, .sending, .sending, .photo, .photo, .photo, .reading])
        #expect(model.phase == .review)
        #expect(!model.isAnalysing)
    }

    @Test("A recording says its own line where the photo says the photo's")
    func audioSaysListeningWhereThePhotoSaysLooking() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedAudio()
        let model = harness.model
        await harness.server.observePhases { model.phase }

        model.beginPreparing()
        #expect(model.phase == .preparing)
        await model.submitMedia(staged)

        let phases = await harness.server.phases
        try #require(phases.count == 6)
        #expect(!phases.contains(.idle))
        let stages = phases.map {
            MealAnalysisStage.resolve(phase: $0, channel: .audioRecording, isProposing: false)
        }
        #expect(stages == [.sending, .sending, .sending, .audio, .audio, .reading])
        #expect(model.channel == .audioRecording)
        #expect(model.phase == .review)
    }

    @Test("A preparation that fails says why, and the next capture starts clean")
    func preparingThatFailsSaysWhyAndTheNextCaptureStartsClean() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let model = harness.model

        model.beginPreparing()
        #expect(model.phase == .preparing)
        model.reportCaptureFailure(.unreadableMedia)
        #expect(model.phase == .failed(.unreadableMedia))
        #expect(!model.canRetry)

        model.beginPreparing()
        #expect(model.phase == .preparing)
        await model.submitMedia(try harness.stagedPhoto())
        #expect(model.phase == .review)

        // A review is never thrown away by a preparation that arrives late.
        model.beginPreparing()
        #expect(model.phase == .review)
        #expect(model.review != nil)
    }

    @Test("Closing the sheet while a file is prepared leaves nothing behind")
    func closingTheSheetWhilePreparingLeavesNothingBehind() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPhoto()
        let model = harness.model

        model.beginPreparing()
        #expect(model.phase == .preparing)
        model.discardSheet()
        #expect(model.phase == .idle)

        // The file finishes preparing after the sheet is gone.
        await model.submitMedia(staged)
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
        #expect(await harness.server.calls.isEmpty)
        #expect(model.phase == .idle)
        model.beginPreparing()
        #expect(model.phase == .idle, "A closed sheet begins nothing")
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

        // A valid review no longer needs a per-food acknowledgment. The
        // ownership guarantee below still depends on proposalCreated, not
        // on merely obtaining this request.
        #expect(harness.model.phase == .review)
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
    /// The model's phase at the moment of each call (the model is suspended
    /// inside the call, so the reading is deterministic).
    private(set) var phases: [MealDraftPhase] = []
    private var phaseProbe: (@MainActor @Sendable () -> MealDraftPhase)?
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

    func observePhases(_ probe: @escaping @MainActor @Sendable () -> MealDraftPhase) {
        phaseProbe = probe
    }

    private func notePhase() async {
        guard let phaseProbe else { return }
        phases.append(await phaseProbe())
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
        await notePhase()
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
        await notePhase()
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
        await notePhase()
        try record(.complete)
        return asset("uploaded")
    }

    func requestProcessing(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot {
        await notePhase()
        processKeys.append(attempt.key.value)
        try record(.process)
        return asset("uploaded")
    }

    func asset(id: String) async throws -> MediaAssetSnapshot {
        await notePhase()
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
        await notePhase()
        draftKeys.append(attempt.key.value)
        try record(.draft(attempt.payload))
        return draft
    }
}
