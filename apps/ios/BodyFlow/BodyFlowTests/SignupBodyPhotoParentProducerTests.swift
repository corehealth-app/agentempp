#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup photo parent producer authority and retained D1", .serialized)
struct SignupBodyPhotoParentProducerTests {
    @Test("PP01 gallery/permission authorization is obsolete after mode reentry or full owner restore",
        arguments: SignupParentProducerExit.allCases)
    func postAwaitAuthorizationKeepsOriginalModeAndOwner(_ exit: SignupParentProducerExit) async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let core = try #require(h.model.capture)
        try #require(core.hasAcceptedConsent && h.model.choice == .photos)
        #expect(h.model.camera?.origin == MealCameraAccess.Origin.none)
        let gate = CaptureConsentGate(holds: true), probe = SignupParentProducerProbe()
        let source = CaptureModelHarness.data
        let producing = Task {
            await h.model.producePhoto(pose: .side, channel: exit.channel) { authorization in
                try await authorization.validate()
                await probe.began()
                await gate.enter() // permission/gallery callback deliberately ignores cancellation
                // The capability must reject its captured owner/mode even from
                // a noncancelled continuation, not only Task.isCancelled.
                let authorized = await Task.detached {
                    do { try await authorization.validate(); return true }
                    catch { return false }
                }.value
                await probe.postAwait(authorized: authorized, permissionResult: exit.isPermission)
                return authorized ? source : nil
            }
            await gate.operationFinished()
        }
        let entered = await gate.entryOrOperationEnd()
        if !entered {
            await gate.release(); await producing.value
            try #require(entered, "Forwarding must enter the actual loader before exit")
        }
        do {
            switch exit {
            case .galleryModeReentry, .permissionModeReentry:
                h.model.select(.typed)
                h.model.select(.photos)
                await h.model.acceptConsent()
                try #require(core.hasAcceptedConsent && h.model.choice == .photos,
                    "Reaccept must restore current eligibility; stale auth still stays obsolete")
                #expect(h.model.camera?.origin == MealCameraAccess.Origin.none)
            case .permissionOwnerRestore:
                h.ownerBox.current = .init(userID: h.owner.userID, restoreGeneration: 2)
                #expect(h.model.camera == nil)
            }
            await gate.release(); await producing.value
            let report = await probe.report(), trace = await h.peer.snapshot()
            #expect(report.loads == 1 && report.authorizedBefore == 1)
            #expect(report.authorizedAfter == 0 && report.rejectedAfter == 1)
            #expect(report.permissionPresentations == 0,
                "A late granted permission cannot authorize the old UI to show its camera")
            #expect(trace.count(.stage) == 0 && trace.count(.create) == 0 && trace.count(.put) == 0)
            #expect(trace.count(.complete) == 0 && trace.count(.delete) == 0 && trace.count(.repair) == 0)
            #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil && source == CaptureModelHarness.data)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await h.model.waitForLocalCleanup()
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        } catch {
            await gate.release(); await producing.value
            throw error
        }
    }

    @Test("PP02 parent registers loader in D1 before await; actual D0 precedes its return and DELETE")
    func deletionRetainsHeldSourceAndRunsRealD0() async throws {
        let h = try await SignupDeleteCompositionHarness(holdPUT: true)
        let probe = SignupParentProducerProbe(), discard = CaptureConsentGate()
        let photos = SignupParentProducerPhotos(base: h.photos, probe: probe)
        let original = h.scope
        // Preserve the real lease, registry, staging and actual URL discard.
        // Only an event AFTER successful real discard signals D0 in this test.
        let scope = SignupBodyPhotoCaptureScope(userID: original.userID, photos: photos,
            uploader: original.uploader, staging: original.staging, camera: original.camera,
            validateSession: original.validateSession, stagePhoto: original.stagePhoto,
            performWork: original.performWork,
            discardStaged: { url in
                try await original.discardStaged(url)
                await probe.discarded(url)
                await discard.enter()
            }, rememberUnboundCreate: original.rememberUnboundCreate)
        let factory = PresentationFactoryPeer(scope: scope)
        let model = SignupDeleteCompositionHarness.makeModel(flow: h.flow, owner: h.owner,
            box: h.ownerBox, factory: factory, clock: h.clock, prefix: "parent-producer-delete")
        defer { model.invalidate(); h.removeFolder() }
        await model.load(); model.select(.photos); await model.acceptConsent()
        let core = try #require(model.capture)
        try #require(core.hasAcceptedConsent)
        let controlBytes = Data("producer-control-do-not-purge".utf8)
        let control = try h.staging.stage(controlBytes, fileExtension: "jpg")
        let sending = Task {
            await core.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
            await h.putGate.operationFinished()
        }
        let putEntered = await h.putGate.entryOrOperationEnd()
        if !putEntered {
            await h.putGate.release(); await sending.value
            try #require(putEntered, "Existing Core PUT must hold a real own file")
        }
        let loader = CaptureConsentGate(holds: true), cancellation = SignupParentProducerCancellationBox()
        let producing = Task {
            await model.producePhoto(pose: .side, channel: .gallery) { authorization in
                try await withTaskCancellationHandler {
                    try await authorization.validate()
                    await probe.began()
                    await loader.enter()
                    let authorized = await Task.detached {
                        do { try await authorization.validate(); return true }
                        catch { return false }
                    }.value
                    await probe.postAwait(authorized: authorized, permissionResult: false)
                    await probe.sourceReturning()
                    return nil
                } onCancel: { cancellation.cancel() }
            }
            await loader.operationFinished()
        }
        let entered = await loader.entryOrOperationEnd()
        if !entered {
            await loader.release(); await producing.value
            await h.putGate.release(); await sending.value
            try #require(entered, "Producer forwarding must enter before DELETE")
        }
        var deleting: Task<Void, Never>?
        do {
            let controller = try #require(model.deletion,
                "The loader must already be retained by the existing D1 before its await")
            try #require(controller.captureModel === core)
            let work = Task { await model.deletePhotos(); await discard.operationFinished() }
            deleting = work
            let discarded = await discard.entryOrOperationEnd()
            try #require(discarded, "Signal comes from real scoped own-file removal, not cancellation")
            #expect(!core.isActive && core.state == nil && model.deletion === controller)
            #expect(cancellation.isCancelled && controller.phase == .draining)
            let beforeReturn = await probe.report(), held = await h.photos.report()
            #expect(!beforeReturn.sourceReturning && held.attempts.isEmpty)
            let removed = try #require(beforeReturn.discarded.first)
            #expect(!FileManager.default.fileExists(atPath: removed.path))
            #expect(try Data(contentsOf: control) == controlBytes)
            // Complete the old noncooperative PUT, leaving only the loader
            // retained. It still cannot authorize bytes or UI after deletion.
            await h.putGate.release(); await sending.value
            await loader.release(); await producing.value
            await work.value
            let final = await probe.report(), sent = await h.photos.report()
            #expect(final.sourceReturning && final.deleteReturnOrdering == [true])
            #expect(final.rejectedAfter == 1 && final.authorizedAfter == 0)
            #expect(sent.attempts.count == 1 && sent.attempts.first?.operation == .mediaDelete)
            #expect(sent.attempts.first?.payload == SignupBodyPhotoDeleteCommand())
            #expect(sent.repairs == 0 && controller.phase == .ready)
            let baseTrace = await h.base.snapshot()
            #expect(baseTrace.count(.stage) == 1 && baseTrace.count(.create) == 1)
            #expect(baseTrace.count(.put) == 1 && baseTrace.count(.complete) == 0,
                "Only the already-held Core operation staged; the loader never staged")
            #expect(try Data(contentsOf: control) == controlBytes)
            #expect(await factory.snapshot() == [h.owner.userID])
            #expect(await h.factory.snapshot().isEmpty,
                "The undecorated harness model/factory were never loaded")
            try await model.waitForLocalCleanup()
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        } catch {
            await h.putGate.release(); await sending.value
            await loader.release(); await producing.value
            if let deleting { await deleting.value }
            throw error
        }
    }

    @Test("PP03 one valid staged-byte input forwards once; nil returns without stage",
        arguments: [false, true])
    func inputAndNilForwardExactlyOnce(returnNil: Bool) async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let core = try #require(h.model.capture)
        try #require(core.hasAcceptedConsent)
        #expect(h.model.camera?.origin == MealCameraAccess.Origin.none)
        let probe = SignupParentProducerProbe(), input = CaptureModelHarness.data
        await h.model.producePhoto(pose: .back, channel: .gallery) { authorization in
            try await authorization.validate()
            await probe.began()
            try await authorization.validate()
            return returnNil ? nil : input
        }
        let report = await probe.report(), trace = await h.peer.snapshot()
        #expect(report.loads == 1 && report.authorizedBefore == 1)
        let expected = returnNil ? 0 : 1
        #expect(trace.count(.stage) == expected && trace.count(.create) == expected)
        #expect(trace.count(.put) == expected && trace.count(.complete) == expected)
        #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
        if !returnNil {
            let request = try #require(trace.creates.first)
            #expect(request.payload.pose == .back && request.payload.sizeBytes == input.count)
            let staged = trace.calls.compactMap { call -> Int? in
                if case let .stage(count, channel) = call, channel == .gallery { return count }
                return nil
            }
            #expect(staged == [input.count])
        }
        #expect(input == CaptureModelHarness.data)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        h.ownerBox.current = .init(userID: h.owner.userID, restoreGeneration: 2)
        #expect(h.model.camera == nil)
        h.model.invalidate()
        try await h.model.waitForLocalCleanup()
    }
}
#endif
