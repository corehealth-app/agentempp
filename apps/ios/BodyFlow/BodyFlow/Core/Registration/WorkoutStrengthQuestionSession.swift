import Foundation
import Observation

enum WorkoutStrengthQuestionSessionError: Error, Equatable, Sendable {
    case inactive
    case capacityUnavailable
}

/// Session-owned, bounded retention of visible questions and uncertain writes.
/// It never evicts an unresolved intent to admit another workout.
@MainActor
@Observable
final class WorkoutStrengthQuestionSession {
    private struct Entry {
        let model: WorkoutStrengthClarificationModel
        var token: UUID?
        weak var presentation: WorkoutStrengthQuestionPresentation?
    }
    private let provider: any WorkoutStrengthClarificationProviding
    private let isSessionActive: @MainActor @Sendable () -> Bool
    private var entries: [String: Entry] = [:]
    private var closed = false
    private static let capacity = 16

    init(provider: any WorkoutStrengthClarificationProviding,
         isSessionActive: @escaping @MainActor @Sendable () -> Bool) {
        self.provider = provider
        self.isSessionActive = isSessionActive
    }

    var retainedCount: Int { entries.count }

    func attach(workoutID: String, timeProvider: any TimeProviding,
                keyProvider: any IdempotencyKeyProviding,
                invalidationCenter: FeatureInvalidationCenter) throws -> WorkoutStrengthQuestionPresentation {
        guard !closed, isSessionActive() else { throw WorkoutStrengthQuestionSessionError.inactive }
        guard let id = WorkoutStrengthWire.uuid(workoutID) else { throw BodyFlowCapabilityError.invalidInput }
        entries = entries.filter { ($0.value.token != nil && $0.value.presentation != nil) || $0.value.model.pendingAttempt != nil }
        let model: WorkoutStrengthClarificationModel
        if let existing = entries[id] {
            model = existing.model
            model.cancel() // retire the previous local wait before transferring presentation
        } else {
            guard entries.count < Self.capacity else { throw WorkoutStrengthQuestionSessionError.capacityUnavailable }
            model = try WorkoutStrengthClarificationModel(workoutID: id, provider: provider,
                timeProvider: timeProvider, keyProvider: keyProvider, invalidationCenter: invalidationCenter,
                isSessionActive: isSessionActive)
        }
        let token = UUID()
        let presentation = WorkoutStrengthQuestionPresentation(session: self, model: model, token: token)
        entries[id] = Entry(model: model, token: token, presentation: presentation)
        return presentation
    }

    fileprivate func owns(_ presentation: WorkoutStrengthQuestionPresentation) -> Bool {
        !closed && isSessionActive() && entries[presentation.model.workoutID]?.token == presentation.token
            && entries[presentation.model.workoutID]?.model === presentation.model
    }

    fileprivate func detach(_ presentation: WorkoutStrengthQuestionPresentation) {
        guard owns(presentation) else { return }
        presentation.model.cancel()
        let id = presentation.model.workoutID
        if presentation.model.pendingAttempt == nil { entries.removeValue(forKey: id) }
        else { entries[id]?.token = nil; entries[id]?.presentation = nil }
    }

    func close() {
        guard !closed else { return }
        closed = true
        for entry in entries.values { entry.model.cancel() }
        entries.removeAll()
    }
}

/// Every action is guarded by this presentation's token, including departure.
/// An old sheet cannot cancel the new History host under the same auth ticket.
@MainActor
@Observable
final class WorkoutStrengthQuestionPresentation {
    let model: WorkoutStrengthClarificationModel
    private(set) var isReady = false
    private var refreshSequence = 0
    fileprivate let token: UUID
    private weak var session: WorkoutStrengthQuestionSession?
    fileprivate init(session: WorkoutStrengthQuestionSession, model: WorkoutStrengthClarificationModel, token: UUID) {
        self.session = session
        self.model = model
        self.token = token
    }
    var isCurrent: Bool { session?.owns(self) == true }
    var historyFeedback: RegistrationFeedbackSnapshot? {
        guard isCurrent, isReady, !model.isBusy, model.failure == nil else { return nil }
        return model.feedback
    }
    var canAnswer: Bool { isCurrent && isReady && model.canAnswer }
    var canRetryAnswer: Bool { isCurrent && isReady && model.canRetryAnswer }
    func refresh() async {
        guard isCurrent, !model.isSubmitting else { return }
        isReady = false
        refreshSequence += 1
        let currentRefresh = refreshSequence
        let before = model.readPublicationSequence
        await model.reload() // reentry reads official state; never auto-retry POST
        guard isCurrent, !Task.isCancelled, currentRefresh == refreshSequence,
              model.readPublicationSequence > before, model.failure == nil else { return }
        isReady = true
    }
    func answer(_ answer: WorkoutStrengthAnswer) async {
        guard canAnswer else { return }
        await model.answer(answer)
    }
    func retryAnswer() async {
        guard canRetryAnswer else { return }
        await model.retryAnswer()
    }
    func cancelWait() {
        guard isCurrent else { return }
        refreshSequence += 1
        if model.isLoading { isReady = false }
        model.cancel()
    }
    func end() { session?.detach(self) }
}
