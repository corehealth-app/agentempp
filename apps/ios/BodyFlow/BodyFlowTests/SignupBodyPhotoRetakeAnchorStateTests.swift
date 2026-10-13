#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

/// Scripted provider GETs, not API/SDK/image/clinical evidence. The real
/// Parent/Core/Flow and existing validated harness scope consume every reply.
@MainActor
@Suite("Retake anchor GET gates and exits", .serialized)
struct SignupBodyPhotoRetakeAnchorStateTests {
    @Test("R04 same IDs preserve a proof; partial/new terminal GETs gate result and never auto-confirm",
          arguments: RetakeAnchorGETCase.allCases)
    func officialGETGate(_ script: RetakeAnchorGETCase) async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        do {
            await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
            try #require(h.model.confirmEstimate())
            let core = try #require(h.model.capture)
            let old = try #require(h.flow.draft.bodyPhotoConfirmation)
            let before = await h.peer.snapshot()
            try #require(old.value == 24 && h.model.beginRetake())
            await h.peer.setStateProjection { RetakeAnchorGETScript.project($0, script: script) }
            await h.model.load() // Explicit GET, not a retake side effect or UI tap.
            if script == .reading {
                try #require(await core.waitForPollingEvent())
                try #require(await h.clock.waitForRegistrations(1))
            }
            let state = try #require(core.state)
            let wantRoute: SignupBodyPhotoRoute
            switch script {
            case .sameIDs, .pending, .reading, .missingEstimate: wantRoute = .capture
            case .legacy, .unusable, .ready: wantRoute = .result
            }
            #expect(h.model.route == wantRoute)
            #expect(h.model.capture === core && core.isActive && core.hasAcceptedConsent)
            if script == .sameIDs {
                #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .photos)
                #expect(h.flow.draft.bodyPhotoConfirmation == old && old.matches(h.flow.draft))
                #expect(state.poses.first?.photo?.id == "00000000-0000-4000-8000-000000001001")
            } else {
                #expect(state.poses.first?.photo?.id == "00000000-0000-4000-8000-000000002001")
                #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyFatOrigin == nil)
                #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            }
            if script == .ready {
                #expect(h.model.confirmableEstimate?.value == Decimal(24))
                #expect(state.estimate?.readings?.map(\.bodyFatPercent) == [Decimal(18), Decimal(24), Decimal(30)])
            } else {
                #expect(h.model.confirmableEstimate == nil)
                #expect(!h.model.confirmEstimate())
            }
            let first = await h.peer.snapshot()
            #expect(first.calls == before.calls + [.state])
            #expect(await h.factory.snapshot() == [h.owner.userID])

            if wantRoute == .capture {
                await h.peer.setStateProjection { RetakeAnchorGETScript.project($0, script: .ready) }
                await h.model.load() // Recovery is another declared authoritative GET.
                await core.waitForStoppedPollingWork()
                #expect(h.model.route == .result && h.model.capture === core)
                #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyPhotoConfirmation == nil)
                #expect(h.model.confirmableEstimate?.value == Decimal(24))
                let recovered = await h.peer.snapshot()
                #expect(recovered.calls == before.calls + [.state, .state])
            }
            if script != .legacy && script != .unusable {
                #expect(h.model.confirmEstimate(), "Only this explicit real Parent action applies the new same-24 estimate")
                #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .photos)
                #expect(h.flow.draft.bodyPhotoConfirmation?.sourceIDs.front == "00000000-0000-4000-8000-000000002001")
                #expect(h.flow.draft.bodyPhotoConfirmation?.sourceIDs.side == old.sourceIDs.side)
                #expect(h.flow.draft.bodyPhotoConfirmation?.sourceIDs.back == old.sourceIDs.back)
                #expect(h.flow.draft.bodyPhotoConfirmation?.value == old.value)
                #expect(h.flow.draft.bodyPhotoConfirmation?.fingerprint != old.fingerprint)
            }
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await stop(h)
        } catch { try await stop(h); throw error }
    }

    @Test("R05 leaving retake clears its intention; reentry with unchanged IDs reaches the old official result",
          arguments: [SignupBodyFatChoice.typed, .skip])
    func leaveRetake(_ choice: SignupBodyFatChoice) async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        do {
            await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
            try #require(h.model.confirmEstimate())
            let core = try #require(h.model.capture), state = try #require(core.state)
            let before = await h.peer.snapshot()
            try #require(h.model.beginRetake())
            h.model.select(choice)
            #expect(h.model.route == nil)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            #expect(h.flow.draft.bodyFatPercent == (choice == .typed ? 24 : nil))
            h.model.select(.photos)
            try #require(h.model.route == .consent)
            await h.model.acceptConsent()
            #expect(h.model.route == .result && h.model.capture === core)
            #expect(core.state?.poses == state.poses)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            #expect(h.flow.draft.bodyFatPercent == (choice == .typed ? 24 : nil))
            let after = await h.peer.snapshot()
            #expect(after.count(.state) == before.count(.state))
            #expect(after.count(.consent) == before.count(.consent) + 1)
            #expect(after.count(.stage) == 0 && after.count(.create) == 0 && after.count(.put) == 0)
            #expect(after.count(.complete) == 0 && after.count(.delete) == 0 && after.count(.repair) == 0)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await stop(h)
        } catch { try await stop(h); throw error }
    }

    @Test("R06 invalidated retake denies entry and a held new-ID GET cannot publish or apply a late result")
    func invalidateRetakeDuringGET() async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        var loading: Task<Void, Never>?
        do {
            await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
            try #require(h.model.confirmEstimate())
            let core = try #require(h.model.capture), proof = h.flow.draft.bodyPhotoConfirmation
            let before = await h.peer.snapshot()
            try #require(h.model.beginRetake())
            await h.peer.setStateProjection { RetakeAnchorGETScript.project($0, script: .ready) }
            await h.peer.holdNextState()
            let work = Task { @MainActor in
                await h.model.load()
                await h.stateGate.operationFinished()
            }
            loading = work
            try #require(await h.stateGate.entryOrOperationEnd())
            h.model.invalidate()
            await h.stateGate.release(); await work.value
            #expect(!h.model.isActive && !core.isActive && core.state == nil)
            #expect(h.model.route == nil && h.model.confirmableEstimate == nil)
            #expect(!h.model.beginRetake() && !h.model.confirmEstimate())
            #expect(h.flow.draft.bodyPhotoConfirmation == proof && h.flow.draft.bodyFatPercent == 24)
            let after = await h.peer.snapshot()
            #expect(after.calls == before.calls + [.state])
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await stop(h)
        } catch {
            loading?.cancel(); await h.stateGate.release(); await loading?.value
            try await stop(h); throw error
        }
    }

    @Test("R07 DELETE admission clears retake; existing receipt/GET recovery cannot restore an old proof",
          arguments: [false, true])
    func deleteRetake(reloadFailure: Bool) async throws {
        let h = try await SignupDeleteCompositionHarness(
            recovery: reloadFailure ? .reload : nil, readingAfterDelete: true)
        let deletionGate = CaptureConsentGate(holds: true), reloadGate = CaptureConsentGate(holds: true)
        var deleting: Task<Void, Never>?
        do {
            try await h.prepare(); try #require(h.model.confirmEstimate())
            let old = try #require(h.model.capture), oldIDs = try #require(old.state?.estimate?.sourceIDs)
            let before = await h.photos.report()
            try #require(h.model.beginRetake())
            await h.photos.restoreOriginalReadIDs() // Existing counted DTO script, no Storage absence claim.
            await h.photos.holdDelete(deletionGate); await h.photos.holdReload(reloadGate)
            let work = h.begin(ending: [deletionGate, reloadGate]); deleting = work
            try #require(await deletionGate.entryOrOperationEnd())
            #expect(h.flow.hasPendingBodyPhotoDeletion && h.model.route == nil)
            #expect(h.model.confirmableEstimate == nil && !h.model.beginRetake())
            #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyPhotoConfirmation == nil)
            await deletionGate.release()
            try #require(await reloadGate.entryOrOperationEnd())
            #expect(h.model.deletion?.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
            #expect(h.model.deletion?.phase == .awaitingReload)
            await reloadGate.release(); await work.value
            let d1 = try #require(h.model.deletion)
            if reloadFailure {
                if case .failed = d1.phase {} else { Issue.record("The scripted first GET failure must remain visible") }
                #expect(h.flow.hasPendingBodyPhotoDeletion && h.model.route == nil)
                #expect(d1.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
                let failed = await h.photos.report()
                await h.model.retryDeletion()
                let retry = await h.photos.report()
                #expect(retry.attempts == failed.attempts && retry.postDeleteReads == failed.postDeleteReads + 1)
            }
            let adopted = try #require(h.model.capture)
            #expect(h.model.deletion === d1 && d1.phase == .ready && adopted !== old && !old.isActive)
            if !reloadFailure {
                try #require(await adopted.waitForPollingEvent())
                try #require(await h.clock.waitForRegistrations(1))
                await h.clock.advance(by: .milliseconds(1_500))
                try #require(await adopted.waitForPollingEvent(untilStopped: true))
            }
            #expect(!h.flow.hasPendingBodyPhotoDeletion && h.model.route == .result)
            #expect(adopted.state?.estimate?.sourceIDs == oldIDs,
                "Same old IDs in the existing replay script expose a forgotten retake anchor")
            #expect(adopted.state?.estimate?.bySex.masculine.bodyFatPercent == Decimal(24))
            #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyFatOrigin == nil)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            let final = await h.photos.report()
            #expect(final.attempts.count == 1 && final.postDeleteReads == 2 && final.repairs == 0)
            #expect(final.stateReads == before.stateReads + 2)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
            #expect(await h.cleanup.registry.activeCount == 0)
            try await h.drain(); h.removeFolder()
        } catch {
            await deletionGate.release(); await reloadGate.release(); await deleting?.value
            try await h.drain(); h.removeFolder(); throw error
        }
    }

    private func stop(_ h: PresentationHarness) async throws {
        h.model.invalidate()
        if let core = h.model.capture {
            await core.invalidateAndWaitForOwnedCaptureWork()
            try await core.waitForLocalCleanup()
        }
        try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        #expect(await h.cleanup.registry.activeCount == 0)
        h.clean()
    }
}

enum RetakeAnchorGETCase: String, CaseIterable, Equatable, Sendable {
    case sameIDs, pending, reading, missingEstimate, legacy, unusable, ready
}

/// Immutable public-state projection below Core. All provider calls still go
/// through PresentationPhotoPeer/base; no current model state is assigned.
private enum RetakeAnchorGETScript {
    nonisolated static func project(_ raw: SignupBodyPhotoState, script: RetakeAnchorGETCase) -> SignupBodyPhotoState {
        if script == .sameIDs { return raw }
        let front = "00000000-0000-4000-8000-000000002001"
        let poses = raw.poses.map { slot in
            guard slot.pose == .front, let photo = slot.photo else { return slot }
            let status: String
            switch script { case .pending: status = "pending_upload"; case .reading: status = "reading"; default: status = "read" }
            return SignupBodyPhotoSlot(pose: .front,
                photo: .init(id: front, status: status, createdAt: photo.createdAt))
        }
        let estimate: SignupBodyPhotoEstimate?
        if script == .missingEstimate { estimate = nil }
        else if let previous = raw.estimate {
            let unusable = SignupBodyPhotoEstimate.Decision(usable: false, bodyFatPercent: nil, reason: "synthetic-anchor-control")
            estimate = .init(isEstimate: previous.isEstimate,
                bySex: script == .unusable ? .init(masculine: unusable, feminine: unusable) : previous.bySex,
                sourceIDs: .init(front: front, side: "00000000-0000-4000-8000-000000001002", back: "00000000-0000-4000-8000-000000001003"),
                fingerprint: String(repeating: "b", count: 64), readings: script == .legacy ? nil : previous.readings)
        } else { estimate = nil }
        return .init(available: raw.available, unavailableReason: raw.unavailableReason,
            consent: raw.consent, minimumAge: raw.minimumAge, poses: poses,
            estimate: estimate, remainingUploads: raw.remainingUploads)
    }
}
#endif
