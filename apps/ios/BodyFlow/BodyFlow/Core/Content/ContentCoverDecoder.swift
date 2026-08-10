import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ContentCoverTargetSize: Equatable, Sendable {
    let widthPixels: Int
    let heightPixels: Int

    init(widthPixels: Int, heightPixels: Int) {
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
    }

    fileprivate var isValid: Bool {
        (1...ContentCoverDimensionPolicy.maximumDimension).contains(widthPixels)
            && (1...ContentCoverDimensionPolicy.maximumDimension).contains(heightPixels)
    }

}

struct ContentCoverImage: @unchecked Sendable {
    let cgImage: CGImage
}

struct ContentCoverDecoder: Sendable {
    fileprivate static let maximumBodyBytes = 10_485_760

    func decode(
        _ stream: ContentCoverByteStream,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage {
        let declaredType = try validatedDeclaredType(for: stream)
        guard target.isValid else {
            throw BodyFlowCapabilityError.invalidContentCover
        }
        let cancellation = ContentCoverStreamCancellation(cancel: stream.cancel)

        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            let body = try await boundedBody(
                from: stream,
                cancellation: cancellation
            )
            try Task.checkCancellation()
            let image = try decodedThumbnail(
                from: body,
                declaredType: declaredType,
                target: target
            )
            try Task.checkCancellation()
            return image
        }, onCancel: {
            Task {
                await cancellation.cancel()
            }
        })
    }

    private func boundedBody(
        from stream: ContentCoverByteStream,
        cancellation: ContentCoverStreamCancellation
    ) async throws -> Data {
        var body = Data()
        if let declaredLength = stream.declaredLength {
            body.reserveCapacity(Int(declaredLength))
        }
        var receivedBytes = 0

        do {
            for try await chunk in stream.chunks {
                try Task.checkCancellation()
                let (nextByteCount, overflow) = receivedBytes.addingReportingOverflow(chunk.count)
                guard !overflow, nextByteCount <= Self.maximumBodyBytes else {
                    await cancellation.cancel()
                    throw BodyFlowCapabilityError.contentCoverTooLarge
                }
                receivedBytes = nextByteCount
                body.append(chunk)
            }
            try Task.checkCancellation()
            return body
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BodyFlowCapabilityError {
            throw error
        } catch {
            try Task.checkCancellation()
            throw BodyFlowCapabilityError.invalidContentCover
        }
    }

    private func validatedDeclaredType(
        for stream: ContentCoverByteStream
    ) throws -> SupportedImageType {
        guard stream.redirectLocation == nil else {
            throw BodyFlowCapabilityError.invalidContentCover
        }
        guard stream.statusCode != 404 else {
            throw BodyFlowCapabilityError.contentCoverNotFound
        }
        guard stream.statusCode == 200 else {
            throw BodyFlowCapabilityError.invalidContentCover
        }
        if let declaredLength = stream.declaredLength {
            guard declaredLength >= 0 else {
                throw BodyFlowCapabilityError.invalidContentCover
            }
            guard declaredLength <= Int64(Self.maximumBodyBytes) else {
                throw BodyFlowCapabilityError.contentCoverTooLarge
            }
        }
        guard let mimeType = stream.mimeType,
              let type = SupportedImageType(mimeType: mimeType)
        else {
            throw BodyFlowCapabilityError.invalidContentCover
        }
        return type
    }

    private func decodedThumbnail(
        from body: Data,
        declaredType: SupportedImageType,
        target: ContentCoverTargetSize
    ) throws -> ContentCoverImage {
        guard let source = CGImageSourceCreateWithData(body as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              CFEqual(sourceType, declaredType.identifier as CFString),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        let dimensions = try ContentCoverDimensionPolicy.validating(
            width: width,
            height: height
        )

        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: dimensions.thumbnailMaximumPixelSize(
                for: target
            ),
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        return ContentCoverImage(cgImage: thumbnail)
    }

}

struct ContentCoverDimensions: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixelCount: Int

    fileprivate func thumbnailMaximumPixelSize(
        for target: ContentCoverTargetSize
    ) -> Int {
        let scale = min(
            1,
            Double(target.widthPixels) / Double(width),
            Double(target.heightPixels) / Double(height)
        )
        let scaledWidth = max(1, Int((Double(width) * scale).rounded(.down)))
        let scaledHeight = max(1, Int((Double(height) * scale).rounded(.down)))
        return max(scaledWidth, scaledHeight)
    }
}

private actor ContentCoverStreamCancellation {
    private let operation: @Sendable () async -> Void
    private var didCancel = false

    init(cancel: @escaping @Sendable () async -> Void) {
        operation = cancel
    }

    func cancel() async {
        guard !didCancel else { return }
        didCancel = true
        await operation()
    }
}

enum ContentCoverDimensionPolicy {
    static let maximumDimension = 16_384
    static let maximumPixelCount = 64_000_000

    static func validating(
        width: NSNumber,
        height: NSNumber
    ) throws -> ContentCoverDimensions {
        guard let width = exactPositiveInteger(from: width),
              let height = exactPositiveInteger(from: height)
        else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        let (pixelCount, overflowed) = width.multipliedReportingOverflow(by: height)
        guard !overflowed,
              width <= maximumDimension,
              height <= maximumDimension,
              pixelCount <= maximumPixelCount
        else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        return ContentCoverDimensions(
            width: width,
            height: height,
            pixelCount: pixelCount
        )
    }

    private static func exactPositiveInteger(from number: NSNumber) -> Int? {
        if CFNumberIsFloatType(number as CFNumber) {
            guard let value = Int(exactly: number.doubleValue), value > 0 else {
                return nil
            }
            return value
        }

        guard let value = Int(exactly: number.uint64Value), value > 0 else {
            return nil
        }
        return value
    }
}

private enum SupportedImageType {
    case jpeg
    case png
    case webP

    init?(mimeType: String) {
        switch mimeType {
        case "image/jpeg": self = .jpeg
        case "image/png": self = .png
        case "image/webp": self = .webP
        default: return nil
        }
    }

    var identifier: String {
        switch self {
        case .jpeg: UTType.jpeg.identifier
        case .png: UTType.png.identifier
        case .webP: UTType.webP.identifier
        }
    }
}
