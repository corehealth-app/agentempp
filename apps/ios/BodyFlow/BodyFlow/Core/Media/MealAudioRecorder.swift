import AVFoundation
import Foundation
import Observation

/// Records the patient describing the meal: AAC in an .m4a, mono, and never
/// longer than the limit — the recorder stops by itself at 180 seconds.
@MainActor
@Observable
final class MealAudioRecorder: NSObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case recording
        case finished(URL)
        case failed(MealCaptureFailure)
    }

    @MainActor
    struct SessionAccess {
        let requestPermission: @MainActor () async -> Bool
        let configureActivate: @MainActor () throws -> Void
        let deactivate: @MainActor () throws -> Void
    }

    private let staging: MediaStagingStore
    private let sessionAccess: SessionAccess
    private var ownsAudioSession = false
    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void, Never>?

    private(set) var state = State.idle
    private(set) var elapsed: TimeInterval = 0
    private var isStarting = false
    private var pendingStartID: UUID?

    /// The recorder stops a little before the limit: the file measures a few
    /// milliseconds more than was asked, and a recording that ran to the end
    /// must not be refused as too long.
    static let recordingLimit = MealMediaLimits.maximumAudioDuration - 0.5

    init(
        staging: MediaStagingStore,
        sessionAccess: SessionAccess? = nil
    ) {
        self.staging = staging
        self.sessionAccess = sessionAccess ?? SessionAccess(
            requestPermission: {
                await AVAudioApplication.requestRecordPermission()
            },
            configureActivate: {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .default)
                try session.setActive(true)
            },
            deactivate: {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
            }
        )
    }

    static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    func start() async {
        guard state != .recording, !isStarting else { return }
        isStarting = true
        discard()
        let startID = UUID()
        pendingStartID = startID
        defer {
            isStarting = false
            if pendingStartID == startID { pendingStartID = nil }
        }
        let permissionGranted = await sessionAccess.requestPermission()
        guard pendingStartID == startID else { return }
        guard permissionGranted else {
            state = .failed(.permissionDenied)
            return
        }
        do {
            try sessionAccess.configureActivate()
            ownsAudioSession = true
            let url = try staging.makeFileURL(fileExtension: "m4a")
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            recorder.delegate = self
            guard recorder.record(forDuration: Self.recordingLimit) else {
                staging.remove(url)
                throw MealCaptureFailure.captureUnavailable
            }
            self.recorder = recorder
            elapsed = 0
            state = .recording
            startTicker()
        } catch {
            releaseSession()
            state = .failed(.captureUnavailable)
        }
    }

    func stop() {
        guard state == .recording, let recorder else { return }
        recorder.stop()
    }

    /// Drops the recording in hand, whatever its state.
    func discard() {
        pendingStartID = nil
        ticker?.cancel()
        ticker = nil
        if let recorder {
            recorder.delegate = nil
            recorder.stop()
            staging.remove(recorder.url)
        }
        if case let .finished(url) = state {
            staging.remove(url)
        }
        recorder = nil
        releaseSession()
        elapsed = 0
        state = .idle
    }

    /// Hands the finished file over; the recorder forgets it.
    func takeRecording() -> URL? {
        guard case let .finished(url) = state else { return nil }
        recorder = nil
        elapsed = 0
        state = .idle
        return url
    }

    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        let url = recorder.url
        Task { @MainActor in
            self.finish(url: url, successfully: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: (any Error)?
    ) {
        let url = recorder.url
        Task { @MainActor in
            self.finish(url: url, successfully: false)
        }
    }

    private func finish(url: URL, successfully: Bool) {
        guard recorder?.url == url else { return }
        ticker?.cancel()
        ticker = nil
        recorder = nil
        releaseSession()
        if successfully {
            state = .finished(url)
        } else {
            staging.remove(url)
            state = .failed(.captureUnavailable)
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let recorder = self.recorder, recorder.isRecording else {
                    return
                }
                self.elapsed = min(
                    recorder.currentTime,
                    MealMediaLimits.maximumAudioDuration
                )
            }
        }
    }

    private func releaseSession() {
        guard ownsAudioSession else { return }
        do {
            try sessionAccess.deactivate()
            ownsAudioSession = false
        } catch {
            // Keep the cleanup obligation so a later discard can retry.
        }
    }
}
