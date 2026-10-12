#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup cleanup root ownership", .serialized)
struct SignupBodyPhotoCleanupCoordinatorOwnerTests {
    @Test("C05b obsolete root owner cannot commit despite a still-valid lease",
        arguments: [CleanupProcessorHold.read, .repair, .prepare, .acknowledge])
    func obsoleteRootOwnerHasNoLocalAuthority(hold: CleanupProcessorHold) async throws {
        let h = try await CleanupProcessorHarness(hold: hold)
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1])
        let owner = CleanupProcessorOwnerFlag()
        let model = SignupBodyPhotoCleanupCoordinator(scope: h.scope, isCurrentOwner: { owner.isCurrent })
        let task = Task { await model.run(eventID: UUID()); await h.gate.operationFinished() }
        let entered = await h.gate.entryOrOperationEnd()
        if !entered {
            await h.gate.release(); await task.value
            try #require(entered)
        }
        do {
            let expected = try await h.queue()
            let bytes = try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a))
            owner.isCurrent = false // Root changed, session generation intentionally did not.
            await h.gate.release(); await task.value
            let final = try await h.queue()
            #expect(final == expected)
            #expect(try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
            let snapshot = await h.peer.snapshot()
            if hold == .read { #expect(snapshot.repairs.isEmpty) }
            #expect(snapshot.acknowledgementResults.isEmpty)
            let count = await h.registry.activeCount
            #expect(count == 0)
        } catch {
            await h.gate.release(); await task.value
            throw error
        }
    }
}

@MainActor
private final class CleanupProcessorOwnerFlag {
    var isCurrent = true
}
#endif
