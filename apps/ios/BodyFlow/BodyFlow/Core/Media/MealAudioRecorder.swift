import AVFoundation
import Foundation
import Observation

/// Captures a mono voice note and stops automatically at the time limit.
/// The Flow composer uses a mono PCM WAV at a speech sample rate.
@MainActor
@Observable
final class MealAudioRecorder: NSObject, AVAudioRecorderDelegate {
    enum CaptureFormat {
        case aac
        case linearPCM
    }

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

    private struct EngineCapture {
        let engine: AVAudioEngine
        let file: FlowVoicePCMFile
        let url: URL

        func stop() -> MealCaptureFailure? {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            return file.close()
        }
    }

    private let staging: MediaStagingStore
    private let captureFormat: CaptureFormat
    private let sessionAccess: SessionAccess
    private var ownsAudioSession = false
    private var recorder: AVAudioRecorder?
    private var engineCapture: EngineCapture?
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
        captureFormat: CaptureFormat = .aac,
        sessionAccess: SessionAccess? = nil
    ) {
        self.staging = staging
        self.captureFormat = captureFormat
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
            let pcm = captureFormat == .linearPCM
            let url = try staging.makeFileURL(fileExtension: pcm ? "wav" : "m4a")
            do {
                if pcm {
                    engineCapture = try startEngineCapture(at: url)
                } else {
                    let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
                    recorder.delegate = self
                    guard recorder.record(forDuration: Self.recordingLimit)
                    else { throw MealCaptureFailure.captureUnavailable }
                    self.recorder = recorder
                }
            } catch {
                staging.remove(url)
                throw error
            }
            elapsed = 0
            state = .recording
            startTicker()
        } catch {
            releaseSession()
            state = .failed((error as? MealCaptureFailure) == .nothingRecognized
                ? .nothingRecognized : .captureUnavailable)
        }
    }

    func stop() {
        guard state == .recording else { return }
        if let capture = engineCapture {
            finish(url: capture.url, failure: capture.stop())
        } else {
            recorder?.stop()
        }
    }

    private func startEngineCapture(at url: URL) throws -> EngineCapture {
        guard AVAudioSession.sharedInstance().isInputAvailable, !AVAudioApplication.shared.isInputMuted
        else { throw MealCaptureFailure.nothingRecognized }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let file = try FlowVoicePCMFile(
            url: url, inputFormat: format, maximumDuration: Self.recordingLimit
        )
        input.installTap(onBus: 0, bufferSize: 1_024, format: nil) { @Sendable buffer, _ in
            file.append(buffer)
        }
        let capture = EngineCapture(engine: engine, file: file, url: url)
        do {
            try engine.start()
            return capture
        } catch {
            _ = capture.stop()
            throw error
        }
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
        if let capture = engineCapture {
            _ = capture.stop()
            staging.remove(capture.url)
            engineCapture = nil
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
            self.finish(url: url, failure: flag ? nil : .captureUnavailable)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: (any Error)?
    ) {
        let url = recorder.url
        Task { @MainActor in
            self.finish(url: url, failure: .captureUnavailable)
        }
    }

    private func finish(url: URL, failure: MealCaptureFailure?) {
        guard recorder?.url == url || engineCapture?.url == url else { return }
        ticker?.cancel()
        ticker = nil
        recorder = nil
        engineCapture = nil
        releaseSession()
        if let failure {
            staging.remove(url)
            state = .failed(failure)
        } else {
            state = .finished(url)
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            let started = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                if let capture = self.engineCapture {
                    let progress = capture.file.progress
                    self.elapsed = progress.seconds
                    if progress.shouldStop || started.duration(to: .now) >= .seconds(Self.recordingLimit) {
                        self.stop()
                        return
                    }
                } else {
                    guard let recorder = self.recorder, recorder.isRecording else { return }
                    self.elapsed = min(recorder.currentTime, MealMediaLimits.maximumAudioDuration)
                }
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
