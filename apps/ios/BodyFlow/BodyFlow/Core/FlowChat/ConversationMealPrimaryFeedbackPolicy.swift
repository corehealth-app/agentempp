import Foundation

/// Presentation only, after the caller's actual owned read/session gate. It
/// grants no write or current clinical authority. Six literal server sections
/// may be primary only while the current group proves every original fact.
enum ConversationMealPrimaryFeedbackPolicy {
  static func showsPrimary(
    receipt: ConversationThreadPageSnapshot.LinkedReceipt,
    feedback: ConversationFeedbackPresentationSnapshot.Bound?,
    group: ConversationMealGroupSnapshot?,
    scope: ConversationFeedbackPresentationSnapshot.Scope
  ) -> Bool {
    if case .v3Sections = feedback?.presentation.content {
      return ConversationMealV3PrimaryFeedbackPolicy.showsPrimary(receipt: receipt, feedback: feedback, group: group, scope: scope)
    }
    guard let feedback, let group, let current = group.current,
      let actualOriginal = group.originalReceipt.linked,
      identicalLinkedReceipt(actualOriginal, receipt),
      feedback.scope == scope, receipt.ownerID.uuidString.lowercased() == scope.ownerID,
      receipt.epoch.uuidString.lowercased() == scope.epoch,
      group.ownerID == receipt.ownerID, group.commandID == receipt.commandID,
      group.originalInputHash == receipt.inputHash, group.epoch == receipt.epoch,
      group.revision == 0, group.lineageCompatible, group.lastOperation == nil,
      receipt.parentCommandID != receipt.commandID,
      receipt.providerKey
        == "conversation.clarification/\(receipt.ownerID.uuidString.lowercased())/\(receipt.parentCommandID.uuidString.lowercased())",
      current.localDate == receipt.localDate, current.timezone == receipt.timezone,
      feedback.presentation.original.schema == "registration.feedback.v2",
      feedback.presentation.original.registrationID
        == receipt.registrationID.uuidString.lowercased(),
      feedback.presentation.original.localDate == receipt.localDate,
      feedback.presentation.provenance.commandID == receipt.commandID.uuidString.lowercased(),
      feedback.presentation.provenance.epoch == scope.epoch,
      let groupClock = ConversationProtocolInstant(group.observedAt),
      let policyClock = ConversationProtocolInstant(feedback.presentation.provenance.observedAt),
      let originalTime = ConversationProtocolInstant(receipt.consumedAt),
      groupClock >= policyClock, policyClock >= originalTime,
      case .sections(let original, let sections) = feedback.presentation.content,
      sections.map(\.key) == [.saved, .items, .summary, .day, .block, .education],
      original.mealKind == receipt.mealType.rawValue,
      current.items.count == original.items.count,
      Set(current.items.map(\.id)) == Set(receipt.logIDs),
      Set(original.items.map(\.logID)) == Set(receipt.logIDs.map { $0.uuidString.lowercased() })
    else { return false }
    let rows = Dictionary(
      uniqueKeysWithValues: current.items.map { ($0.id.uuidString.lowercased(), $0) })
    return original.items.allSatisfy { fact in
      guard let row = rows[fact.logID], let source = row.source,
        row.foodName.utf16.elementsEqual(fact.foodName.utf16), row.quantityG == fact.quantityG,
        row.kcal == fact.nutrients.kcal, row.proteinG == fact.nutrients.proteinG,
        row.carbsG == fact.nutrients.carbsG, row.fatG == fact.nutrients.fatG,
        source.utf16.elementsEqual(fact.nutritionSource.utf16),
        row.mealType == receipt.mealType,
        ConversationProtocolInstant(row.consumedAt) == originalTime
      else { return false }
      return true
    }
  }

  private static func identicalLinkedReceipt(
    _ actual: ConversationThreadPageSnapshot.LinkedReceipt,
    _ original: ConversationThreadPageSnapshot.LinkedReceipt
  ) -> Bool {
    actual.ownerID == original.ownerID && actual.commandID == original.commandID
      && actual.inputHash == original.inputHash && actual.registrationID == original.registrationID
      && actual.providerKey == original.providerKey && actual.mealType == original.mealType
      && actual.localDate == original.localDate && actual.timezone == original.timezone
      && actual.consumedAt == original.consumedAt && actual.logIDs == original.logIDs
      && actual.effectVersion == original.effectVersion
      && actual.parentCommandID == original.parentCommandID
      && actual.parentInputHash == original.parentInputHash
      && actual.parentDecisionHash == original.parentDecisionHash && actual.epoch == original.epoch
  }

  static func showsPrimary(
    receipt: SavedConversationMealCommandResultSnapshot.Receipt,
    feedback: ConversationFeedbackPresentationSnapshot.Bound?,
    group: ConversationMealGroupSnapshot?,
    scope: ConversationFeedbackPresentationSnapshot.Scope
  ) -> Bool {
    if case .v3Sections = feedback?.presentation.content {
      return ConversationMealV3PrimaryFeedbackPolicy.showsPrimary(receipt: receipt, feedback: feedback, group: group, scope: scope)
    }
    guard let feedback, let group, let current = group.current,
      feedback.scope == scope, group.ownerID.uuidString.lowercased() == scope.ownerID,
      group.epoch.uuidString.lowercased() == scope.epoch, group.revision == 0,
      group.lineageCompatible, group.lastOperation == nil, group.originalReceipt.report == receipt,
      group.commandID.uuidString.lowercased() == receipt.commandID,
      group.originalInputHash == receipt.inputHash, receipt.ownerID == scope.ownerID,
      current.localDate == receipt.localDate, current.timezone == receipt.timezone,
      feedback.presentation.original.schema == "registration.feedback.v2",
      feedback.presentation.original.registrationID == receipt.registrationID,
      feedback.presentation.original.localDate == receipt.localDate,
      feedback.presentation.provenance.commandID == receipt.commandID,
      feedback.presentation.provenance.epoch == scope.epoch,
      let groupClock = ConversationProtocolInstant(group.observedAt),
      let policyClock = ConversationProtocolInstant(feedback.presentation.provenance.observedAt),
      groupClock >= policyClock,
      case .sections(let original, let sections) = feedback.presentation.content,
      sections.count == 6, original.mealKind == receipt.mealType.rawValue,
      current.items.count == original.items.count,
      Set(current.items.map { $0.id.uuidString.lowercased() }) == Set(receipt.logIDs),
      Set(original.items.map(\.logID)) == Set(receipt.logIDs),
      let originalTime = ConversationProtocolInstant(receipt.consumedAt)
    else { return false }
    let rows = Dictionary(
      uniqueKeysWithValues: current.items.map { ($0.id.uuidString.lowercased(), $0) })
    return original.items.allSatisfy { fact in
      guard let row = rows[fact.logID], let source = row.source,
        row.foodName.utf16.elementsEqual(fact.foodName.utf16), row.quantityG == fact.quantityG,
        row.kcal == fact.nutrients.kcal, row.proteinG == fact.nutrients.proteinG,
        row.carbsG == fact.nutrients.carbsG, row.fatG == fact.nutrients.fatG,
        source.utf16.elementsEqual(fact.nutritionSource.utf16),
        row.mealType == receipt.mealType,
        ConversationProtocolInstant(row.consumedAt) == originalTime
      else { return false }
      return true
    }
  }
}
