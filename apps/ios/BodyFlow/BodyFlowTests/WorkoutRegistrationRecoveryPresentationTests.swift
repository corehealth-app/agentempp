import Foundation
import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

@Suite("Workout revision recovery presentation")
@MainActor
struct WorkoutRegistrationRecoveryPresentationTests {
    @Test("version conflicts keep their specific capability states", arguments: [
        "registration_revision_conflict", "registration_revision_required", "registration_request_conflict",
        "registration_revision_exhausted", "registration_capture_conflict", "registration_authority_stale",
    ])
    func conflictCodesAreNotBlindMutationRetry(_ code: String) {
        let actual = MobileAPITransportError.conflict(code: code, requestID: "test-revision").capabilityError
        let expected: BodyFlowCapabilityError = code == "registration_revision_conflict"
            ? .registrationRevisionConflict
            : code == "registration_authority_stale" ? .registrationAuthorityStale : .registrationReviewRequired
        #expect(actual == expected)
        #expect(actual.telemetryValue == .idempotencyConflict)
    }

    @Test("a retained registration offers an explicit current-version read", arguments: SupportedAppLanguage.allCases)
    func conflictOffersReview(_ language: SupportedAppLanguage) throws {
        for error in [BodyFlowCapabilityError.registrationRevisionConflict, .registrationReviewRequired] {
            let state = RegistrationMutationState.failed(.confirm(try selection()), error)
            let descriptor = RegistrationOperationSummaryDescriptor(state: state, captureError: error, language: language)
            #expect(descriptor.action == .reviewCurrent)
            #expect(descriptor.kind == .error)
            #expect(descriptor.message == (language == .portugueseBrazil
                ? (error == .registrationRevisionConflict
                    ? "Este rascunho mudou. Consulte a versão atual antes de continuar."
                    : "Não foi possível validar este rascunho. Consulte a versão atual antes de continuar.")
                : (error == .registrationRevisionConflict
                    ? "This draft changed. Check the current version before continuing."
                    : "Could not validate this draft. Check the current version before continuing.")))
        }
        #expect(RegistrationCopy.string("registration.operation.review-current", language: language)
            == (language == .portugueseBrazil ? "Revisar versão atual" : "Review current version"))
    }

    @Test("permanently stale authority offers a new explicit proposal without claiming it retried", arguments: SupportedAppLanguage.allCases)
    func staleAuthorityOffersAnExit(_ language: SupportedAppLanguage) throws {
        let error = BodyFlowCapabilityError.registrationAuthorityStale
        let descriptor = RegistrationOperationSummaryDescriptor(
            state: .failed(.confirm(try selection()), error), captureError: error, language: language
        )
        #expect(descriptor.action == .newProposal)
        #expect(descriptor.message == (language == .portugueseBrazil
            ? "Este rascunho não está mais disponível. Seus campos foram mantidos para uma nova proposta."
            : "This draft is no longer available. Your fields were kept for a new proposal."))
    }

    @Test("observing each current status is informational and never an applied edit or confirmation", arguments: [
        "pending", "confirmed", "cancelled", "expired",
    ])
    func currentProjectionNeverCelebrates(_ status: String) throws {
        let response = try current(status: status)
        let state = RegistrationMutationState.succeeded(.workoutCurrent(response))
        #expect(state.receipt?.requestID == "workout-current-read")
        #expect(state.receipt?.confirmedRegistrationID == nil)
        #expect(PerformeRegistrationProjection.confirmation(for: state) == nil)
        let outcome = PerformeRegistrationProjection.registration(state, captureError: nil)
        #expect(outcome == (status == "pending" ? .ready : status == "confirmed" ? .confirmed : .cancelled))
        for language in SupportedAppLanguage.allCases {
            let descriptor = RegistrationOperationSummaryDescriptor(state: state, captureError: nil, language: language)
            #expect(descriptor.kind == (status == "pending" ? .info : .warning))
            #expect(descriptor.action == ((status == "cancelled" || status == "expired") ? .newProposal : nil))
            #expect(RegistrationOperationSummaryDescriptor.feedback(for: descriptor.kind) == nil)
            #expect(RegistrationOperationSummaryDescriptor.celebration(for: descriptor.kind) == nil)
            let expected: String = switch (status, language) {
            case ("pending", .portugueseBrazil): "Versão atual carregada. Revise antes de confirmar. Seus campos foram mantidos."
            case ("pending", _): "Current version loaded. Review it before confirming. Your fields were kept."
            case ("confirmed", .portugueseBrazil): "Este registro já está salvo. Seus campos foram mantidos."
            case ("confirmed", _): "This record is already saved. Your fields were kept."
            case ("cancelled", .portugueseBrazil): "Este rascunho foi cancelado. Seus campos foram mantidos para uma nova proposta."
            case ("cancelled", _): "This draft was cancelled. Your fields were kept for a new proposal."
            case (_, .portugueseBrazil): "Este rascunho expirou. Seus campos foram mantidos para uma nova proposta."
            default: "This draft expired. Your fields were kept for a new proposal."
            }
            #expect(descriptor.message == expected)
        }
        let presentation = PerformeOperationPresentation()
        let token = presentation.begin()
        presentation.finish(token, outcome: outcome, confirmation: nil, isCancelled: false)
        #expect(presentation.state == .active)
        #expect(presentation.feedback == nil)
        #expect(presentation.successToken == nil)
    }

    @Test("an expired versioned edit restores all four authored fields in the drawn workout form")
    func expiredEditFieldsReachTheActualForm() async throws {
        let draft = WorkoutProposalRequest(
            workoutType: "Natação intervalada", durationMin: 63, intensity: .high,
            performedAt: APITimestamp(value: Date(timeIntervalSince1970: 1784589999))
        )
        let model = WorkoutRegistrationModel(
            registration: ExpiredWorkoutFormService(response: try current(status: "pending")),
            timeProvider: FixedTimeProvider(value: Date(timeIntervalSince1970: 1784589300)),
            keyProvider: RandomIdempotencyKeyProvider(), invalidationCenter: FeatureInvalidationCenter(),
            registrationProtocol: .uiV1
        )
        await model.submit(draft)
        #expect(model.phase == .proposal)
        #expect(model.currentProposal?.workoutVersion?.contentRevision == 0)
        await model.saveEdit(draft)
        #expect(model.captureError == .registrationExpired)
        #expect(model.phase == .form)
        #expect(model.currentProposal == nil)
        #expect(model.pendingDraft == draft)
        let submitted = RecoveryRequestBox()
        let view = WorkoutRegistrationContent(
            model: model, propose: { submitted.value = $0 }, saveEdit: { _ in }, retry: {},
            reviewCurrent: {}, confirm: {}, cancel: {}, presentsLocalDemonstration: false
        )
        try RealAccountSampleDataTests.hosted(view.environment(\.locale, Locale(identifier: "pt-BR")), height: 1100) { root in
            var propose: UIButton?
            func collect(_ view: UIView) {
                if let button = view as? UIButton, button.accessibilityIdentifier == "registration.workout.propose" {
                    propose = button
                }
                view.subviews.forEach(collect)
            }
            collect(root)
            try #require(propose).sendActions(for: .touchUpInside)
        }
        #expect(submitted.value == draft)
    }

    @Test("a marked input cannot enable ui-v1 in an instance with the legacy default")
    func markedDraftCannotSelectItsOwnProtocol() async throws {
        let row = try current(status: "pending").data
        let legacy = RegistrationProposalResponse(data: RegistrationSnapshot(
            id: row.id, status: row.status, createdAt: row.createdAt, expiresAt: row.expiresAt,
            resolvedAt: row.resolvedAt, proposal: row.proposal
        ), meta: MobileResponseMetadata(apiVersion: "v1", requestID: "legacy-selection"))
        let service = ExpiredWorkoutFormService(response: legacy)
        let model = WorkoutRegistrationModel(
            registration: service,
            timeProvider: FixedTimeProvider(value: Date(timeIntervalSince1970: 1784589300)),
            keyProvider: RandomIdempotencyKeyProvider(), invalidationCenter: FeatureInvalidationCenter()
        )
        let marked = WorkoutProposalRequest(
            workoutType: "Natação", durationMin: 40, intensity: .high,
            performedAt: APITimestamp(value: Date(timeIntervalSince1970: 1784589999)),
            registrationProtocol: .uiV1
        )
        await model.submit(marked)
        guard case let .workout(actual) = try #require(await service.proposedAttempt).payload else {
            Issue.record("Expected a workout input"); return
        }
        #expect(actual.registrationProtocol == nil)
        #expect(model.pendingDraft?.registrationProtocol == nil)
        #expect(actual.workoutType == marked.workoutType)
        #expect(actual.durationMin == marked.durationMin)
        #expect(actual.intensity == marked.intensity)
        #expect(actual.performedAt == marked.performedAt)
    }

    @Test("a form blocked for explicit recovery does not offer an enabled no-op submit", arguments: [
        BodyFlowCapabilityError.registrationReviewRequired, .registrationAuthorityStale,
    ])
    func blockedProposalFormDisablesItsRealButton(_ error: BodyFlowCapabilityError) async throws {
        let service = ExpiredWorkoutFormService(response: try current(status: "pending"), proposalFailure: error)
        let model = WorkoutRegistrationModel(
            registration: service,
            timeProvider: FixedTimeProvider(value: Date(timeIntervalSince1970: 1784589300)),
            keyProvider: RandomIdempotencyKeyProvider(), invalidationCenter: FeatureInvalidationCenter(),
            registrationProtocol: .uiV1
        )
        await model.submit(WorkoutProposalRequest(workoutType: "Natação", durationMin: 40, intensity: .high, performedAt: nil))
        #expect(model.captureError == error)
        #expect(model.requiresCurrentReview)
        #expect(!model.isBusy)
        #expect(model.currentProposal == nil)
        let submitted = RecoveryRequestBox()
        let view = WorkoutRegistrationContent(
            model: model, propose: { submitted.value = $0 }, saveEdit: { _ in }, retry: {},
            reviewCurrent: {}, confirm: {}, cancel: {}, presentsLocalDemonstration: false
        )
        try RealAccountSampleDataTests.hosted(view, height: 1100) { root in
            var propose: UIButton?
            func collect(_ view: UIView) {
                if let button = view as? UIButton, button.accessibilityIdentifier == "registration.workout.propose" { propose = button }
                view.subviews.forEach(collect)
            }
            collect(root)
            let button = try #require(propose)
            #expect(!button.isEnabled)
            button.sendActions(for: .touchUpInside)
        }
        #expect(submitted.value == nil)
    }

    private func selection() throws -> MutationAttempt<RegistrationIDCommand> {
        MutationAttempt(
            operation: .proposalConfirm, key: try IdempotencyKey(validating: "7C9C0C5E-1F6A-4A1A-9C0B-0F1D2E3A4B5C"),
            payload: RegistrationIDCommand(
                registrationID: "7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c",
                workoutVersion: WorkoutRegistrationVersion(contentRevision: 2)
            ), createdAt: Date(timeIntervalSince1970: 1784589300)
        )
    }

    private func current(status: String) throws -> RegistrationProposalResponse {
        let version = try #require(WorkoutRegistrationVersion(contentRevision: 0))
        return RegistrationProposalResponse(data: RegistrationSnapshot(
            id: "7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c", status: status,
            createdAt: APITimestamp(value: Date(timeIntervalSince1970: 1784589300)),
            expiresAt: APITimestamp(value: Date(timeIntervalSince1970: 1784675700)),
            resolvedAt: status == "pending" ? nil : APITimestamp(value: Date(timeIntervalSince1970: 1784590000)),
            proposal: .workout(WorkoutProposalSnapshot(workoutType: "Natação", durationMin: 40, estimatedKcal: 400, intensity: "moderada")),
            workoutVersion: version
        ), meta: MobileResponseMetadata(apiVersion: "v1", requestID: "workout-current-read"))
    }
}

@MainActor private final class RecoveryRequestBox { var value: WorkoutProposalRequest? }

private actor ExpiredWorkoutFormService: RegistrationProviding {
    let response: RegistrationProposalResponse
    let proposalFailure: BodyFlowCapabilityError?
    private(set) var proposedAttempt: MutationAttempt<RegistrationProposalRequest>?
    init(response: RegistrationProposalResponse, proposalFailure: BodyFlowCapabilityError? = nil) {
        self.response = response
        self.proposalFailure = proposalFailure
    }
    func propose(_ attempt: MutationAttempt<RegistrationProposalRequest>) async throws -> RegistrationProposalResponse {
        proposedAttempt = attempt
        if let proposalFailure { throw proposalFailure }
        return response
    }
    func edit(_ attempt: MutationAttempt<RegistrationEditCommand>) async throws -> RegistrationProposalResponse { throw BodyFlowCapabilityError.registrationExpired }
    func confirm(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationConfirmationResponse { throw BodyFlowCapabilityError.operationUnavailable }
    func cancel(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationCancellationResponse { throw BodyFlowCapabilityError.operationUnavailable }
}
