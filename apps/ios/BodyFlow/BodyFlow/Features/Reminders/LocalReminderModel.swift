import Foundation
import Observation

enum LocalReminderStatus: Equatable, Sendable {
    case loading
    /// This account has not turned reminders on for this iPhone.
    case notEnabled
    /// Notifications are off for the app in the iPhone Settings.
    case permissionDenied
    /// The patient's notification preferences are off on the server.
    case preferencesOff
    /// No documented time zone: nothing can be derived, nothing is scheduled.
    case timeZoneMissing
    case scheduled(LocalReminderCoverage)
    /// The last sync could not reach the server; earlier reminders remain.
    case unavailable
}

struct LocalReminderCoverage: Equatable, Sendable {
    /// Reminders the system holds (read back), renewal notice excluded.
    let scheduledCount: Int
    let coverageEnd: Date?
    let renewalScheduled: Bool
    let skipped: [LocalReminderSkipReason: Int]
    /// Planned requests the system did not keep.
    let notAccepted: Int
    let previewMode: RoutinePreviewMode
    /// The patient's documented zone the times were derived in (for display).
    let timeZoneIdentifier: String
}

/// One authenticated session's local reminders. Syncs on demand (session
/// start, foreground, routine changes); asks for permission only from
/// `activate()`; never schedules after its session ended.
@MainActor
@Observable
final class LocalReminderModel {
    private(set) var status: LocalReminderStatus = .loading
    private(set) var isWorking = false
    let ownerKey: String

    @ObservationIgnored private let sources: LocalReminderSources
    @ObservationIgnored private let scheduler: LocalReminderScheduler
    @ObservationIgnored private let optIn: any LocalReminderOptInStoring
    @ObservationIgnored private let timeZone: @Sendable () -> PatientTimeZoneContext
    /// False while `/me` has not answered (e.g. an offline launch).
    @ObservationIgnored private let timeZoneSettled: @Sendable () -> Bool
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let language: SupportedAppLanguage
    /// Captured when the session starts; a later sign-out invalidates it.
    @ObservationIgnored private let sessionEpoch: UInt64
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var clearedForeignOwners = false

    init(
        userID: String,
        sources: LocalReminderSources,
        scheduler: LocalReminderScheduler,
        optIn: any LocalReminderOptInStoring,
        timeZone: @escaping @Sendable () -> PatientTimeZoneContext,
        timeZoneSettled: @escaping @Sendable () -> Bool = { true },
        now: @escaping @Sendable () -> Date,
        language: SupportedAppLanguage
    ) {
        ownerKey = LocalReminderPlanner.ownerKey(for: userID)
        self.sources = sources
        self.scheduler = scheduler
        self.optIn = optIn
        self.timeZone = timeZone
        self.timeZoneSettled = timeZoneSettled
        self.now = now
        self.language = language
        sessionEpoch = scheduler.currentEpoch()
    }

    var isEnabled: Bool {
        optIn.isEnabled(ownerKey: ownerKey)
    }

    /// One sync at a time; a request during a sync runs one more pass after
    /// it, and every caller returns only after the pass that covers it.
    func refresh() async {
        guard !ended else { return }
        if let running {
            needsAnotherPass = true
            await running.value
            return
        }
        let loop = Task {
            repeat {
                self.needsAnotherPass = false
                await self.performSync()
            } while self.needsAnotherPass && !self.ended && !Task.isCancelled
        }
        running = loop
        await loop.value
        running = nil
    }

    /// The only place that asks for notification permission.
    func activate() async {
        guard !ended else { return }
        isWorking = true
        defer { isWorking = false }
        if await scheduler.authorization() == .notDetermined {
            _ = await scheduler.requestAuthorization()
        }
        optIn.setEnabled(true, ownerKey: ownerKey)
        await refresh()
    }

    func deactivate() async {
        isWorking = true
        defer { isWorking = false }
        optIn.setEnabled(false, ownerKey: ownerKey)
        if let running { await running.value }
        await scheduler.clearOwner(ownerKey)
        status = .notEnabled
    }

    /// The shell of this session is gone: stop syncing and remove this
    /// owner's reminders (a sign-out also clears through the lifecycle).
    func endSession() {
        guard !ended else { return }
        ended = true
        running?.cancel()
        let scheduler = scheduler
        let ownerKey = ownerKey
        let epoch = sessionEpoch
        // Only while no newer session exists: a sign-out already cleared
        // everything, and must not race the next session's reminders.
        Task { await scheduler.clearOwner(ownerKey, ifEpoch: epoch) }
    }

    private func performSync() async {
        if !clearedForeignOwners {
            // Session start, with or without reminders on: nothing of another
            // account (or of a clean-up that could not be confirmed) remains.
            clearedForeignOwners = await scheduler.clearForeignOwners(keeping: ownerKey)
        }
        guard isEnabled else {
            status = .notEnabled
            return
        }
        switch await scheduler.authorization() {
        case .notDetermined:
            status = .notEnabled
            return
        case .denied:
            await scheduler.clearOwner(ownerKey)
            status = .permissionDenied
            return
        case .authorized:
            break
        }
        guard let zone = try? timeZone().requireTimeZone() else {
            guard timeZoneSettled() else {
                // `/me` has not answered (offline): keep what is scheduled.
                status = .unavailable
                return
            }
            await scheduler.clearOwner(ownerKey)
            status = .timeZoneMissing
            return
        }
        do {
            let preferences = try await sources.reminders.notificationPreferences().data
            guard preferences.pushEnabled else {
                await scheduler.clearOwner(ownerKey)
                status = .preferencesOff
                return
            }
            async let supplements = sources.routine.list(kind: .supplement, includeArchived: false)
            async let medications = sources.routine.list(kind: .medication, includeArchived: false)
            async let rules = sources.reminders.reminderRules()
            let items = try await supplements.data.items + medications.data.items
            let ruleList = try await rules.data
            // The reevaluation date only feeds reevaluation rules; without it
            // those rules are reported as not scheduled.
            let nextReevaluation = try? await sources.progress.progress().data?.nextReevaluation
            try Task.checkCancellation()

            let plan = LocalReminderPlanner.plan(LocalReminderPlannerInput(
                ownerKey: ownerKey,
                routineItems: items,
                rules: ruleList,
                preferences: preferences,
                nextReevaluationDate: nextReevaluation,
                timeZone: zone,
                now: now(),
                copy: LocalReminderCopy.make(language: language)
            ))
            switch await scheduler.apply(plan, ownerKey: ownerKey, epoch: sessionEpoch) {
            case .superseded:
                // The session ended: nothing of it is scheduled any more.
                if !ended { status = .unavailable }
                return
            case let .applied(result):
                status = .scheduled(LocalReminderCoverage(
                    scheduledCount: result.scheduledCount,
                    coverageEnd: result.coverageEnd,
                    renewalScheduled: result.renewalScheduled,
                    skipped: plan.skipped,
                    notAccepted: result.notAccepted,
                    previewMode: preferences.previewMode,
                    timeZoneIdentifier: zone.identifier
                ))
            }
        } catch is CancellationError {
            return
        } catch {
            guard !ended else { return }
            status = .unavailable
        }
    }
}

extension LocalReminderCopy {
    static func make(language: SupportedAppLanguage) -> LocalReminderCopy {
        func text(_ key: String.LocalizationValue) -> String {
            (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
        }
        return LocalReminderCopy(
            genericTitle: text("reminders.notification.generic.title"),
            genericBody: text("reminders.notification.generic.body"),
            routineNameBody: text("reminders.notification.name.body"),
            categoryTitles: [
                ReminderRuleCategory.meal.rawValue: text("reminders.notification.category.meal"),
                ReminderRuleCategory.hydration.rawValue: text("reminders.notification.category.hydration"),
                ReminderRuleCategory.workout.rawValue: text("reminders.notification.category.workout"),
                ReminderRuleCategory.reevaluation.rawValue: text("reminders.notification.category.reevaluation"),
                ReminderRuleCategory.content.rawValue: text("reminders.notification.category.content"),
                ReminderRuleCategory.reengagement.rawValue: text("reminders.notification.category.reengagement"),
            ],
            renewalTitle: text("reminders.notification.renewal.title"),
            renewalBody: text("reminders.notification.renewal.body")
        )
    }
}
