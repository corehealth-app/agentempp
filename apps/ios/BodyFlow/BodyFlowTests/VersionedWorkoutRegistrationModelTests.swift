import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Versioned workout registration model")
struct VersionedWorkoutRegistrationModelTests {
    @Test("new proposals select only the injected protocol; the default stays legacy", arguments: [false, true])
    func explicitProtocolIsFrozenInTheAttempt(versioned: Bool) async throws {
        let response = try Self.response(revision: versioned ? 0 : nil)
        let h = try Self.harness(propose: [.success(response)], selection: versioned ? .uiV1 : nil)
        await h.model.submit(Self.authored)
        let attempt = try #require(await h.service.proposals.first)
        guard case let .workout(request) = attempt.payload else {
            Issue.record("Expected the authored workout")
            return
        }
        Self.expectFields(request, equalTo: Self.authored)
        #expect(request.registrationProtocol == (versioned ? .uiV1 : nil))
        #expect(attempt.key == Self.key(1))
        #expect(attempt.createdAt == Self.now)
        #expect(h.model.currentProposal == response.data)
        #expect(h.model.allowsPendingActions)
    }

    @Test("PROPOSE retry retains protocol, UUID, all authored fields and creation time")
    func proposalRetryIsTheSameAttempt() async throws {
        let h = try Self.harness(propose: [.failure(.offline), .success(Self.response())])
        await h.model.submit(Self.authored)
        let retained = try #require(h.model.retainedFailedAttempt)
        guard case let .propose(attempt) = retained else {
            Issue.record("Expected a retained proposal")
            return
        }
        await h.model.retry()
        #expect(await h.service.proposals == [attempt, attempt])
        guard case let .workout(request) = attempt.payload else { Issue.record("Expected workout"); return }
        #expect(request.registrationProtocol == .uiV1)
        Self.expectFields(request, equalTo: Self.authored)
        #expect(attempt.key == Self.key(1))
        #expect(attempt.createdAt == Self.now)
        #expect(await h.service.calls == [.propose, .propose])
    }

    @Test("EDIT retry freezes reviewed revision zero and the complete original attempt")
    func editRetryDoesNotRebase() async throws {
        let edited = try Self.response(revision: 1, receiptKey: Self.sqlKey(2), type: "Remo indoor", duration: 61, intensity: "leve")
        let h = try Self.harness(edit: [.failure(.offline), .success(edited)])
        await h.model.submit(Self.authored)
        await h.model.saveEdit(Self.edited)
        guard case let .edit(attempt) = try #require(h.model.retainedFailedAttempt) else {
            Issue.record("Expected a retained edit")
            return
        }
        #expect(attempt.payload.workoutVersion?.contentRevision == 0)
        #expect(attempt.key == Self.key(2))
        #expect(attempt.createdAt == Self.now)
        guard case let .workout(request) = attempt.payload.proposal else { Issue.record("Expected workout"); return }
        Self.expectFields(request, equalTo: Self.edited)
        await h.model.retry()
        #expect(await h.service.edits == [attempt, attempt])
        #expect(h.model.currentProposal == edited.data)
        #expect(h.model.mutationState == .succeeded(.edit(edited)))
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
    }

    @Test("CONFIRM retry reuses revision zero and UUID instead of confirming another snapshot")
    func confirmationRetryIsTheSameAttempt() async throws {
        let confirmed = try Self.confirmation()
        let h = try Self.harness(confirm: [.failure(.offline), .success(confirmed)])
        await h.model.submit(Self.authored)
        await h.model.confirm()
        guard case let .confirm(attempt) = try #require(h.model.retainedFailedAttempt) else {
            Issue.record("Expected a retained confirmation")
            return
        }
        #expect(attempt.payload.workoutVersion?.contentRevision == 0)
        #expect(attempt.key == Self.key(2))
        await h.model.retry()
        #expect(await h.service.confirmations == [attempt, attempt])
        #expect(h.model.phase == .confirmed)
        #expect(h.model.confirmedRegistration == confirmed.data.registration)
    }

    @Test("CANCEL freezes the reviewed version with its own UUID")
    func cancellationCapturesTheReviewedVersion() async throws {
        let cancelled = try Self.response(status: "cancelled")
        let h = try Self.harness(cancel: [.success(cancelled)])
        await h.model.submit(Self.authored)
        await h.model.cancel()
        let attempt = try #require(await h.service.cancellations.first)
        #expect(attempt.payload.registrationID == Self.id)
        #expect(attempt.payload.workoutVersion?.contentRevision == 0)
        #expect(attempt.key == Self.key(2))
        #expect(h.model.phase == .cancelled)
    }

    @Test("revision conflict retains all four draft fields and blocks mutations without automatic GET", arguments: [Mutation.edit, .confirm, .cancel])
    func revisionConflictRequiresExplicitReview(operation: Mutation) async throws {
        let h = try await Self.conflicted(operation: operation)
        let retained = try #require(h.model.retainedFailedAttempt)
        #expect(h.model.requiresCurrentReview)
        #expect(!h.model.isBusy)
        #expect(!h.model.allowsPendingActions)
        #expect(h.model.captureError == .registrationRevisionConflict)
        #expect(try h.model.currentProposal == Self.response().data)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: operation == .edit ? Self.edited : Self.authored)
        let before = await h.service.calls
        await h.model.saveEdit(Self.edited)
        await h.model.confirm()
        await h.model.cancel()
        #expect(await h.service.calls == before)
        #expect(await h.service.reads.isEmpty)
        #expect(h.model.retainedFailedAttempt == retained)
    }

    @Test("review-required conflicts cannot trigger a blind mutable retry")
    func reviewRequiredDoesNotResendTheEdit() async throws {
        let h = try await Self.conflicted(error: .registrationReviewRequired)
        let retained = try #require(h.model.retainedFailedAttempt)
        #expect(h.model.requiresCurrentReview)
        #expect(!h.model.allowsPendingActions)
        #expect(h.model.captureError == .registrationReviewRequired)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        // No automatic read occurs merely because the mutation failed.
        #expect(await h.service.calls == [.propose, .edit])
        #expect(h.model.retainedFailedAttempt == retained)
    }

    @Test("ui-v1 already-confirmed EDIT/CANCEL preserves work and requires GET instead of legacy fake success", arguments: [Mutation.edit, .cancel])
    func alreadyConfirmedIsReviewForVersionedMutations(operation: Mutation) async throws {
        let current = try Self.response(revision: 2, status: "confirmed")
        let h = try await Self.conflicted(operation: operation, error: .registrationAlreadyConfirmed, reads: [.success(current)])
        let retained = try #require(h.model.retainedFailedAttempt)
        #expect(h.model.captureError == .registrationReviewRequired)
        #expect(h.model.requiresCurrentReview)
        #expect(h.model.phase == .proposal)
        #expect(h.model.mutationState.receipt == nil)
        #expect(h.model.confirmedRegistration == nil)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: operation == .edit ? Self.edited : Self.authored)
        #expect(await h.service.reads.isEmpty)
        await h.model.reviewCurrentVersion()
        #expect(h.model.mutationState == .succeeded(.workoutCurrent(current)))
        #expect(h.model.phase == .confirmed)
        #expect(h.model.retainedFailedAttempt == retained)
        #expect(h.model.mutationState.receipt?.confirmedRegistrationID == nil)
    }

    @Test("GET failure retries only GET; success keeps draft and old attempt, and a new edit selects visible revision2")
    func recoveryReadDoesNotRewriteTheFailedAttempt() async throws {
        let current = try Self.response(revision: 2, type: "Bike", duration: 75, intensity: "moderada")
        let newEdit = try Self.response(revision: 3, receiptKey: Self.sqlKey(3), receiptExpected: 2, type: "Remo indoor", duration: 61, intensity: "leve")
        let h = try Self.harness(edit: [.failure(.registrationRevisionConflict), .success(newEdit)], reads: [.failure(.offline), .success(current)])
        await h.model.submit(Self.authored)
        await h.model.saveEdit(Self.edited)
        let failed = try #require(h.model.retainedFailedAttempt)
        await h.model.reviewCurrentVersion()
        #expect(h.model.requiresCurrentReview)
        #expect(h.model.captureError == .offline)
        #expect(try h.model.currentProposal == Self.response().data)
        #expect(h.model.retainedFailedAttempt == failed)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        await h.model.retry()
        #expect(await h.service.calls == [.propose, .edit, .read, .read])
        #expect(await h.service.reads == [Self.id, Self.id])
        #expect(h.model.mutationState == .succeeded(.workoutCurrent(current)))
        #expect(!h.model.requiresCurrentReview)
        #expect(h.model.currentProposal == current.data)
        #expect(h.model.retainedFailedAttempt == failed)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        await h.model.retry()
        #expect(await h.service.calls == [.propose, .edit, .read, .read])
        await h.model.saveEdit(Self.edited)
        let attempts = await h.service.edits
        #expect(attempts.count == 2)
        #expect(attempts[0].payload.workoutVersion?.contentRevision == 0)
        #expect(attempts[1].payload.workoutVersion?.contentRevision == 2)
        #expect(attempts[0].key == Self.key(2))
        #expect(attempts[1].key == Self.key(3))
        #expect(h.model.currentProposal == newEdit.data)
    }

    @Test("a held review is busy and duplicate taps cannot start another read or mutation")
    func heldReviewIsDeduplicated() async throws {
        let h = try await Self.conflicted(reads: [.hold])
        let task = Task { await h.model.reviewCurrentVersion() }
        await h.service.waitUntilReadHeld()
        #expect(h.model.isReviewingCurrent)
        #expect(h.model.isBusy)
        #expect(!h.model.allowsPendingActions)
        await h.model.reviewCurrentVersion()
        await h.model.retry()
        await h.model.saveEdit(Self.edited)
        await h.model.confirm()
        await h.model.cancel()
        #expect(await h.service.calls == [.propose, .edit, .read])
        try await h.service.finishRead(.success(Self.response(revision: 2)))
        await task.value
        #expect(!h.model.isReviewingCurrent)
        #expect(!h.model.isBusy)
        #expect(h.model.allowsPendingActions)
    }

    @Test("malformed recovery projections preserve old snapshot, draft and failed attempt", arguments: [InvalidProjection.wrongID, .missingVersion, .wrongKind, .unknownStatus])
    func recoveryCannotInventAuthority(invalid: InvalidProjection) async throws {
        let h = try await Self.conflicted(reads: [.success(Self.invalidProjection(invalid))])
        let failed = try #require(h.model.retainedFailedAttempt)
        await h.model.reviewCurrentVersion()
        #expect(h.model.captureError == .serviceUnavailable)
        #expect(h.model.requiresCurrentReview)
        #expect(try h.model.currentProposal == Self.response().data)
        #expect(h.model.retainedFailedAttempt == failed)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        #expect(h.model.mutationState.receipt == nil)
        #expect(await h.service.calls == [.propose, .edit, .read])
    }

    @Test("a provider without the reader cannot fabricate current revision or fall back to a mutation")
    func missingReaderRemainsAReviewFailure() async throws {
        let service = try VersionedModelService(propose: [.success(Self.response())], edit: [.failure(.registrationRevisionConflict)])
        let model = Self.model(provider: MutationOnlyVersionedProvider(base: service), center: FeatureInvalidationCenter())
        await model.submit(Self.authored)
        await model.saveEdit(Self.edited)
        let retained = try #require(model.retainedFailedAttempt)
        await model.reviewCurrentVersion()
        #expect(model.requiresCurrentReview)
        #expect(model.captureError == .serviceUnavailable)
        #expect(model.retainedFailedAttempt == retained)
        Self.expectFields(try #require(model.pendingDraft), equalTo: Self.edited)
        #expect(await service.calls == [.propose, .edit])
    }

    @Test("receipt0/1 with current revision2 is an observation, never an edit reapplied")
    func oldReceiptAndCurrentProjectionStayDistinct() async throws {
        let current = try Self.response(revision: 2, receiptKey: Self.sqlKey(2), type: "Bike", duration: 75)
        let h = try Self.harness(edit: [.success(current)])
        await h.model.submit(Self.authored)
        await h.model.saveEdit(Self.edited)
        #expect(h.model.currentProposal == current.data)
        #expect(h.model.currentProposal?.editReceipt?.expectedRevision == 0)
        #expect(h.model.currentProposal?.editReceipt?.resultRevision == 1)
        #expect(h.model.currentProposal?.workoutVersion?.contentRevision == 2)
        #expect(h.model.mutationState == .succeeded(.workoutCurrent(current)))
        #expect(h.model.mutationState.receipt?.confirmedRegistrationID == nil)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        #expect(h.center.revision(for: .today) == 2)
        #expect(h.center.revision(for: .history) == 0)
    }

    @Test("PROPOSE replay may already return a later pending revision")
    func proposalReplayCanReturnCurrentRevisionTwo() async throws {
        let current = try Self.response(revision: 2, type: "Bike", duration: 75)
        let h = try Self.harness(propose: [.success(current)])
        await h.model.submit(Self.authored)
        #expect(h.model.currentProposal == current.data)
        #expect(h.model.mutationState == .succeeded(.workoutCurrent(current)))
        #expect(h.model.allowsPendingActions)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.authored)
    }

    @Test("terminal PROPOSE/EDIT observations use the official status and never report a mutation just applied", arguments: [TerminalOrigin.propose, .edit], ["confirmed", "cancelled", "expired"])
    func lateTerminalProjectionIsAnObservation(origin: TerminalOrigin, status: String) async throws {
        let current = try Self.response(revision: 2, status: status, receiptKey: origin == .edit ? Self.sqlKey(2) : nil)
        let h = try Self.harness(propose: origin == .propose ? [.success(current)] : nil, edit: origin == .edit ? [.success(current)] : [])
        await h.model.submit(Self.authored)
        if origin == .edit { await h.model.saveEdit(Self.edited) }
        #expect(h.model.mutationState == .succeeded(.workoutCurrent(current)))
        #expect(h.model.mutationState.receipt?.confirmedRegistrationID == nil)
        #expect(!h.model.allowsPendingActions)
        #expect(h.model.phase == (status == "confirmed" ? .confirmed : .proposal))
        if status != "confirmed" {
            #expect(h.model.currentProposal == current.data)
            Self.expectFields(try #require(h.model.pendingDraft), equalTo: origin == .edit ? Self.edited : Self.authored)
        }
        let before = await h.service.calls
        await h.model.confirm()
        await h.model.cancel()
        await h.model.saveEdit(Self.edited)
        #expect(await h.service.calls == before)
    }

    @Test("GET cancelled/expired keeps the official card until explicit prepareNewProposal preserves the draft", arguments: ["cancelled", "expired"])
    func terminalReviewNeedsAnExplicitNewIntention(status: String) async throws {
        let current = try Self.response(revision: 2, status: status)
        let h = try await Self.conflicted(reads: [.success(current)])
        await h.model.reviewCurrentVersion()
        #expect(h.model.currentProposal == current.data)
        #expect(h.model.phase == .proposal)
        #expect(!h.model.allowsPendingActions)
        #expect(h.model.mutationState == .succeeded(.workoutCurrent(current)))
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        h.model.prepareNewProposal()
        #expect(h.model.phase == .form)
        #expect(h.model.currentProposal == nil)
        #expect(h.model.captureError == nil)
        #expect(h.model.mutationState == .idle)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        #expect(await h.service.calls == [.propose, .edit, .read])
    }

    @Test("expired/not-pending errors without a DTO return ui-v1 to the form without losing work", arguments: [BodyFlowCapabilityError.registrationExpired, .registrationNotPending])
    func terminalErrorPreservesTheAuthoredDraft(error: BodyFlowCapabilityError) async throws {
        let h = try Self.harness(edit: [.failure(error)])
        await h.model.submit(Self.authored)
        await h.model.saveEdit(Self.edited)
        #expect(h.model.phase == .form)
        #expect(h.model.currentProposal == nil)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        h.model.prepareNewProposal()
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        #expect(h.model.captureError == nil)
        #expect(h.model.mutationState == .idle)
        #expect(await h.service.calls == [.propose, .edit])
    }

    @Test("ui-v1 malformed PROPOSE replies cannot become a successful proposal", arguments: [InvalidProjection.missingVersion, .wrongKind, .unknownStatus])
    func malformedProposalRetainsTheAttempt(invalid: InvalidProjection) async throws {
        let h = try Self.harness(propose: [.success(Self.invalidProjection(invalid))])
        await h.model.submit(Self.authored)
        #expect(h.model.captureError == .serviceUnavailable)
        #expect(h.model.currentProposal == nil)
        #expect(h.model.mutationState.receipt == nil)
        guard case .propose = try #require(h.model.retainedFailedAttempt) else { Issue.record("Expected original proposal attempt"); return }
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.authored)
        #expect(h.center.revision(for: .today) == 0)
    }

    @Test("EDIT validates receipt identity, expected revision, projection ID and required receipt", arguments: [InvalidEdit.missingReceipt, .anotherRequestKey, .anotherExpectedRevision, .anotherRegistrationID])
    func malformedEditRetainsTheAttempt(invalid: InvalidEdit) async throws {
        let reply: RegistrationProposalResponse
        switch invalid {
        case .missingReceipt: reply = try Self.response(revision: 1)
        case .anotherRequestKey: reply = try Self.response(revision: 1, receiptKey: Self.sqlKey(9))
        case .anotherExpectedRevision: reply = try Self.response(revision: 2, receiptKey: Self.sqlKey(2), receiptExpected: 1)
        case .anotherRegistrationID: reply = try Self.response(revision: 1, id: Self.otherID, receiptKey: Self.sqlKey(2))
        }
        let h = try Self.harness(edit: [.success(reply)])
        await h.model.submit(Self.authored)
        await h.model.saveEdit(Self.edited)
        #expect(h.model.captureError == .serviceUnavailable)
        #expect(try h.model.currentProposal == Self.response().data)
        #expect(h.model.mutationState.receipt == nil)
        guard case let .edit(attempt) = try #require(h.model.retainedFailedAttempt) else { Issue.record("Expected original edit attempt"); return }
        #expect(attempt.key == Self.key(2))
        #expect(attempt.payload.workoutVersion?.contentRevision == 0)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
    }

    @Test("confirmation cannot claim another ID or a revision the patient never selected", arguments: [false, true])
    func malformedConfirmationDoesNotPublish(wrongID: Bool) async throws {
        let reply = try Self.confirmation(revision: wrongID ? 0 : 2, id: wrongID ? Self.otherID : Self.id)
        let h = try Self.harness(confirm: [.success(reply)])
        await h.model.submit(Self.authored)
        await h.model.confirm()
        #expect(h.model.captureError == .serviceUnavailable)
        #expect(try h.model.currentProposal == Self.response().data)
        #expect(h.model.confirmedRegistration == nil)
        #expect(h.model.mutationState.receipt == nil)
        guard case .confirm = try #require(h.model.retainedFailedAttempt) else { Issue.record("Expected original confirmation attempt"); return }
        #expect(h.center.revision(for: .history) == 0)
    }

    @Test("authority-stale mutation/GET cannot loop; explicit new intention preserves all fields", arguments: [false, true])
    func permanentAuthorityFailureDoesNotRetry(staleDuringRead: Bool) async throws {
        let h = try await Self.conflicted(error: staleDuringRead ? .registrationRevisionConflict : .registrationAuthorityStale,
            reads: staleDuringRead ? [.failure(.registrationAuthorityStale)] : [])
        if staleDuringRead { await h.model.reviewCurrentVersion() }
        let failed = try #require(h.model.retainedFailedAttempt)
        let before = await h.service.calls
        #expect(h.model.captureError == .registrationAuthorityStale)
        #expect(h.model.requiresCurrentReview)
        #expect(!h.model.allowsPendingActions)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        await h.model.retry()
        await h.model.reviewCurrentVersion()
        await h.model.confirm()
        #expect(await h.service.calls == before)
        #expect(h.model.retainedFailedAttempt == failed)
        h.model.prepareNewProposal()
        #expect(h.model.phase == .form)
        #expect(h.model.currentProposal == nil)
        #expect(!h.model.requiresCurrentReview)
        #expect(h.model.captureError == nil)
        #expect(h.model.mutationState == .idle)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        #expect(await h.service.calls == before)
    }

    @Test("review-required proposal without an ID offers an explicit new intention and preserves the draft")
    func proposalConflictWithoutIDDoesNotInventARead() async throws {
        let h = try Self.harness(propose: [.failure(.registrationReviewRequired)])
        await h.model.submit(Self.authored)
        guard case .propose = try #require(h.model.retainedFailedAttempt) else { Issue.record("Expected proposal attempt"); return }
        await h.model.reviewCurrentVersion()
        await h.model.retry()
        #expect(await h.service.calls == [.propose])
        h.model.prepareNewProposal()
        #expect(h.model.phase == .form)
        #expect(h.model.captureError == nil)
        #expect(h.model.mutationState == .idle)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.authored)
    }

    @Test("dismissed late EDIT success or failure cannot publish state, focus or invalidation", arguments: [false, true])
    func dismissedEditCannotPublish(failure: Bool) async throws {
        let h = try Self.harness(edit: [.hold])
        await h.model.submit(Self.authored)
        let task = Task { await h.model.saveEdit(Self.edited) }
        await h.service.waitUntilEditHeld()
        h.model.discardSheet()
        let before = Self.visibleState(h)
        try await h.service.finishEdit(failure ? .failure(.registrationRevisionConflict) : .success(Self.response(revision: 1, receiptKey: Self.sqlKey(2))))
        await task.value
        #expect(Self.visibleState(h) == before)
        #expect(!h.model.isBusy)
    }

    @Test("dismissed late GET success or failure cannot publish state, focus or invalidation", arguments: [false, true])
    func dismissedReviewCannotPublish(failure: Bool) async throws {
        let h = try await Self.conflicted(reads: [.hold])
        let task = Task { await h.model.reviewCurrentVersion() }
        await h.service.waitUntilReadHeld()
        h.model.discardSheet()
        let before = Self.visibleState(h)
        try await h.service.finishRead(failure ? .failure(.registrationAuthorityStale) : .success(Self.response(revision: 2, status: "confirmed")))
        await task.value
        #expect(Self.visibleState(h) == before)
        #expect(!h.model.isBusy)
        #expect(!h.model.isReviewingCurrent)
    }

    @Test("a legacy edit refused for missing revision preserves its attempt and reads official authority explicitly", arguments: [false, true])
    func legacyRevisionRequiredCanRecoverWithoutPromotingTheAttempt(permanentlyStale: Bool) async throws {
        let current = try Self.response(revision: 2)
        let h = try Self.harness(
            propose: [.success(Self.response(revision: nil))], edit: [.failure(.registrationReviewRequired)],
            reads: permanentlyStale ? [.failure(.registrationAuthorityStale)] : [.success(current)], selection: nil
        )
        await h.model.submit(Self.authored)
        #expect(h.model.currentProposal?.workoutVersion == nil)
        await h.model.saveEdit(Self.edited)
        #expect(h.model.captureError == .registrationReviewRequired)
        #expect(h.model.requiresCurrentReview)
        guard case let .edit(original) = try #require(h.model.retainedFailedAttempt) else {
            Issue.record("Expected the original legacy edit"); return
        }
        #expect(original.payload.workoutVersion == nil)
        Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        #expect(await h.service.calls == [.propose, .edit])
        await h.model.retry()
        #expect(await h.service.calls == [.propose, .edit, .read])
        #expect(h.model.retainedFailedAttempt == .edit(original))
        #expect(original.payload.workoutVersion == nil)
        if permanentlyStale {
            #expect(h.model.captureError == .registrationAuthorityStale)
            await h.model.retry()
            #expect(await h.service.calls == [.propose, .edit, .read])
            h.model.prepareNewProposal()
            #expect(h.model.phase == .form)
            #expect(!h.model.requiresCurrentReview)
            Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        } else {
            #expect(h.model.mutationState == .succeeded(.workoutCurrent(current)))
            #expect(h.model.currentProposal == current.data)
            #expect(h.model.allowsPendingActions)
            Self.expectFields(try #require(h.model.pendingDraft), equalTo: Self.edited)
        }
    }

    enum Mutation: Equatable, Sendable { case edit, confirm, cancel }
    enum TerminalOrigin: Equatable, Sendable { case propose, edit }
    enum InvalidProjection: Equatable, Sendable { case wrongID, missingVersion, wrongKind, unknownStatus }
    enum InvalidEdit: Equatable, Sendable { case missingReceipt, anotherRequestKey, anotherExpectedRevision, anotherRegistrationID }
    private static let id = "a17f0000-0000-4000-8000-000000000100"
    private static let otherID = "a17f0000-0000-4000-8000-000000000200"
    private static let now = Date(timeIntervalSince1970: 1_792_076_400)
    private static let authored = WorkoutProposalRequest(workoutType: "Natação", durationMin: 47, intensity: .high,
        performedAt: APITimestamp(value: now.addingTimeInterval(321)))
    private static let edited = WorkoutProposalRequest(workoutType: "Remo indoor", durationMin: 61, intensity: .light,
        performedAt: APITimestamp(value: now.addingTimeInterval(654)))

    private static func key(_ index: Int) -> IdempotencyKey {
        try! IdempotencyKey(validating: VersionedUUIDKeys.literal(index))
    }
    private static func sqlKey(_ index: Int) -> String { "wue1:\(VersionedUUIDKeys.literal(index))" }

    private static func expectFields(_ actual: WorkoutProposalRequest, equalTo expected: WorkoutProposalRequest) {
        #expect(actual.workoutType == expected.workoutType)
        #expect(actual.durationMin == expected.durationMin)
        #expect(actual.intensity == expected.intensity)
        #expect(actual.performedAt == expected.performedAt)
    }

    // Fixtures are decoded from the actual flat BFF whitelist. Provider/hash,
    // raw13, source timestamp and arbitrary caller calories are never included.
    private static func response(revision: Int? = 0, status: String = "pending", id: String = "a17f0000-0000-4000-8000-000000000100",
        receiptKey: String? = nil, receiptExpected: Int = 0, type: String = "Natação", duration: Int = 47,
        intensity: String = "alta") throws -> RegistrationProposalResponse {
        var row: [String: Any] = ["id": id, "status": status,
            "created_at": "2026-10-15T15:00:00.123456+00:00", "expires_at": "2026-10-16T15:00:00.123456+00:00",
            "resolved_at": status == "pending" ? NSNull() as Any : "2026-10-15T15:01:00.123456+00:00" as Any,
            "proposal": ["kind": "workout", "workout_type": type, "duration_min": duration, "estimated_kcal": 333, "intensity": intensity]]
        if let revision { row["workout_protocol"] = "ui-v1"; row["content_revision"] = revision }
        if let receiptKey { row["receipt"] = ["requestKey": receiptKey, "expectedRevision": receiptExpected, "resultRevision": receiptExpected + 1] }
        return try decode(RegistrationProposalResponse.self, row: row)
    }

    private static func confirmation(revision: Int = 0, id: String = "a17f0000-0000-4000-8000-000000000100") throws -> RegistrationConfirmationResponse {
        let row = try response(revision: revision, status: "confirmed", id: id).data
        var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        value["already_confirmed"] = false
        value["deduped"] = false
        return try decode(RegistrationConfirmationResponse.self, row: value)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, row: [String: Any]) throws -> Value {
        let envelope: [String: Any] = ["data": row, "meta": ["api_version": "v1", "request_id": "s17h1-synthetic"]]
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]))
    }

    // These deliberately invalid provider projections use the public typed
    // initializer to exercise model guards independently of the wire decoder.
    private static func invalidProjection(_ invalid: InvalidProjection) throws -> RegistrationProposalResponse {
        let valid = try response(revision: invalid == .missingVersion ? nil : 2,
            status: invalid == .unknownStatus ? "processing" : "pending", id: invalid == .wrongID ? otherID : id)
        guard invalid == .wrongKind else { return valid }
        let row = valid.data
        return RegistrationProposalResponse(data: RegistrationSnapshot(id: row.id, status: row.status,
            createdAt: row.createdAt, expiresAt: row.expiresAt, resolvedAt: row.resolvedAt,
            proposal: .unknown, workoutVersion: row.workoutVersion), meta: valid.meta)
    }

    private static func model(provider: any RegistrationProviding, selection: WorkoutRegistrationProtocol? = .uiV1,
        center: FeatureInvalidationCenter) -> WorkoutRegistrationModel {
        if let selection {
            return WorkoutRegistrationModel(registration: provider, timeProvider: FixedTimeProvider(value: now),
                keyProvider: VersionedUUIDKeys(), invalidationCenter: center, registrationProtocol: selection)
        }
        return WorkoutRegistrationModel(registration: provider, timeProvider: FixedTimeProvider(value: now),
            keyProvider: VersionedUUIDKeys(), invalidationCenter: center)
    }

    private static func harness(propose: [VersionedModelOutcome<RegistrationProposalResponse>]? = nil,
        edit: [VersionedModelOutcome<RegistrationProposalResponse>] = [],
        confirm: [VersionedModelOutcome<RegistrationConfirmationResponse>] = [],
        cancel: [VersionedModelOutcome<RegistrationCancellationResponse>] = [],
        reads: [VersionedModelOutcome<RegistrationProposalResponse>] = [],
        selection: WorkoutRegistrationProtocol? = .uiV1) throws -> VersionedModelHarness {
        let service = VersionedModelService(propose: try propose ?? [.success(response())], edit: edit,
            confirm: confirm, cancel: cancel, reads: reads)
        let center = FeatureInvalidationCenter()
        return VersionedModelHarness(model: model(provider: service, selection: selection, center: center), service: service, center: center)
    }

    private static func conflicted(operation: Mutation = .edit, error: BodyFlowCapabilityError = .registrationRevisionConflict,
        reads: [VersionedModelOutcome<RegistrationProposalResponse>] = []) async throws -> VersionedModelHarness {
        let h = try harness(edit: operation == .edit ? [.failure(error)] : [],
            confirm: operation == .confirm ? [.failure(error)] : [], cancel: operation == .cancel ? [.failure(error)] : [], reads: reads)
        await h.model.submit(authored)
        switch operation {
        case .edit: await h.model.saveEdit(edited)
        case .confirm: await h.model.confirm()
        case .cancel: await h.model.cancel()
        }
        return h
    }

    private static func visibleState(_ h: VersionedModelHarness) -> VersionedVisibleState {
        VersionedVisibleState(proposal: h.model.currentProposal, draft: h.model.pendingDraft,
            confirmed: h.model.confirmedRegistration, phase: h.model.phase, mutation: h.model.mutationState,
            error: h.model.captureError, focus: h.model.accessibilityFocusTarget,
            requiresReview: h.model.requiresCurrentReview, retained: h.model.retainedFailedAttempt,
            today: h.center.revision(for: .today), history: h.center.revision(for: .history))
    }
}

@MainActor
private struct VersionedModelHarness {
    let model: WorkoutRegistrationModel
    let service: VersionedModelService
    let center: FeatureInvalidationCenter
}
private struct VersionedVisibleState: Equatable {
    let proposal: RegistrationSnapshot?
    let draft: WorkoutProposalRequest?
    let confirmed: RegistrationSnapshot?
    let phase: WorkoutRegistrationPhase
    let mutation: RegistrationMutationState
    let error: BodyFlowCapabilityError?
    let focus: RegistrationAccessibilityFocusTarget?
    let requiresReview: Bool
    let retained: RegistrationMutationAttempt?
    let today: Int
    let history: Int
}

private final class VersionedUUIDKeys: IdempotencyKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var next = 0
    static func literal(_ value: Int) -> String {
        let tail = String(value, radix: 16, uppercase: true)
        return "A17F0000-0000-4000-8000-" + String(repeating: "0", count: 12 - tail.count) + tail
    }
    func nextKey() throws -> IdempotencyKey {
        try lock.withLock { next += 1; return try IdempotencyKey(validating: Self.literal(next)) }
    }
}

private enum VersionedModelOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(BodyFlowCapabilityError)
    case hold
}

private actor VersionedModelService: RegistrationProviding, WorkoutRegistrationReading {
    enum Call: Equatable, Sendable { case propose, edit, confirm, cancel, read }
    private var proposeResults: [VersionedModelOutcome<RegistrationProposalResponse>]
    private var editResults: [VersionedModelOutcome<RegistrationProposalResponse>]
    private var confirmResults: [VersionedModelOutcome<RegistrationConfirmationResponse>]
    private var cancelResults: [VersionedModelOutcome<RegistrationCancellationResponse>]
    private var readResults: [VersionedModelOutcome<RegistrationProposalResponse>]
    private var heldEdit: CheckedContinuation<RegistrationProposalResponse, any Error>?
    private var heldRead: CheckedContinuation<RegistrationProposalResponse, any Error>?
    private var editWaiters: [CheckedContinuation<Void, Never>] = []
    private var readWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls: [Call] = []
    private(set) var proposals: [MutationAttempt<RegistrationProposalRequest>] = []
    private(set) var edits: [MutationAttempt<RegistrationEditCommand>] = []
    private(set) var confirmations: [MutationAttempt<RegistrationIDCommand>] = []
    private(set) var cancellations: [MutationAttempt<RegistrationIDCommand>] = []
    private(set) var reads: [String] = []

    init(propose: [VersionedModelOutcome<RegistrationProposalResponse>], edit: [VersionedModelOutcome<RegistrationProposalResponse>] = [],
        confirm: [VersionedModelOutcome<RegistrationConfirmationResponse>] = [], cancel: [VersionedModelOutcome<RegistrationCancellationResponse>] = [],
        reads: [VersionedModelOutcome<RegistrationProposalResponse>] = []) {
        proposeResults = propose; editResults = edit; confirmResults = confirm; cancelResults = cancel; readResults = reads
    }
    func propose(_ attempt: MutationAttempt<RegistrationProposalRequest>) async throws -> RegistrationProposalResponse {
        calls.append(.propose); proposals.append(attempt)
        guard !proposeResults.isEmpty else { Issue.record("Unexpected PROPOSE"); throw BodyFlowCapabilityError.serviceUnavailable }
        return try Self.immediate(proposeResults.removeFirst())
    }
    func edit(_ attempt: MutationAttempt<RegistrationEditCommand>) async throws -> RegistrationProposalResponse {
        calls.append(.edit); edits.append(attempt)
        guard !editResults.isEmpty else { Issue.record("Unexpected EDIT"); throw BodyFlowCapabilityError.serviceUnavailable }
        let result = editResults.removeFirst()
        if case .hold = result {
            return try await withCheckedThrowingContinuation { continuation in
                heldEdit = continuation
                let waiters = editWaiters; editWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        return try Self.immediate(result)
    }
    func confirm(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationConfirmationResponse {
        calls.append(.confirm); confirmations.append(attempt)
        guard !confirmResults.isEmpty else { Issue.record("Unexpected CONFIRM"); throw BodyFlowCapabilityError.serviceUnavailable }
        return try Self.immediate(confirmResults.removeFirst())
    }
    func cancel(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationCancellationResponse {
        calls.append(.cancel); cancellations.append(attempt)
        guard !cancelResults.isEmpty else { Issue.record("Unexpected CANCEL"); throw BodyFlowCapabilityError.serviceUnavailable }
        return try Self.immediate(cancelResults.removeFirst())
    }
    func loadWorkoutRegistration(id: String) async throws -> RegistrationProposalResponse {
        calls.append(.read); reads.append(id)
        guard !readResults.isEmpty else { Issue.record("Unexpected GET"); throw BodyFlowCapabilityError.serviceUnavailable }
        let result = readResults.removeFirst()
        if case .hold = result {
            return try await withCheckedThrowingContinuation { continuation in
                heldRead = continuation
                let waiters = readWaiters; readWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        return try Self.immediate(result)
    }
    func waitUntilEditHeld() async {
        if heldEdit != nil { return }
        await withCheckedContinuation { editWaiters.append($0) }
    }
    func waitUntilReadHeld() async {
        if heldRead != nil { return }
        await withCheckedContinuation { readWaiters.append($0) }
    }
    func finishEdit(_ result: VersionedModelOutcome<RegistrationProposalResponse>) {
        guard let continuation = heldEdit else { Issue.record("No held EDIT"); return }
        heldEdit = nil
        do { continuation.resume(returning: try Self.immediate(result)) } catch { continuation.resume(throwing: error) }
    }
    func finishRead(_ result: VersionedModelOutcome<RegistrationProposalResponse>) {
        guard let continuation = heldRead else { Issue.record("No held GET"); return }
        heldRead = nil
        do { continuation.resume(returning: try Self.immediate(result)) } catch { continuation.resume(throwing: error) }
    }
    private static func immediate<Value: Sendable>(_ result: VersionedModelOutcome<Value>) throws -> Value {
        switch result {
        case let .success(value): return value
        case let .failure(error): throw error
        case .hold: Issue.record("Unexpected held operation"); throw BodyFlowCapabilityError.serviceUnavailable
        }
    }
}

private struct MutationOnlyVersionedProvider: RegistrationProviding {
    let base: VersionedModelService
    func propose(_ attempt: MutationAttempt<RegistrationProposalRequest>) async throws -> RegistrationProposalResponse { try await base.propose(attempt) }
    func edit(_ attempt: MutationAttempt<RegistrationEditCommand>) async throws -> RegistrationProposalResponse { try await base.edit(attempt) }
    func confirm(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationConfirmationResponse { try await base.confirm(attempt) }
    func cancel(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationCancellationResponse { try await base.cancel(attempt) }
}
