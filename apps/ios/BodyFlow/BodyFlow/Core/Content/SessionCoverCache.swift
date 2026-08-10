import CoreGraphics
import Foundation
import UIKit

protocol SessionCoverCaching: Sendable {
    func image(
        for key: ContentCoverCacheKey,
        now: Date
    ) async -> ContentCoverImage?

    func insert(
        _ image: ContentCoverImage,
        for key: ContentCoverCacheKey,
        expiresAt: Date,
        ownership: UUID?
    ) async throws

    func remove(
        _ key: ContentCoverCacheKey,
        ifOwnedBy ownership: UUID
    ) async

    func remove(publicationID: String, version: Int) async
    func removeAll() async
}

struct ContentCoverCacheKey: Equatable, Hashable, Sendable {
    let publicationID: String
    let version: Int
    let targetWidthPixels: Int
    let targetHeightPixels: Int

    init(
        publicationID: String,
        version: Int,
        target: ContentCoverTargetSize
    ) {
        self.publicationID = publicationID
        self.version = version
        targetWidthPixels = target.widthPixels
        targetHeightPixels = target.heightPixels
    }
}

struct SessionCoverCacheSnapshot: Equatable, Sendable {
    let keys: [ContentCoverCacheKey]
    let totalCost: Int
    let count: Int
    let totalCostLimit: Int
    let countLimit: Int
    let insertionCount: Int
}

actor SessionCoverCache: SessionCoverCaching {
    private static let fixedTotalCostLimit = 33_554_432
    private static let fixedCountLimit = 64

    private final class KeyBox: NSObject {
        let value: ContentCoverCacheKey

        init(_ value: ContentCoverCacheKey) {
            self.value = value
        }

        override var hash: Int {
            value.hashValue
        }

        override func isEqual(_ object: Any?) -> Bool {
            (object as? KeyBox)?.value == value
        }
    }

    private final class ImageBox {
        let value: ContentCoverImage

        init(_ value: ContentCoverImage) {
            self.value = value
        }
    }

    private struct LedgerEntry: Sendable {
        let cost: Int
        let expiresAt: Date
        let ownership: UUID?
    }

    private let objects = NSCache<KeyBox, ImageBox>()
    private var ledger: [ContentCoverCacheKey: LedgerEntry] = [:]
    private var leastToMostRecent: [ContentCoverCacheKey] = []
    private var totalCost = 0
    private var insertionCount = 0
    private let memoryWarningObserver: SessionCoverMemoryWarningObserver
#if DEBUG
    private var memoryWarningRevision = 0
    private var memoryWarningWaiters: [(
        afterRevision: Int,
        continuation: CheckedContinuation<Void, Never>
    )] = []
#endif

    init(
        memoryWarningCenter: NotificationCenter = .default,
        memoryWarningName: Notification.Name = UIApplication.didReceiveMemoryWarningNotification
    ) {
        objects.totalCostLimit = Self.fixedTotalCostLimit
        objects.countLimit = Self.fixedCountLimit
        let memoryWarningObserver = SessionCoverMemoryWarningObserver()
        self.memoryWarningObserver = memoryWarningObserver
        memoryWarningObserver.bind(
            center: memoryWarningCenter,
            name: memoryWarningName
        ) { [weak self] in
            Task {
                await self?.handleMemoryWarning()
            }
        }
    }

    func image(
        for key: ContentCoverCacheKey,
        now: Date
    ) -> ContentCoverImage? {
        guard let entry = ledger[key] else {
            return nil
        }
        guard entry.expiresAt > now else {
            removeEntry(for: key)
            return nil
        }
        guard let image = objects.object(forKey: KeyBox(key))?.value else {
            removeLedgerEntry(for: key)
            return nil
        }

        promoteToMostRecent(key)
        return image
    }

    func insert(
        _ image: ContentCoverImage,
        for key: ContentCoverCacheKey,
        expiresAt: Date,
        ownership: UUID? = nil
    ) throws {
        let cost = try Self.checkedCost(
            bytesPerRow: image.cgImage.bytesPerRow,
            height: image.cgImage.height
        )
        guard cost <= Self.fixedTotalCostLimit else {
            throw BodyFlowCapabilityError.contentCoverTooLarge
        }

        if ledger[key] != nil {
            removeEntry(for: key)
        }

        while shouldEvictBeforeInsertion(cost: cost),
              let leastRecent = leastToMostRecent.first {
            removeEntry(for: leastRecent)
        }

        let (nextTotalCost, overflowed) = totalCost.addingReportingOverflow(cost)
        guard !overflowed,
              nextTotalCost <= Self.fixedTotalCostLimit,
              ledger.count < Self.fixedCountLimit
        else {
            throw BodyFlowCapabilityError.contentCoverTooLarge
        }

        objects.setObject(ImageBox(image), forKey: KeyBox(key), cost: cost)
        ledger[key] = LedgerEntry(
            cost: cost,
            expiresAt: expiresAt,
            ownership: ownership
        )
        leastToMostRecent.append(key)
        totalCost = nextTotalCost
        insertionCount += 1
    }

    func remove(
        _ key: ContentCoverCacheKey,
        ifOwnedBy ownership: UUID
    ) {
        guard ledger[key]?.ownership == ownership else {
            return
        }
        removeEntry(for: key)
    }

    func remove(publicationID: String, version: Int) {
        let keys = leastToMostRecent.filter {
            $0.publicationID == publicationID && $0.version == version
        }
        for key in keys {
            removeEntry(for: key)
        }
    }

    func handleMemoryWarning() {
        removeAll()
#if DEBUG
        memoryWarningRevision &+= 1
        let ready = memoryWarningWaiters.filter {
            memoryWarningRevision > $0.afterRevision
        }
        memoryWarningWaiters.removeAll {
            memoryWarningRevision > $0.afterRevision
        }
        for waiter in ready {
            waiter.continuation.resume()
        }
#endif
    }

    func removeAll() {
        ledger.removeAll(keepingCapacity: false)
        leastToMostRecent.removeAll(keepingCapacity: false)
        totalCost = 0
        insertionCount = 0
        objects.removeAllObjects()
    }

    func debugSnapshot() -> SessionCoverCacheSnapshot {
        SessionCoverCacheSnapshot(
            keys: leastToMostRecent,
            totalCost: totalCost,
            count: ledger.count,
            totalCostLimit: objects.totalCostLimit,
            countLimit: objects.countLimit,
            insertionCount: insertionCount
        )
    }

#if DEBUG
    func memoryWarningRevisionForTesting() -> Int {
        memoryWarningRevision
    }

    func waitUntilMemoryWarningHandled(after revision: Int) async {
        guard memoryWarningRevision <= revision else { return }
        await withCheckedContinuation { continuation in
            memoryWarningWaiters.append((revision, continuation))
        }
    }
#endif

    static func checkedCost(bytesPerRow: Int, height: Int) throws -> Int {
        guard bytesPerRow > 0, height > 0 else {
            throw BodyFlowCapabilityError.contentCoverTooLarge
        }
        let (cost, overflowed) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !overflowed, cost > 0 else {
            throw BodyFlowCapabilityError.contentCoverTooLarge
        }
        return cost
    }

    private func shouldEvictBeforeInsertion(cost: Int) -> Bool {
        if ledger.count >= Self.fixedCountLimit {
            return true
        }
        let (projectedCost, overflowed) = totalCost.addingReportingOverflow(cost)
        return overflowed || projectedCost > Self.fixedTotalCostLimit
    }

    private func promoteToMostRecent(_ key: ContentCoverCacheKey) {
        leastToMostRecent.removeAll { $0 == key }
        leastToMostRecent.append(key)
    }

    private func removeEntry(for key: ContentCoverCacheKey) {
        objects.removeObject(forKey: KeyBox(key))
        removeLedgerEntry(for: key)
    }

    private func removeLedgerEntry(for key: ContentCoverCacheKey) {
        guard let entry = ledger.removeValue(forKey: key) else {
            return
        }
        leastToMostRecent.removeAll { $0 == key }
        totalCost -= entry.cost
    }
}

private final class SessionCoverMemoryWarningObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var center: NotificationCenter?
    private var token: (any NSObjectProtocol)?

    func bind(
        center: NotificationCenter,
        name: Notification.Name,
        operation: @escaping @Sendable () -> Void
    ) {
        let token = center.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { _ in
            operation()
        }
        lock.withLock {
            self.center = center
            self.token = token
        }
    }

    deinit {
        let registration = lock.withLock {
            let center = self.center
            let token = self.token
            self.center = nil
            self.token = nil
            return (center, token)
        }
        if let center = registration.0, let token = registration.1 {
            center.removeObserver(token)
        }
    }
}
