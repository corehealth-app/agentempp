#if DEBUG
import Foundation
import Observation
import Testing
@testable import BodyFlow

/// Synchronous one-shot Observation receipt. No actor hop can confuse a late
/// callback with readiness publication, and it owns no model/task/provider.
private final class SignupDeletionReadinessObservationReceipt: @unchecked Sendable {
    private let lock = NSLock()
    private var changes = 0
    func recordChange() {
        lock.lock()
        changes += 1
        lock.unlock()
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return changes
    }
}

@MainActor
@Suite("Signup photo deletion readiness observation", .serialized)
struct SignupBodyPhotoDeletionReadinessObservationTests {
    @Test("RO01 retained receipt reload completion invalidates the retry getter exactly once")
    func failedReloadPublishesRetryReadinessAfterParentTaskEnds() async throws {
        let h = try await SignupDeleteCompositionHarness(recovery: .reload)
        defer { h.removeFolder() }
        let heldRead = CaptureConsentGate(holds: true)
        var deleting: Task<Void, Never>?
        do {
            try await h.prepare()
            await h.photos.holdReload(heldRead)
            let work = h.begin(ending: [heldRead])
            deleting = work
            let entered = await heldRead.entryOrOperationEnd()
            try #require(entered, "Must hold the actual GET after a known DELETE receipt")
            let d1 = try #require(h.model.deletion)
            #expect(d1.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
            #expect(d1.phase == .awaitingReload)
            #expect(h.flow.hasPendingBodyPhotoDeletion)
            let before = await h.photos.report()
            #expect(before.attempts.count == 1 && before.postDeleteReads == 1)
            let receipt = SignupDeletionReadinessObservationReceipt()
            // Observe ONLY the UI getter while parent deletionTask is installed.
            // Its early false guard must not need a separate D1.phase observer.
            let heldReadiness = withObservationTracking {
                h.model.canRetryPhotoDeletion
            } onChange: {
                receipt.recordChange()
            }
            #expect(!heldReadiness)
            #expect(receipt.count == 0)
            await heldRead.release()
            await work.value
            #expect(h.model.deletion === d1)
            #expect(d1.phase == .failed(.offline))
            #expect(d1.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
            #expect(h.model.canRetryPhotoDeletion)
            #expect(receipt.count == 1,
                "BodyData must receive getter invalidation when its retained parent task clears")
            #expect(h.flow.hasPendingBodyPhotoDeletion)
            #expect(h.model.route == nil)
            let after = await h.photos.report()
            #expect(after.attempts == before.attempts && after.stateReads == before.stateReads)
            #expect(after.postDeleteReads == before.postDeleteReads && after.repairs == 0)
            #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            try await h.drain()
        } catch {
            await heldRead.release()
            deleting?.cancel()
            if let deleting { await deleting.value }
            try await h.drain()
            throw error
        }
    }
}
#endif
