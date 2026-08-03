import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import BodyFlow

@Suite("Session cover cache")
struct SessionCoverCacheTests {
    @Test("cache admits the exact cost and count limits, then evicts before insertion")
    func enforcesExactFixedLimits() async throws {
        let cache = SessionCoverCache()

        for index in 0..<64 {
            try await cache.insert(
                Prompt14CacheFixture.image(width: 1, height: 1),
                for: Prompt14CacheFixture.key(publicationID: "publication-\(index)"),
                expiresAt: .distantFuture
            )
        }

        var snapshot = await cache.debugSnapshot()
        #expect(snapshot.count == 64)
        #expect(snapshot.countLimit == 64)
        #expect(snapshot.totalCostLimit == 33_554_432)

        let oldest = Prompt14CacheFixture.key(publicationID: "publication-0")
        let newest = Prompt14CacheFixture.key(publicationID: "publication-64")
        try await cache.insert(
            Prompt14CacheFixture.image(width: 1, height: 1),
            for: newest,
            expiresAt: .distantFuture
        )

        snapshot = await cache.debugSnapshot()
        #expect(snapshot.count == 64)
        #expect(snapshot.totalCost <= 33_554_432)
        #expect(!snapshot.keys.contains(oldest))
        #expect(snapshot.keys.last == newest)

        await cache.removeAll()
        let exactLimitImage = Prompt14CacheFixture.image(width: 4_096, height: 2_048)
        #expect(exactLimitImage.cgImage.bytesPerRow * exactLimitImage.cgImage.height == 33_554_432)
        try await cache.insert(
            exactLimitImage,
            for: oldest,
            expiresAt: .distantFuture
        )
        snapshot = await cache.debugSnapshot()
        #expect(snapshot.totalCost == 33_554_432)
        #expect(snapshot.keys == [oldest])

        try await cache.insert(
            Prompt14CacheFixture.image(width: 1, height: 1),
            for: newest,
            expiresAt: .distantFuture
        )
        snapshot = await cache.debugSnapshot()
        #expect(snapshot.totalCost <= 33_554_432)
        #expect(snapshot.keys == [newest])
    }

    @Test("cost arithmetic fails closed and an oversized entry preserves residents")
    func rejectsOverflowAndOversizedEntryWithoutMutation() async throws {
        #expect(throws: BodyFlowCapabilityError.contentCoverTooLarge) {
            try SessionCoverCache.checkedCost(bytesPerRow: Int.max, height: 2)
        }

        let cache = SessionCoverCache()
        let residentKey = Prompt14CacheFixture.key(publicationID: "resident")
        try await cache.insert(
            Prompt14CacheFixture.image(width: 2, height: 2),
            for: residentKey,
            expiresAt: .distantFuture
        )
        let before = await cache.debugSnapshot()

        await #expect(throws: BodyFlowCapabilityError.contentCoverTooLarge) {
            try await cache.insert(
                Prompt14CacheFixture.image(width: 4_096, height: 2_049),
                for: Prompt14CacheFixture.key(publicationID: "oversized"),
                expiresAt: .distantFuture
            )
        }

        let after = await cache.debugSnapshot()
        #expect(after == before)
        #expect(await cache.image(for: residentKey, now: .distantPast) != nil)
    }

    @Test("cache promotes hits and evicts the deterministic least-recent key")
    func promotesHitsBeforeLRUEviction() async throws {
        let cache = SessionCoverCache()
        let largeImage = Prompt14CacheFixture.image(width: 2_048, height: 2_048)
        let keys = ["a", "b", "c"].map {
            Prompt14CacheFixture.key(publicationID: $0)
        }

        try await cache.insert(largeImage, for: keys[0], expiresAt: .distantFuture)
        try await cache.insert(largeImage, for: keys[1], expiresAt: .distantFuture)
        #expect(await cache.image(for: keys[0], now: .distantPast) != nil)
        try await cache.insert(largeImage, for: keys[2], expiresAt: .distantFuture)

        let snapshot = await cache.debugSnapshot()
        #expect(snapshot.keys == [keys[0], keys[2]])
        #expect(await cache.image(for: keys[1], now: .distantPast) == nil)
    }

    @Test("cache key separates publication, version, width, and height")
    func separatesEveryKeyDimension() async throws {
        let cache = SessionCoverCache()
        let image = Prompt14CacheFixture.image(width: 2, height: 2)
        let inserted = Prompt14CacheFixture.key(
            publicationID: "publication-a",
            version: 4,
            width: 240,
            height: 160
        )
        try await cache.insert(image, for: inserted, expiresAt: .distantFuture)

        #expect(await cache.image(for: inserted, now: .distantPast) != nil)
        for differentKey in [
            Prompt14CacheFixture.key(publicationID: "publication-b", version: 4, width: 240, height: 160),
            Prompt14CacheFixture.key(publicationID: "publication-a", version: 5, width: 240, height: 160),
            Prompt14CacheFixture.key(publicationID: "publication-a", version: 4, width: 241, height: 160),
            Prompt14CacheFixture.key(publicationID: "publication-a", version: 4, width: 240, height: 161),
        ] {
            #expect(await cache.image(for: differentKey, now: .distantPast) == nil)
        }
    }

    @Test("expiry is inclusive and removes the stale entry")
    func expiresAtTheExactDeadline() async throws {
        let cache = SessionCoverCache()
        let key = Prompt14CacheFixture.key(publicationID: "expiring")
        let deadline = Date(timeIntervalSince1970: 2_000_000_000)
        try await cache.insert(
            Prompt14CacheFixture.image(width: 2, height: 2),
            for: key,
            expiresAt: deadline
        )

        #expect(await cache.image(for: key, now: deadline.addingTimeInterval(-0.001)) != nil)
        #expect(await cache.image(for: key, now: deadline) == nil)
        #expect(await cache.debugSnapshot().count == 0)
    }

    @Test("targeted version removal preserves unrelated entries")
    func removesAllTargetsForOnlyTheSelectedVersion() async throws {
        let cache = SessionCoverCache()
        let selectedTargets = [
            Prompt14CacheFixture.key(publicationID: "publication", version: 4, width: 240, height: 160),
            Prompt14CacheFixture.key(publicationID: "publication", version: 4, width: 480, height: 320),
        ]
        let preserved = [
            Prompt14CacheFixture.key(publicationID: "publication", version: 5),
            Prompt14CacheFixture.key(publicationID: "other", version: 4),
        ]
        for key in selectedTargets + preserved {
            try await cache.insert(
                Prompt14CacheFixture.image(width: 2, height: 2),
                for: key,
                expiresAt: .distantFuture
            )
        }

        await cache.remove(publicationID: "publication", version: 4)

        for key in selectedTargets {
            #expect(await cache.image(for: key, now: .distantPast) == nil)
        }
        for key in preserved {
            #expect(await cache.image(for: key, now: .distantPast) != nil)
        }
    }

    @Test("memory warning and repeated clear empty ledger and object cache")
    func clearsOnMemoryWarningIdempotently() async throws {
        let center = NotificationCenter()
        let notificationName = Notification.Name("Prompt14SessionCoverCacheMemoryWarning")
        let cache = SessionCoverCache(
            memoryWarningCenter: center,
            memoryWarningName: notificationName
        )
        let key = Prompt14CacheFixture.key(publicationID: "publication")
        try await cache.insert(
            Prompt14CacheFixture.image(width: 2, height: 2),
            for: key,
            expiresAt: .distantFuture
        )

        let revision = await cache.memoryWarningRevisionForTesting()
        center.post(
            name: notificationName,
            object: nil
        )
        await cache.waitUntilMemoryWarningHandled(after: revision)
        #expect(await cache.debugSnapshot().count == 0)

        await cache.handleMemoryWarning()

        #expect(await cache.debugSnapshot().count == 0)
        #expect(await cache.image(for: key, now: .distantPast) == nil)
    }
}

enum Prompt14CacheFixture {
    static func key(
        publicationID: String,
        version: Int = 4,
        width: Int = 240,
        height: Int = 160
    ) -> ContentCoverCacheKey {
        ContentCoverCacheKey(
            publicationID: publicationID,
            version: version,
            target: ContentCoverTargetSize(widthPixels: width, heightPixels: height)
        )
    }

    static func image(width: Int, height: Int) -> ContentCoverImage {
        let bytesPerRow = width * 4
        let bytes = Data(repeating: 0x7F, count: bytesPerRow * height)
        let provider = CGDataProvider(data: bytes as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return ContentCoverImage(cgImage: image)
    }
}
