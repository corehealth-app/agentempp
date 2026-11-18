import Foundation

struct JourneySocialResolutionSnapshot: Decodable, Sendable {
  enum Status: String, Sendable { case applied, fenced }
  let status: Status
  let operationID: UUID
  let kind: String
  let expectedRevision: Int
  let profile: JourneySocialProfile
  private let historicalReceipt: JourneySocialMutationSnapshot?

  init(from decoder: any Decoder) throws {
    let raw = try ConversationMealEditJSON(from: decoder)
    try raw.boundPublicPacket()
    let o = try raw.object([
      "status", "operation_id", "kind", "expected_revision", "receipt", "profile",
    ])
    guard let status = try Status(rawValue: o.required("status").string()) else {
      throw JourneySocialInvalid.value
    }
    self.status = status
    operationID = try o.required("operation_id").uuid()
    kind = try o.required("kind").string()
    try socialRequire(["profile", "block", "report"].contains(kind))
    let revision = try o.required("expected_revision").amount(min: 0, max: 9_007_199_254_740_990)
    try socialRequire(revision.rounded() == revision)
    expectedRevision = Int(revision)
    profile = try o.required("profile").decode(JourneySocialProfile.self)
    if status == .fenced {
      guard case .null = try o.required("receipt") else { throw JourneySocialInvalid.value }
      historicalReceipt = nil
    } else {
      // Parse the same original receipt under historical replay rules. This
      // adapter issues no mutation and never labels old consent as current.
      historicalReceipt = try ConversationMealEditJSON.object([
        "status": .string("replayed"), "receipt": o.required("receipt"),
        "profile": o.required("profile"),
      ]).decode(JourneySocialMutationSnapshot.self)
    }
  }
  func validate(for pending: JourneySocialPendingOperation, current: JourneySocialBinding) throws {
    guard pending.matches(current) else { throw JourneySocialPendingError.scopeChanged }
    let operation = pending.operation
    try socialRequire(
      operationID == operation.id && kind == operation.kind
        && expectedRevision == operation.expectedRevision)
    try profile.validate(binding: operation.binding)
    try profile.validate(binding: current)
    if let historicalReceipt {
      try historicalReceipt.validate(for: operation)
      if case .report(let id) = historicalReceipt.receipt { try current.publicID(id) }
    } else {
      try socialRequire(status == .fenced)
    }
  }
}
