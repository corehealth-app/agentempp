import Foundation
import Observation

/// An official documents-only presentation; never a replacement signup draft.
struct OnboardingLegacyDocumentsPresentation: Equatable, Sendable {
    let locale: String
    let requirements: OnboardingRequirements
    let acceptedActions: [OnboardingDocumentAction]

    init(state: OnboardingServerState) throws {
        guard state.legacyReconsent == .documentsOnly, !state.completion.completed, state.draft == nil,
              state.requirements.available,
              state.requirements.documents.allSatisfy({ $0.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false })
        else { throw OnboardingRepositoryError.documentsUnavailable }
        let current = try OnboardingLegacyDocumentInput(locale: state.locale,
            actions: state.requirements.documents.map(\.explicitAction))
        locale = state.locale
        requirements = state.requirements
        let recorded = Set(state.acceptedActions.map {
            OnboardingDocumentAction(documentKey: $0.documentKey, version: $0.version, locale: $0.locale,
                contentHash: $0.contentHash, action: $0.action)
        })
        acceptedActions = current.documentActions.filter(recorded.contains)
    }
}

@MainActor @Observable
final class LegacyReconsentModel {
    struct Pending: Equatable, Sendable {
        let input: OnboardingLegacyDocumentInput
        let key: IdempotencyKey
    }
    let ownerToken: OnboardingOwnerToken
    let presentation: OnboardingLegacyDocumentsPresentation
    private(set) var selectedActions: Set<OnboardingDocumentAction>
    private(set) var pending: Pending?
    private(set) var acknowledgement: OnboardingLegacyDocumentAcknowledgement?
    private(set) var isBusy = false
    private(set) var isActive = true
    private(set) var hasError = false
    @ObservationIgnored private let repository: any OnboardingRepository
    @ObservationIgnored private let keys: any IdempotencyKeyProviding
    @ObservationIgnored private let isCurrentOwner: @MainActor (OnboardingOwnerToken) -> Bool
    @ObservationIgnored private let onReconcile: @MainActor () -> Void
    @ObservationIgnored private var attemptID: UUID?
    @ObservationIgnored private var requestedReconciliation = false

    init(ownerToken: OnboardingOwnerToken, presentation: OnboardingLegacyDocumentsPresentation,
         repository: any OnboardingRepository,
         keys: any IdempotencyKeyProviding = RandomIdempotencyKeyProvider(),
         isCurrentOwner: @escaping @MainActor (OnboardingOwnerToken) -> Bool,
         onReconcile: @escaping @MainActor () -> Void) {
        self.ownerToken = ownerToken; self.presentation = presentation
        self.repository = repository; self.keys = keys
        self.isCurrentOwner = isCurrentOwner; self.onReconcile = onReconcile
        selectedActions = Set(presentation.acceptedActions)
    }

    var allowsEditing: Bool { ownsPresentation && pending == nil && acknowledgement == nil && !isBusy && !requestedReconciliation }
    var canSubmit: Bool {
        guard ownsPresentation, !isBusy, acknowledgement == nil, !requestedReconciliation else { return false }
        if pending != nil { return true }
        let required = Set(presentation.requirements.documents.filter(\.required).map(\.explicitAction))
        return required.isSubset(of: selectedActions) && !selectedActions.isEmpty
    }
    private var ownsPresentation: Bool { isActive && isCurrentOwner(ownerToken) }

    func update(_ action: OnboardingDocumentAction, selected: Bool) {
        guard allowsEditing, !presentation.acceptedActions.contains(action),
              presentation.requirements.documents.contains(where: { $0.explicitAction == action }) else { return }
        if selected { selectedActions.insert(action) } else { selectedActions.remove(action) }
        hasError = false
    }

    func invalidate() {
        isActive = false; attemptID = nil; isBusy = false
        // The retired instance cannot grant a returned account any authority.
        selectedActions = []; pending = nil
    }

    func submit() async {
        guard !Task.isCancelled, canSubmit else { return }
        if pending == nil {
            do {
                let input = try OnboardingLegacyDocumentInput(locale: presentation.locale,
                    actions: presentation.requirements.documents.map(\.explicitAction).filter(selectedActions.contains))
                let key = try keys.nextKey()
                guard UUID(uuidString: key.value) != nil else { throw OnboardingRepositoryError.invalidDraft }
                pending = Pending(input: input, key: key)
            } catch { hasError = true; return }
        }
        guard let original = pending else { return }
        let attempt = UUID(); attemptID = attempt; isBusy = true; hasError = false
        do {
            let ack = try await repository.acceptLegacyDocuments(original.input, for: ownerToken.userID, key: original.key)
            guard ownsPresentation, attemptID == attempt else { return }
            try Task.checkCancellation()
            guard ack.matches(original.input, key: original.key) else { throw OnboardingRepositoryError.serviceUnavailable }
            acknowledgement = ack
            isBusy = false; attemptID = nil
            reconcileOnce()
        } catch {
            guard ownsPresentation, attemptID == attempt else { return }
            isBusy = false; attemptID = nil
            if error as? OnboardingRepositoryError == .requirementsChanged {
                reconcileOnce()
            } else {
                // Even cancellation/timeout can follow a committed command.
                // Retain the exact original input/key and block any edits.
                hasError = true
            }
        }
    }

    private func reconcileOnce() {
        guard ownsPresentation, !requestedReconciliation else { return }
        requestedReconciliation = true
        // Root owns the new GET. It may synchronously retire this model.
        onReconcile()
    }
}
