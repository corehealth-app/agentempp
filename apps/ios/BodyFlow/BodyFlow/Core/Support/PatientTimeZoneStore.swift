import Foundation

/// The patient's documented time zone for the running session. The demo
/// seeds it from the launch configuration; a real account resolves it from
/// `GET /me` after sign-in and resets it when that session ends, so no
/// screen ever reads another user's zone. Validation stays in
/// `PatientTimeZoneContext.requireTimeZone()`: an undocumented or unknown
/// identifier keeps snooze and local times unavailable.
final class PatientTimeZoneStore: @unchecked Sendable {
    private let lock = NSLock()
    private let seed: PatientTimeZoneContext
    private var context: PatientTimeZoneContext

    init(seed: PatientTimeZoneContext) {
        self.seed = seed
        context = seed
    }

    var current: PatientTimeZoneContext {
        lock.withLock { context }
    }

    func resolve(documentedIANAIdentifier: String?) {
        lock.withLock {
            context = PatientTimeZoneContext(
                documentedIANAIdentifier: documentedIANAIdentifier
            )
        }
    }

    func reset() {
        lock.withLock { context = seed }
    }
}

/// Sign-out and a cross-user switch clear it through the session lifecycle
/// as well, independently of the shell owner's teardown.
extension PatientTimeZoneStore: SensitiveStateClearing {
    func clearSensitiveState() async {
        reset()
    }
}
