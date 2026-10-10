import Foundation
import SwiftUI
import Testing
@testable import BodyFlow

@Suite("Final polish — presentation ownership and fallbacks")
@MainActor
struct FinalPolishPresentationTests {
    @Test func tabDisplayOrderKeepsFiveIndependentRoutes() {
        #expect(AppTab.displayOrder == [.today, .plan, .register, .progress, .profile])
        let router = AppRouter()
        for tab in AppTab.displayOrder {
            router.navigate(to: .detail(tab: tab, id: "preserved-\(tab.rawValue)"), in: tab)
        }
        router.popToRoot(in: .register)
        #expect(router.path(for: .register).isEmpty)
        for tab in [AppTab.today, .plan, .progress, .profile] {
            #expect(router.path(for: tab).count == 1)
        }
    }

    @Test func readingSurfacesStayOpaqueAndFloatingFallbackIsExplicit() {
        let standard = BodyFlowVisualPolicy()
        for role in [BodyFlowSurfaceRole.canvas, .content, .card, .elevated, .modal, .interactive] {
            #expect(standard.treatment(for: role, supportsLiquidGlass: true) == .opaque)
        }
        #expect(standard.treatment(for: .floating, supportsLiquidGlass: true) == .liquidGlass)
        #expect(standard.treatment(for: .floating, supportsLiquidGlass: false) == .material)
        for policy in [
            BodyFlowVisualPolicy(reduceTransparency: true),
            BodyFlowVisualPolicy(increasedContrast: true),
            BodyFlowVisualPolicy(lowPower: true),
            BodyFlowVisualPolicy(thermalLimited: true),
        ] {
            #expect(policy.treatment(for: .floating, supportsLiquidGlass: true) == .opaque)
            #expect(policy.treatment(for: .floating, supportsLiquidGlass: false) == .opaque)
        }
        #expect(BodyFlowVisualPolicy(reduceMotion: true).allowsMotion == false)
        #expect(BodyFlowVisualPolicy(lowPower: true).allowsMotion == false)
        #expect(BodyFlowVisualPolicy(thermalLimited: true).allowsMotion == false)
    }

    @Test func oldOperationAndClosedSessionCannotPublishOrVibrate() {
        let presentation = PerformeOperationPresentation()
        let old = presentation.begin()
        let current = presentation.begin()
        presentation.finish(old, outcome: .confirmed, isCancelled: false)
        #expect(presentation.state == .processing)
        #expect(presentation.feedback == nil)
        presentation.finish(current, outcome: .ready, isCancelled: false)
        #expect(presentation.state == .active)
        #expect(presentation.outcome == .ready)
        #expect(presentation.feedback == nil)
        let closing = presentation.begin()
        presentation.invalidate()
        presentation.finish(closing, outcome: .confirmed, isCancelled: false)
        #expect(presentation.state == .idle)
        #expect(presentation.feedback == nil)
    }

    @Test func confirmationFeedbackOccursOncePerOperationAndNotForProposalsOrCancellation() {
        let presentation = PerformeOperationPresentation()
        let first = presentation.begin()
        presentation.finish(first, outcome: .confirmed, confirmation: .registration("record-1"), isCancelled: false)
        let firstFeedback = presentation.feedback
        #expect(presentation.state == .success)
        #expect(firstFeedback?.result == .success)
        presentation.finish(first, outcome: .failed, isCancelled: false)
        #expect(presentation.feedback == firstFeedback)
        #expect(presentation.state == .success)
        presentation.expireSuccess(for: first)
        #expect(presentation.state == .active)
        let second = presentation.begin()
        presentation.finish(second, outcome: .confirmed, confirmation: .registration("record-2"), isCancelled: false)
        #expect(presentation.feedback?.id != firstFeedback?.id)
        presentation.expireSuccess(for: first)
        #expect(presentation.state == .success)
        let cancelled = presentation.begin()
        presentation.finish(cancelled, outcome: .confirmed, isCancelled: true)
        #expect(presentation.state == .active)
        #expect(presentation.feedback == nil)
        let error = presentation.begin()
        presentation.finish(error, outcome: .failed, isCancelled: false)
        presentation.expireSuccess(for: error)
        #expect(presentation.state == .error)
        #expect(presentation.feedback?.result == .failure)
    }

    @Test func shortLoadAndStaleTimersNeverShowSpinner() {
        var gate = BodyFlowLoadingGate()
        let quick = gate.begin()
        gate.end()
        gate.reveal(quick)
        #expect(!gate.isVisible)
        let old = gate.begin()
        let current = gate.begin()
        gate.reveal(old)
        #expect(!gate.isVisible)
        gate.reveal(current)
        #expect(gate.isVisible)
        gate.end()
        #expect(!gate.isVisible)
    }

    @Test func staleConfirmCallbackDoesNotCelebrateTheSamePersistedReceiptAgain() {
        let presentation = PerformeOperationPresentation()
        let confirmed = presentation.begin()
        presentation.finish(confirmed, outcome: .confirmed, confirmation: .registration("meal-confirmed-1"), isCancelled: false)
        #expect(presentation.feedback?.result == .success)
        // A stale second Confirm is ignored by the model; its receipt is unchanged.
        let ignored = presentation.begin()
        presentation.finish(ignored, outcome: .confirmed, confirmation: .registration("meal-confirmed-1"), isCancelled: false)
        #expect(presentation.state == .active)
        #expect(presentation.feedback == nil)
    }

    @Test func failedProposalThenFreshDraftReviewDoesNotReuseOldError() {
        #expect(PerformeRegistrationProjection.meal(
            intent: .draftText("Nova refeição"), draft: .review,
            mutation: .idle, captureError: .invalidInput
        ) == .ready)
        #expect(PerformeRegistrationProjection.meal(
            intent: .confirm, draft: .review,
            mutation: .idle, captureError: .invalidInput
        ) == .failed)
    }

    // MARK: First update (2026-10-10) — one indicator for the meal analysis
    //
    // The loading block and the brand mark read ONE decision
    // (`RegistrationSheet.mealAnalysisStage`): the mark shows its own
    // progress exactly where no block is on screen.

    private func analysisStage(
        kind: RegistrationKind = .meal,
        hasLiveCapture: Bool = true,
        hasProposal: Bool = false,
        registrationPhase: MealRegistrationPhase = .capture,
        draftPhase: MealDraftPhase,
        channel: MealSourceChannel? = .camera,
        isSubmitting: Bool = false
    ) -> MealAnalysisStage? {
        RegistrationSheet.mealAnalysisStage(
            kind: kind, hasLiveCapture: hasLiveCapture, hasProposal: hasProposal,
            registrationPhase: registrationPhase, draftPhase: draftPhase,
            channel: channel, isSubmitting: isSubmitting
        )
    }

    @Test func brandMarkLeavesTheProgressToTheAnalysisLoader() {
        // A meal captured on a real account, no proposal yet: the block is on
        // screen for every stage, so the mark does not spin.
        #expect(analysisStage(draftPhase: .preparing, channel: nil) == .preparing)
        #expect(analysisStage(draftPhase: .uploading) == .sending)
        #expect(analysisStage(draftPhase: .processing, channel: .camera) == .photo)
        #expect(analysisStage(draftPhase: .processing, channel: .gallery) == .photo)
        #expect(analysisStage(draftPhase: .processing, channel: .audioRecording) == .audio)
        #expect(analysisStage(draftPhase: .reading, channel: .text) == .reading)
        // The operation that carries the capture is "submitting" for the
        // sheet at the same time: still one indicator.
        #expect(analysisStage(draftPhase: .uploading, isSubmitting: true) == .sending)
    }

    /// Locks (the critic's first finding): with a proposal on screen the
    /// draft is still in review underneath and the registration is
    /// submitting — that is "Confirmar", "Salvar edição" and "Cancelar
    /// proposta", whose only indicator is the brand mark.
    @Test func confirmEditAndCancelKeepTheBrandProgress() {
        for registrationPhase in [MealRegistrationPhase.proposal, .capture, .cancelled] {
            #expect(analysisStage(
                hasProposal: true, registrationPhase: registrationPhase,
                draftPhase: .review, isSubmitting: true
            ) == nil)
            #expect(analysisStage(
                hasProposal: true, registrationPhase: registrationPhase,
                draftPhase: .idle, isSubmitting: true
            ) == nil)
        }
        // A confirmed meal: nothing is waited for on the capture.
        for draftPhase in [MealDraftPhase.review, .idle, .reading] {
            #expect(analysisStage(
                registrationPhase: .confirmed, draftPhase: draftPhase, isSubmitting: true
            ) == nil)
        }
        // The local demonstration (no live capture) and the other records
        // keep today's indicators in every phase.
        for draftPhase in [MealDraftPhase.preparing, .uploading, .processing, .reading, .review, .idle] {
            #expect(analysisStage(hasLiveCapture: false, draftPhase: draftPhase, isSubmitting: true) == nil)
            for kind in [RegistrationKind.training, .hydration, .weight] {
                #expect(analysisStage(kind: kind, draftPhase: draftPhase, isSubmitting: true) == nil)
            }
        }
        // Nothing is waited for.
        #expect(analysisStage(draftPhase: .idle) == nil)
        #expect(analysisStage(draftPhase: .failed(.offline)) == nil)
        #expect(analysisStage(draftPhase: .review) == nil)
    }

    /// The wait after "Calcular refeição" belongs to the same block: the
    /// review is in hand, no proposal exists yet and the reviewed foods were
    /// sent. (Replaces the lock that kept today's two indicators there.)
    @Test func calculationWaitBelongsToTheLoader() {
        #expect(analysisStage(draftPhase: .review, isSubmitting: true) == .calculating)
        #expect(analysisStage(
            registrationPhase: .cancelled, draftPhase: .review, isSubmitting: true
        ) == .calculating)
        // The proposal arrived: the block leaves and "Confirmar" keeps the mark.
        #expect(analysisStage(hasProposal: true, draftPhase: .review, isSubmitting: true) == nil)
        #expect(analysisStage(hasProposal: true, draftPhase: .review, isSubmitting: false) == nil)
    }

    @Test func startOverClearsCaptureErrorAndRejectsThePriorOperation() {
        let presentation = PerformeOperationPresentation()
        let old = presentation.begin()
        presentation.finish(old, outcome: .failed, isCancelled: false)
        #expect(presentation.state == .error)
        presentation.capturePhaseChanged(.idle)
        #expect(presentation.state == .active)
        #expect(presentation.feedback == nil)
        presentation.finish(old, outcome: .failed, isCancelled: false)
        #expect(presentation.state == .active)
        presentation.capturePhaseChanged(.failed(.permissionDenied))
        #expect(presentation.state == .error)
        #expect(presentation.feedback == nil)
    }
}
