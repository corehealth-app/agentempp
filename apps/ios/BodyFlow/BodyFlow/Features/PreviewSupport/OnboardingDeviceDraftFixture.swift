#if DEBUG
import Foundation

/// UI-test fixture (update of 2026-10-11, package A4). The sign-up of a real
/// account keeps its unfinished draft on the phone; the demonstration does
/// not go through that path, so a UI test could not see it. This runs the
/// real repository over a stand-in server that has nothing of the account.
/// Debug builds only; nothing of it exists in Release.
enum OnboardingDeviceDraftFixture {
    /// A folder of its own inside the app's container: the fixture never
    /// reads or removes what a real account kept.
    static var store: OnboardingDeviceDraftStore {
        OnboardingDeviceDraftStore(
            directory: URL.applicationSupportDirectory
                .appendingPathComponent("ui-testing", isDirectory: true)
        )
    }
}

/// Explicit synthetic authority for the isolated Debug fixture only.
/// The real Release graph always uses its authentication lifecycle.
actor OnboardingDeviceDraftFixtureLifecycle: SessionLifecycleProviding {
    private let store: OnboardingDeviceDraftStore
    private var active = true
    init(store: OnboardingDeviceDraftStore) { self.store = store }
    private var lease: SessionLease {
        SessionLease(userID: DemoUser.id, generation: 0, bearer: "synthetic-fixture")
    }
    func currentBearerToken() -> String? { active ? lease.bearer : nil }
    func leaseForRequest() throws -> SessionLease {
        guard active else { throw SessionLifecycleError.missingSession }
        return lease
    }
    func validate(_ candidate: SessionLease) throws {
        guard active, candidate.userID == lease.userID,
              candidate.generation == lease.generation else {
            throw SessionLifecycleError.sessionSuperseded
        }
    }
    func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease {
        throw SessionLifecycleError.refreshFailed
    }
    func signOut() -> RemoteRevocationOutcome {
        active = false
        store.clear()
        return .confirmed
    }
    func beginPatientWork(
        lease: SessionLease, cancel: @escaping @Sendable () -> Void
    ) throws -> UUID {
        try validate(lease)
        return UUID()
    }
    func finishPatientWork(_ id: UUID) {}
    func performPatientStateOperation<Value: Sendable>(
        lease: SessionLease, operation: @Sendable () throws -> Value
    ) throws -> Value {
        try Task.checkCancellation()
        try validate(lease)
        return try operation()
    }
}

/// Answers the read of a sign-up that was never finished and that the
/// server keeps nothing of. Every other request fails, as with no server.
struct OnboardingDeviceDraftFixtureTransport: MobileAPIExecuting {
    func execute<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> Response {
        let unfinished = OnboardingServerState(
            locale: DemoOnboardingSuggestions.currentDevice.localeIdentifier,
            completion: OnboardingCompletionState(completed: false, completedAt: nil),
            requirements: .unavailable,
            acceptedActions: []
        )
        guard request.method == .get,
              request.path == "/api/mobile/v1/onboarding",
              let response = unfinished as? Response else {
            throw MobileAPITransportError.network
        }
        return response
    }
}
#endif
