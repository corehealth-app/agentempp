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

    static func actionContext(
        kind: RoutineItemKind,
        itemID: String,
        schedules: [RoutineScheduleSnapshot]
    ) -> Self? {
        let schedule = schedules.first(where: {
            $0.occurrence?.status == "pending"
        }) ?? schedules.first(where: {
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

    init(
        kind: RoutineItemKind,
        itemID: String,
        schedules: [RoutineScheduleSnapshot]
    ) {
        self.schedules = schedules
        context = RoutineOccurrenceContext.actionContext(
            kind: kind,
            itemID: itemID,
            schedules: schedules
        )
    }

    func shouldApply(
        over applied: Self?,
        isSubmitting: Bool
    ) -> Bool {
        !isSubmitting && self != applied
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
    let occurredAt: Date

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
        occurredAt = timeProvider.now
    }

    var isSubmitting: Bool {
        if case .submitting = mutationState { true } else { false }
    }

    func snoozeDate(for selection: RoutineSnoozeSelection) -> Date? {
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
        let snoozedUntil: APITimestamp?
        switch status {
        case .taken, .skipped:
            snoozedUntil = nil
        case .snoozed:
            guard let selection, let date = snoozeDate(for: selection) else {
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
