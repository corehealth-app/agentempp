import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns whatever the camera or the library gave into the photo that leaves
/// the phone: at most 2048 px on the long side, JPEG, upright, and with none
/// of the original's metadata (no EXIF, no GPS, no device data) — the pixels
/// are drawn into a new image and only they are written.
enum MealPhotoNormalizer {
    static func normalizedJPEG(from data: Data) throws -> Data {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0
        else {
            throw MealCaptureFailure.unreadableMedia
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: MealMediaLimits.maximumPhotoPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw MealCaptureFailure.unreadableMedia
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw MealCaptureFailure.unreadableMedia
        }
        let properties = [
            kCGImageDestinationLossyCompressionQuality: MealMediaLimits.photoCompressionQuality,
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            throw MealCaptureFailure.unreadableMedia
        }
        return output as Data
    }
}

/// Reads what an audio file is before it is sent: a type the server accepts
/// and the real length, measured from the file.
enum MealAudioInspector {
    struct Description: Equatable, Sendable {
        let mimeType: String
        let fileExtension: String
        let duration: TimeInterval
    }

    static let mimeTypesByExtension = [
        "m4a": "audio/mp4",
        "mp4": "audio/mp4",
        "mp3": "audio/mpeg",
        "wav": "audio/wav",
        "aac": "audio/aac",
    ]

    /// The extension staged files use for each accepted type.
    static func stagedExtension(for pathExtension: String) -> String? {
        let lowered = pathExtension.lowercased()
        guard mimeTypesByExtension[lowered] != nil else { return nil }
        return lowered == "mp4" ? "m4a" : lowered
    }

    static func describe(_ fileURL: URL) async throws -> Description {
        guard let fileExtension = stagedExtension(for: fileURL.pathExtension),
              let mimeType = mimeTypesByExtension[fileExtension]
        else {
            throw MealCaptureFailure.unsupportedFile
        }
        let asset = AVURLAsset(url: fileURL)
        let seconds: TimeInterval
        do {
            seconds = try await asset.load(.duration).seconds
        } catch {
            throw MealCaptureFailure.unreadableMedia
        }
        guard seconds.isFinite, seconds > 0 else {
            throw MealCaptureFailure.unreadableMedia
        }
        guard seconds <= MealMediaLimits.maximumAudioDuration else {
            throw MealCaptureFailure.audioTooLong
        }
        return Description(mimeType: mimeType, fileExtension: fileExtension, duration: seconds)
    }
}

/// Stages captures: the only place a photo or a recording becomes a file
/// ready to upload.
struct MealMediaStager: Sendable {
    let staging: MediaStagingStore

    func stagePhoto(_ data: Data, channel: MealSourceChannel) throws -> StagedMedia {
        guard channel.isPhoto else { throw MealCaptureFailure.invalidInput }
        let jpeg = try MealPhotoNormalizer.normalizedJPEG(from: data)
        guard jpeg.count <= MealMediaLimits.maximumPhotoBytes else {
            throw MealCaptureFailure.fileTooLarge
        }
        let url = try staging.stage(jpeg, fileExtension: "jpg")
        return StagedMedia(
            fileURL: url,
            kind: .mealPhoto,
            mimeType: "image/jpeg",
            sizeBytes: jpeg.count,
            duration: nil,
            channel: channel
        )
    }

    /// A recording already written inside the staging area.
    func stageRecording(at fileURL: URL) async throws -> StagedMedia {
        do {
            return try await stagedAudio(at: fileURL, channel: .audioRecording)
        } catch {
            staging.remove(fileURL)
            throw error
        }
    }

    /// A file the patient picked: checked where it is, then copied.
    func stageImportedAudio(from source: URL) async throws -> StagedMedia {
        guard let fileExtension = MealAudioInspector.stagedExtension(
            for: source.pathExtension
        ) else {
            throw MealCaptureFailure.unsupportedFile
        }
        let size = try Self.fileSize(of: source)
        guard size <= MealMediaLimits.maximumAudioBytes else {
            throw MealCaptureFailure.fileTooLarge
        }
        let copy = try staging.stageCopy(of: source, fileExtension: fileExtension)
        do {
            return try await stagedAudio(at: copy, channel: .audioImport)
        } catch {
            staging.remove(copy)
            throw error
        }
    }

    private func stagedAudio(
        at fileURL: URL,
        channel: MealSourceChannel
    ) async throws -> StagedMedia {
        let description = try await MealAudioInspector.describe(fileURL)
        let size = try Self.fileSize(of: fileURL)
        guard size > 0 else { throw MealCaptureFailure.unreadableMedia }
        guard size <= MealMediaLimits.maximumAudioBytes else {
            throw MealCaptureFailure.fileTooLarge
        }
        return StagedMedia(
            fileURL: fileURL,
            kind: .audioNote,
            mimeType: description.mimeType,
            sizeBytes: size,
            duration: description.duration,
            channel: channel
        )
    }

    private static func fileSize(of url: URL) throws -> Int {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw MealCaptureFailure.unreadableMedia
        }
        return size
    }
}
