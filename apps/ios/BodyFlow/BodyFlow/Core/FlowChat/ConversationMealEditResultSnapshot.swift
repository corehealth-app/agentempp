import Foundation

/// An immutable factual effect, never a refreshed group or clinical snapshot.
struct ConversationMealEditEffectSnapshot: Decodable, Sendable {
  enum Kind: String, Sendable {
    case saved
    case saveUndone = "save_undone"
    case registrationUndone = "registration_undone"
  }
  let ownerID: UUID
  let commandID: UUID
  let operationID: UUID
  let operationInputHash: String
  let kind: Kind
  let revision: Int
  let appliedAt: String
  let undoExpiresAt: String?
  let targetOperationID: UUID?
  let removedItemIDs: [UUID]
  let newItemIDs: [UUID]
  let nextRecordID: UUID?
  init(from decoder: any Decoder) throws {
    do {
      let raw = try ConversationMealEditJSON(from: decoder)
      try raw.boundPublicPacket()
      let o = try raw.object([
        "schema", "owner_id", "command_id", "operation_id", "input_hash", "kind", "revision",
        "applied_at", "undo_expires_at", "target_operation_id", "removed_item_ids", "new_item_ids",
        "next_record_id",
      ])
      try editCheck(o.required("schema").string() == "conversation.meal-edit-effect-public.v1")
      ownerID = try o.required("owner_id").uuid()
      commandID = try o.required("command_id").uuid()
      operationID = try o.required("operation_id").uuid()
      operationInputHash = try o.required("input_hash").hash()
      guard let k = Kind(rawValue: try o.required("kind").string()) else {
        throw ConversationMealEditInvalid.value
      }
      kind = k
      revision = try o.required("revision").revision()
      try editCheck(revision > 0)
      appliedAt = try o.required("applied_at").clock()
      undoExpiresAt = try o.required("undo_expires_at").optional { try $0.clock() }
      targetOperationID = try o.required("target_operation_id").optional { try $0.uuid() }
      removedItemIDs = try o.required("removed_item_ids").ids(nonempty: true)
      newItemIDs = try o.required("new_item_ids").ids()
      nextRecordID = try o.required("next_record_id").optional { try $0.uuid() }
      try editCheck(Set(removedItemIDs).isDisjoint(with: Set(newItemIDs)))
      switch kind {
      case .saved:
        guard let deadline = undoExpiresAt else { throw ConversationMealEditInvalid.value }
        let start = try editInstant(appliedAt)
        let end = try editInstant(deadline)
        try editCheck(
          removedItemIDs.count == 1 && !newItemIDs.isEmpty && nextRecordID == newItemIDs.first
            && targetOperationID == nil && end.seconds - start.seconds == 300
            && end.nanos == start.nanos)
      case .saveUndone:
        try editCheck(
          undoExpiresAt == nil && revision >= 2 && targetOperationID != nil
            && targetOperationID != operationID && newItemIDs.count == 1
            && nextRecordID == newItemIDs.first)
      case .registrationUndone:
        try editCheck(
          undoExpiresAt == nil && revision == 1 && targetOperationID == nil && newItemIDs.isEmpty
            && nextRecordID == nil)
      }
    } catch { throw editDecodeFailure(decoder) }
  }
}

struct ConversationMealEditResultSnapshot: Decodable, Sendable {
  let ownerID: UUID
  let commandID: UUID
  let originalInputHash: String
  let epoch: UUID
  let receipt: ConversationMealEditEffectSnapshot
  init(data: Data) throws {
    guard data.count <= 65_536 else { throw ConversationMealEditInvalid.value }
    self = try JSONDecoder().decode(Self.self, from: data)
  }
  init(from decoder: any Decoder) throws {
    do {
      let raw = try ConversationMealEditJSON(from: decoder)
      try raw.boundPublicPacket()
      let o = try raw.object([
        "schema", "status", "owner_id", "command_id", "input_hash", "epoch", "receipt",
      ])
      try editCheck(
        o.required("schema").string() == "conversation.meal-edit-result.v1"
          && o.required("status").string() == "saved")
      ownerID = try o.required("owner_id").uuid()
      commandID = try o.required("command_id").uuid()
      originalInputHash = try o.required("input_hash").hash()
      epoch = try o.required("epoch").uuid()
      receipt = try o.required("receipt").decode(ConversationMealEditEffectSnapshot.self)
      try editCheck(receipt.ownerID == ownerID && receipt.commandID == commandID)
    } catch { throw editDecodeFailure(decoder) }
  }
  func matches(operation op: ConversationMealEditOperation) -> Bool {
    guard ownerID == op.ownerID, commandID == op.commandID,
      originalInputHash == op.originalInputHash, epoch == op.epoch,
      receipt.operationID == op.operationID, receipt.operationInputHash == op.operationInputHash,
      receipt.revision == op.expectedRevision + 1
    else { return false }
    switch op.action {
    case .save(let recordID, _):
      return receipt.kind == .saved && receipt.removedItemIDs == [recordID]
    case .undoSave(let target):
      return receipt.kind == .saveUndone && receipt.targetOperationID == target
    case .undoRegistration: return receipt.kind == .registrationUndone && op.expectedRevision == 0
    }
  }
}
struct ConversationMealEditAbsentSnapshot: Decodable, Sendable {
  let ownerID: UUID
  let commandID: UUID
  let originalInputHash: String
  let epoch: UUID
  let operationID: UUID
  let operationInputHash: String
  init(from decoder: any Decoder) throws {
    do {
      let raw = try ConversationMealEditJSON(from: decoder)
      try raw.boundPublicPacket()
      let o = try raw.object([
        "schema", "status", "owner_id", "command_id", "input_hash", "epoch", "operation_id",
        "operation_input_hash",
      ])
      try editCheck(
        o.required("schema").string() == "conversation.meal-edit-state.v1"
          && o.required("status").string() == "absent")
      ownerID = try o.required("owner_id").uuid()
      commandID = try o.required("command_id").uuid()
      originalInputHash = try o.required("input_hash").hash()
      epoch = try o.required("epoch").uuid()
      operationID = try o.required("operation_id").uuid()
      operationInputHash = try o.required("operation_input_hash").hash()
    } catch { throw editDecodeFailure(decoder) }
  }
  func matches(operation op: ConversationMealEditOperation) -> Bool {
    ownerID == op.ownerID && commandID == op.commandID && originalInputHash == op.originalInputHash
      && epoch == op.epoch && operationID == op.operationID
      && operationInputHash == op.operationInputHash
  }
}
enum ConversationMealEditReply: Decodable, Sendable {
  case saved(ConversationMealEditResultSnapshot)
  case absent(ConversationMealEditAbsentSnapshot)
  init(data: Data) throws {
    guard data.count <= 65_536 else { throw ConversationMealEditInvalid.value }
    self = try JSONDecoder().decode(Self.self, from: data)
  }
  init(from decoder: any Decoder) throws {
    let raw = try ConversationMealEditJSON(from: decoder)
    try raw.boundPublicPacket()
    switch try raw.member("schema").string() {
    case "conversation.meal-edit-result.v1":
      self = .saved(try raw.decode(ConversationMealEditResultSnapshot.self))
    case "conversation.meal-edit-state.v1":
      self = .absent(try raw.decode(ConversationMealEditAbsentSnapshot.self))
    default: throw editDecodeFailure(decoder)
    }
  }
  func acceptsHTTPStatus(_ code: Int) -> Bool { code == 200 }
  func matches(operation: ConversationMealEditOperation) -> Bool {
    switch self {
    case .saved(let v): v.matches(operation: operation)
    case .absent(let v): v.matches(operation: operation)
    }
  }
}
