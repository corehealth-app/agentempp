import Foundation
import Testing

@testable import BodyFlow

@Suite("Meal audio session ownership")
@MainActor
struct MealAudioSessionOwnershipTests {
    @Test("Discarding an idle recorder twice never touches the audio session")
    func idleDoubleDiscardDoesNotTouchSession() throws {
        let fixture = try BlockedAudioStaging()
        defer { fixture.cleanUp() }
        let session = AudioSessionProbe(permissionGranted: true)
        let recorder = MealAudioRecorder(staging: fixture.staging, sessionAccess: session.access)

        #expect(session.events == [])
        #expect(recorder.state == .idle)
        #expect(recorder.elapsed == 0)
        recorder.discard()
        recorder.discard()
        #expect(session.events == [])
        #expect(recorder.state == .idle)
        #expect(recorder.elapsed == 0)
    }

    @Test("Denied permission never acquires or releases an audio session")
    func deniedPermissionNeverAcquiresOrReleases() async throws {
        let fixture = try BlockedAudioStaging()
        defer { fixture.cleanUp() }
        let session = AudioSessionProbe(permissionGranted: false)
        let recorder = MealAudioRecorder(staging: fixture.staging, sessionAccess: session.access)

        await recorder.start()
        #expect(session.events == [.requestPermission])
        #expect(recorder.state == .failed(.permissionDenied))
        #expect(recorder.elapsed == 0)
        recorder.discard()
        recorder.discard()
        #expect(session.events == [.requestPermission])
        #expect(recorder.state == .idle)
        #expect(recorder.elapsed == 0)
    }

    @Test("An activation that throws never grants a session to release")
    func failedActivationDoesNotReleaseUnacquiredSession() async throws {
        let fixture = try BlockedAudioStaging()
        defer { fixture.cleanUp() }
        let session = AudioSessionProbe(permissionGranted: true, activationThrows: true)
        let recorder = MealAudioRecorder(staging: fixture.staging, sessionAccess: session.access)

        await recorder.start()
        #expect(session.events == [.requestPermission, .configureActivate])
        #expect(recorder.state == .failed(.captureUnavailable))
        #expect(recorder.elapsed == 0)
        recorder.discard()
        recorder.discard()
        #expect(session.events == [.requestPermission, .configureActivate])
        #expect(recorder.state == .idle)
        #expect(recorder.elapsed == 0)
    }

    @Test("A staging failure after activation releases exactly once")
    func stagingFailureAfterAcquisitionReleasesExactlyOnce() async throws {
        let fixture = try BlockedAudioStaging()
        defer { fixture.cleanUp() }
        let session = AudioSessionProbe(permissionGranted: true)
        let recorder = MealAudioRecorder(staging: fixture.staging, sessionAccess: session.access)

        await recorder.start()
        #expect(session.events == [.requestPermission, .configureActivate, .deactivate])
        #expect(recorder.state == .failed(.captureUnavailable))
        #expect(recorder.elapsed == 0)
        recorder.discard()
        recorder.discard()
        #expect(session.events == [.requestPermission, .configureActivate, .deactivate])
        #expect(recorder.state == .idle)
        #expect(recorder.elapsed == 0)
    }

    @Test("Failed deactivation is retried by discard and success ends the retries")
    func failedDeactivationRetainsCleanupUntilSuccess() async throws {
        let fixture = try BlockedAudioStaging()
        defer { fixture.cleanUp() }
        let session = AudioSessionProbe(permissionGranted: true, deactivationFailures: 1)
        let recorder = MealAudioRecorder(staging: fixture.staging, sessionAccess: session.access)

        await recorder.start()
        #expect(session.events == [.requestPermission, .configureActivate, .deactivate])
        #expect(recorder.state == .failed(.captureUnavailable))
        #expect(recorder.elapsed == 0)

        recorder.discard()
        #expect(session.events == [
            .requestPermission, .configureActivate, .deactivate, .deactivate,
        ])
        #expect(recorder.state == .idle)
        #expect(recorder.elapsed == 0)

        recorder.discard()
        #expect(session.events == [
            .requestPermission, .configureActivate, .deactivate, .deactivate,
        ])
        #expect(recorder.state == .idle)
        #expect(recorder.elapsed == 0)
    }
}

/// Observes the real recorder's calls at its system audio boundary.
/// It never requests native permission, configures AVAudioSession, or records.
@MainActor
private final class AudioSessionProbe {
    enum Event: Equatable {
        case requestPermission
        case configureActivate
        case deactivate
    }

    private(set) var events: [Event] = []
    private let permissionGranted: Bool
    private let activationThrows: Bool
    private var deactivationFailures: Int

    init(
        permissionGranted: Bool,
        activationThrows: Bool = false,
        deactivationFailures: Int = 0
    ) {
        self.permissionGranted = permissionGranted
        self.activationThrows = activationThrows
        self.deactivationFailures = deactivationFailures
    }

    var access: MealAudioRecorder.SessionAccess {
        MealAudioRecorder.SessionAccess(
            requestPermission: {
                self.events.append(.requestPermission)
                return self.permissionGranted
            },
            configureActivate: {
                self.events.append(.configureActivate)
                if self.activationThrows { throw AudioOwnershipFixtureFailure.activation }
            },
            deactivate: {
                self.events.append(.deactivate)
                if self.deactivationFailures > 0 {
                    self.deactivationFailures -= 1
                    throw AudioOwnershipFixtureFailure.deactivation
                }
            }
        )
    }
}

/// A regular file occupies temporaryDirectory, so createDirectory below
/// it must fail. The real staging store is exercised during preflight.
/// Therefore every start path stops before AVAudioRecorder's constructor.
private struct BlockedAudioStaging {
    let directory: URL
    let staging: MediaStagingStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "meal-audio-ownership-\(UUID().uuidString)", isDirectory: true
        )
        let blocker = directory.appendingPathComponent("regular-file", isDirectory: false)
        staging = MediaStagingStore(temporaryDirectory: blocker)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try Data("synthetic staging blocker".utf8).write(to: blocker)
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: blocker.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw AudioOwnershipFixtureFailure.blockerIsNotARegularFile
            }
            do {
                _ = try staging.makeFileURL(fileExtension: "m4a")
                throw AudioOwnershipFixtureFailure.stagingWasUnexpectedlyAvailable
            } catch let failure as MealCaptureFailure {
                guard failure == .unavailable else { throw failure }
            }
        } catch {
            cleanUp()
            throw error
        }
    }

    func cleanUp() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Could not remove this test's synthetic staging directory: \(error)")
        }
    }
}

private enum AudioOwnershipFixtureFailure: Error {
    case activation
    case deactivation
    case blockerIsNotARegularFile
    case stagingWasUnexpectedlyAvailable
}
