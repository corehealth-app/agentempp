import Foundation
import Testing

@testable import BodyFlow

@Suite("Typed feature states")
struct FeatureReadStateTests {
    @Test("idle has no visible state or content")
    func idle() {
        let presentation = FeatureReadState<String>.idle.presentation

        #expect(presentation.value == nil)
        #expect(presentation.fullScreenState == nil)
        #expect(!presentation.showsStaleBanner)
    }

    @Test("loading maps to the full loading state")
    func loading() {
        let presentation = FeatureReadState<String>.loading.presentation

        #expect(presentation.value == nil)
        #expect(presentation.fullScreenState == .loading)
        #expect(!presentation.showsStaleBanner)
    }

    @Test("loaded preserves the exact content")
    func loaded() {
        let exactValue = ReadFixture(id: "loaded-value", count: 11)
        let presentation = FeatureReadState<ReadFixture>
            .loaded(exactValue)
            .presentation

        #expect(presentation.value == exactValue)
        #expect(presentation.fullScreenState == nil)
        #expect(!presentation.showsStaleBanner)
    }

    @Test("empty maps to the full empty state without inventing content")
    func empty() {
        let presentation = FeatureReadState<String>.empty.presentation

        #expect(presentation.value == nil)
        #expect(presentation.fullScreenState == .empty)
        #expect(!presentation.showsStaleBanner)
    }

    @Test("initial offline uses the full offline state with Retry")
    func initialOffline() {
        let presentation = FeatureReadState<String>
            .offline(previousValue: nil)
            .presentation

        #expect(presentation.value == nil)
        #expect(presentation.fullScreenState == .offline)
        #expect(presentation.fullScreenState?.descriptor.showsRetry == true)
        #expect(!presentation.showsStaleBanner)
    }

    @Test("initial error uses the full error state with Retry")
    func initialError() {
        let presentation = FeatureReadState<String>
            .failed(previousValue: nil, error: .serviceUnavailable)
            .presentation

        #expect(presentation.value == nil)
        #expect(presentation.fullScreenState == .recoverableError)
        #expect(presentation.fullScreenState?.descriptor.showsRetry == true)
        #expect(!presentation.showsStaleBanner)
    }

    @Test("offline after content preserves the exact value and shows a stale banner")
    func staleOffline() {
        let exactValue = ReadFixture(id: "server-value", count: 17)
        let presentation = FeatureReadState<ReadFixture>
            .offline(previousValue: exactValue)
            .presentation

        #expect(presentation.value == exactValue)
        #expect(presentation.fullScreenState == nil)
        #expect(presentation.showsStaleBanner)
    }

    @Test("error after content preserves the exact value and shows a stale banner")
    func staleError() {
        let exactValue = ReadFixture(id: "unchanged-value", count: 29)
        let presentation = FeatureReadState<ReadFixture>
            .failed(previousValue: exactValue, error: .invalidInput)
            .presentation

        #expect(presentation.value == exactValue)
        #expect(presentation.fullScreenState == nil)
        #expect(presentation.showsStaleBanner)
    }

    @Test("unavailable uses the exact copy without Retry")
    func unavailable() {
        let presentation = FeatureReadState<String>.unavailable.presentation
        let descriptor = presentation.fullScreenState?.descriptor

        #expect(presentation.value == nil)
        #expect(descriptor?.title == "Indisponível nesta versão")
        #expect(descriptor?.showsRetry == false)
        #expect(!presentation.showsStaleBanner)
    }

    @Test(arguments: [
        (ScreenState.loading, "state.loading"),
        (ScreenState.empty, "state.empty"),
        (ScreenState.offline, "state.offline"),
        (ScreenState.recoverableError, "state.error"),
        (ScreenState.unavailable, "state.unavailable"),
    ])
    func screenStatesExposeStableIdentifiers(
        state: ScreenState,
        identifier: String
    ) {
        #expect(state.accessibilityIdentifier == identifier)
    }

    @Test(arguments: [
        BodyFlowCapabilityError.operationUnavailable,
        .offline,
        .serviceUnavailable,
        .invalidInput,
        .idempotencyConflict,
        .registrationNotPending,
        .registrationExpired,
        .routineTransitionInvalid,
        .routineSnoozeInvalid,
        .invalidIdempotencyKey,
    ])
    func readFailureRetainsTypedCapabilityError(
        error: BodyFlowCapabilityError
    ) {
        let state = FeatureReadState<String>.failed(
            previousValue: "exact-previous-value",
            error: error
        )

        guard case let .failed(previousValue, retainedError) = state else {
            Issue.record("Expected a typed failed read state")
            return
        }

        #expect(previousValue == "exact-previous-value")
        #expect(retainedError == error)
        #expect(state == .failed(
            previousValue: "exact-previous-value",
            error: error
        ))
    }

    @Test("mutation failure retains its exact attempt and has no receipt")
    func mutationFailureRetainsAttempt() {
        let attempt = MutationFixture(id: "attempt-0001", value: 250)
        let state = FeatureMutationState<MutationFixture, String>
            .failed(attempt, .serviceUnavailable)

        #expect(state.attempt == attempt)
        #expect(state.receipt == nil)
        #expect(state == .failed(attempt, .serviceUnavailable))
    }

    @Test("mutation cases expose exact attempt receipt and unavailable values")
    func mutationCasesMatchStableInterface() {
        typealias State = FeatureMutationState<MutationFixture, String>
        let attempt = MutationFixture(id: "attempt-0002", value: 500)
        let submitting = State.submitting(attempt)
        let succeeded = State.succeeded("receipt-0002")
        let unavailable = State.unavailable

        #expect(submitting.attempt == attempt)
        #expect(submitting.receipt == nil)
        #expect(succeeded.attempt == nil)
        #expect(succeeded.receipt == "receipt-0002")
        #expect(unavailable.attempt == nil)
        #expect(unavailable.receipt == nil)
        #expect(submitting == .submitting(attempt))
        #expect(succeeded == .succeeded("receipt-0002"))
        #expect(unavailable == .unavailable)
    }

    @Test("registration mutation attempts keep all four concrete attempts")
    func registrationMutationAttempts() throws {
        let createdAt = Date(timeIntervalSince1970: 1_785_283_200)
        let proposal = BodyFlowTestFixtures.registrationProposal
        let edit = BodyFlowTestFixtures.registrationEdit
        let registrationID = BodyFlowTestFixtures.registrationID
        let createAttempt = MutationAttempt(
            operation: .proposalCreate,
            key: try IdempotencyKey(validating: "registration-create-0001"),
            payload: proposal,
            createdAt: createdAt
        )
        let editAttempt = MutationAttempt(
            operation: .proposalEdit,
            key: try IdempotencyKey(validating: "registration-edit-0001"),
            payload: edit,
            createdAt: createdAt
        )
        let confirmAttempt = MutationAttempt(
            operation: .proposalConfirm,
            key: try IdempotencyKey(validating: "registration-confirm-0001"),
            payload: registrationID,
            createdAt: createdAt
        )
        let cancelAttempt = MutationAttempt(
            operation: .proposalCancel,
            key: try IdempotencyKey(validating: "registration-cancel-0001"),
            payload: registrationID,
            createdAt: createdAt
        )

        let attempts = [
            RegistrationMutationAttempt.propose(createAttempt),
            .edit(editAttempt),
            .confirm(confirmAttempt),
            .cancel(cancelAttempt),
        ]

        #expect(attempts.map(\.operation) == [
            .proposalCreate,
            .proposalEdit,
            .proposalConfirm,
            .proposalCancel,
        ])
    }

    @Test("registration mutation receipts keep all four concrete receipts")
    func registrationMutationReceipts() throws {
        let proposal = try JSONDecoder().decode(
            RegistrationProposalResponse.self,
            from: Data(Self.proposalResponseJSON.utf8)
        )
        let confirmation = try JSONDecoder().decode(
            RegistrationConfirmationResponse.self,
            from: Data(Self.confirmationResponseJSON.utf8)
        )
        let receipts = [
            RegistrationMutationReceipt.propose(proposal),
            .edit(proposal),
            .confirm(confirmation),
            .cancel(proposal),
        ]

        #expect(receipts.map(\.requestID) == [
            "proposal-request",
            "proposal-request",
            "confirmation-request",
            "proposal-request",
        ])
    }

    private static let proposalResponseJSON = """
    {
      "data": {
        "id": "registration-0001",
        "status": "proposed",
        "created_at": "2026-07-22T12:00:00.000Z",
        "expires_at": "2026-07-22T12:30:00.000Z",
        "resolved_at": null,
        "proposal": {"kind": "unknown"}
      },
      "meta": {"api_version": "v1", "request_id": "proposal-request"}
    }
    """

    private static let confirmationResponseJSON = """
    {
      "data": {
        "id": "registration-0001",
        "status": "confirmed",
        "created_at": "2026-07-22T12:00:00.000Z",
        "expires_at": "2026-07-22T12:30:00.000Z",
        "resolved_at": "2026-07-22T12:05:00.000Z",
        "proposal": {"kind": "unknown"},
        "already_confirmed": false,
        "deduped": false
      },
      "meta": {"api_version": "v1", "request_id": "confirmation-request"}
    }
    """
}

private struct ReadFixture: Equatable, Sendable {
    let id: String
    let count: Int
}

private struct MutationFixture: Equatable, Sendable {
    let id: String
    let value: Int
}
