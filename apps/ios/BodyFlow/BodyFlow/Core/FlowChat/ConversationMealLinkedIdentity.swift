import Foundation

enum ConversationMealLinkedIdentityError: Error, Equatable, Sendable { case invalid }

/// A READ-ONLY observation from an owned v2 edit/descriptor or fulfillment.
/// It contains no original effect and cannot prepare edits or acknowledge work.
struct ConversationMealLinkedReadReference: Equatable, Sendable {
  let parentBinding: ConversationThreadPageSnapshot.Binding
  let childBinding: ConversationThreadPageSnapshot.Binding
  let parentDecisionHash: String
  var commandID: UUID { childBinding.commandID }
  var inputHash: String { childBinding.inputHash }
  var ownerID: UUID { childBinding.ownerID }
  var epoch: UUID { childBinding.epoch }
  init(
    parentBinding: ConversationThreadPageSnapshot.Binding,
    childBinding: ConversationThreadPageSnapshot.Binding, parentDecisionHash: String
  ) throws {
    guard !parentBinding.isChild, childBinding.isChild,
      parentBinding.ownerID == childBinding.ownerID, parentBinding.epoch == childBinding.epoch,
      parentBinding.commandID != childBinding.commandID,
      parentDecisionHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
      let parentAt = ConversationProtocolInstant(parentBinding.admittedAt),
      let childAt = ConversationProtocolInstant(childBinding.admittedAt), childAt >= parentAt
    else { throw ConversationMealLinkedIdentityError.invalid }
    self.parentBinding = parentBinding
    self.childBinding = childBinding
    self.parentDecisionHash = parentDecisionHash
  }
  func resolve(group: ConversationMealGroupSnapshot) throws -> ConversationMealLinkedIdentity {
    guard let receipt = group.originalReceipt.linked else {
      throw ConversationMealLinkedIdentityError.invalid
    }
    let complete = try ConversationMealLinkedIdentity(
      parentBinding: parentBinding, childBinding: childBinding,
      parentDecisionHash: parentDecisionHash, receipt: receipt)
    guard complete.matches(group: group) else { throw ConversationMealLinkedIdentityError.invalid }
    return complete
  }
}

/// Immutable factual identity from an actual owned fulfillment/reply result.
/// It is neither a v1 report nor an Auth/current-clinical/write capability.
/// Missing parent/admission facts must be recovered by real reads, not inferred.
struct ConversationMealLinkedIdentity: Equatable, Sendable {
  let reference: ConversationMealLinkedReadReference
  var parentBinding: ConversationThreadPageSnapshot.Binding { reference.parentBinding }
  var childBinding: ConversationThreadPageSnapshot.Binding { reference.childBinding }
  var parentDecisionHash: String { reference.parentDecisionHash }
  let receipt: ConversationThreadPageSnapshot.LinkedReceipt
  var commandID: UUID { childBinding.commandID }
  var inputHash: String { childBinding.inputHash }
  var admittedAt: String { childBinding.admittedAt }
  var ownerID: UUID { childBinding.ownerID }
  var epoch: UUID { childBinding.epoch }

  init(
    parentBinding: ConversationThreadPageSnapshot.Binding,
    childBinding: ConversationThreadPageSnapshot.Binding, parentDecisionHash: String,
    receipt: ConversationThreadPageSnapshot.LinkedReceipt
  ) throws {
    guard !parentBinding.isChild, childBinding.isChild,
      receipt.matches(child: childBinding, parent: parentBinding, decisionHash: parentDecisionHash)
    else { throw ConversationMealLinkedIdentityError.invalid }
    reference = try .init(
      parentBinding: parentBinding, childBinding: childBinding,
      parentDecisionHash: parentDecisionHash)
    self.receipt = receipt
  }
  func matches(group: ConversationMealGroupSnapshot) -> Bool {
    guard let original = group.originalReceipt.linked,
      group.ownerID == ownerID, group.commandID == commandID,
      group.originalInputHash == inputHash, group.epoch == epoch,
      let groupAdmitted = ConversationProtocolInstant(group.admittedAt),
      let childAdmitted = ConversationProtocolInstant(admittedAt), groupAdmitted == childAdmitted
    else { return false }
    return Self.sameReceipt(original, receipt)
  }
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.parentBinding == rhs.parentBinding && lhs.childBinding == rhs.childBinding
      && lhs.parentDecisionHash == rhs.parentDecisionHash && sameReceipt(lhs.receipt, rhs.receipt)
  }
  private static func sameReceipt(
    _ lhs: ConversationThreadPageSnapshot.LinkedReceipt,
    _ rhs: ConversationThreadPageSnapshot.LinkedReceipt
  ) -> Bool {
    lhs.ownerID == rhs.ownerID && lhs.commandID == rhs.commandID && lhs.inputHash == rhs.inputHash
      && lhs.registrationID == rhs.registrationID && lhs.providerKey == rhs.providerKey
      && lhs.mealType == rhs.mealType && lhs.localDate == rhs.localDate
      && lhs.timezone == rhs.timezone
      && lhs.consumedAt == rhs.consumedAt && lhs.logIDs == rhs.logIDs
      && lhs.effectVersion == rhs.effectVersion && lhs.parentCommandID == rhs.parentCommandID
      && lhs.parentInputHash == rhs.parentInputHash
      && lhs.parentDecisionHash == rhs.parentDecisionHash
      && lhs.epoch == rhs.epoch
  }
}
