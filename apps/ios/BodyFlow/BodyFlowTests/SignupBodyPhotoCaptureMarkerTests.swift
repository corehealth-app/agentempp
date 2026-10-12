#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup capture durable marker causal contracts", .serialized)
struct SignupBodyPhotoCaptureMarkerTests {
    @Test("C07a CREATE waits for a durable unbound marker")
    func markerBeforeCreate() async throws {
        let h = try await CaptureMarkerHarness(hold: .beforeWrite)
        defer { h.clean() }
        await h.accept()
        let task = Task { await h.capture(); await h.marker.barrier.operationFinished() }
        let entered = await h.marker.barrier.entryOrOperationEnd()
        let before = await h.server.snapshot()
        #expect(entered)
        #expect(before.count(.create) == 0 && before.count(.put) == 0 && before.count(.complete) == 0)
        await h.marker.barrier.release(); await task.value
        let queue = try await h.state.queue()
        let requested = await h.marker.requested
        let observed = await h.photos.markersBeforeCreate
        #expect(requested.count == 1)
        #expect(queue.unboundCreates == requested)
        #expect(observed == [requested])
        let final = await h.server.snapshot()
        #expect(final.count(.create) == 1 && final.count(.put) == 1 && final.count(.complete) == 1)
        #expect(final.count(.delete) == 0 && final.count(.repair) == 0)
        #expect(h.model.phase == .ready)
    }

    @Test("C07b failed atomic marker persistence prevents every dispatch")
    func failedPersistencePreventsDispatch() async throws {
        let h = try await CaptureMarkerHarness()
        defer { h.clean() }
        try await h.state.seed(generations: [CleanupProcessorHarness.g2])
        let bytes = try Data(contentsOf: h.state.store.fileURL(for: CleanupProcessorHarness.a))
        await h.accept()
        h.state.writeFault.arm()
        await h.capture()
        let trace = await h.server.snapshot()
        #expect(trace.count(.stage) == 1)
        #expect(trace.count(.create) == 0 && trace.count(.put) == 0 && trace.count(.complete) == 0)
        #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
        #expect(h.model.phase == .failed(.unavailable))
        #expect(try Data(contentsOf: h.state.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
        let requested = await h.marker.requested
        #expect(requested.count == 1)
        let queue = try await h.state.queue()
        #expect(queue.unboundCreates.isEmpty)
        #expect(queue.scope(CleanupProcessorHarness.g2) != nil)
    }

    @Test("C07c response-lost CREATE retry keeps its original UUID/key/payload/date")
    func retryRetainsMarkerAndAttempt() async throws {
        let h = try await CaptureMarkerHarness(failOnceAt: .create)
        defer { h.clean() }
        await h.accept()
        await h.capture()
        #expect(h.model.phase == .failed(.offline))
        await h.model.retry(pose: .front)
        let requested = await h.marker.requested
        try #require(requested.count == 2)
        #expect(requested[0] == requested[1])
        let queue = try await h.state.queue()
        #expect(queue.unboundCreates == [requested[0]])
        let trace = await h.server.snapshot()
        try #require(trace.creates.count == 2)
        #expect(trace.creates[0] == trace.creates[1])
        #expect(trace.count(.stage) == 1 && trace.count(.put) == 1 && trace.count(.complete) == 1)
        let observed = await h.photos.markersBeforeCreate
        #expect(observed == [[requested[0]], [requested[0]]])
        #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
    }

    @Test("C07d a retake retains both unbound operations after decline/local cleanup")
    func retakeKeepsOldMarker() async throws {
        let h = try await CaptureMarkerHarness(readingFailsOnce: true)
        defer { h.clean() }
        await h.accept()
        await h.capture()
        #expect(h.model.phase == .failed(.readingFailed))
        await h.capture()
        let requested = await h.marker.requested
        try #require(requested.count == 2)
        #expect(requested[0] != requested[1])
        let before = try await h.state.queue()
        #expect(before.unboundCreates == requested)
        let observed = await h.photos.markersBeforeCreate
        #expect(observed == [[requested[0]], requested])
        h.model.declineConsent()
        try await h.model.waitForLocalCleanup()
        let after = try await h.state.queue()
        #expect(after.unboundCreates == requested)
        let trace = await h.server.snapshot()
        try #require(trace.creates.count == 2)
        #expect(trace.creates[0].key != trace.creates[1].key)
        #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
    }

    @Test("C07e a switch during marker persistence prevents old CREATE",
        arguments: [CaptureMarkerHold.beforeWrite, .afterWrite], [false, true])
    func switchBeforeCreate(hold: CaptureMarkerHold, returnToA: Bool) async throws {
        let h = try await CaptureMarkerHarness(hold: hold)
        defer { h.clean() }
        await h.accept()
        let task = Task { await h.capture(); await h.marker.barrier.operationFinished() }
        let entered = await h.marker.barrier.entryOrOperationEnd()
        if !entered {
            await h.marker.barrier.release(); await task.value
            try #require(entered)
        }
        do {
            try await h.state.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.b))
            if returnToA { try await h.state.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.a)) }
            let later = returnToA ? CleanupProcessorHarness.a : CleanupProcessorHarness.b
            let bytes = try await h.state.seedLaterOwner(later)
            await h.marker.barrier.release(); await task.value
            let trace = await h.server.snapshot()
            #expect(trace.count(.create) == 0 && trace.count(.put) == 0 && trace.count(.complete) == 0)
            #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
            #expect(try Data(contentsOf: h.state.store.fileURL(for: later)) == bytes)
        } catch {
            await h.marker.barrier.release(); await task.value
            throw error
        }
    }

    @Test("C07f the live scope's marker uses its retained lease and supplied protected store")
    func liveMarkerFactoryCannotRenewAnOldScope() async throws {
        let h = try await CaptureMarkerHarness()
        defer { h.clean() }
        let transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://mobile.example.test"),
            sessionLifecycle: h.state.lifecycle, session: URLSession(configuration: .ephemeral), clock: ContinuousClock())
        let factory = SignupBodyPhotoCaptureCapability.live(transport: transport,
            lifecycle: h.state.lifecycle, uploader: h.server, staging: h.staging, camera: .unavailable,
            cleanupStore: h.state.store)
        let scope = try await factory.scoped(CleanupProcessorHarness.a)
        let marker = UUID()
        try await scope.rememberUnboundCreate(marker)
        let queue = try await h.state.queue()
        #expect(queue.unboundCreates == [marker])
        try await h.state.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.b))
        try await h.state.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.a))
        let bytes = try await h.state.seedLaterOwner(CleanupProcessorHarness.a)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) {
            try await scope.rememberUnboundCreate(UUID())
        }
        #expect(try Data(contentsOf: h.state.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
        let trace = await h.server.snapshot()
        #expect(trace.count(.create) == 0 && trace.count(.delete) == 0 && trace.count(.repair) == 0)
    }

    @Test("C07g an old constructor has no implicit marker authority")
    func constructorMarkerDefaultFailsClosed() async throws {
        let h = try await CaptureMarkerHarness()
        defer { h.clean() }
        let lifecycle = h.state.lifecycle, lease = h.state.lease, staging = h.staging
        let scope = SignupBodyPhotoCaptureScope(userID: lease.userID, photos: h.photos, uploader: h.server,
            staging: staging, camera: .unavailable,
            validateSession: { try await lifecycle.validate(lease) },
            stagePhoto: { _, _ in throw SignupBodyPhotoFailure.unavailable },
            performWork: { try await SignupSessionBoundWork(lifecycle: lifecycle, lease: lease).run($0) },
            discardStaged: { url in
                try await lifecycle.performPatientStateOperation(lease: lease) { staging.remove(url) }
            })
        await #expect(throws: SignupBodyPhotoFailure.unavailable) { try await scope.rememberUnboundCreate(UUID()) }
        let queue = try await h.state.queue()
        #expect(queue.unboundCreates.isEmpty)
    }
}
#endif
