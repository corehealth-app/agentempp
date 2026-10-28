import Foundation

extension CurrentClinicalPolicy {
  var restrictsFlowGuidance: Bool {
    pauseWeightLossGuidance || hide.objective || hide.calories || hide.protein || hide.balance
      || hide.block
  }
  func permitsFlowDraft(_ domain: PlanDraftDomain) -> Bool {
    !hide.objective
      && (domain == .training || (!pauseWeightLossGuidance && !hide.calories && !hide.protein))
  }
  /// The clock advancing alone does not make an already protected copy unsafe.
  /// This key concerns presentation only, never clinical or write authority.
  func hasSameFlowPresentation(as other: CurrentClinicalPolicy) -> Bool {
    version == other.version && assessment == other.assessment && hide == other.hide
      && recordingAllowed == other.recordingAllowed
      && pauseWeightLossGuidance == other.pauseWeightLossGuidance
      && professionalAssessmentRecommended == other.professionalAssessmentRecommended
      && phaseSelectionPending == other.phaseSelectionPending && targetSource == other.targetSource
  }
}
extension FlowMessage {
  func withholdingClinicalContent() -> FlowMessage {
    guard role == .assistant else { return self }
    return FlowMessage(
      id: id, conversationID: conversationID, role: role,
      content: String(localized: "flow.clinical.previous-response"), state: state,
      requestID: requestID, createdAt: createdAt)
  }
}
