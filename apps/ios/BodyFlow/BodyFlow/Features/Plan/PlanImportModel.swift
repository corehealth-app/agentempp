import Foundation
import Observation

enum PlanImportPhase: Equatable, Sendable {
    case idle
    case uploading
    case starting
    /// The reading began; the review of this draft takes over from here.
    case started(draftID: String)
    case failed(PlanImportFailure)
}

enum PlanImportFailure: Hashable, Sendable {
    case capture(MealCaptureFailure)
    case draft(PlanDraftFailure)
}

/// Sends the photo or PDF of a plan and starts its reading. The document
/// becomes a draft for review — this model never produces a plan.
@MainActor
@Observable
final class PlanImportModel {
    private struct Pipeline {
        let staged: StagedMedia
        let domain: PlanDraftDomain
        var createAttempt: MutationAttempt<MediaUploadRequest>?
        var assetID: String?
        var isUploaded = false
        var completeAttempt: MutationAttempt<MediaAssetCommand>?
        var isCompleted = false
        var importAttempt: MutationAttempt<PlanImportRequest>?
    }

    private let capability: PlanDraftCapability
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding

    private var pipeline: Pipeline?
    private var sequence = 0
    /// The work in hand; cancelling drops it, and the server's copy is only
    /// deleted after it has stopped.
    private var work: Task<Void, Never>?

    private(set) var phase = PlanImportPhase.idle
    var domain = PlanDraftDomain.training

    init(
        capability: PlanDraftCapability,
        timeProvider: any TimeProviding,
        keyProvider: any IdempotencyKeyProviding
    ) {
        self.capability = capability
        self.timeProvider = timeProvider
        self.keyProvider = keyProvider
    }

    var isAvailable: Bool { capability.supportsImport }

    var isWorking: Bool { phase == .uploading || phase == .starting }

    var canRetry: Bool {
        guard pipeline != nil, case let .failed(failure) = phase else { return false }
        switch failure {
        case .capture(.offline), .capture(.unavailable), .capture(.uploadRejected),
             .draft(.offline), .draft(.unavailable):
            return true
        default:
            return false
        }
    }

    nonisolated static func precheck(_ staged: StagedMedia) -> MealCaptureFailure? {
        guard staged.kind == .planDocument else { return .invalidInput }
        guard staged.sizeBytes > 0 else { return .unreadableMedia }
        guard staged.sizeBytes <= MealMediaLimits.maximumPlanDocumentBytes else {
            return .fileTooLarge
        }
        return ["application/pdf", "image/jpeg"].contains(staged.mimeType)
            ? nil : .unsupportedFile
    }

    func submit(_ staged: StagedMedia) async {
        guard !isWorking else {
            capability.staging.remove(staged.fileURL)
            return
        }
        dropPipeline()
        guard isAvailable else {
            capability.staging.remove(staged.fileURL)
            phase = .failed(.capture(.captureUnavailable))
            return
        }
        if let failure = Self.precheck(staged) {
            capability.staging.remove(staged.fileURL)
            phase = .failed(.capture(failure))
            return
        }
        pipeline = Pipeline(staged: staged, domain: domain)
        await start()
    }

    private func start() async {
        let task = Task { await run() }
        work = task
        await task.value
        if work == task { work = nil }
    }

    func reportCaptureFailure(_ failure: MealCaptureFailure) {
        guard !isWorking else { return }
        dropPipeline()
        phase = .failed(.capture(failure))
    }

    func retry() async {
        guard canRetry else { return }
        await start()
    }

    func startOver() {
        sequence += 1
        dropPipeline()
        phase = .idle
    }

    /// The screen left the stack. Work under way goes on to its end (the
    /// draft then waits in the Plan tab); a capture that had failed is
    /// dropped.
    func screenClosed() {
        guard !isWorking else { return }
        dropPipeline()
    }

    private func run() async {
        guard let media = capability.media, let uploader = capability.uploader,
              let staged = pipeline?.staged, let domain = pipeline?.domain
        else {
            phase = .failed(.capture(.captureUnavailable))
            return
        }
        sequence += 1
        let current = sequence
        do {
            if pipeline?.isCompleted != true {
                phase = .uploading
                if pipeline?.isUploaded != true {
                    if pipeline?.createAttempt == nil {
                        pipeline?.createAttempt = try attempt(
                            .mediaCreate, payload: staged.uploadRequest
                        )
                    }
                    guard let createAttempt = pipeline?.createAttempt else {
                        throw CancellationError()
                    }
                    let created = try await media.create(createAttempt)
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
                guard let assetID = pipeline?.assetID else {
                    throw MealCaptureFailure.unavailable
                }
                if pipeline?.completeAttempt == nil {
                    pipeline?.completeAttempt = try attempt(
                        .mediaComplete, payload: MediaAssetCommand(assetID: assetID)
                    )
                }
                guard let completeAttempt = pipeline?.completeAttempt else {
                    throw CancellationError()
                }
                _ = try await media.complete(completeAttempt)
                try ensureCurrent(current)
                pipeline?.isCompleted = true
                capability.staging.remove(staged.fileURL)
            }

            guard let assetID = pipeline?.assetID else { throw MealCaptureFailure.unavailable }
            phase = .starting
            if pipeline?.importAttempt == nil {
                pipeline?.importAttempt = try attempt(
                    .planImport,
                    payload: PlanImportRequest(mediaAssetID: assetID, domain: domain)
                )
            }
            guard let importAttempt = pipeline?.importAttempt else { throw CancellationError() }
            let receipt = try await capability.drafts.startImport(importAttempt)
            try ensureCurrent(current)
            // The document now belongs to its draft; nothing is deleted here.
            pipeline = nil
            phase = .started(draftID: receipt.draftID)
        } catch is CancellationError {
            if sequence == current, isWorking { phase = .idle }
        } catch let failure as PlanDraftFailure {
            guard sequence == current else { return }
            phase = .failed(.draft(failure))
        } catch {
            guard sequence == current else { return }
            phase = .failed(.capture(MealCaptureFailure(error)))
        }
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

    /// Drops a document that never became a draft: the staged file and the
    /// server's copy.
    private func dropPipeline() {
        let running = work
        work = nil
        running?.cancel()
        guard let dropped = pipeline else { return }
        pipeline = nil
        let staging = capability.staging
        let media = capability.media
        // Once the import was asked, the draft may exist and needs its
        // document: nothing is deleted from here (the server refuses it too).
        let deletion = dropped.importAttempt == nil
            ? try? attempt(.mediaDelete, payload: MediaAssetCommand(assetID: ""))
            : nil
        Task {
            await running?.value
            staging.remove(dropped.staged.fileURL)
            guard let deletion, let media else { return }
            var assetID = dropped.assetID
            if assetID == nil, let createAttempt = dropped.createAttempt {
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
    }
}

extension MealMediaStager {
    /// A photo of a plan: normalized like every photo that leaves the phone.
    func stagePlanPhoto(_ data: Data, channel: MealSourceChannel) throws -> StagedMedia {
        let photo = try stagePhoto(data, channel: channel)
        return StagedMedia(
            fileURL: photo.fileURL,
            kind: .planDocument,
            mimeType: photo.mimeType,
            sizeBytes: photo.sizeBytes,
            duration: nil,
            channel: channel
        )
    }

    /// A PDF the patient picked: checked where it is, then copied.
    func stagePlanPDF(from source: URL) throws -> StagedMedia {
        guard source.pathExtension.lowercased() == "pdf" else {
            throw MealCaptureFailure.unsupportedFile
        }
        guard let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0
        else {
            throw MealCaptureFailure.unreadableMedia
        }
        guard size <= MealMediaLimits.maximumPlanDocumentBytes else {
            throw MealCaptureFailure.fileTooLarge
        }
        let copy = try staging.stageCopy(of: source, fileExtension: "pdf")
        guard let handle = try? FileHandle(forReadingFrom: copy),
              let header = try? handle.read(upToCount: 5),
              header == Data("%PDF-".utf8)
        else {
            staging.remove(copy)
            throw MealCaptureFailure.unsupportedFile
        }
        try? handle.close()
        return StagedMedia(
            fileURL: copy,
            kind: .planDocument,
            mimeType: "application/pdf",
            sizeBytes: size,
            duration: nil,
            channel: .gallery
        )
    }
}
