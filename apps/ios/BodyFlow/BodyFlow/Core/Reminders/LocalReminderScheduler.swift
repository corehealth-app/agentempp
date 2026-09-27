import Foundation

struct LocalReminderApplyResult: Equatable, Sendable {
    /// Reminders the system holds after the apply (renewal notice excluded).
    let scheduledCount: Int
    let renewalScheduled: Bool
    /// Planned requests the system did not keep (refused, or dropped).
    let notAccepted: Int
    /// The last reminder the system actually holds.
    let coverageEnd: Date?
}

enum LocalReminderApplyOutcome: Equatable, Sendable {
    case applied(LocalReminderApplyResult)
    /// The session ended (or changed) while this sync ran; nothing was kept.
    case superseded
}

/// The single writer of this app's local notifications. Every operation runs
/// alone (an async lock around the actor), and `invalidate()` stops a sync
/// that started for a previous session from scheduling anything — a late
/// response can never re-add reminders for a user who just left.
actor LocalReminderScheduler {
    private let center: any LocalNotificationCentering
    private let epochs = LocalReminderEpochCounter()
    /// "A reminder clean-up is owed", kept across launches in production.
    nonisolated let cleanupMarker: any LocalReminderCleanupMarking
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
        center: any LocalNotificationCentering,
        cleanupMarker: any LocalReminderCleanupMarking = InMemoryLocalReminderCleanupMarker()
    ) {
        self.center = center
        self.cleanupMarker = cleanupMarker
    }

    /// Read synchronously: a session captures it when it starts, so a sync
    /// of that session can never schedule after the session was invalidated.
    nonisolated func currentEpoch() -> UInt64 {
        epochs.current
    }

    /// Ends the current session's right to schedule. Synchronous, so it takes
    /// effect at once, even while a sync is suspended; that sync then stops
    /// at its next step and removes what it added.
    @discardableResult
    nonisolated func invalidate() -> UInt64 {
        epochs.bump()
    }

    private var epoch: UInt64 {
        epochs.current
    }

    func authorization() async -> LocalNotificationAuthorization {
        await center.authorization()
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization()) ?? false
    }

    /// Makes the pending reminders equal to `plan` for `ownerKey` and reports
    /// what the system actually holds afterwards (read back, not assumed).
    func apply(
        _ plan: LocalReminderPlan,
        ownerKey: String,
        epoch expected: UInt64
    ) async -> LocalReminderApplyOutcome {
        await acquire()
        defer { release() }
        // A cancelled sync (its session ended) or an older epoch schedules nothing.
        guard expected == epoch, !Task.isCancelled else { return .superseded }

        let ours = LocalReminderPlanner.identifierPrefix
        let owner = LocalReminderPlanner.identifierPrefix(ownerKey: ownerKey)
        let pending = Set(await center.pendingIdentifiers().filter { $0.hasPrefix(ours) })
        let wanted = Set(plan.reminders.map(\.identifier))
        // Stale times of this owner and anything left by another owner.
        await center.removePending(Array(pending.subtracting(wanted)))
        let foreignDelivered = await center.deliveredIdentifiers()
            .filter { $0.hasPrefix(ours) && !$0.hasPrefix(owner) }
        await center.removeDelivered(foreignDelivered)

        // Every planned reminder is (re)added: adding an identifier that is
        // already pending replaces its content, so a new privacy mode, a new
        // dose text or another language never leaves old text on the lock
        // screen.
        var added: [String] = []
        for reminder in plan.reminders {
            guard expected == epoch, !Task.isCancelled else { break }
            do {
                try await center.add(reminder, ownerKey: ownerKey)
                if !pending.contains(reminder.identifier) {
                    added.append(reminder.identifier)
                }
            } catch {
                continue
            }
        }
        guard expected == epoch, !Task.isCancelled else {
            await center.removePending(added)
            return .superseded
        }

        let held = Set(await center.pendingIdentifiers())
        let kept = plan.reminders.filter { held.contains($0.identifier) }
        let keptReminders = kept.filter { !$0.isRenewal }
        return .applied(LocalReminderApplyResult(
            scheduledCount: keptReminders.count,
            renewalScheduled: kept.contains(where: \.isRenewal),
            notAccepted: plan.reminders.count - kept.count,
            coverageEnd: keptReminders.map(\.fireDate).max()
        ))
    }

    /// Removes every reminder of this app, pending and delivered, and returns
    /// true only after reading back that none remains.
    @discardableResult
    func clearAll(invalidating: Bool = true) async -> Bool {
        if invalidating { invalidate() }
        await acquire()
        defer { release() }
        let ours = LocalReminderPlanner.identifierPrefix
        for attempt in 0..<3 {
            let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(ours) }
            let delivered = await center.deliveredIdentifiers().filter { $0.hasPrefix(ours) }
            if pending.isEmpty && delivered.isEmpty {
                cleanupMarker.clear()
                return true
            }
            await center.removePending(pending)
            await center.removeDelivered(delivered)
            if attempt < 2 { try? await Task.sleep(for: .milliseconds(100)) }
        }
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(ours) }
        let delivered = await center.deliveredIdentifiers().filter { $0.hasPrefix(ours) }
        let clean = pending.isEmpty && delivered.isEmpty
        if clean { cleanupMarker.clear() }
        return clean
    }

    /// Removes one owner's reminders, pending and delivered (a session that
    /// ended or turned reminders off); another account's are untouched.
    @discardableResult
    func clearOwner(_ ownerKey: String, ifEpoch expected: UInt64? = nil) async -> Bool {
        await acquire()
        defer { release() }
        // A clean-up bound to a session that was already superseded does
        // nothing: the sign-out cleared, and a newer session owns the center.
        if let expected, expected != epoch { return true }
        let owner = LocalReminderPlanner.identifierPrefix(ownerKey: ownerKey)
        await center.removePending(await center.pendingIdentifiers().filter { $0.hasPrefix(owner) })
        await center.removeDelivered(await center.deliveredIdentifiers().filter { $0.hasPrefix(owner) })
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(owner) }
        let delivered = await center.deliveredIdentifiers().filter { $0.hasPrefix(owner) }
        return pending.isEmpty && delivered.isEmpty
    }

    /// Removes the reminders of every other owner, pending and delivered,
    /// and returns true only after reading back that none remains.
    @discardableResult
    func clearForeignOwners(keeping ownerKey: String) async -> Bool {
        await acquire()
        defer { release() }
        let ours = LocalReminderPlanner.identifierPrefix
        let owner = LocalReminderPlanner.identifierPrefix(ownerKey: ownerKey)
        func foreign(_ identifiers: [String]) -> [String] {
            identifiers.filter { $0.hasPrefix(ours) && !$0.hasPrefix(owner) }
        }
        await center.removePending(foreign(await center.pendingIdentifiers()))
        await center.removeDelivered(foreign(await center.deliveredIdentifiers()))
        let pendingLeft = foreign(await center.pendingIdentifiers())
        let deliveredLeft = foreign(await center.deliveredIdentifiers())
        let clean = pendingLeft.isEmpty && deliveredLeft.isEmpty
        if clean { cleanupMarker.clear() }
        return clean
    }

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

final class LocalReminderEpochCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    var current: UInt64 {
        lock.withLock { value }
    }

    func bump() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }
}

/// Runs every clearer in order (the lifecycle accepts exactly one).
struct CompositeSensitiveStateClearer: SensitiveStateClearing {
    let clearers: [any SensitiveStateClearing]

    func clearSensitiveState() async {
        for clearer in clearers {
            await clearer.clearSensitiveState()
        }
    }
}

/// On sign-out and user switch: no reminder of the ended session survives,
/// pending or delivered, and no sync of that session can schedule again. A
/// durable marker is set first and removed only once the clean-up is
/// confirmed, so a clean-up interrupted by the process ending is finished
/// on the next launch without a session or the next session start.
struct LocalReminderSessionClearer: SensitiveStateClearing {
    let scheduler: LocalReminderScheduler

    func clearSensitiveState() async {
        scheduler.cleanupMarker.set()
        // clearAll removes the marker only once it confirms the clean-up.
        if await scheduler.clearAll() { return }
        await scheduler.clearAll(invalidating: false)
    }
}

/// "A reminder clean-up is owed." Holds no account data.
protocol LocalReminderCleanupMarking: Sendable {
    var isSet: Bool { get }
    func set()
    func clear()
}

struct UserDefaultsLocalReminderCleanupMarker: LocalReminderCleanupMarking {
    private static let key = "\(LocalReminderPlanner.identifierPrefix)reminders-cleanup-pending"

    var isSet: Bool { UserDefaults.standard.bool(forKey: Self.key) }
    func set() { UserDefaults.standard.set(true, forKey: Self.key) }
    func clear() { UserDefaults.standard.removeObject(forKey: Self.key) }
}

final class InMemoryLocalReminderCleanupMarker: LocalReminderCleanupMarking, @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
    func clear() { lock.withLock { value = false } }
}
