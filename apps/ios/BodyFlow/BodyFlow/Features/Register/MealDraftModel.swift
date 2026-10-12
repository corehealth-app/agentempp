import Foundation
import Observation

enum MealDraftPhase: Equatable, Sendable {
    case idle
    /// A photo or a recording was captured and its file is being prepared
    /// for sending: the analysis has begun for the person, though nothing
    /// has left the phone yet.
    case preparing
    case uploading
    case processing
    case reading
    case review
    case failed(MealCaptureFailure)
}

/// Text, photo or recording up to the candidates the patient reviews. The
/// proposal itself stays with `MealRegistrationModel`: this model hands it a
/// reviewed request and nothing else.
///
/// A failed step is resumed, not restarted: the asset is created once (same
/// idempotency key), and a file already accepted by the server is not sent
/// again. The staged file leaves the phone's temporary folder as soon as the
/// server confirms the upload, and whenever the capture is dropped.
@MainActor
@Observable
final class MealDraftModel {
    private enum Input: Equatable {
        case text(String)
        case media(StagedMedia)
    }

    private struct Pipeline {
        let input: Input
        var createAttempt: MutationAttempt<MediaUploadRequest>?
        var assetID: String?
        var isUploaded = false
        var completeAttempt: MutationAttempt<MediaAssetCommand>?
        var isCompleted = false
        var processAttempt: MutationAttempt<MediaAssetCommand>?
        var isProcessingRequested = false
        var isProcessed = false
    }

    private let media: (any MealMediaProviding)?
    private let drafts: (any MealDraftProviding)?
    private let uploader: (any StorageUploading)?
    private let staging: MediaStagingStore
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private let clock: any Clock<Duration>
    private let pollInterval: Duration
    private let maximumPolls: Int
    private let calendar: Calendar

    private var pipeline: Pipeline?
    private var sequence = 0
    private var handedToProposal = false
    /// The work in hand. Dropping a capture cancels it, and the server's
    /// copy is only deleted after it has stopped (a delete sent while the
    /// upload is still travelling would leave the file behind).
    private var work: Task<Void, Never>?
    /// The sheet is gone: nothing that arrives late is sent.
    private var isClosed = false

    private(set) var phase = MealDraftPhase.idle
    private(set) var channel: MealSourceChannel?
    var review: MealDraftReview?

    init(
        media: (any MealMediaProviding)?,
        drafts: (any MealDraftProviding)?,
        uploader: (any StorageUploading)?,
        staging: MediaStagingStore,
        timeProvider: any TimeProviding,
        keyProvider: any IdempotencyKeyProviding,
        clock: any Clock<Duration> = ContinuousClock(),
        pollInterval: Duration = .milliseconds(1_500),
        maximumPolls: Int = 80,
        calendar: Calendar = .current
    ) {
        self.media = media
        self.drafts = drafts
        self.uploader = uploader
        self.staging = staging
        self.timeProvider = timeProvider
        self.keyProvider = keyProvider
        self.clock = clock
        self.pollInterval = pollInterval
        self.maximumPolls = maximumPolls
        self.calendar = calendar
    }

    /// Free text can become candidates.
    var isAvailable: Bool { drafts != nil }

    /// Photos and recordings can be sent too.
    var supportsMedia: Bool { drafts != nil && media != nil && uploader != nil }

    var isWorking: Bool {
        switch phase {
        case .uploading, .processing, .reading: true
        case .idle, .preparing, .review, .failed: false
        }
    }

    /// From the moment a capture is being prepared until the review: one
    /// continuous wait for the person.
    var isAnalysing: Bool { phase == .preparing || isWorking }

    /// A photo or a recording was captured and its file is being prepared:
    /// the wait starts here, in the same model that owns the rest of it, so
    /// no moment of the analysis shows the choice of ways in between.
    ///
    /// Every preparation ends in `submitMedia` or `reportCaptureFailure`.
    /// A review in hand and a capture already travelling are left alone.
    func beginPreparing() {
        guard !isClosed else { return }
        switch phase {
        case .idle, .failed: break
        case .preparing, .uploading, .processing, .reading, .review: return
        }
        // Whatever was left of an earlier capture goes, as it would when the
        // new one is sent.
        dropPipeline(deletingAsset: true)
        review = nil
        channel = nil
        phase = .preparing
    }

    /// A failure a new attempt of the same capture can get past.
    var canRetry: Bool {
        guard case let .failed(failure) = phase, pipeline != nil else { return false }
        switch failure {
        case .offline, .unavailable, .processingFailed, .processingTimedOut, .uploadRejected:
            return true
        case .subscriptionRequired, .invalidInput, .audioTooLong, .fileTooLarge,
             .unsupportedFile, .unreadableMedia, .nothingRecognized, .permissionDenied,
             .captureUnavailable:
            return false
        }
    }

    func submitText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isWorking, !isClosed else { return }
        guard !trimmed.isEmpty, trimmed.count <= MealMediaLimits.maximumTextLength else {
            fail(.invalidInput)
            return
        }
        dropPipeline(deletingAsset: true)
        channel = .text
        pipeline = Pipeline(input: .text(trimmed))
        await start()
    }

    func submitMedia(_ staged: StagedMedia) async {
        // A capture that finished preparing after the sheet was closed, or
        // while another one is on its way, is dropped where it is.
        guard !isWorking, !isClosed else {
            staging.remove(staged.fileURL)
            return
        }
        dropPipeline(deletingAsset: true)
        channel = staged.channel
        guard supportsMedia else {
            staging.remove(staged.fileURL)
            fail(.captureUnavailable)
            return
        }
        if let failure = Self.precheck(staged) {
            staging.remove(staged.fileURL)
            fail(failure)
            return
        }
        pipeline = Pipeline(input: .media(staged))
        await start()
    }

    /// Reports a capture that never produced a file (permission, camera,
    /// unreadable pick), so the screen says why.
    func reportCaptureFailure(_ failure: MealCaptureFailure) {
        guard !isWorking, !isClosed else { return }
        dropPipeline(deletingAsset: true)
        fail(failure)
    }

    func retry() async {
        guard canRetry, !isClosed else { return }
        await start()
    }

    private func start() async {
        let task = Task { await run() }
        work = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if work == task { work = nil }
    }

    /// Back to the choice of source; whatever was captured is dropped.
    func startOver() {
        sequence += 1
        dropPipeline(deletingAsset: !handedToProposal)
        handedToProposal = false
        review = nil
        channel = nil
        phase = .idle
    }

    /// The reviewed request. Nothing changes hands yet: the media belongs to
    /// the proposal only once the proposal exists (`proposalCreated`).
    func reviewedRequest(language: SupportedAppLanguage) -> MealProposalRequest? {
        guard phase == .review, !isClosed,
              let request = review?.request(language: language)
        else {
            return nil
        }
        return request
    }

    /// The server created the proposal: its media stays there with it.
    func proposalCreated() {
        handedToProposal = true
    }

    func discardSheet() {
        isClosed = true
        sequence += 1
        dropPipeline(deletingAsset: !handedToProposal)
        if isAnalysing { phase = .idle }
    }

    nonisolated static func precheck(_ staged: StagedMedia) -> MealCaptureFailure? {
        guard staged.sizeBytes > 0 else { return .unreadableMedia }
        switch staged.kind {
        case .mealPhoto:
            guard staged.channel.isPhoto else { return .invalidInput }
            return staged.sizeBytes > MealMediaLimits.maximumPhotoBytes ? .fileTooLarge : nil
        case .planDocument, .signupBodyPhoto:
            // Plans and signup body photos use their dedicated flows, never a meal.
            return .invalidInput
        case .audioNote:
            guard staged.channel.isAudio else { return .invalidInput }
            guard let duration = staged.duration, duration > 0 else { return .unreadableMedia }
            if duration > MealMediaLimits.maximumAudioDuration { return .audioTooLong }
            return staged.sizeBytes > MealMediaLimits.maximumAudioBytes ? .fileTooLarge : nil
        }
    }

    private func run() async {
        guard let drafts, pipeline != nil else {
            fail(.captureUnavailable)
            return
        }
        sequence += 1
        let current = sequence
        do {
            if case let .media(staged) = pipeline?.input {
                try await send(staged, sequence: current)
            }
            try ensureCurrent(current)
            phase = .reading
            // Reading is repeated with a new key: a stored failure must not
            // be replayed to a patient who asked to try again.
            let request: MealDraftRequest
            switch pipeline?.input {
            case let .text(text): request = .text(text)
            case .media:
                guard let assetID = pipeline?.assetID else { throw MealCaptureFailure.unavailable }
                request = .media(assetID: assetID)
            case nil: throw CancellationError()
            }
            let draft = try await drafts.draft(try attempt(.mealDraft, payload: request))
            try ensureCurrent(current)
            guard !draft.items.isEmpty,
                  let channel,
                  let source = MealProposalSource(
                      channel: channel,
                      mediaAssetID: channel == .text ? nil : pipeline?.assetID
                  )
            else {
                throw MealCaptureFailure.nothingRecognized
            }
            review = MealDraftReview(
                draft: draft,
                source: source,
                mealType: TextMealDetector.statedMealType(in: statedText(for: request, draft: draft))
                    ?? TextMealDetector.suggestedMealType(at: timeProvider.now, calendar: calendar)
            )
            phase = .review
        } catch is CancellationError {
            if sequence == current, isWorking { phase = .idle }
        } catch {
            guard sequence == current else { return }
            fail(MealCaptureFailure(error))
        }
    }

    /// What the patient said or typed, where a meal named in it
    /// ("no almoço") outranks the hour of the day.
    private func statedText(for request: MealDraftRequest, draft: MealDraftSnapshot) -> String? {
        if case let .text(text) = request { return text }
        return draft.transcript
    }

    private func send(_ staged: StagedMedia, sequence current: Int) async throws {
        guard let media, let uploader else { throw MealCaptureFailure.captureUnavailable }

        if pipeline?.isCompleted != true {
            phase = .uploading
            if pipeline?.isUploaded != true {
                if pipeline?.createAttempt == nil {
                    pipeline?.createAttempt = try attempt(
                        .mediaCreate,
                        payload: staged.uploadRequest
                    )
                }
                guard let createAttempt = pipeline?.createAttempt else {
                    throw CancellationError()
                }
                // Asking again with the same key returns the same asset and a
                // fresh ticket while the upload is still pending.
                let created = try await media.create(createAttempt)
                // The identity is kept even when this run was dropped
                // meanwhile, so the drop can delete what was created.
                pipeline?.assetID = created.asset.id
                try ensureCurrent(current)
                switch created.asset.state {
                case .pendingUpload:
                    guard let ticket = created.upload else {
                        throw MealCaptureFailure.unavailable
                    }
                    try await uploader.upload(staged, with: ticket)
                    try ensureCurrent(current)
                case .uploaded, .processing, .processed:
                    break
                case .failed, .deleted, .unknown:
                    throw MealCaptureFailure.uploadRejected
                }
                pipeline?.isUploaded = true
            }
            guard let assetID = pipeline?.assetID else { throw MealCaptureFailure.unavailable }
            if pipeline?.completeAttempt == nil {
                pipeline?.completeAttempt = try attempt(
                    .mediaComplete,
                    payload: MediaAssetCommand(assetID: assetID)
                )
            }
            guard let completeAttempt = pipeline?.completeAttempt else {
                throw CancellationError()
            }
            _ = try await media.complete(completeAttempt)
            try ensureCurrent(current)
            pipeline?.isCompleted = true
            staging.remove(staged.fileURL)
        }

        guard let assetID = pipeline?.assetID else { throw MealCaptureFailure.unavailable }
        phase = .processing
        if pipeline?.isProcessed == true { return }
        if pipeline?.isProcessingRequested != true {
            if pipeline?.processAttempt == nil {
                pipeline?.processAttempt = try attempt(
                    .mediaProcess,
                    payload: MediaAssetCommand(assetID: assetID)
                )
            }
            guard let processAttempt = pipeline?.processAttempt else {
                throw CancellationError()
            }
            _ = try await media.requestProcessing(processAttempt)
            try ensureCurrent(current)
            pipeline?.isProcessingRequested = true
        }

        for poll in 0..<maximumPolls {
            if poll > 0 {
                try await clock.sleep(for: pollInterval)
                try ensureCurrent(current)
            }
            let asset = try await media.asset(id: assetID)
            try ensureCurrent(current)
            switch asset.state {
            case .processed:
                pipeline?.isProcessed = true
                return
            case let .failed(code):
                // A new request needs a new key, or the stored answer of the
                // failed one would come back.
                pipeline?.processAttempt = nil
                pipeline?.isProcessingRequested = false
                throw code == "audio_too_long"
                    ? MealCaptureFailure.audioTooLong : MealCaptureFailure.processingFailed
            case .deleted:
                throw MealCaptureFailure.unavailable
            case .pendingUpload, .uploaded, .processing, .unknown:
                continue
            }
        }
        throw MealCaptureFailure.processingTimedOut
    }

    private func attempt<Payload: Hashable & Sendable>(
        _ operation: MutationOperation,
        payload: Payload
    ) throws -> MutationAttempt<Payload> {
        do {
            return MutationAttempt(
                operation: operation,
                key: try keyProvider.nextKey(),
                payload: payload,
                createdAt: timeProvider.now
            )
        } catch {
            throw MealCaptureFailure.captureUnavailable
        }
    }

    private func ensureCurrent(_ current: Int) throws {
        guard sequence == current, !Task.isCancelled else { throw CancellationError() }
    }

    private func fail(_ failure: MealCaptureFailure) {
        review = nil
        phase = .failed(failure)
    }

    /// Drops the capture in hand: the staged file always, and the server's
    /// copy when no proposal depends on it.
    private func dropPipeline(deletingAsset: Bool) {
        let running = work
        work = nil
        running?.cancel()
        guard let dropped = pipeline else { return }
        pipeline = nil
        let staging = staging
        let media = media
        let deletion = deletingAsset
            ? try? attempt(.mediaDelete, payload: MediaAssetCommand(assetID: ""))
            : nil
        let knownAssetID = dropped.assetID
        let createAttempt = dropped.createAttempt
        Task {
            // Only after the work has stopped: the upload is no longer
            // travelling and the asset, if one was created, is known.
            await running?.value
            if case let .media(staged) = dropped.input {
                staging.remove(staged.fileURL)
            }
            guard let deletion, let media else { return }
            var assetID = knownAssetID
            if assetID == nil, let createAttempt {
                // The creation may have reached the server without its
                // answer reaching the app: the same request names the asset.
                assetID = try? await media.create(createAttempt).asset.id
            }
            guard let assetID else { return }
            let attempt = MutationAttempt(
                operation: deletion.operation,
                key: deletion.key,
                payload: MediaAssetCommand(assetID: assetID),
                createdAt: deletion.createdAt
            )
            for delay in [0, 2, 8] {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                if (try? await media.delete(attempt)) != nil { return }
            }
        }
        if case let .media(staged) = dropped.input, running == nil {
            staging.remove(staged.fileURL)
        }
    }
}
