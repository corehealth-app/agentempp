import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import BodyFlow

enum Prompt14CoverFixtures {
    static let jpeg = encodedImage(type: .jpeg, width: 600, height: 400)
    static let portraitJPEG = encodedImage(type: .jpeg, width: 400, height: 600)
    static let png = encodedImage(type: .png, width: 2, height: 1)
    // A first-party, deterministic 1 × 1 lossy WebP bitstream.
    static let webP = Data(base64Encoded: "UklGRiIAAABXRUJQVlA4IBYAAACQAQCdASoBAAEAAUAmJaQAA3AA/v3AgAA=")!

    static func stream(
        body: Data,
        statusCode: Int = 200,
        declaredLength: Int64? = nil,
        mimeType: String? = "image/png",
        redirectLocation: URL? = nil,
        chunkSize: Int = 1_024
    ) -> CoverFixture {
        let probe = CoverStreamProbe(body: body, chunkSize: chunkSize)
        return CoverFixture(
            stream: ContentCoverByteStream(
                statusCode: statusCode,
                declaredLength: declaredLength,
                mimeType: mimeType,
                cacheMaxAgeSeconds: nil,
                redirectLocation: redirectLocation,
                chunks: AsyncThrowingStream(unfolding: {
                    await probe.nextChunk()
                }),
                cancel: {
                    await probe.cancel()
                }
            ),
            probe: probe
        )
    }

    static func chunkedBody(byteCount: Int) -> CoverFixture {
        var body = png
        body.append(Data(repeating: 0, count: byteCount - body.count))
        return stream(
            body: body,
            declaredLength: nil,
            mimeType: "image/png",
            chunkSize: 65_536
        )
    }

    static func oversizedBodyWithSentinel() -> CoverFixture {
        var acceptedBody = png
        acceptedBody.append(Data(repeating: 0, count: 10_485_760 - acceptedBody.count))
        return scripted(
            chunks: [acceptedBody, Data([0]), Data([0xFF])],
            mimeType: "image/png"
        )
    }

    static func scripted(
        chunks: [Data],
        statusCode: Int = 200,
        declaredLength: Int64? = nil,
        mimeType: String? = "image/png",
        redirectLocation: URL? = nil
    ) -> CoverFixture {
        let probe = CoverStreamProbe(chunks: chunks)
        return CoverFixture(
            stream: ContentCoverByteStream(
                statusCode: statusCode,
                declaredLength: declaredLength,
                mimeType: mimeType,
                cacheMaxAgeSeconds: nil,
                redirectLocation: redirectLocation,
                chunks: AsyncThrowingStream(unfolding: {
                    await probe.nextChunk()
                }),
                cancel: {
                    await probe.cancel()
                }
            ),
            probe: probe
        )
    }

    static func stalledStream() -> StalledCoverFixture {
        let probe = StalledCoverProbe()
        return StalledCoverFixture(
            stream: ContentCoverByteStream(
                statusCode: 200,
                declaredLength: nil,
                mimeType: "image/png",
                cacheMaxAgeSeconds: nil,
                redirectLocation: nil,
                chunks: AsyncThrowingStream(unfolding: {
                    await probe.nextChunk()
                }),
                cancel: {
                    await probe.cancel()
                }
            ),
            probe: probe
        )
    }

    static func pngHeader(width: UInt32, height: UInt32) -> Data {
        var body = Data([137, 80, 78, 71, 13, 10, 26, 10])
        var ihdr = Data()
        ihdr.append(bigEndian: width)
        ihdr.append(bigEndian: height)
        ihdr.append(contentsOf: [8, 2, 0, 0, 0])
        body.append(pngChunk(named: "IHDR", payload: ihdr))
        body.append(pngChunk(named: "IEND", payload: Data()))
        return body
    }

    private static func encodedImage(type: UTType, width: Int, height: Int) -> Data {
        let bytesPerRow = width * 4
        let pixelBytes = Data(repeating: 0x7F, count: bytesPerRow * height)
        let provider = CGDataProvider(data: pixelBytes as CFData)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let encoded = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            encoded,
            type.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return encoded as Data
    }

    private static func pngChunk(named name: String, payload: Data) -> Data {
        var chunk = Data()
        chunk.append(bigEndian: UInt32(payload.count))
        let type = Data(name.utf8)
        chunk.append(type)
        chunk.append(payload)
        chunk.append(bigEndian: crc32(type + payload))
        return chunk
    }

    private static func crc32(_ bytes: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320
            }
        }
        return crc ^ UInt32.max
    }
}

struct CoverFixture: Sendable {
    let stream: ContentCoverByteStream
    let probe: CoverStreamProbe
}

actor CoverStreamProbe {
    private let chunks: [Data]
    private var nextChunkIndex = 0
    private(set) var chunkCount = 0
    private(set) var deliveredByteCount = 0
    private(set) var cancelCount = 0

    init(body: Data, chunkSize: Int) {
        self.chunks = stride(from: 0, to: body.count, by: chunkSize).map { offset in
            body.subdata(in: offset..<min(offset + chunkSize, body.count))
        }
    }

    init(chunks: [Data]) {
        self.chunks = chunks
    }

    func nextChunk() -> Data? {
        guard nextChunkIndex < chunks.count else { return nil }
        let chunk = chunks[nextChunkIndex]
        defer {
            nextChunkIndex += 1
            chunkCount += 1
            deliveredByteCount += chunk.count
        }
        return chunk
    }

    func cancel() {
        cancelCount += 1
    }
}

struct StalledCoverFixture: Sendable {
    let stream: ContentCoverByteStream
    let probe: StalledCoverProbe
}

actor StalledCoverProbe {
    private var nextChunkContinuation: CheckedContinuation<Data?, Never>?
    private var stalledContinuation: CheckedContinuation<Void, Never>?
    private var cancelledContinuation: CheckedContinuation<Void, Never>?
    private var cancelled = false
    private(set) var cancelCount = 0

    func nextChunk() async -> Data? {
        guard !cancelled else { return nil }
        return await withCheckedContinuation { continuation in
            if cancelled {
                continuation.resume(returning: nil)
            } else {
                nextChunkContinuation = continuation
                stalledContinuation?.resume()
                stalledContinuation = nil
            }
        }
    }

    func waitUntilStalled() async {
        guard nextChunkContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            stalledContinuation = continuation
        }
    }

    func waitUntilCancelled() async {
        guard !cancelled else { return }
        await withCheckedContinuation { continuation in
            cancelledContinuation = continuation
        }
    }

    func cancel() {
        guard !cancelled else { return }
        cancelCount += 1
        cancelled = true
        nextChunkContinuation?.resume(returning: nil)
        nextChunkContinuation = nil
        cancelledContinuation?.resume()
        cancelledContinuation = nil
    }

    func release() {
        nextChunkContinuation?.resume(returning: nil)
        nextChunkContinuation = nil
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
