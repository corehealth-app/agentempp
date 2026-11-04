import Foundation

/// Presentation only, after the caller's actual owned read/session gate. It
/// grants no write or current clinical authority. Six literal server sections
/// may be primary only while the current group proves every original fact.
enum ConversationMealPrimaryFeedbackPolicy {
  static func showsPrimary(
    receipt: SavedConversationMealCommandResultSnapshot.Receipt,
    feedback: ConversationFeedbackPresentationSnapshot.Bound?,
    group: ConversationMealGroupSnapshot?,
    scope: ConversationFeedbackPresentationSnapshot.Scope
  ) -> Bool {
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
