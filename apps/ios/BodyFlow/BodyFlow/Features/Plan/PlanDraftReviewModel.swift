import Foundation
import Observation

enum PlanDraftReviewPhase: Equatable, Sendable {
    case loading
    /// The document is still being read, or the proposal generated.
    case inProgress
    case review
    case confirmed
    case discarded
    /// The draft ended without content (reading failed, expired…).
    case closed(PlanDraftStatus, failureCode: String?)
    case failed(PlanDraftFailure)
}

/// The review of one draft: read, edit, save, confirm or discard. Confirming
/// sends the version on screen, and only when nothing typed is unsaved — what
/// becomes the plan is exactly what the patient saw.
@MainActor
@Observable
final class PlanDraftReviewModel {
    let draftID: String

    private let provider: any PlanDraftProviding
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private let planChanged: @MainActor () -> Void
    private let clock: any Clock<Duration>
    private let pollInterval: Duration
    private let maximumPolls: Int

    private var sequence = 0
    private var edits: [String: String] = [:]
    private var pendingConfirmation: MutationAttempt<PlanDraftConfirmation>?

    private(set) var phase = PlanDraftReviewPhase.loading
    private(set) var snapshot: PlanDraftSnapshot?
    private(set) var document: PlanDraftDocument?
    private(set) var isWorking = false
    /// A failure of the last action; the content on screen is kept.
    private(set) var actionFailure: PlanDraftFailure?

    init(
        draftID: String,
        provider: any PlanDraftProviding,
        timeProvider: any TimeProviding,
        keyProvider: any IdempotencyKeyProviding,
        planChanged: @escaping @MainActor () -> Void = {},
        clock: any Clock<Duration> = ContinuousClock(),
        pollInterval: Duration = .seconds(2),
        maximumPolls: Int = 90
    ) {
        self.draftID = draftID
        self.provider = provider
        self.timeProvider = timeProvider
        self.keyProvider = keyProvider
        self.planChanged = planChanged
        self.clock = clock
        self.pollInterval = pollInterval
        self.maximumPolls = maximumPolls
    }

    var hasUnsavedChanges: Bool { !edits.isEmpty }

    func hasInvalidEdits(language: SupportedAppLanguage) -> Bool {
        guard let document else { return false }
        return fields(of: document).contains { field in
            guard let text = edits[field.pointer] else { return false }
            return PlanDraftDocument.value(for: text, of: field, language: language) == nil
        }
    }

    func canSave(language: SupportedAppLanguage) -> Bool {
        phase == .review && !isWorking && hasUnsavedChanges
            && !hasInvalidEdits(language: language)
    }

    /// Only a complete draft, exactly as shown, can be confirmed: nothing
    /// typed and unsaved, something to confirm, and nothing the screen
    /// could not show.
    var canConfirm: Bool {
        phase == .review && !isWorking && !hasUnsavedChanges
            && snapshot?.canConfirm == true
            && document?.isEmpty == false
            && document?.hasUnreadableContent == false
    }

    /// The reload found the draft changed on the server and what the patient
    /// had typed was dropped; the screen says so.
    private(set) var droppedEdits = false

    var canDiscard: Bool {
        !isWorking && (phase == .review || phase == .inProgress)
    }

    func text(of field: PlanDraftDocument.Field, language: SupportedAppLanguage) -> String {
        edits[field.pointer] ?? document?.text(of: field, language: language) ?? ""
    }

    func setText(
        _ text: String,
        of field: PlanDraftDocument.Field,
        language: SupportedAppLanguage
    ) {
        guard phase == .review, !isWorking, let document else { return }
        if text == document.text(of: field, language: language) {
            edits[field.pointer] = nil
        } else {
            edits[field.pointer] = text
        }
        actionFailure = nil
        droppedEdits = false
    }

    /// Why the server asked to look at a field; nil once the patient typed
    /// something there (the next save re-evaluates it).
    func uncertainty(of field: PlanDraftDocument.Field) -> String? {
        guard edits[field.pointer] == nil else { return nil }
        return snapshot?.uncertainFields.first { $0.pointer == field.pointer }?.reason
    }

    /// Why the server flagged a whole item (a medication, a dose or a
    /// supplement): the item keeps its name and says why it was flagged.
    func uncertainty(ofRow row: PlanDraftDocument.Row) -> String? {
        snapshot?.uncertainFields.first { $0.pointer == row.id }?.reason
    }

    func isInvalid(_ field: PlanDraftDocument.Field, language: SupportedAppLanguage) -> Bool {
        guard let text = edits[field.pointer] else { return false }
        return PlanDraftDocument.value(for: text, of: field, language: language) == nil
    }

    func load() async {
        // The screen came back (another tab was visited) with something
        // typed and not saved: what the patient typed stays as it is.
        if phase == .review, hasUnsavedChanges { return }
        sequence += 1
        let current = sequence
        if snapshot == nil { phase = .loading }
        actionFailure = nil
        do {
            var polls = 0
            while true {
                let loaded = try await provider.draft(id: draftID)
                guard sequence == current, !Task.isCancelled else { return }
                publish(loaded, keepingEdits: false)
                guard loaded.state.isInProgress else { return }
                polls += 1
                guard polls < maximumPolls else {
                    phase = .failed(.unavailable)
                    return
                }
                try await clock.sleep(for: pollInterval)
                guard sequence == current, !Task.isCancelled else { return }
            }
        } catch is CancellationError {
            return
        } catch {
            guard sequence == current else { return }
            phase = .failed(PlanDraftFailure(error))
        }
    }

    /// Removes one exercise, item, day or meal from the content on screen.
    /// Edits typed below it would point elsewhere, so they are saved first.
    func remove(_ path: PlanDraftDocument.Path, language: SupportedAppLanguage) async {
        guard phase == .review, !isWorking, !hasInvalidEdits(language: language),
              var changed = editedDocument(language: language)
        else {
            return
        }
        changed.remove(at: path)
        await send(changed)
    }

    func save(language: SupportedAppLanguage) async {
        guard canSave(language: language), let changed = editedDocument(language: language)
        else {
            return
        }
        await send(changed)
    }

    func confirm() async {
        guard canConfirm, let snapshot else { return }
        await perform {
            // A retry of the same confirmation repeats the same request.
            let attempt: MutationAttempt<PlanDraftConfirmation>
            let payload = PlanDraftConfirmation(
                draftID: draftID,
                payloadVersion: snapshot.payloadVersion
            )
            if let pending = pendingConfirmation, pending.payload == payload {
                attempt = pending
            } else {
                attempt = try makeAttempt(.planDraftConfirm, payload: payload)
                pendingConfirmation = attempt
            }
            let confirmed = try await provider.confirm(attempt)
            pendingConfirmation = nil
            publish(confirmed, keepingEdits: false)
            planChanged()
        }
    }

    func discard() async {
        guard canDiscard else { return }
        await perform {
            let discarded = try await provider.discard(
                try makeAttempt(.planDraftDiscard, payload: PlanDraftCommand(draftID: draftID))
            )
            publish(discarded, keepingEdits: false)
        }
    }

    func invalidate() {
        sequence += 1
        isWorking = false
    }

    private func send(_ changed: PlanDraftDocument) async {
        guard let snapshot else { return }
        await perform {
            let updated = try await provider.update(try makeAttempt(
                .planDraftEdit,
                payload: PlanDraftEdit(
                    draftID: draftID,
                    payloadVersion: snapshot.payloadVersion,
                    payload: changed.root
                )
            ))
            publish(updated, keepingEdits: false)
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        sequence += 1
        let current = sequence
        isWorking = true
        actionFailure = nil
        defer { if sequence == current { isWorking = false } }
        do {
            try await action()
        } catch is CancellationError {
            return
        } catch {
            guard sequence == current else { return }
            let failure = PlanDraftFailure(error)
            actionFailure = failure
            // The draft on screen is no longer the one on the server.
            if failure == .draftChanged || failure == .notReviewable || failure == .expired {
                pendingConfirmation = nil
                if let reloaded = try? await provider.draft(id: draftID), sequence == current {
                    let hadEdits = hasUnsavedChanges
                    publish(reloaded, keepingEdits: false)
                    actionFailure = failure
                    droppedEdits = hadEdits
                }
            }
        }
    }

    private func publish(_ loaded: PlanDraftSnapshot, keepingEdits: Bool) {
        snapshot = loaded
        document = PlanDraftDocument(domain: loaded.domain, payload: loaded.payload)
        if !keepingEdits { edits = [:] }
        switch loaded.state {
        case .extracting, .generating:
            phase = .inProgress
        case .needsCompletion, .readyForReview:
            phase = .review
        case .confirmed:
            phase = .confirmed
        case .discarded:
            phase = .discarded
        case .expired, .failed, .unknown:
            phase = .closed(loaded.state, failureCode: loaded.failureCode)
        }
    }

    private func editedDocument(language: SupportedAppLanguage) -> PlanDraftDocument? {
        guard var changed = document else { return nil }
        for field in fields(of: changed) {
            guard let text = edits[field.pointer] else { continue }
            guard let value = PlanDraftDocument.value(for: text, of: field, language: language)
            else {
                return nil
            }
            changed.set(value, at: field.path)
            if field.key == "quantity_g" { clearQuantityDependents(of: field, in: &changed) }
        }
        return changed
    }

    /// The calories and macros of an item belonged to its old quantity: with
    /// a new one they are cleared (and so are the meal's totals), never kept
    /// and never recalculated here.
    private func clearQuantityDependents(
        of field: PlanDraftDocument.Field,
        in document: inout PlanDraftDocument
    ) {
        let item = Array(field.path.dropLast())
        for key in PlanDraftDocument.quantityDependentKeys
        where document.value(at: item + [.key(key)]) != nil {
            document.set(.null, at: item + [.key(key)])
        }
        let meal = Array(item.dropLast(2))
        for key in PlanDraftDocument.quantityDependentTotals
        where document.value(at: meal + [.key(key)]) != nil {
            document.set(.null, at: meal + [.key(key)])
        }
    }

    private func fields(of document: PlanDraftDocument) -> [PlanDraftDocument.Field] {
        document.sections.flatMap { $0.fields + $0.rows.flatMap(\.fields) }
    }

    private func makeAttempt<Payload: Hashable & Sendable>(
        _ operation: MutationOperation,
        payload: Payload
    ) throws -> MutationAttempt<Payload> {
        do {
            return MutationAttempt(
                operation: operation,
                key: try keyProvider.nextKey(),
                payload: payload,
                createdAt: timeProvider.now
            )
        } catch {
            throw PlanDraftFailure.unavailable
        }
    }
}
