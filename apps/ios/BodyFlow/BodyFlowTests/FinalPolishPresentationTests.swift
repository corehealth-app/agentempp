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
