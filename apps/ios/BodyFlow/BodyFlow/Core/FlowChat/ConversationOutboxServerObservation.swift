import Foundation

/// Session-scoped backend observation. Auth subject and patient row identity
/// are different domains. Only the trusted authenticated session reader may
/// establish their association; no composer/header value establishes it.
struct ConversationOutboxServerObservation: Sendable {
    let authUserID: UUID
    let ownerID: UUID
    let localSessionGeneration: UInt64
    let epoch: UUID
    let isEnqueueOnly: Bool
    private let authority: ConversationOutboxObservationAuthority
    private let token: UUID

    /// Trusted core/test seam. The actual controller uses its shared authority
    /// so beginning a newer read revokes prior observations synchronously.
    init(authUserID: UUID, ownerID: UUID, localSessionGeneration: UInt64, epoch: UUID) {
        let token = UUID()
        self.init(authUserID: authUserID, ownerID: ownerID, localSessionGeneration: localSessionGeneration,
                  epoch: epoch, authority: .init(pinnedToken: token), token: token, enqueueOnly: false)
    }
    fileprivate init(authUserID: UUID, ownerID: UUID, localSessionGeneration: UInt64, epoch: UUID,
                     authority: ConversationOutboxObservationAuthority, token: UUID, enqueueOnly: Bool) {
        self.authUserID = authUserID; self.ownerID = ownerID
        self.localSessionGeneration = localSessionGeneration; self.epoch = epoch
        self.authority = authority; self.token = token; isEnqueueOnly = enqueueOnly
    }
    func isSameGrant(as other: Self) -> Bool {
        authority === other.authority && token == other.token && authUserID == other.authUserID && ownerID == other.ownerID && localSessionGeneration == other.localSessionGeneration && epoch == other.epoch && isEnqueueOnly == other.isEnqueueOnly
    }
    func withCurrentAuthority<Value>(_ operation: () throws -> Value) throws -> Value {
        try authority.perform(token: token, operation)
    }
}

/// Local request identity, never an ordering of backend epoch UUIDs. The lock
/// spans each synchronous disk/visible operation; a newly accepted mapping
/// cannot race a previous mapping's local ACK or publication.
final class ConversationOutboxObservationAuthority: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var pending: UUID?
    private var current: UUID?
    private var closed = false
    init() {}
    fileprivate init(pinnedToken: UUID) { current = pinnedToken }
    func beginRefresh() throws -> UUID {
        try locked {
            guard !closed else { throw ConversationOutboxError.sessionClosed }
            let id = UUID(); pending = id; current = nil; return id
        }
    }
    func accept(refreshID: UUID, authUserID: UUID, ownerID: UUID, localSessionGeneration: UInt64, epoch: UUID, enqueueOnly: Bool = false) throws -> ConversationOutboxServerObservation {
        try locked {
            guard !closed, pending == refreshID else { throw ConversationOutboxError.staleObservation }
            current = refreshID; pending = nil
            return .init(authUserID: authUserID, ownerID: ownerID, localSessionGeneration: localSessionGeneration,
                         epoch: epoch, authority: self, token: refreshID, enqueueOnly: enqueueOnly)
        }
    }
    func withPendingRefresh<Value>(_ refreshID: UUID, _ operation: () throws -> Value) throws -> Value {
        try locked {
            guard !closed, pending == refreshID else { throw ConversationOutboxError.staleObservation }
            return try operation()
        }
    }
    func checkOpen() throws { try locked { if closed { throw ConversationOutboxError.sessionClosed } } }
    func close() { locked { closed = true; pending = nil; current = nil } }
    fileprivate func perform<Value>(token: UUID, _ operation: () throws -> Value) throws -> Value {
        try locked {
            guard !closed, current == token else { throw ConversationOutboxError.staleObservation }
            return try operation()
        }
    }
    private func locked<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock.lock(); defer { lock.unlock() }; return try operation()
    }
}

/// Only current owned data is visible. Legacy/foreign/old-epoch work remains
/// encrypted and receives metadata sufficient for a deliberate safe decision.
struct ConversationOutboxViewSnapshot: Sendable {
    struct Held: Sendable {
        enum Reason: Sendable { case ownerUnavailable, epochUnavailable, differentScope }
        let commandID: UUID
        let canDiscardUnsent: Bool
        let reason: Reason
    }
    let entries: [ConversationOutboxEntry]
    let held: [Held]
}

/// Read-only token for an explicit local user decision. It never permits send
/// or acknowledgement; description/reflection never reveal the original body.
struct ConversationOutboxDecisionTicket: Sendable, CustomStringConvertible, CustomReflectable {
    let commandID: UUID
    let inputHash: String
    let wireBody: Data
    let originalServerEpoch: UUID?
    let originalPatientOwnerID: UUID?
    let ownerHash: String
    let localSessionGeneration: UInt64
    let scope: UUID
    var description: String { "ConversationOutboxDecisionTicket(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
