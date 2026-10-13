#if DEBUG
import Foundation
import SwiftUI
import XCTest
@testable import BodyFlow

@MainActor
final class SignupBodyPhotoCapturePendingRenderingTests: XCTestCase {
    func testActualParentProducerShowsPreparingAndSendingWithoutRenderWorkOrNumericProgress() async throws {
        let h = try await SignupPhotoPendingViewHarness()
        var producing: Task<Void, Never>?
        do {
            await h.prepare()
            let core = try XCTUnwrap(h.model.capture)
            XCTAssertEqual(h.model.route, .capture)
            XCTAssertTrue(core.isActive && core.hasAcceptedConsent)
            XCTAssertNil(core.state?.estimate)
            XCTAssertEqual(core.phase, .idle)
            let baseline = await h.base.peer.snapshot()
            XCTAssertEqual(baseline.count(.state), 1)
            XCTAssertEqual(baseline.mutationAndStageSteps, [.consent])

            // Four scripted fixture bytes. This is NOT JPEG/normalizer or SDK proof.
            let source = CaptureModelHarness.data
            XCTAssertEqual(source, Data([0xff, 0xd8, 0xff, 0xd9]))
            let probe = h.probe
            let task = Task {
                await h.model.producePhoto(pose: .front, channel: .gallery) { authorization in
                    try await authorization.validate()
                    await probe.loaded(source)
                    return source
                }
                for gate in h.gates { await gate.operationFinished() }
            }
            producing = task

            let stageEntered = await h.stageGate.entryOrOperationEnd()
            XCTAssertTrue(stageEntered, "Actual delegated stage must hold before measuring preparing")
            guard stageEntered else { throw SignupPhotoPendingFixtureError.missingStage }
            let deletion = try XCTUnwrap(h.model.deletion)
            XCTAssertTrue(deletion.captureModel === core)
            XCTAssertEqual(core.phase, .preparing)
            XCTAssertEqual(core.retainedInputBytes, source.count)
            let stagedResult = await h.probe.staged()
            let staged = try XCTUnwrap(stagedResult)
            XCTAssertEqual(staged.channel, .gallery)
            XCTAssertEqual(staged.kind, .signupBodyPhoto)
            XCTAssertEqual(staged.mimeType, "image/jpeg")
            XCTAssertEqual(staged.sizeBytes, source.count)
            XCTAssertEqual(try Data(contentsOf: staged.fileURL), source)
            let preparing = await h.base.peer.snapshot()
            XCTAssertEqual(preparing.mutationAndStageSteps, [.consent, .stage])
            assertStage(preparing, source: source)
            await assertPending(.preparing, trace: preparing, h: h, core: core, deletion: deletion)

            await h.stageGate.release()
            let createEntered = await h.createGate.entryOrOperationEnd()
            XCTAssertTrue(createEntered, "Actual delegated CREATE must hold before measuring sending")
            guard createEntered else { throw SignupPhotoPendingFixtureError.missingCreate }
            XCTAssertEqual(core.phase, .sending)
            XCTAssertEqual(core.retainedInputBytes, 0)
            let sendingAtCreate = await h.base.peer.snapshot()
            XCTAssertEqual(sendingAtCreate.mutationAndStageSteps, [.consent, .stage, .create])
            let originalCreate = try XCTUnwrap(sendingAtCreate.creates.first)
            XCTAssertEqual(originalCreate.payload.pose, .front)
            XCTAssertEqual(originalCreate.payload.mimeType, staged.mimeType)
            XCTAssertEqual(originalCreate.payload.sizeBytes, staged.sizeBytes)
            XCTAssertFalse(originalCreate.key.value.isEmpty)
            let createdResult = await h.probe.created()
            let created = try XCTUnwrap(createdResult)
            XCTAssertEqual(created.photo.pose, .front)
            XCTAssertEqual(created.photo.status, "pending_upload")
            XCTAssertNotNil(created.upload)
            await assertPending(.sending, trace: sendingAtCreate, h: h, core: core, deletion: deletion)

            await h.createGate.release()
            let putEntered = await h.putGate.entryOrOperationEnd()
            XCTAssertTrue(putEntered, "Actual delegated PUT must hold before measuring sending again")
            guard putEntered else { throw SignupPhotoPendingFixtureError.missingPUT }
            XCTAssertEqual(core.phase, .sending)
            let uploaded = await h.probe.uploaded()
            XCTAssertEqual(uploaded, staged, "PUT retains the exact staged source and channel")
            XCTAssertEqual(try Data(contentsOf: staged.fileURL), source)
            let sendingAtPUT = await h.base.peer.snapshot()
            XCTAssertEqual(sendingAtPUT.mutationAndStageSteps, [.consent, .stage, .create, .put])
            XCTAssertEqual(sendingAtPUT.creates, [originalCreate])
            await assertPending(.sending, trace: sendingAtPUT, h: h, core: core, deletion: deletion)

            await h.putGate.release()
            await task.value
            let final = await h.base.peer.snapshot()
            XCTAssertEqual(final.mutationAndStageSteps, [.consent, .stage, .create, .put, .complete])
            XCTAssertEqual(final.count(.state), baseline.count(.state) + 1,
                "Only the Core's authoritative GET after complete is permitted")
            XCTAssertEqual(final.creates, [originalCreate], "Render never replaces/replays the immutable CREATE")
            XCTAssertEqual(final.completes.count, 1)
            XCTAssertEqual(final.completes.first?.payload.assetID, created.photo.id)
            XCTAssertEqual(core.state?.poses.first { $0.pose == .front }?.photo?.status, "read")
            XCTAssertFalse(FileManager.default.fileExists(atPath: staged.fileURL.path))
            XCTAssertNil(deletion.producerFailure)
            let sources = await h.probe.sources()
            XCTAssertEqual(sources, [source])
            for language in SupportedAppLanguage.allCases {
                let nodes = SignUpRenderingProbe.nodes(
                    SignupBodyPhotoCaptureView(photos: h.model).environment(\.locale, language.formattingLocale),
                    width: 393, height: 3_000)
                XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.capture.pending" },
                    "Preparing/sending feedback must disappear after that real operation completes")
                try assertNoNumericProgress(nodes)
            }
            let afterFinalRender = await h.base.peer.snapshot()
            XCTAssertEqual(afterFinalRender.calls, final.calls)
            await assertRetained(h, core: core, deletion: deletion)
            try await h.model.waitForLocalCleanup()
            try await h.base.cleanup.lifecycle.validate(h.base.cleanup.lease)
            await h.stop(producing: producing)
        } catch {
            await h.stop(producing: producing)
            throw error
        }
    }

    private func assertPending(_ phase: SignupBodyPhotoCapturePhase, trace: CapturePeerSnapshot,
        h: SignupPhotoPendingViewHarness, core: SignupBodyPhotoCaptureModel,
        deletion: SignupBodyPhotoExplicitDeletionModel) async {
        XCTAssertEqual(core.phase, phase, "Known actual phase is a prerequisite for semantic UI assertions")
        XCTAssertEqual(trace.count(.state), 1, "Held stage/CREATE/PUT must not reach the final GET")
        for language in SupportedAppLanguage.allCases {
            let nodes = SignUpRenderingProbe.nodes(
                SignupBodyPhotoCaptureView(photos: h.model).environment(\.locale, language.formattingLocale),
                width: 393, height: 3_000)
            let matching = nodes.filter { $0.identifier == "onboarding.photos.capture.pending" }
            XCTAssertEqual(matching.count, 1, "Semantic RED: missing real preparing/sending feedback")
            if let pending = matching.first {
                let expected: String
                switch (phase, language) {
                case (.preparing, .portugueseBrazil): expected = "Preparando a foto…"
                case (.preparing, .englishUnitedStates): expected = "Preparing the photo…"
                case (.sending, .portugueseBrazil): expected = "Enviando a foto…"
                case (.sending, .englishUnitedStates): expected = "Sending the photo…"
                default: XCTFail("Unsupported pending fixture phase"); continue
                }
                XCTAssertEqual(pending.label, expected)
            }
            XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.capture.error" })
            do { try assertNoNumericProgress(nodes) } catch { XCTFail("Progress matcher failed: \(error)") }
        }
        let after = await h.base.peer.snapshot()
        XCTAssertEqual(after.calls, trace.calls, "Rendering the held phase must not issue GET, retry or mutation")
        XCTAssertEqual(core.phase, phase)
        let sources = await h.probe.sources()
        XCTAssertEqual(sources, [CaptureModelHarness.data])
        await assertRetained(h, core: core, deletion: deletion)
    }

    private func assertRetained(_ h: SignupPhotoPendingViewHarness, core: SignupBodyPhotoCaptureModel,
        deletion: SignupBodyPhotoExplicitDeletionModel) async {
        XCTAssertTrue(h.model.capture === core && h.model.deletion === deletion)
        XCTAssertTrue(deletion.captureModel === core)
        XCTAssertEqual(h.model.route, .capture)
        XCTAssertEqual(h.base.ownerBox.current, h.base.owner)
        XCTAssertEqual(h.base.flow.draft.bodyFatPercent, 23)
        XCTAssertEqual(h.base.flow.draft.bodyFatOrigin, .typed)
        XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation)
        let binds = await h.factory.snapshot(), unusedBinds = await h.base.factory.snapshot()
        XCTAssertEqual(binds, [h.base.owner.userID], "One retained decorated scope; no rebind on rendering")
        XCTAssertTrue(unusedBinds.isEmpty && h.base.model.capture == nil, "Base harness model/factory remains unbound")
    }

    private func assertStage(_ trace: CapturePeerSnapshot, source: Data) {
        XCTAssertEqual(trace.calls.filter { $0.step == .stage }, [.stage(source.count, .gallery)])
    }

    private func assertNoNumericProgress(_ nodes: [SignUpRenderingProbe.Node]) throws {
        let pattern = try NSRegularExpression(pattern: "\\b[0-9]+(?:[.,][0-9]+)?\\s*%")
        XCTAssertFalse(nodes.contains { node in
            pattern.firstMatch(in: node.label, range: NSRange(node.label.startIndex..., in: node.label)) != nil
        }, "Capture feedback has no fabricated numeric percentage")
    }
}

private enum SignupPhotoPendingFixtureError: Error { case missingStage, missingCreate, missingPUT }

private actor SignupPhotoPendingProbe {
    private var sourceValues: [Data] = []
    private var stagedValue: StagedMedia?
    private var createdValue: SignupBodyPhotoCreateReceipt?
    private var uploadedValue: StagedMedia?
    func loaded(_ data: Data) { sourceValues.append(data) }
    func stageReturned(_ value: StagedMedia) { stagedValue = value }
    func createReturned(_ value: SignupBodyPhotoCreateReceipt) { createdValue = value }
    func putReturned(_ value: StagedMedia) { uploadedValue = value }
    func sources() -> [Data] { sourceValues }
    func staged() -> StagedMedia? { stagedValue }
    func created() -> SignupBodyPhotoCreateReceipt? { createdValue }
    func uploaded() -> StagedMedia? { uploadedValue }
}

/// Delegate every public DTO/mutation to the same PresentationHarness peer.
/// The CREATE barrier follows the actual local peer operation, never a fake phase.
private struct SignupPhotoPendingPhotos: SignupBodyPhotosProviding {
    let base: PresentationPhotoPeer
    let gate: CaptureConsentGate
    let probe: SignupPhotoPendingProbe
    func state() async throws -> SignupBodyPhotoState { try await base.state() }
    func consent(_ a: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt { try await base.consent(a) }
    func create(_ a: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt {
        let receipt = try await base.create(a)
        await probe.createReturned(receipt)
        await gate.enter()
        return receipt
    }
    func complete(_ a: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await base.complete(a) }
    func delete(_ a: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.delete(a) }
    func repair(_ a: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.repair(a) }
}

private struct SignupPhotoPendingUploader: StorageUploading {
    let base: any StorageUploading
    let gate: CaptureConsentGate
    let probe: SignupPhotoPendingProbe
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        try await base.upload(media, with: ticket)
        await probe.putReturned(media)
        await gate.enter()
    }
}

@MainActor
private struct SignupPhotoPendingViewHarness {
    let base: PresentationHarness
    let factory: PresentationFactoryPeer
    let model: SignupBodyPhotoPresentationModel
    let stageGate: CaptureConsentGate, createGate: CaptureConsentGate, putGate: CaptureConsentGate
    let probe: SignupPhotoPendingProbe
    var gates: [CaptureConsentGate] { [stageGate, createGate, putGate] }

    init() async throws {
        let base = try await PresentationHarness(manual: 23, hasEstimate: false)
        let original = base.scope, probe = SignupPhotoPendingProbe()
        let stage = CaptureConsentGate(holds: true), create = CaptureConsentGate(holds: true), put = CaptureConsentGate(holds: true)
        let scope = SignupBodyPhotoCaptureScope(userID: original.userID,
            photos: SignupPhotoPendingPhotos(base: base.peer, gate: create, probe: probe),
            uploader: SignupPhotoPendingUploader(base: original.uploader, gate: put, probe: probe),
            staging: original.staging, camera: original.camera,
            validateSession: original.validateSession,
            stagePhoto: { data, channel in
                let file = try await original.stagePhoto(data, channel)
                await probe.stageReturned(file)
                await stage.enter()
                return file
            }, performWork: original.performWork,
            discardStaged: original.discardStaged, rememberUnboundCreate: original.rememberUnboundCreate)
        let factory = PresentationFactoryPeer(scope: scope)
        let box = base.ownerBox, clock = base.clock
        model = SignupBodyPhotoPresentationModel(flow: base.flow, ownerToken: base.owner,
            capability: factory.capability, timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "capture-pending-render"),
            pollingTiming: .init(elapsed: { await clock.elapsed() }, sleep: { try await clock.sleep($0) }),
            isCurrentOwner: { $0 == box.current })
        self.base = base; self.factory = factory; self.probe = probe
        stageGate = stage; createGate = create; putGate = put
    }
    func prepare() async { await model.load(); model.select(.photos); await model.acceptConsent() }
    func stop(producing: Task<Void, Never>?) async {
        for gate in gates { await gate.release() }
        await producing?.value
        model.invalidate()
        if let core = model.capture {
            await core.invalidateAndWaitForOwnedCaptureWork()
            do { try await core.waitForLocalCleanup() }
            catch { XCTFail("Fixture scoped local cleanup failed: \(error)") }
        }
        base.clean()
    }
}
#endif
