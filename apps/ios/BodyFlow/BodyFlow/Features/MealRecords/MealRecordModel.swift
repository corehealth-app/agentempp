import Foundation
import Observation

struct MealRecordCompletion: Equatable, Sendable {
    let attempt: MealRecordMutationAttempt
    let receipt: MealRecordMutationResponse
    let submittedDraft: MealRecordEditDraft?
}

@MainActor
@Observable
final class MealRecordModel {
    /// A local observation of this read attempt, not server cancellation or
    /// permission to reuse data. Only a published response/error is settled.
    enum LoadOutcome: Equatable, Sendable {
        case settled, notStarted, cancelled, superseded
    }

    let recordID: String
    private let provider: any MealRecordProviding
    private let time: any TimeProviding
    private let keys: any IdempotencyKeyProviding
    private let invalidation: FeatureInvalidationCenter
    private let isSessionActive: @MainActor @Sendable () -> Bool
    private var ownership: FeatureLoadOwnership?
    private var sequence = 0
    private var lastReadSequence = -1
    private var attemptSequence = -1
    private var recoveryID: String?
    private var presentationDismissed = false
    private var requiresFreshPresentationRead = false
    // A new official version cannot make unchanged rejected input corrected.
    private var rejectedPatchInputs: [RejectedPatchInput] = []

    private(set) var detail: MealRecordResponse?
    var draft: MealRecordEditDraft?
    private(set) var archivedDraft: MealRecordEditDraft?
    private(set) var retainedAttempt: MealRecordMutationAttempt?
    private(set) var confirmedReceipt: MealRecordMutationResponse?
    private(set) var failure: MealRecordFailure?
    private(set) var readFailure: MealRecordFailure?
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var deletionSelection: Set<String> = []
    private(set) var hasCompletedCurrentPresentation = false
    private(set) var isCorrectingRejectedInput = false
    private(set) var attemptHistory: [MealRecordMutationAttempt] = []
    private(set) var completedMutations: [MealRecordCompletion] = []
    private(set) var archivedDrafts: [MealRecordEditDraft] = []

    var historyFeedback: RegistrationFeedbackSnapshot? {
        guard isSessionActive(), !presentationDismissed, !isLoading, readFailure == nil,
              let value = detail?.data, value.recordID == recoveryID else { return nil }
        return value.feedback
    }

    init(recordID: String, provider: any MealRecordProviding,
         time: any TimeProviding, keys: any IdempotencyKeyProviding,
         invalidation: FeatureInvalidationCenter,
         isSessionActive: @escaping @MainActor @Sendable () -> Bool) {
        self.recordID = recordID; recoveryID = recordID
        self.provider = provider; self.time = time; self.keys = keys
        self.invalidation = invalidation; self.isSessionActive = isSessionActive
    }

    var canStartMutation: Bool {
        retainedAttempt == nil && !hasCompletedCurrentPresentation && hasEditableRead
    }

    private var hasEditableRead: Bool {
        guard isSessionActive(), !isLoading, !isSubmitting,
              !requiresFreshPresentationRead,
              let value = detail?.data, value.recordID == recordID, value.editable, !value.dayClosed,
              let draft, draft.expectedVersion == value.expectedVersion,
              draft.itemIDs == value.itemIDs else { return false }
        return true
    }

    var canCorrectRejectedInput: Bool {
        guard hasEditableRead, !hasCompletedCurrentPresentation,
              case .patch? = retainedAttempt else { return false }
        switch failure {
        case .quantityNotRepresentable?, .nutritionUnresolved?, .groupLimitExceeded?: return true
        default: return false
        }
    }

    var canEditDraft: Bool {
        canStartMutation || (isCorrectingRejectedInput && canCorrectRejectedInput)
    }

    func canSave(language: SupportedAppLanguage) -> Bool {
        guard let body = draft?.patchBody(language: language), rejection(of: body) == nil else { return false }
        if canStartMutation { return true }
        guard isCorrectingRejectedInput, canCorrectRejectedInput,
              case let .patch(original)? = retainedAttempt else { return false }
        return body.expectedVersion == original.payload.body.expectedVersion && body.items != original.payload.body.items
    }

    /// Why Save is unavailable although the form is open: the typed fields
    /// are the ones already declined. Nil while that refusal is on screen.
    func rejectedInputBlock(language: SupportedAppLanguage) -> MealRecordFailure? {
        guard failure == nil, canStartMutation,
              let body = draft?.patchBody(language: language) else { return nil }
        return rejection(of: body)
    }

    /// The same fields stay refused whatever the official version becomes.
    /// A group-limit refusal is about the group, so it ends when the form
    /// stands on another group.
    private func rejection(of body: MealRecordPatchBody) -> MealRecordFailure? {
        for rejected in rejectedPatchInputs.reversed() where rejected.items == body.items {
            if rejected.reason == .groupLimitExceeded, let draft,
               draft.itemIDs != rejected.groupItemIDs { continue }
            return rejected.reason
        }
        return nil
    }

    /// The official read is newer than a form that holds typed fields and no
    /// command is pending: the screen offers the review without any failure.
    var requiresReviewOfCurrentData: Bool {
        guard isSessionActive(), !isLoading, !isSubmitting, !hasCompletedCurrentPresentation,
              !requiresFreshPresentationRead, retainedAttempt == nil,
              let value = detail?.data, value.recordID == recordID, let draft else { return false }
        return draft.expectedVersion != value.expectedVersion || draft.itemIDs != value.itemIDs
    }

    /// Called on view entry, never from the coordinator getter or body rendering.
    /// Only a dismissed, completed presentation starts a fresh read of its
    /// anchor, and only when the anchor outlived the saved change.
    func beginPresentation() {
        guard presentationDismissed, isSessionActive() else { return }
        presentationDismissed = false
        guard retainedAttempt == nil, hasCompletedCurrentPresentation else { return }
        // The saved change removed this very record (a correction always
        // does, and so does deleting it): its id answers 404 from then on.
        // The completed presentation stays and reads keep following the
        // receipt's next_record_id, or nothing when the meal became empty.
        if confirmedReceipt?.data.removedItemIDs.contains(recordID) == true { return }
        hasCompletedCurrentPresentation = false
        requiresFreshPresentationRead = true
        recoveryID = recordID
        detail = nil
        isCorrectingRejectedInput = false
        // Keep confirmedReceipt/history and old fields until the new GET succeeds.
    }

    func beginCorrectingRejectedInput() {
        guard canCorrectRejectedInput, !isCorrectingRejectedInput else { return }
        archiveCurrentDraft()
        isCorrectingRejectedInput = true
        // Editing does not clear/mutate the original attempt or mint a key.
    }

    /// Explicit reads never replay a command. A committed receipt survives a
    /// later GET failure; a working form survives refresh/conflict.
    @discardableResult
    func load() async -> LoadOutcome {
        guard !isSubmitting, isSessionActive(), let id = recoveryID else { return .notStarted }
        let operation = begin(); isLoading = true; readFailure = nil
        let outcome: LoadOutcome = await withTaskCancellationHandler {
            do {
                let response = try await provider.mealRecord(id: id)
                guard publish(operation) else {
                    return Task.isCancelled ? .cancelled : .superseded
                }
                detail = response
                lastReadSequence = operation.sequence
                if requiresFreshPresentationRead {
                    archiveCurrentDraft()
                    draft = MealRecordEditDraft(response.data)
                    deletionSelection = [recordID]
                    requiresFreshPresentationRead = false
                } else if draft == nil, !hasCompletedCurrentPresentation {
                    draft = MealRecordEditDraft(response.data)
                    deletionSelection = [recordID]
                } else if retainedAttempt == nil, !hasCompletedCurrentPresentation,
                          let current = draft, !current.hasTypedFields,
                          current.expectedVersion != response.data.expectedVersion
                            || current.itemIDs != response.data.itemIDs {
                    // Nothing typed and nothing pending: the newer official
                    // read becomes the form's base. Typed fields are never
                    // moved here; `requiresReviewOfCurrentData` offers the review.
                    draft = MealRecordEditDraft(response.data)
                    deletionSelection = [recordID]
                }
                readFailure = nil
                return .settled
            } catch is CancellationError {
                // No server outcome is inferred from cancellation.
                return .cancelled
            } catch {
                guard publish(operation) else {
                    return Task.isCancelled ? .cancelled : .superseded
                }
                readFailure = Self.failure(error)
                return .settled
            }
        } onCancel: { operation.ownership.invalidate() }
        finish(operation)
        return outcome
    }

    /// The same eligibility used by reviewLatest(), exposed to its controls.
    var canReviewLatest: Bool {
        !isLoading && !isSubmitting && isSessionActive() && !hasCompletedCurrentPresentation
            && !requiresFreshPresentationRead && detail != nil
            && (retainedAttempt == nil
                || (failure?.mayRetrySameAttempt == false && lastReadSequence > attemptSequence))
    }

    /// Explicitly review the latest server version. Preserve the old form as
    /// an archive; never merge it silently over a concurrently changed group.
    func reviewLatest() {
        guard canReviewLatest, let detail else { return }
        archiveCurrentDraft()
        draft = MealRecordEditDraft(detail.data)
        deletionSelection = [recordID]
        retainedAttempt = nil; failure = nil; isCorrectingRejectedInput = false
    }

    var canRestoreArchivedFields: Bool {
        canStartMutation && archivedDraft?.items.contains(where: { $0.id == recordID }) == true
    }

    /// User explicitly recovers editable fields after reviewing the official GET.
    /// IDs/version/original physical data stay those of the newly reviewed draft.
    func restoreArchivedFields() {
        guard canRestoreArchivedFields, let archivedDraft,
              let old = archivedDraft.items.first(where: { $0.id == recordID }),
              var current = draft, let index = current.items.firstIndex(where: { $0.id == recordID })
        else { return }
        current.items[index].foodName = old.foodName
        current.items[index].restoreQuantityInput(from: old)
        current.items[index].manualKcalText = old.manualKcalText
        draft = current
    }

    private func archiveCurrentDraft() {
        guard let draft else { return }
        archivedDraft = draft
        if archivedDrafts.last != draft { archivedDrafts.append(draft) }
    }

    func selectForDeletion(id: String, selected: Bool) {
        guard canStartMutation, detail?.data.itemIDs.contains(id) == true else { return }
        if selected { deletionSelection.insert(id) } else { deletionSelection.remove(id) }
    }

    func save(language: SupportedAppLanguage) async {
        guard canSave(language: language), let body = draft?.patchBody(language: language) else { return }
        do {
            let attempt = MutationAttempt(operation: .mealRecordPatch, key: try keys.nextKey(),
                payload: MealRecordPatchCommand(recordID: recordID, body: body,
                    originalGroupItemIDs: detail?.data.itemIDs ?? [],
                    expectedLocalDate: detail?.data.localDate ?? ""), createdAt: time.now)
            await perform(.patch(attempt))
        } catch { failure = Self.failure(error) }
    }

    func delete() async {
        guard canStartMutation, let value = detail?.data else { return }
        let selected = value.itemIDs.filter { deletionSelection.contains($0) }
        guard !selected.isEmpty, selected.count <= 30, selected.count == deletionSelection.count else { return }
        do {
            let attempt = MutationAttempt(operation: .mealRecordDelete, key: try keys.nextKey(),
                payload: MealRecordDeleteCommand(recordID: recordID,
                    body: MealRecordDeleteBody(expectedVersion: value.expectedVersion, itemIDs: selected),
                    originalGroupItemIDs: value.itemIDs, expectedLocalDate: value.localDate),
                createdAt: time.now)
            await perform(.delete(attempt))
        } catch { failure = Self.failure(error) }
    }

    func retry() async {
        guard !isLoading, !isSubmitting, isSessionActive(), !hasCompletedCurrentPresentation,
              let retainedAttempt, failure?.mayRetrySameAttempt == true else { return }
        await perform(retainedAttempt)
    }

    func discardPresentation() {
        presentationDismissed = true
        ownership?.invalidate(); ownership = nil; sequence += 1
        if isSubmitting, retainedAttempt != nil { failure = .interruptedUnknown }
        isSubmitting = false; isLoading = false
        // Retain unknown command/form/key for explicit same-attempt retry.
    }

    func endSession() {
        discardPresentation()
        detail = nil; draft = nil; archivedDraft = nil; retainedAttempt = nil
        confirmedReceipt = nil; failure = nil; readFailure = nil; recoveryID = nil
        deletionSelection = []
        hasCompletedCurrentPresentation = false; requiresFreshPresentationRead = false
        isCorrectingRejectedInput = false
        attemptHistory.removeAll(); completedMutations.removeAll(); archivedDrafts.removeAll()
        rejectedPatchInputs.removeAll()
    }

    private func perform(_ attempt: MealRecordMutationAttempt) async {
        guard !isSubmitting, isSessionActive() else { return }
        let submittedDraft = draft
        if !attemptHistory.contains(attempt) { attemptHistory.append(attempt) }
        isCorrectingRejectedInput = false
        let operation = begin(); retainedAttempt = attempt; failure = nil; isSubmitting = true
        attemptSequence = operation.sequence
        await withTaskCancellationHandler {
            do {
                let receipt: MealRecordMutationResponse
                switch attempt {
                case let .patch(value): receipt = try await provider.patch(value)
                case let .delete(value): receipt = try await provider.delete(value)
                }
                // A malformed success may follow a committed server command.
                // Retain its key/body as unknown; never silently mint a new key.
                guard Self.matches(receipt.data, attempt: attempt) else {
                    throw MealRecordFailure.interruptedUnknown
                }
                guard publish(operation) || adoptsLateReceipt(for: attempt) else { return }
                confirmedReceipt = receipt; retainedAttempt = nil; failure = nil
                hasCompletedCurrentPresentation = true
                completedMutations.append(MealRecordCompletion(attempt: attempt,
                    receipt: receipt, submittedDraft: submittedDraft))
                // The pre-mutation GET is now historical. Preserve the form
                // separately and show current rows only after an explicit GET.
                detail = nil
                recoveryID = receipt.data.nextRecordID
                invalidation.record(keys: [.today, .history])
                // No auto-GET, extra PATCH, draft recreation or totals addition.
            } catch is CancellationError {
                // finish() retains an uncertain command if this operation owns it.
            } catch {
                guard publish(operation) else { return }
                failure = Self.failure(error)
                if case let .patch(value) = attempt, let reason = failure {
                    switch reason {
                    case .quantityNotRepresentable, .nutritionUnresolved, .groupLimitExceeded:
                        let rejected = RejectedPatchInput(items: value.payload.body.items,
                            reason: reason, groupItemIDs: value.payload.originalGroupItemIDs)
                        if !rejectedPatchInputs.contains(rejected) { rejectedPatchInputs.append(rejected) }
                    default: break
                    }
                }
            }
        } onCancel: { operation.ownership.invalidate() }
        finish(operation)
    }

    private func begin() -> Operation {
        ownership?.invalidate(); sequence += 1
        let token = FeatureLoadOwnership(); ownership = token
        return Operation(sequence: sequence, ownership: token)
    }

    private func publish(_ operation: Operation) -> Bool {
        isSessionActive() && !Task.isCancelled && sequence == operation.sequence
            && ownership === operation.ownership && operation.ownership.claimPublication()
    }

    /// Leaving the screen is not the end of the session. A validated receipt
    /// for the command this model still retains is the server's answer to it,
    /// so it is kept while the session lives, whichever later step holds the
    /// turn; that step is closed first so nothing older can publish over it.
    /// After sign-out `endSession()` has already dropped the retained command.
    private func adoptsLateReceipt(for attempt: MealRecordMutationAttempt) -> Bool {
        guard isSessionActive(), retainedAttempt == attempt else { return false }
        ownership?.invalidate(); ownership = nil; sequence += 1
        isSubmitting = false; isLoading = false
        return true
    }

    private func finish(_ operation: Operation) {
        guard sequence == operation.sequence, ownership === operation.ownership else { return }
        if isSubmitting, retainedAttempt != nil, failure == nil { failure = .interruptedUnknown }
        isSubmitting = false; isLoading = false; ownership = nil
        if !isSessionActive() { endSession() }
    }

    private static func failure(_ error: any Error) -> MealRecordFailure {
        if let error = error as? MealRecordFailure { return error }
        if let error = error as? BodyFlowCapabilityError { return .capability(error) }
        return .capability(.serviceUnavailable)
    }

    private static func matches(_ receipt: MealRecordMutationSnapshot,
                                attempt: MealRecordMutationAttempt) -> Bool {
        let removed: [String]
        let recordID: String
        let localDate: String
        let originalGroup: [String]
        switch attempt {
        case let .patch(value):
            guard receipt.operation == .updated,
                  value.payload.body.itemIDs == [value.payload.recordID],
                  (1...30).contains(receipt.newItemIDs.count),
                  let next = receipt.nextRecordID, receipt.newItemIDs.contains(next)
            else { return false }
            removed = value.payload.body.itemIDs
            recordID = value.payload.recordID; localDate = value.payload.expectedLocalDate
            originalGroup = value.payload.originalGroupItemIDs
        case let .delete(value):
            guard receipt.operation == .deleted, receipt.newItemIDs.isEmpty else { return false }
            removed = value.payload.body.itemIDs
            recordID = value.payload.recordID; localDate = value.payload.expectedLocalDate
            originalGroup = value.payload.originalGroupItemIDs
            let remaining = Set(originalGroup).subtracting(removed)
            if let next = receipt.nextRecordID {
                guard remaining.contains(next) else { return false }
            } else if !remaining.isEmpty { return false }
        }
        return receipt.recordID == recordID && (1...30).contains(removed.count)
            && !originalGroup.isEmpty && Set(originalGroup).count == originalGroup.count
            && Set(removed).isSubset(of: Set(originalGroup))
            && Set(removed).count == removed.count
            && receipt.removedItemIDs.count == removed.count
            && Set(receipt.removedItemIDs) == Set(removed)
            && Set(receipt.newItemIDs).count == receipt.newItemIDs.count
            && receipt.newItemIDs.allSatisfy { !$0.isEmpty }
            && Set(receipt.newItemIDs).isDisjoint(with: Set(originalGroup))
            && !receipt.snapshot.id.isEmpty && !localDate.isEmpty && receipt.snapshot.date == localDate
    }

    private struct Operation: Sendable {
        let sequence: Int
        let ownership: FeatureLoadOwnership
    }

    private struct RejectedPatchInput: Equatable {
        let items: [MealProposalItemRequest]
        let reason: MealRecordFailure
        let groupItemIDs: [String]
    }
}

@MainActor
final class MealRecordFeatureCoordinator {
    private let provider: any MealRecordProviding
    private let time: any TimeProviding
    private let keys: any IdempotencyKeyProviding
    private let invalidation: FeatureInvalidationCenter
    private let isSessionActive: @MainActor @Sendable () -> Bool
    private var models: [String: MealRecordModel] = [:]

    init(provider: any MealRecordProviding, time: any TimeProviding,
         keys: any IdempotencyKeyProviding, invalidation: FeatureInvalidationCenter,
         isSessionActive: @escaping @MainActor @Sendable () -> Bool) {
        self.provider = provider; self.time = time; self.keys = keys
        self.invalidation = invalidation; self.isSessionActive = isSessionActive
    }

    func model(id: String) -> MealRecordModel {
        if let model = models[id] { return model }
        let model = MealRecordModel(recordID: id, provider: provider, time: time,
            keys: keys, invalidation: invalidation, isSessionActive: isSessionActive)
        models[id] = model
        return model
    }

    func endSession() {
        for model in models.values { model.endSession() }
        models.removeAll()
    }
}
