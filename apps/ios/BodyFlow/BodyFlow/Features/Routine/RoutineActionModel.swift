import Foundation
import Observation

enum RoutineAccessibilityFocusTarget: Hashable, Sendable {
    case operationSummary
}

struct RoutineOccurrenceContext: Hashable, Sendable {
    let kind: RoutineItemKind
    let itemID: String
    let reminderRuleID: String
    let scheduledFor: APITimestamp

    /// The server refuses an action on an occurrence that has not started
    /// (`scheduled_for` after now), so only a due occurrence is actionable.
    static func actionContext(
        kind: RoutineItemKind,
        itemID: String,
        schedules: [RoutineScheduleSnapshot],
        now: Date
    ) -> Self? {
        let due = schedules.filter { schedule in
            guard let occurrence = schedule.occurrence else { return false }
            return occurrence.scheduledFor.value <= now
        }
        let schedule = due.first(where: {
            $0.occurrence?.status == "pending"
        }) ?? due.first(where: {
            $0.occurrence?.status == "snoozed"
        })
        guard let schedule, let occurrence = schedule.occurrence else { return nil }
        return Self(
            kind: kind,
            itemID: itemID,
            reminderRuleID: schedule.id,
            scheduledFor: occurrence.scheduledFor
        )
    }
}

struct RoutineActionConfiguration: Equatable, Sendable {
    let context: RoutineOccurrenceContext?
    let schedules: [RoutineScheduleSnapshot]
    /// With nothing due yet, the earliest open occurrence still ahead: its
    /// actions open at that instant.
    let upcoming: RoutineUpcomingOccurrence?

    init(
        kind: RoutineItemKind,
        itemID: String,
        schedules: [RoutineScheduleSnapshot],
        now: Date
    ) {
        self.schedules = schedules
        let context = RoutineOccurrenceContext.actionContext(
            kind: kind,
            itemID: itemID,
            schedules: schedules,
            now: now
        )
        self.context = context
        upcoming = context == nil
            ? RoutineUpcomingOccurrence.earliest(in: schedules, after: now)
            : nil
    }

    func shouldApply(
        over applied: Self?,
        isSubmitting: Bool
    ) -> Bool {
        !isSubmitting && self != applied
    }
}

struct RoutineUpcomingOccurrence: Hashable, Sendable {
    let scheduledFor: Date
    /// The rule's patient-local "HH:mm" as the server sent it.
    let localTime: String

    static func earliest(
        in schedules: [RoutineScheduleSnapshot],
        after now: Date
    ) -> Self? {
        schedules
            .compactMap { schedule -> Self? in
                guard let occurrence = schedule.occurrence,
                      occurrence.status == "pending" || occurrence.status == "snoozed",
                      occurrence.scheduledFor.value > now
                else { return nil }
                return Self(
                    scheduledFor: occurrence.scheduledFor.value,
                    localTime: schedule.localTime
                )
            }
            .min { $0.scheduledFor < $1.scheduledFor }
    }
}

@MainActor
@Observable
final class RoutineActionModel {
    private let provider: any RoutineProviding
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private let invalidationCenter: FeatureInvalidationCenter
    private let patientTimeZone: PatientTimeZoneContext
    let context: RoutineOccurrenceContext

    private var activeOwnership: FeatureLoadOwnership?
    private var activeIntent: RoutineActionIntent?
    private var operationSequence = 0

    private(set) var mutationState = RoutineMutationState.idle
    private(set) var accessibilityFocusTarget: RoutineAccessibilityFocusTarget?

    init(
        provider: any RoutineProviding,
        timeProvider: any TimeProviding,
        keyProvider: any IdempotencyKeyProviding,
        invalidationCenter: FeatureInvalidationCenter,
        patientTimeZone: PatientTimeZoneContext,
        context: RoutineOccurrenceContext
    ) {
        self.provider = provider
        self.timeProvider = timeProvider
        self.keyProvider = keyProvider
        self.invalidationCenter = invalidationCenter
        self.patientTimeZone = patientTimeZone
        self.context = context
    }

    /// The action happens when the patient taps, not when the detail
    /// opened: a new attempt reads the clock at submit. A retry resends its
    /// attempt unchanged (same idempotency key, same payload).
    var occurredAt: Date {
        timeProvider.now
    }

    var isSubmitting: Bool {
        if case .submitting = mutationState { true } else { false }
    }

    func snoozeDate(for selection: RoutineSnoozeSelection) -> Date? {
        snoozeDate(for: selection, occurredAt: occurredAt)
    }

    private func snoozeDate(for selection: RoutineSnoozeSelection, occurredAt: Date) -> Date? {
        guard let policy = try? RoutineSnoozePolicy(context: patientTimeZone) else {
            return nil
        }
        return policy.date(
            for: selection,
            scheduledFor: context.scheduledFor.value,
            occurredAt: occurredAt
        )
    }

    func submit(
        status: RoutineActionStatus,
        selection: RoutineSnoozeSelection? = nil
    ) async {
        guard !isSubmitting else { return }
        let intent = RoutineActionIntent(status: status, selection: selection)
        guard activeIntent != intent else { return }
        let occurredAt = self.occurredAt
        let snoozedUntil: APITimestamp?
        switch status {
        case .taken, .skipped:
            snoozedUntil = nil
        case .snoozed:
            guard let selection, let date = snoozeDate(for: selection, occurredAt: occurredAt) else {
                accessibilityFocusTarget = .operationSummary
                return
            }
            snoozedUntil = APITimestamp(value: date)
        }

        do {
            let command = try RoutineActionCommand(
                kind: context.kind,
                itemID: context.itemID,
                status: status,
                reminderRuleID: context.reminderRuleID,
                scheduledFor: context.scheduledFor,
                occurredAt: APITimestamp(value: occurredAt),
                snoozedUntil: snoozedUntil
            )
            let attempt = try MutationAttempt(
                operation: .routineAction,
                key: keyProvider.nextKey(),
                payload: command,
                createdAt: timeProvider.now
            )
            await run(attempt, intent: intent)
        } catch {
            publishConstructionFailure(error)
        }
    }

    func retry() async {
        guard case let .failed(attempt, _) = mutationState else { return }
        await run(
            attempt,
            intent: RoutineActionIntent(
                status: attempt.payload.status,
                selection: nil
            )
        )
    }

    func consumeAccessibilityFocus() { accessibilityFocusTarget = nil }

    func cancel() {
        activeOwnership?.invalidate()
        activeOwnership = nil
        activeIntent = nil
        operationSequence += 1
        if case .submitting = mutationState { mutationState = .idle }
    }

    private func run(
        _ attempt: MutationAttempt<RoutineActionCommand>,
        intent: RoutineActionIntent
    ) async {
        let operation = beginOperation()
        activeIntent = intent
        mutationState = .submitting(attempt)
        accessibilityFocusTarget = nil
        await withTaskCancellationHandler {
            do {
                let receipt = try await provider.record(attempt)
                guard claimPublication(operation) else { return }
                mutationState = .succeeded(receipt)
                invalidationCenter.record(.routineAction(
                    kind: context.kind,
                    itemID: context.itemID
                ))
                accessibilityFocusTarget = .operationSummary
                clear(operation)
            } catch is CancellationError {
                return
            } catch {
                guard claimPublication(operation) else { return }
                let capabilityError = error as? BodyFlowCapabilityError ?? .serviceUnavailable
                mutationState = capabilityError == .operationUnavailable
                    ? .unavailable
                    : .failed(attempt, capabilityError)
                if capabilityError == .idempotencyConflict
                    || capabilityError == .routineTransitionInvalid {
                    invalidationCenter.record(keys: [
                        .routineList(kind: context.kind),
                        .routineHistory(
                            kind: context.kind,
                            itemID: context.itemID
                        ),
                    ])
                }
                accessibilityFocusTarget = .operationSummary
                clear(operation)
            }
        } onCancel: {
            operation.ownership.invalidate()
        }
        if Task.isCancelled, activeOwnership === operation.ownership {
            activeOwnership = nil
            activeIntent = nil
            if case .submitting = mutationState { mutationState = .idle }
        }
    }

    private func publishConstructionFailure(_ error: any Error) {
        let capabilityError = error as? BodyFlowCapabilityError ?? .serviceUnavailable
        if capabilityError == .operationUnavailable { mutationState = .unavailable }
        accessibilityFocusTarget = .operationSummary
    }

    private func beginOperation() -> ActiveRoutineOperation {
        activeOwnership?.invalidate()
        operationSequence += 1
        let ownership = FeatureLoadOwnership()
        activeOwnership = ownership
        return ActiveRoutineOperation(sequence: operationSequence, ownership: ownership)
    }

    private func claimPublication(_ operation: ActiveRoutineOperation) -> Bool {
        !Task.isCancelled
            && !operation.ownership.isInvalidated
            && operation.sequence == operationSequence
            && activeOwnership === operation.ownership
            && operation.ownership.claimPublication()
    }

    private func clear(_ operation: ActiveRoutineOperation) {
        if activeOwnership === operation.ownership {
            activeOwnership = nil
            activeIntent = nil
        }
    }
}

private struct ActiveRoutineOperation: Sendable {
    let sequence: Int
    let ownership: FeatureLoadOwnership
}

private struct RoutineActionIntent: Hashable, Sendable {
    let status: RoutineActionStatus
    let selection: RoutineSnoozeSelection?
}
