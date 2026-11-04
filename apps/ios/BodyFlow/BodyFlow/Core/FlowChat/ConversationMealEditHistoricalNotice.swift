import Foundation

/// A factual historical UI notice. It is neither a saved-result/ACK capability
/// nor permission to resend or mutate an encrypted queue.
struct ConversationMealEditHistoricalNotice: Sendable {
  let identity: ConversationMealLinkedIdentity
  let receipt: ConversationMealEditEffectSnapshot
  private init(
    identity: ConversationMealLinkedIdentity, receipt: ConversationMealEditEffectSnapshot
  ) {
    self.identity = identity
    self.receipt = receipt
  }
  static func qualify(
    operation: ConversationMealEditOperation, read: ConversationThreadJournalRead,
    linked: ConversationMealLinkedIdentity, group: ConversationMealGroupSnapshot
  ) -> Self? {
    let context = read.context
    guard
      read.page.matches(
        authUserID: context.authUserID, ownerID: context.ownerID, epoch: context.epoch),
      linked.ownerID == context.ownerID, linked.epoch == context.epoch,
      operation.ownerID == linked.ownerID, operation.commandID == linked.commandID,
      operation.originalInputHash == linked.inputHash, operation.epoch == linked.epoch,
      let parent = read.page.thread(linked.parentBinding.commandID),
      parent.parentBinding == linked.parentBinding,
      parent.terminalReceipt?.decisionHash == linked.parentDecisionHash,
      linked.matches(group: group), let last = group.lastOperation,
      let groupAt = ConversationProtocolInstant(group.observedAt),
      let pageAt = ConversationProtocolInstant(read.page.observedAt), groupAt >= pageAt
    else { return nil }
    for entry in read.page.items {
      guard case .edit(let edit) = entry.detail, edit.binding == linked.childBinding,
        edit.receipt.matches(operation: operation), last.hasSameFacts(as: edit.receipt),
        group.revision == edit.receipt.revision
      else { continue }
      return .init(identity: linked, receipt: edit.receipt)
    }
    return nil
  }
}
