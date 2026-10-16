import Foundation
import Testing

@testable import BodyFlow

@Suite("Meal audio recorder late permission")
@MainActor
struct MealAudioRecorderLatePermissionTests {
    @Test("Discard ends a pending start before a late permission grant can activate audio")
    func discardedStartIgnoresLatePermissionGrant() async {
        let boundary = LatePermissionAudioBoundary()
        // A value only: no directory is created or capture staged by this test.
        let staging = MediaStagingStore(
            temporaryDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "meal-audio-late-permission-\(UUID().uuidString)", isDirectory: true
            )
        )
        let recorder = MealAudioRecorder(staging: staging, sessionAccess: boundary.access)
        let pendingStart = Task { await recorder.start() }

        // The gate resumes this waiter only after storing the permission
        // continuation. Discard therefore happens while permission is pending.
        await boundary.permission.waitUntilRequested()
        #expect(boundary.permission.requestCount == 1)
        #expect(boundary.activationAttempts == 0)

        recorder.discard()
        #expect(recorder.state == .idle)
        #expect(recorder.elapsed == 0)

        let resumed = boundary.permission.resolve(granted: true)
        #expect(resumed)
        await pendingStart.value

        #expect(boundary.permission.requestCount == 1)
        #expect(boundary.activationAttempts == 0)
        #expect(recorder.state == .idle)
        #expect(recorder.elapsed == 0)
    }
}

@MainActor
private final class LatePermissionAudioBoundary {
    let permission = PendingAudioPermission()
    private(set) var activationAttempts = 0

    var access: MealAudioRecorder.SessionAccess {
        MealAudioRecorder.SessionAccess(
            requestPermission: { await self.permission.request() },
            configureActivate: {
                self.activationAttempts += 1
                // Safety tripwire: even a failing recorder implementation
                // stops here, before staging or AVAudioRecorder construction.
                throw LateAudioPermissionFixtureFailure.activationReached
            },
            // The five ownership tests own the release-count oracles. This
            // boundary never touches the native shared session, even on RED.
            deactivate: {}
        )
    }
}

@MainActor
private final class PendingAudioPermission {
    private(set) var requestCount = 0
    private var response: CheckedContinuation<Bool, Never>?
    private var requestedWaiters: [CheckedContinuation<Void, Never>] = []

    func request() async -> Bool {
        requestCount += 1
        guard requestCount == 1 else {
            Issue.record("This fixture admits exactly one permission request")
            return false
        }
        return await withCheckedContinuation { continuation in
            response = continuation
            let waiters = requestedWaiters
            requestedWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilRequested() async {
        guard response == nil else { return }
        await withCheckedContinuation { requestedWaiters.append($0) }
    }

    func resolve(granted: Bool) -> Bool {
        guard let continuation = response else {
            Issue.record("Permission was not pending when the test tried to resolve it")
            return false
        }
        response = nil
        continuation.resume(returning: granted)
        return true
    }
}

private enum LateAudioPermissionFixtureFailure: Error {
    case activationReached
}
