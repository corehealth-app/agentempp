#if DEBUG
import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

/// Local synthetic scope only. These are model-contract tests, not UI/JWT proof.
@MainActor
@Suite("Signup photo DEBUG fixture actual Parent/Core flow", .serialized)
struct SignupBodyPhotoCaptureFixtureFlowTests {
    @Test("Consent and three actual synthetic producer captures are required before the 18/24/30 result")
    func resultRequiresThreeParentCapturesAndExplicitConfirmation() async throws {
        let h = try await PresentationHarness()
        defer { h.clean() }
        let directory = h.cleanup.folder.appendingPathComponent("b9-fixture")
        let fixture = SignupBodyPhotoCaptureFixture(mode: .demo, buildFlavor: .debug,
            directory: directory, allowedOwnerID: h.owner.userID, document: Self.document)
        let model = SignupBodyPhotoPresentationModel(flow: h.flow, ownerToken: h.owner,
            capability: fixture.capability, timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "b9-full-fixture"),
            isCurrentOwner: { $0 == h.ownerBox.current })
        defer { model.invalidate() }
        await model.load()
        #expect(model.capture?.state?.poses.allSatisfy { $0.photo == nil } == true)
        #expect(model.capture?.state?.estimate == nil)
        #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyPhotoConfirmation == nil)
        model.select(.photos)
        #expect(model.route == .consent && model.camera == nil)
        await model.acceptConsent()
        #expect(model.route == .capture && model.camera?.origin == .synthetic)
        for (index, pose) in SignupBodyPhotoPose.allCases.enumerated() {
            await model.producePhoto(pose: pose, channel: .camera) { authorization in
                try await authorization.validate()
                let bytes = DemoMealCamera.samplePhoto() // real JPEG; not a raw marker stub
                try await authorization.validate()
                return bytes
            }
            #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyFatOrigin == nil)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            let report = await fixture.report()
            #expect(report.creates == index + 1 && report.uploads == index + 1)
            #expect(report.completes == index + 1 && report.rememberedCreates == index + 1)
            if index < 2 {
                #expect(model.route == .capture && model.capture?.state?.estimate == nil)
                #expect(model.confirmableEstimate == nil && !model.confirmEstimate())
            }
        }
        let state = try #require(model.capture?.state)
        #expect(model.route == .result)
        #expect(state.estimate?.readings?.map(\.pose) == SignupBodyPhotoPose.allCases)
        #expect(state.estimate?.readings?.map(\.bodyFatPercent) == [Decimal(18), Decimal(24), Decimal(30)])
        #expect(model.currentEstimateDecision?.bodyFatPercent == 24)
        #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(model.confirmEstimate())
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .photos)
        let proof = try #require(h.flow.draft.bodyPhotoConfirmation)
        #expect(proof == OnboardingBodyPhotoConfirmation.candidate(from: state, sex: .masculine))
        #expect(proof.matches(h.flow.draft) && !h.flow.requiresBodyPhotoRevalidation)
        try await model.waitForLocalCleanup()
        let report = await fixture.report()
        #expect(report.consents == 1 && report.creates == 3 && report.uploads == 3 && report.completes == 3)
        #expect(report.deletes == 0)
    }

    @Test("A wrong synthetic owner cannot obtain a scope; Release/non-demo never supplies state",
          arguments: [AppBuildFlavor.debug, .release])
    func configurationAndOwnerBoundaries(flavor: AppBuildFlavor) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("b9-disabled-" + UUID().uuidString)
        let fixture = SignupBodyPhotoCaptureFixture(mode: .demo, buildFlavor: flavor,
            directory: directory, allowedOwnerID: DemoUser.id, document: Self.document)
        await #expect(throws: (any Error).self) { try await fixture.capability.scoped("different-synthetic-owner") }
        if flavor == .release {
            await #expect(throws: SignupBodyPhotoFailure.unavailable) { try await fixture.state() }
        }
        let real = SignupBodyPhotoCaptureFixture(mode: .releaseUnavailable, buildFlavor: .debug,
            directory: directory, allowedOwnerID: DemoUser.id, document: Self.document)
        await #expect(throws: SignupBodyPhotoFailure.unavailable) { try await real.state() }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Local receipts require stable idempotency and the exact owned staged JPEG before complete")
    func localReceiptPipelineCannotSkipOrForgeUpload() async throws {
        let h = try await PresentationHarness()
        defer { h.clean() }
        let fixture = SignupBodyPhotoCaptureFixture(mode: .demo, buildFlavor: .debug,
            directory: h.cleanup.folder.appendingPathComponent("b9-receipts"),
            allowedOwnerID: h.owner.userID, document: Self.document)
        let scope = try await fixture.capability.scoped(h.owner.userID)
        let keys = DeterministicIdempotencyKeyProvider(prefix: "b9-receipt")
        let now = PresentationHarness.now
        let consent = MutationAttempt(operation: .mediaCreate, key: try keys.nextKey(),
            payload: SignupBodyPhotoConsentRequest(version: Self.document.version,
                bodyHash: Self.document.bodyHash, birthDate: "1990-01-02"), createdAt: now)
        _ = try await scope.photos.consent(consent)
        let media = try await scope.stagePhoto(DemoMealCamera.samplePhoto(), .camera)
        let create = MutationAttempt(operation: .mediaCreate, key: try keys.nextKey(),
            payload: SignupBodyPhotoCreateRequest(pose: .front, mimeType: media.mimeType,
                sizeBytes: media.sizeBytes), createdAt: now)
        let first = try await scope.photos.create(create)
        let replay = try await scope.photos.create(create)
        #expect(first.photo.id == replay.photo.id && replay.replayed)
        let changed = MutationAttempt(operation: create.operation, key: create.key,
            payload: SignupBodyPhotoCreateRequest(pose: .side, mimeType: media.mimeType,
                sizeBytes: media.sizeBytes), createdAt: create.createdAt)
        await #expect(throws: SignupBodyPhotoFailure.invalidInput) { try await scope.photos.create(changed) }
        let complete = MutationAttempt(operation: .mediaComplete, key: try keys.nextKey(),
            payload: MediaAssetCommand(assetID: first.photo.id), createdAt: now)
        await #expect(throws: SignupBodyPhotoFailure.uploadNotPending) { try await scope.photos.complete(complete) }
        let ticket = try #require(first.upload)
        let unowned = StagedMedia(fileURL: h.cleanup.folder.appendingPathComponent("not-owned.jpg"),
            kind: media.kind, mimeType: media.mimeType, sizeBytes: media.sizeBytes,
            duration: nil, channel: .camera)
        await #expect(throws: SignupBodyPhotoFailure.invalidInput) { try await scope.uploader.upload(unowned, with: ticket) }
        try await scope.uploader.upload(media, with: ticket)
        let uploaded = try await scope.photos.state()
        #expect(uploaded.poses.first?.photo?.status == "uploaded" && uploaded.estimate == nil)
        _ = try await scope.photos.complete(complete)
        let repeated = try await scope.photos.complete(complete)
        #expect(repeated.photo.id == first.photo.id && repeated.photo.status == "read")
        let currentReplay = try await scope.photos.create(create)
        #expect(currentReplay.photo.status == "read" && currentReplay.upload == nil)
        try await scope.discardStaged(media.fileURL)
        #expect(!FileManager.default.fileExists(atPath: media.fileURL.path))
        let state = try await scope.photos.state()
        #expect(state.estimate == nil, "One actual completed capture must not fabricate the three-photo result")
        let report = await fixture.report()
        #expect(report.creates == 1 && report.uploads == 1 && report.completes == 1)
    }

    private static var document: SignupBodyPhotoConsent {
        let body = "LOCAL SYNTHETIC TEST DOCUMENT; not a legal publication."
        let digest = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(documentKey: "body_photo_estimate_consent", version: "b9-test-v1",
            locale: "pt-BR", body: body, bodyHash: digest, acceptedAt: nil)
    }
}
#endif
