import AVFoundation
import Foundation

/// Writes the buffers delivered by the audio engine to a bounded mono WAV.
/// The tap and the UI can call this from separate threads. The lock gives the
/// file and converter a single owner and prevents writing after stop.
final class FlowVoicePCMFile: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let frameLimit: AVAudioFramePosition
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var failed = false
    private var hasSignal = false

    init(url: URL, inputFormat: AVAudioFormat, maximumDuration: TimeInterval) throws {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { throw MealCaptureFailure.captureUnavailable }
        self.converter = converter
        self.frameLimit = AVAudioFramePosition(outputFormat.sampleRate * maximumDuration)
        self.file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: outputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(outputFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
    }

    var progress: (seconds: TimeInterval, shouldStop: Bool) {
        lock.withLock {
            (Double(frames) / converter.outputFormat.sampleRate, failed || frames >= frameLimit)
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard file != nil, !failed, frames < frameLimit, buffer.frameLength > 0 else { return }
            guard buffer.format == converter.inputFormat else {
                failed = true
                return
            }
            let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 256
            writeConverted(buffer, capacity: capacity)
        }
    }

    func close() -> MealCaptureFailure? {
        lock.withLock {
            if file != nil, !failed, frames > 0, frames < frameLimit {
                writeConverted(nil, capacity: 512)
            }
            file?.close()
            file = nil
            if failed { return .captureUnavailable }
            return hasSignal ? nil : .nothingRecognized
        }
    }

    private func writeConverted(_ input: AVAudioPCMBuffer?, capacity: AVAudioFrameCount) {
        guard let file,
              let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)
        else {
            failed = true
            return
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            guard let input else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard !supplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error else {
            failed = true
            return
        }
        converted.frameLength = min(converted.frameLength, AVAudioFrameCount(frameLimit - frames))
        guard converted.frameLength > 0 else { return }
        do {
            try file.write(from: converted)
            frames += AVAudioFramePosition(converted.frameLength)
            if !hasSignal, let samples = converted.floatChannelData?[0] {
                // Ignore digital silence, including rounding to a single
                // signed PCM sample step. Quiet speech is still accepted.
                hasSignal = (0..<Int(converted.frameLength)).contains {
                    abs(samples[$0]) >= 2.0 / 32_768.0
                }
            }
        } catch {
            failed = true
        }
    }
}
