import Foundation
import Observation

/// One model per original authenticated shell. Uncertain writes retain their
/// exact intention/key; re-entry cannot silently choose another operation.
@MainActor @Observable
final class ClinicalFirstPhaseModel {
    private struct Prepare { let phase: BodyFlowObjective; let key: IdempotencyKey }
    private struct Confirm { let preview: ClinicalFirstPhasePreview; let key: IdempotencyKey }
    let userID: String
    private let source: any ClinicalFirstPhaseProviding
    private let keyProvider: any IdempotencyKeyProviding
    private var provider: (any ClinicalFirstPhaseProviding)?
    private var pendingPrepare: Prepare?
    private var pendingConfirm: Confirm?
    private var ended = false
    private(set) var choices: ClinicalFirstPhaseChoices?
    private(set) var preview: ClinicalFirstPhasePreview?
    private(set) var confirmation: ClinicalFirstPhaseConfirmation?
    private(set) var error: ClinicalFirstPhaseFailure?
    private(set) var isBusy = false
    var hasPendingConfirmation: Bool { pendingConfirm != nil && confirmation == nil }
    init(userID: String, provider: any ClinicalFirstPhaseProviding, keyProvider: any IdempotencyKeyProviding) {
        self.userID = userID; source = provider; self.keyProvider = keyProvider
    }
    private func scoped() async throws -> any ClinicalFirstPhaseProviding {
        if let provider { return provider }
        let bound = try await source.scoped(for: userID)
        try Task.checkCancellation(); guard !ended else { throw CancellationError() }
        provider = bound; return bound
    }
    func load() async {
        guard !ended, !isBusy, !hasPendingConfirmation, confirmation == nil else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let provider = try await scoped(), value = try await provider.choices().validated()
            try Task.checkCancellation()
            try await provider.publish { [self] in guard !ended else { throw CancellationError() }; choices = value }
        } catch { await failed(error) }
    }
    func prepare(_ phase: BodyFlowObjective) async {
        guard !ended, !isBusy, !hasPendingConfirmation, confirmation == nil,
              choices?.availability == .available, choices?.options.contains(where: { $0.phase == phase && $0.status == .available }) == true else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            if pendingPrepare?.phase != phase { pendingPrepare = Prepare(phase: phase, key: try keyProvider.nextKey()) }
            guard let attempt = pendingPrepare else { return }
            let provider = try await scoped(), value = try await provider.prepare(phase: attempt.phase, key: attempt.key).validated()
            guard value.phase == attempt.phase else { throw ClinicalFirstPhaseFailure.invalidResponse }
            try Task.checkCancellation()
            try await provider.publish { [self] in guard !ended else { throw CancellationError() }; preview = value }
        } catch { await failed(error) }
    }
    func confirm() async {
        guard !ended, !isBusy, confirmation == nil, let preview else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            if pendingConfirm == nil { pendingConfirm = Confirm(preview: preview, key: try keyProvider.nextKey()) }
            guard let attempt = pendingConfirm else { return }
            let provider = try await scoped(), value = try await provider.confirm(preview: attempt.preview, key: attempt.key).validated()
            guard value.confirmationID == attempt.preview.previewID, value.phase == attempt.preview.phase,
                  value.effectiveDate == attempt.preview.effectiveDate else { throw ClinicalFirstPhaseFailure.invalidResponse }
            try Task.checkCancellation()
            try await provider.publish { [self] in guard !ended else { throw CancellationError() }; confirmation = value; pendingConfirm = nil }
        } catch { await failed(error) }
    }
    func backToChoices() {
        guard !ended, !isBusy, !hasPendingConfirmation, confirmation == nil else { return }
        preview = nil; pendingPrepare = nil; error = nil
    }
    func invalidate() {
        ended = true; choices = nil; preview = nil; confirmation = nil; error = nil
        pendingPrepare = nil; pendingConfirm = nil; provider = nil
    }
    private func failed(_ failure: any Error) async {
        if failure is CancellationError || ended || Task.isCancelled { return }
        if failure as? ClinicalFirstPhaseFailure == .sessionEnded || failure is SessionLifecycleError { invalidate(); return }
        guard let provider else { error = failure as? ClinicalFirstPhaseFailure ?? .unavailable; return }
        do {
            try await provider.publish { [self] in
                guard !ended else { throw CancellationError() }
                error = failure as? ClinicalFirstPhaseFailure ?? .unavailable
                if error == .changed { preview = nil; pendingPrepare = nil; pendingConfirm = nil; choices = nil }
            }
        } catch { invalidate() }
    }
}
