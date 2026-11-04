import Foundation

/// An observation supplied by the future trusted authenticated capability
/// adapter, bound to the lease that made that request. This value is not a
/// capability signature and cannot establish freshness or authority by itself.
/// UUIDs are identities, never an ordering of backend resets.
struct ConversationOutboxServerObservation: Sendable {
    let ownerID: UUID
    let localSessionGeneration: UInt64
    let epoch: UUID
}

/// Read-only token for an explicit local user decision. Unlike a dispatch
/// ticket, it never permits network send or acknowledgement of queued work.
struct ConversationOutboxDecisionTicket: Sendable, CustomStringConvertible, CustomReflectable {
    let commandID: UUID
    let inputHash: String
    let wireBody: Data
    let originalServerEpoch: UUID?
    let ownerHash: String
    let localSessionGeneration: UInt64
    let scope: UUID

    var description: String { "ConversationOutboxDecisionTicket(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
