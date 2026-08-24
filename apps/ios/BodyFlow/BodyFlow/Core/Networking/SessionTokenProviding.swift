import Foundation

protocol SessionTokenProviding: Sendable {
    func currentBearerToken() async -> String?
}

struct SessionLease: Equatable, Sendable, CustomStringConvertible,
    CustomReflectable {
    let userID: String
    let generation: UInt64
    let bearer: String

    var description: String { "SessionLease(redacted)" }
    var customMirror: Mirror {
        Mirror(self, children: [:], displayStyle: .struct)
    }
}

enum SessionLifecycleError: Error, Equatable, Sendable {
    case missingSession
    case refreshFailed
    case sessionSuperseded
    case localInvalidationFailed
}

struct SessionRefreshPolicy: Sendable {
    let now: @Sendable () -> Date
    let leeway: TimeInterval

    static let production = SessionRefreshPolicy(
        now: Date.init,
        leeway: 60
    )
}

protocol SessionLifecycleProviding: SessionTokenProviding {
    func restorePublicSession() async throws -> AuthSession?
    func `switch`(to record: AuthenticationSessionRecord) async throws
    func leaseForRequest() async throws -> SessionLease
    func refreshAfterUnauthorized(lease: SessionLease) async throws
        -> SessionLease
    func validate(_ lease: SessionLease) async throws
    func signOut() async -> RemoteRevocationOutcome
    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) async throws -> UUID
    func finishPatientWork(_ id: UUID) async
}

extension SessionLifecycleProviding {
    func restorePublicSession() async throws -> AuthSession? {
        throw SessionLifecycleError.missingSession
    }

    func `switch`(to record: AuthenticationSessionRecord) async throws {
        throw SessionLifecycleError.refreshFailed
    }
}

protocol SensitiveStateClearing: Sendable {
    func clearSensitiveState() async
}

struct NoopSensitiveStateClearer: SensitiveStateClearing {
    func clearSensitiveState() async {}
}
