import CoreGraphics
import Foundation
import Testing

@testable import BodyFlow

@Suite("Content cover loader")
struct ContentCoverLoaderTests {
    private let origin = try! ContentCoverTrustedOrigin(
        validating: URL(string: "https://mobile.bodyflow.test")!
    )
    private let target = ContentCoverTargetSize(widthPixels: 240, heightPixels: 160)
    private let baseDate = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("nil origin fails unavailable without constructing or streaming a request")
    func unavailableOriginPerformsNoTransport() async {
        let stream = CoverLoaderStreamSpy()
        let loader = ContentCoverLoader(
            stream: stream,
            origin: nil,
            decoder: ContentCoverDecoder(),
            cache: SessionCoverCache(),
            timeProvider: LockedCoverTimeProvider(now: baseDate)
        )

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(url: "not-even-a-path"),
                target: target
            )
        }
        #expect(await stream.streamCallCount == 0)
        #expect(await stream.cancelAllCallCount == 0)
    }

    @Test("invalid cover capability never crosses the stream boundary")
    func invalidPathPerformsNoTransport() async {
        let stream = CoverLoaderStreamSpy()
        let loader = makeLoader(stream: stream)

        await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(url: "https://external.example/cover"),
                target: target
            )
        }
        #expect(await stream.streamCallCount == 0)
    }

    @Test("an invalid capability is rejected even when the matching image is cached")
    func warmCacheCannotBypassPathValidation() async throws {
        let stream = CoverLoaderStreamSpy()
        let cache = SessionCoverCache()
        let loader = makeLoader(stream: stream, cache: cache)
        try await cache.insert(
            Prompt14CacheFixture.image(width: 2, height: 2),
            for: Prompt14CacheFixture.key(publicationID: "publication", version: 4),
            expiresAt: .distantFuture
        )

        await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(url: "https://external.example/cover"),
                target: target
            )
        }
        #expect(await stream.streamCallCount == 0)
    }

    @Test("cache expiry uses the earlier capability deadline")
    func capabilityExpiryWins() async throws {
        let clock = LockedCoverTimeProvider(now: baseDate)
        let stream = CoverLoaderStreamSpy(maxAgeSeconds: 600)
        let loader = makeLoader(stream: stream, clock: clock)
        let expiringCover = cover(expiresAt: baseDate.addingTimeInterval(60))

        _ = try await loader.image(
            publicationID: "publication",
            version: 4,
            cover: expiringCover,
            target: target
        )
        clock.setNow(baseDate.addingTimeInterval(59))
        _ = try await loader.image(
            publicationID: "publication",
            version: 4,
            cover: expiringCover,
            target: target
        )
        #expect(await stream.streamCallCount == 1)

        clock.setNow(baseDate.addingTimeInterval(60))
        await #expect(throws: BodyFlowCapabilityError.contentCoverNotFound) {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: expiringCover,
                target: target
            )
        }
        #expect(await stream.streamCallCount == 1)
    }

    @Test("cache expiry uses the earlier response max-age deadline")
    func headerExpiryWins() async throws {
        let clock = LockedCoverTimeProvider(now: baseDate)
        let stream = CoverLoaderStreamSpy(maxAgeSeconds: 30)
        let loader = makeLoader(stream: stream, clock: clock)
        let longCapability = cover(expiresAt: baseDate.addingTimeInterval(600))

        _ = try await loader.image(
            publicationID: "publication",
            version: 4,
            cover: longCapability,
            target: target
        )
        clock.setNow(baseDate.addingTimeInterval(29))
        _ = try await loader.image(
            publicationID: "publication",
            version: 4,
            cover: longCapability,
            target: target
        )
        #expect(await stream.streamCallCount == 1)

        clock.setNow(baseDate.addingTimeInterval(30))
        _ = try await loader.image(
            publicationID: "publication",
            version: 4,
            cover: longCapability,
            target: target
        )
        #expect(await stream.streamCallCount == 2)
    }

    @Test("capability expiry suppresses publication even without a cache header")
    func capabilityExpiryAppliesWithoutCacheHeader() async {
        let stream = CoverLoaderStreamSpy(maxAgeSeconds: nil)
        let loader = makeLoader(stream: stream)

        await #expect(throws: BodyFlowCapabilityError.contentCoverNotFound) {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(expiresAt: baseDate),
                target: target
            )
        }
        #expect(await stream.streamCallCount == 0)
        #expect(await stream.bodyCancelCount == 0)
    }

    @Test("zero max-age expires at receipt and cannot publish")
    func zeroMaxAgeSuppressesPublication() async {
        let stream = CoverLoaderStreamSpy(maxAgeSeconds: 0)
        let loader = makeLoader(stream: stream)

        await #expect(throws: BodyFlowCapabilityError.contentCoverNotFound) {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(),
                target: target
            )
        }
        #expect(await stream.streamCallCount == 1)
        #expect(await stream.bodyCancelCount == 1)
    }

    @Test("concurrent callers for one key share exactly one stream and publication")
    func coalescesConcurrentLoads() async throws {
        let stream = CoverLoaderStreamSpy(startsSuspended: true)
        let cache = SessionCoverCache()
        let loader = makeLoader(stream: stream, cache: cache)
        let cover = cover()

        let first = Task {
            try await loader.image(
                publicationID: "publication", version: 4, cover: cover, target: target
            )
        }
        await stream.waitUntilStarted()
        let second = Task {
            try await loader.image(
                publicationID: "publication", version: 4, cover: cover, target: target
            )
        }
        await loader.waitUntilWaiterCount(
            2,
            publicationID: "publication",
            version: 4,
            target: target
        )
        await stream.release()

        let firstImage = try await first.value
        let secondImage = try await second.value
        #expect(firstImage.cgImage.width == secondImage.cgImage.width)
        #expect(await stream.streamCallCount == 1)
        let snapshot = await cache.debugSnapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot.insertionCount == 1)
    }

    @Test("each coalesced caller keeps its own capability deadline")
    func coalescedCallerCannotOutliveItsCapability() async throws {
        let clock = LockedCoverTimeProvider(now: baseDate)
        let stream = CoverLoaderStreamSpy(startsSuspended: true)
        let loader = makeLoader(stream: stream, clock: clock)
        let longCapability = cover(expiresAt: baseDate.addingTimeInterval(600))
        let shortCapability = cover(expiresAt: baseDate.addingTimeInterval(10))

        let longLivedCaller = Task {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: longCapability,
                target: target
            )
        }
        await stream.waitUntilStarted()
        let expiredCaller = Task {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: shortCapability,
                target: target
            )
        }
        await loader.waitUntilWaiterCount(
            2,
            publicationID: "publication",
            version: 4,
            target: target
        )
        clock.setNow(baseDate.addingTimeInterval(11))
        await stream.release()

        _ = try await longLivedCaller.value
        await #expect(throws: BodyFlowCapabilityError.contentCoverNotFound) {
            try await expiredCaller.value
        }
        #expect(await stream.streamCallCount == 1)
    }

    @Test("one cancelled caller does not cancel a shared load needed by another")
    func cancellationIsScopedToOneCaller() async throws {
        let stream = CoverLoaderStreamSpy(startsSuspended: true)
        let loader = makeLoader(stream: stream)
        let cover = cover()

        let cancelledCaller = Task {
            try await loader.image(
                publicationID: "publication", version: 4, cover: cover, target: target
            )
        }
        await stream.waitUntilStarted()
        let successfulCaller = Task {
            try await loader.image(
                publicationID: "publication", version: 4, cover: cover, target: target
            )
        }
        await loader.waitUntilWaiterCount(
            2,
            publicationID: "publication",
            version: 4,
            target: target
        )
        cancelledCaller.cancel()
        await stream.release()

        await #expect(throws: CancellationError.self) {
            try await cancelledCaller.value
        }
        _ = try await successfulCaller.value
        #expect(await stream.streamCallCount == 1)
        #expect(await stream.bodyCancelCount == 0)
    }

    @Test("a sole cancelled caller cannot publish after a late stream release")
    func lastCallerCancellationSuppressesLatePublication() async {
        let stream = CoverLoaderStreamSpy(startsSuspended: true)
        let cache = SessionCoverCache()
        let loader = makeLoader(stream: stream, cache: cache)
        let task = Task {
            try await loader.image(
                publicationID: "publication", version: 4, cover: cover(), target: target
            )
        }

        await stream.waitUntilStarted()
        task.cancel()
        await stream.waitUntilBodyCancelled()
        await stream.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await cache.debugSnapshot().count == 0)
    }

    @Test("a sole caller cancelled during cache insertion leaves no published image")
    func cancellationDuringInsertionRemovesOwnedPublication() async {
        let stream = CoverLoaderStreamSpy()
        let cache = SuspendedInsertionCoverCache()
        let loader = makeLoader(stream: stream, cache: cache)
        let load = Task {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(),
                target: target
            )
        }

        await cache.waitUntilInsertionStarted()
        load.cancel()
        await cache.releaseInsertion()

        await #expect(throws: CancellationError.self) {
            try await load.value
        }
        #expect(await cache.count == 0)
    }

    @Test("a 404 removes every cached target for only that publication version")
    func notFoundRemovesAffectedVersion() async throws {
        let stream = CoverLoaderStreamSpy(statusCodes: [404])
        let cache = SessionCoverCache()
        let loader = makeLoader(stream: stream, cache: cache)
        let affected = [
            Prompt14CacheFixture.key(publicationID: "publication", version: 4, width: 120, height: 80),
            Prompt14CacheFixture.key(publicationID: "publication", version: 4, width: 480, height: 320),
        ]
        let preserved = Prompt14CacheFixture.key(publicationID: "publication", version: 5)
        for key in affected + [preserved] {
            try await cache.insert(
                Prompt14CacheFixture.image(width: 2, height: 2),
                for: key,
                expiresAt: .distantFuture
            )
        }

        await #expect(throws: BodyFlowCapabilityError.contentCoverNotFound) {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(),
                target: target
            )
        }

        for key in affected {
            #expect(await cache.image(for: key, now: .distantPast) == nil)
        }
        #expect(await cache.image(for: preserved, now: .distantPast) != nil)
    }

    @Test("version removal cancels its flight and prevents late repopulation")
    func versionRemovalCancelsLatePublication() async {
        let stream = CoverLoaderStreamSpy(startsSuspended: true)
        let cache = SessionCoverCache()
        let loader = makeLoader(stream: stream, cache: cache)
        let task = Task {
            try await loader.image(
                publicationID: "publication", version: 4, cover: cover(), target: target
            )
        }

        await stream.waitUntilStarted()
        await loader.remove(publicationID: "publication", version: 4)
        await stream.waitUntilBodyCancelled()
        await stream.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await cache.debugSnapshot().count == 0)
    }

    @Test("version invalidation remains a barrier after key retirement")
    func versionInvalidationCannotBeCrossedByRetiringKey() async throws {
        let stream = CoverLoaderStreamSpy()
        let cache = InvalidationBarrierCoverCache()
        let loader = makeLoader(stream: stream, cache: cache)
        let first = Task {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(),
                target: target
            )
        }

        await cache.waitUntilFirstInsertionStarted()
        first.cancel()
        await loader.waitUntilKeyRetirementRegistered(
            publicationID: "publication",
            version: 4,
            target: target
        )
        let replacement = Task {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(),
                target: target
            )
        }
        let removal = Task {
            await loader.remove(publicationID: "publication", version: 4)
        }
        await cache.waitUntilVersionRemovalStarted()
        await cache.releaseFirstInsertion()
        await loader.waitUntilVersionInvalidationBarrierObserved(
            publicationID: "publication",
            version: 4
        )

        #expect(await stream.streamCallCount == 1)
        await cache.releaseVersionRemoval()
        await removal.value
        await stream.waitUntilStarts(count: 2)

        await #expect(throws: CancellationError.self) {
            try await first.value
        }
        _ = try await replacement.value
        #expect(await cache.count == 1)
    }

    @Test("session end cancels all work, clears state, and blocks late or subsequent publication")
    func endSessionCancelsAndClosesLoader() async {
        let stream = CoverLoaderStreamSpy(startsSuspended: true)
        let cache = SessionCoverCache()
        let loader = makeLoader(stream: stream, cache: cache)
        let first = Task {
            try await loader.image(
                publicationID: "publication-a", version: 4, cover: cover(), target: target
            )
        }
        let second = Task {
            try await loader.image(
                publicationID: "publication-b", version: 4, cover: cover(), target: target
            )
        }

        await stream.waitUntilStarts(count: 2)
        await loader.endSession()
        await stream.release()

        for task in [first, second] {
            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
        #expect(await stream.cancelAllCallCount == 1)
        #expect(await cache.debugSnapshot().count == 0)

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await loader.image(
                publicationID: "publication-c", version: 4, cover: cover(), target: target
            )
        }
        #expect(await stream.streamCallCount == 2)

        await loader.endSession()
        #expect(await stream.cancelAllCallCount == 1)
    }

    @Test("session end waits for a cancelled publication before its final clear")
    func endSessionClearsAnInsertionThatCompletesLate() async {
        let stream = CoverLoaderStreamSpy()
        let cache = SuspendedInsertionCoverCache()
        let loader = makeLoader(stream: stream, cache: cache)
        let load = Task {
            try await loader.image(
                publicationID: "publication",
                version: 4,
                cover: cover(),
                target: target
            )
        }

        await cache.waitUntilInsertionStarted()
        let ending = Task {
            await loader.endSession()
        }
        await stream.waitUntilCancelAll()
        await cache.releaseInsertion()
        await ending.value

        await #expect(throws: CancellationError.self) {
            try await load.value
        }
        #expect(await cache.count == 0)
        #expect(await cache.removeAllCallCount == 1)
    }

    private func makeLoader(
        stream: CoverLoaderStreamSpy,
        cache: any SessionCoverCaching = SessionCoverCache(),
        clock: LockedCoverTimeProvider? = nil
    ) -> ContentCoverLoader {
        ContentCoverLoader(
            stream: stream,
            origin: origin,
            decoder: ContentCoverDecoder(),
            cache: cache,
            timeProvider: clock ?? LockedCoverTimeProvider(now: baseDate)
        )
    }

    private func cover(
        url: String = "/api/mobile/v1/content/covers/AbC_123-xyz",
        expiresAt: Date? = nil
    ) -> PublishedContentCover {
        PublishedContentCover(
            url: url,
            expiresAt: APITimestamp(value: expiresAt ?? baseDate.addingTimeInterval(600))
        )
    }
}

final class LockedCoverTimeProvider: @unchecked Sendable, TimeProviding {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        value = now
    }

    var now: Date {
        lock.withLock { value }
    }

    func setNow(_ value: Date) {
        lock.withLock {
            self.value = value
        }
    }
}

actor CoverLoaderStreamSpy: ContentCoverByteStreaming {
    private let maxAgeSeconds: Int?
    private var statusCodes: [Int]
    private let startsSuspended: Bool
    private var releaseContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var startedContinuations: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var bodyCancelledContinuations: [CheckedContinuation<Void, Never>] = []
    private var cancelAllContinuations: [CheckedContinuation<Void, Never>] = []
    private var deliveredStreamIDs: Set<Int> = []
    private var cancelledStreamIDs: Set<Int> = []
    private var bodyStartCount = 0
    private var released = false
    private(set) var streamCallCount = 0
    private(set) var cancelAllCallCount = 0
    private(set) var bodyCancelCount = 0

    init(
        maxAgeSeconds: Int? = 300,
        statusCodes: [Int] = [],
        startsSuspended: Bool = false
    ) {
        self.maxAgeSeconds = maxAgeSeconds
        self.statusCodes = statusCodes
        self.startsSuspended = startsSuspended
    }

    func stream(_ request: ContentCoverTransportRequest) async throws -> ContentCoverByteStream {
        streamCallCount += 1
        let streamID = streamCallCount
        let statusCode = statusCodes.isEmpty ? 200 : statusCodes.removeFirst()
        let owner = self
        return ContentCoverByteStream(
            statusCode: statusCode,
            declaredLength: Int64(Prompt14CoverFixtures.png.count),
            mimeType: "image/png",
            cacheMaxAgeSeconds: maxAgeSeconds,
            redirectLocation: nil,
            chunks: AsyncThrowingStream(unfolding: {
                await owner.nextChunk(for: streamID)
            }),
            cancel: {
                await owner.recordBodyCancellation(for: streamID)
            }
        )
    }

    func cancelAll() {
        cancelAllCallCount += 1
        let cancelAllContinuations = cancelAllContinuations
        self.cancelAllContinuations.removeAll()
        for continuation in cancelAllContinuations {
            continuation.resume()
        }
        let streamIDs = Array(releaseContinuations.keys)
        for streamID in streamIDs {
            recordBodyCancellation(for: streamID)
        }
    }

    func waitUntilStarted() async {
        await waitUntilStarts(count: 1)
    }

    func waitUntilStarts(count: Int) async {
        guard bodyStartCount < count else { return }
        await withCheckedContinuation { continuation in
            startedContinuations.append((count, continuation))
        }
    }

    func waitUntilBodyCancelled() async {
        guard bodyCancelCount == 0 else { return }
        await withCheckedContinuation { continuation in
            bodyCancelledContinuations.append(continuation)
        }
    }

    func waitUntilCancelAll() async {
        guard cancelAllCallCount == 0 else { return }
        await withCheckedContinuation { continuation in
            cancelAllContinuations.append(continuation)
        }
    }

    func release() {
        released = true
        let continuations = Array(releaseContinuations.values)
        releaseContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func nextChunk(for streamID: Int) async -> Data? {
        guard !deliveredStreamIDs.contains(streamID),
              !cancelledStreamIDs.contains(streamID)
        else {
            return nil
        }
        bodyStartCount += 1
        resumeStartedWaiters()
        if startsSuspended, !released {
            await withCheckedContinuation { continuation in
                releaseContinuations[streamID] = continuation
            }
        }
        guard !cancelledStreamIDs.contains(streamID) else {
            return nil
        }
        deliveredStreamIDs.insert(streamID)
        return Prompt14CoverFixtures.png
    }

    private func recordBodyCancellation(for streamID: Int) {
        guard cancelledStreamIDs.insert(streamID).inserted else { return }
        bodyCancelCount += 1
        releaseContinuations.removeValue(forKey: streamID)?.resume()
        let continuations = bodyCancelledContinuations
        bodyCancelledContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func resumeStartedWaiters() {
        let ready = startedContinuations.filter { bodyStartCount >= $0.count }
        startedContinuations.removeAll { bodyStartCount >= $0.count }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}

actor SuspendedInsertionCoverCache: SessionCoverCaching {
    private var insertionStartedContinuations: [CheckedContinuation<Void, Never>] = []
    private var insertionContinuation: CheckedContinuation<Void, Never>?
    private var insertionStarted = false
    private var storedOwnership: UUID?
    private(set) var count = 0
    private(set) var removeAllCallCount = 0

    func image(
        for key: ContentCoverCacheKey,
        now: Date
    ) -> ContentCoverImage? {
        nil
    }

    func insert(
        _ image: ContentCoverImage,
        for key: ContentCoverCacheKey,
        expiresAt: Date,
        ownership: UUID?
    ) async throws {
        insertionStarted = true
        let waiters = insertionStartedContinuations
        insertionStartedContinuations.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            insertionContinuation = continuation
        }
        storedOwnership = ownership
        count += 1
    }

    func remove(
        _ key: ContentCoverCacheKey,
        ifOwnedBy ownership: UUID
    ) {
        guard storedOwnership == ownership else { return }
        storedOwnership = nil
        count = 0
    }

    func remove(publicationID: String, version: Int) {
        storedOwnership = nil
        count = 0
    }

    func removeAll() {
        removeAllCallCount += 1
        storedOwnership = nil
        count = 0
    }

    func waitUntilInsertionStarted() async {
        guard !insertionStarted else { return }
        await withCheckedContinuation { continuation in
            insertionStartedContinuations.append(continuation)
        }
    }

    func releaseInsertion() {
        insertionContinuation?.resume()
        insertionContinuation = nil
    }
}

actor InvalidationBarrierCoverCache: SessionCoverCaching {
    private var firstInsertionStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstInsertionContinuation: CheckedContinuation<Void, Never>?
    private var versionRemovalStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var versionRemovalContinuation: CheckedContinuation<Void, Never>?
    private var insertionCount = 0
    private var ownership: UUID?
    private(set) var count = 0

    func image(
        for key: ContentCoverCacheKey,
        now: Date
    ) -> ContentCoverImage? {
        nil
    }

    func insert(
        _ image: ContentCoverImage,
        for key: ContentCoverCacheKey,
        expiresAt: Date,
        ownership: UUID?
    ) async throws {
        insertionCount += 1
        if insertionCount == 1 {
            let waiters = firstInsertionStartedWaiters
            firstInsertionStartedWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                firstInsertionContinuation = continuation
            }
        }
        self.ownership = ownership
        count = 1
    }

    func remove(
        _ key: ContentCoverCacheKey,
        ifOwnedBy ownership: UUID
    ) {
        guard self.ownership == ownership else { return }
        self.ownership = nil
        count = 0
    }

    func remove(publicationID: String, version: Int) async {
        let waiters = versionRemovalStartedWaiters
        versionRemovalStartedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            versionRemovalContinuation = continuation
        }
        ownership = nil
        count = 0
    }

    func removeAll() {
        ownership = nil
        count = 0
    }

    func waitUntilFirstInsertionStarted() async {
        guard insertionCount == 0 else { return }
        await withCheckedContinuation { continuation in
            firstInsertionStartedWaiters.append(continuation)
        }
    }

    func releaseFirstInsertion() {
        firstInsertionContinuation?.resume()
        firstInsertionContinuation = nil
    }

    func waitUntilVersionRemovalStarted() async {
        guard versionRemovalContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            versionRemovalStartedWaiters.append(continuation)
        }
    }

    func releaseVersionRemoval() {
        versionRemovalContinuation?.resume()
        versionRemovalContinuation = nil
    }
}
