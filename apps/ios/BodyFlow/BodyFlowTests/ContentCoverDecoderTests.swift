import CoreGraphics
import Foundation
import Testing

@testable import BodyFlow

@Suite("Content cover decoding")
struct ContentCoverDecoderTests {
    @Test("decoder accepts JPEG, PNG, and WebP only when each declaration matches its bytes (catches removing MIME/type matching)")
    func acceptsExactMimeTypesThatMatchImageBytes() async throws {
        for (body, mimeType) in [
            (Prompt14CoverFixtures.jpeg, "image/jpeg"),
            (Prompt14CoverFixtures.png, "image/png"),
            (Prompt14CoverFixtures.webP, "image/webp"),
        ] {
            let image = try await ContentCoverDecoder().decode(
                Prompt14CoverFixtures.stream(body: body, mimeType: mimeType).stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
            #expect(image.cgImage.width > 0)
            #expect(image.cgImage.height > 0)
        }
    }

    @Test("decoder rejects missing and unsupported MIME metadata before consuming chunks (catches moving MIME validation after iteration)")
    func rejectsInvalidPreBodyMimeWithoutConsumption() async {
        let fixtures = [
            Prompt14CoverFixtures.stream(body: Prompt14CoverFixtures.png, mimeType: nil),
            Prompt14CoverFixtures.stream(body: Prompt14CoverFixtures.png, mimeType: "image/gif"),
        ]

        for fixture in fixtures {
            await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
                try await ContentCoverDecoder().decode(
                    fixture.stream,
                    target: .init(widthPixels: 240, heightPixels: 160)
                )
            }
            #expect(await fixture.probe.chunkCount == 0)
        }
    }

    @Test("decoder rejects bytes whose detected type mismatches the MIME declaration (catches removing source-type matching)")
    func rejectsMismatchedMimeDeclaration() async {
        await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try await ContentCoverDecoder().decode(
                Prompt14CoverFixtures.stream(
                    body: Prompt14CoverFixtures.png,
                    mimeType: "image/jpeg"
                ).stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
        }
    }

    @Test("decoder rejects status and redirect metadata without consuming a body chunk (catches moving metadata validation after iteration)")
    func rejectsInvalidPreBodyMetadataWithoutConsumption() async {
        let fixtures = [
            Prompt14CoverFixtures.stream(body: Prompt14CoverFixtures.png, statusCode: 500),
            Prompt14CoverFixtures.stream(
                body: Prompt14CoverFixtures.png,
                redirectLocation: URL(string: "https://redirect.example/cover")!
            ),
            Prompt14CoverFixtures.stream(
                body: Prompt14CoverFixtures.png,
                declaredLength: 10_485_761
            ),
            Prompt14CoverFixtures.stream(
                body: Prompt14CoverFixtures.png,
                declaredLength: -1
            ),
        ]

        await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try await ContentCoverDecoder().decode(
                fixtures[0].stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
        }
        await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try await ContentCoverDecoder().decode(
                fixtures[1].stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
        }
        await #expect(throws: BodyFlowCapabilityError.contentCoverTooLarge) {
            try await ContentCoverDecoder().decode(
                fixtures[2].stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
        }
        await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try await ContentCoverDecoder().decode(
                fixtures[3].stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
        }

        for fixture in fixtures {
            #expect(await fixture.probe.chunkCount == 0)
        }
    }

    @Test("decoder maps a 404 response to contentCoverNotFound before body consumption (catches losing not-found classification)")
    func mapsNotFoundBeforeConsumingChunks() async {
        let fixture = Prompt14CoverFixtures.stream(
            body: Prompt14CoverFixtures.png,
            statusCode: 404
        )

        await #expect(throws: BodyFlowCapabilityError.contentCoverNotFound) {
            try await ContentCoverDecoder().decode(
                fixture.stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
        }
        #expect(await fixture.probe.chunkCount == 0)
    }

    @Test("decoder accepts exactly 10 MiB declared and actual bodies (catches an off-by-one lower limit)")
    func acceptsExactTenMiBBoundary() async throws {
        let declaredFixture = Prompt14CoverFixtures.stream(
            body: Prompt14CoverFixtures.png,
            declaredLength: 10_485_760
        )
        let actualFixture = Prompt14CoverFixtures.chunkedBody(byteCount: 10_485_760)

        _ = try await ContentCoverDecoder().decode(
            declaredFixture.stream,
            target: .init(widthPixels: 240, heightPixels: 160)
        )
        _ = try await ContentCoverDecoder().decode(
            actualFixture.stream,
            target: .init(widthPixels: 240, heightPixels: 160)
        )
    }

    @Test("actual body is cancelled at byte 10 MiB plus one (catches delayed byte-limit cancellation)")
    func rejectsOversizedStream() async {
        let fixture = Prompt14CoverFixtures.chunkedBody(byteCount: 10_485_761)

        await #expect(throws: BodyFlowCapabilityError.contentCoverTooLarge) {
            try await ContentCoverDecoder().decode(
                fixture.stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
        }
        #expect(await fixture.probe.cancelCount == 1)
    }

    @Test("decoder cancels at the first byte above 10 MiB without requesting a sentinel chunk (catches continuing after the limit)")
    func stopsBeforeOversizedStreamSentinel() async {
        let fixture = Prompt14CoverFixtures.oversizedBodyWithSentinel()

        await #expect(throws: BodyFlowCapabilityError.contentCoverTooLarge) {
            try await ContentCoverDecoder().decode(
                fixture.stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
        }
        #expect(await fixture.probe.deliveredByteCount == 10_485_761)
        #expect(await fixture.probe.chunkCount == 2)
        #expect(await fixture.probe.cancelCount == 1)
    }

    @Test("decoder rejects zero, oversized, too-many-pixel, and overflow dimensions before thumbnailing (catches removing raster safety limits)")
    func rejectsUnsafeDimensions() async {
        let cases: [(UInt32, UInt32)] = [
            (0, 1),
            (16_385, 1),
            (1, 16_385),
            (8_001, 8_000),
            (UInt32.max, UInt32.max),
        ]

        for (width, height) in cases {
            await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
                try await ContentCoverDecoder().decode(
                    Prompt14CoverFixtures.stream(
                        body: Prompt14CoverFixtures.pngHeader(width: width, height: height)
                    ).stream,
                    target: .init(widthPixels: 240, heightPixels: 160)
                )
            }
        }
    }

    @Test("dimension policy rejects nonrepresentable numbers without trapping (catches unsafe Double-to-Int conversion)")
    func rejectsNonrepresentableDimensions() {
        #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try ContentCoverDimensionPolicy.validating(
                width: NSNumber(value: UInt64.max),
                height: NSNumber(value: 1)
            )
        }
    }

    @Test("dimension policy enforces exact side, pixel, and multiplication limits (catches reordering or weakening arithmetic checks)")
    func enforcesDimensionPolicyBoundaries() throws {
        let exactSide = try ContentCoverDimensionPolicy.validating(
            width: NSNumber(value: 16_384),
            height: NSNumber(value: 1)
        )
        #expect(exactSide.width == 16_384)
        #expect(exactSide.height == 1)

        let exactPixels = try ContentCoverDimensionPolicy.validating(
            width: NSNumber(value: 8_000),
            height: NSNumber(value: 8_000)
        )
        #expect(exactPixels.pixelCount == 64_000_000)

        for dimensions in [
            (NSNumber(value: 16_385), NSNumber(value: 1)),
            (NSNumber(value: 8_000), NSNumber(value: 8_001)),
            (NSNumber(value: Int.max), NSNumber(value: Int.max)),
        ] {
            #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
                try ContentCoverDimensionPolicy.validating(
                    width: dimensions.0,
                    height: dimensions.1
                )
            }
        }
    }

    @Test("decoder downscales a valid raster to the target pixel bounds (catches full-resolution image creation)")
    func downscalesToRequestedPixelSize() async throws {
        let image = try await ContentCoverDecoder().decode(
            Prompt14CoverFixtures.stream(
                body: Prompt14CoverFixtures.jpeg,
                mimeType: "image/jpeg"
            ).stream,
            target: .init(widthPixels: 240, heightPixels: 160)
        )

        #expect(image.cgImage.width == 240)
        #expect(image.cgImage.height == 160)
    }

    @Test("decoder fits landscape and portrait source rasters within unequal targets (catches max-target-dimension thumbnail sizing)")
    func fitsUnequalTargetBounds() async throws {
        for (body, target) in [
            (Prompt14CoverFixtures.jpeg, ContentCoverTargetSize(widthPixels: 160, heightPixels: 240)),
            (Prompt14CoverFixtures.portraitJPEG, ContentCoverTargetSize(widthPixels: 240, heightPixels: 160)),
        ] {
            let image = try await ContentCoverDecoder().decode(
                Prompt14CoverFixtures.stream(body: body, mimeType: "image/jpeg").stream,
                target: target
            )
            #expect(image.cgImage.width <= target.widthPixels)
            #expect(image.cgImage.height <= target.heightPixels)
        }
    }

    @Test("decoder cancellation cancels a stalled stream and never returns a late image (catches swallowing CancellationError)")
    func preservesTaskCancellationAndCancelsStream() async {
        let fixture = Prompt14CoverFixtures.stalledStream()
        let task = Task {
            try await ContentCoverDecoder().decode(
                fixture.stream,
                target: .init(widthPixels: 240, heightPixels: 160)
            )
        }

        await fixture.probe.waitUntilStalled()
        task.cancel()
        await fixture.probe.release()
        await fixture.probe.waitUntilCancelled()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await fixture.probe.cancelCount == 1)
    }
}
