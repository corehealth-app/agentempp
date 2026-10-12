import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing

@testable import BodyFlow

@Suite("Signup body photo client")
struct SignupBodyPhotoClientTests {
    @Test("The signup upload kind is recognized without changing meal media")
    func bodyPhotoUploadKindIsRecognized() {
        #expect(MediaUploadKind(rawValue: "body_checkin_photo") != nil)
    }
    private static let photoID = "0a0a0a0a-1111-4222-8333-444455556666"
    private static let otherIDs = ["0a0a0a0a-1111-4222-8333-444455556667", "0a0a0a0a-1111-4222-8333-444455556668"]
    private static let date = "2026-10-12T15:00:00.123456+00:00"
    private static let stateJSON = """
    {"available":true,"unavailable_reason":null,"minimum_age":18,"remaining_uploads":6,
     "consent":{"document_key":"body_photo_estimate_consent","version":"test-v1","locale":"pt-BR",
      "body":"SYNTHETIC consent only","body_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","accepted_at":"2026-10-12T15:00:00Z"},
     "poses":[{"pose":"front","photo":{"id":"0a0a0a0a-1111-4222-8333-444455556666","status":"read","created_at":"2026-10-12T15:00:00Z"}},
      {"pose":"side","photo":{"id":"0a0a0a0a-1111-4222-8333-444455556667","status":"read","created_at":"2026-10-12T15:00:00Z"}},
      {"pose":"back","photo":{"id":"0a0a0a0a-1111-4222-8333-444455556668","status":"read","created_at":"2026-10-12T15:00:00Z"}}],
     "estimate":{"is_estimate":true,"by_sex":{"masculino":{"usable":true,"body_fat_percent":24},"feminino":{"usable":true,"body_fat_percent":24}},
      "source_ids":{"front":"0a0a0a0a-1111-4222-8333-444455556666","side":"0a0a0a0a-1111-4222-8333-444455556667","back":"0a0a0a0a-1111-4222-8333-444455556668"},
      "fingerprint":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}
    """

    private func attempt<P: Hashable & Sendable>(_ payload: P, operation: MutationOperation = .mediaCreate) throws -> MutationAttempt<P> {
        MutationAttempt(operation: operation, key: try IdempotencyKey(validating: "signup-photo-test-key-001"), payload: payload, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    private func result<Value: Sendable>(_ operation: () async throws -> Value) async -> (Value?, SignupBodyPhotoFailure?) {
        do { return (try await operation(), nil) }
        catch { return (nil, SignupBodyPhotoFailure(error)) }
    }

    private func response(_ data: String) -> Data {
        Data("{\"data\":\(data),\"meta\":{\"api_version\":\"v1\",\"request_id\":\"synthetic-photo-test\"}}".utf8)
    }

    private func photo(_ status: String) -> String {
        "{\"id\":\"\(Self.photoID)\",\"pose\":\"front\",\"status\":\"\(status)\",\"created_at\":\"\(Self.date)\"}"
    }

    @Test("Current public state decodes the server mean and opaque confirmation identifiers")
    func decodesCurrentWire() throws {
        let state = try JSONDecoder().decode(SignupBodyPhotoState.self, from: Data(Self.stateJSON.utf8))
        #expect(state.poses.map(\.pose) == [.front, .side, .back])
        #expect(state.estimate?.bySex.masculine.bodyFatPercent == 24)
        #expect(state.estimate?.bySex.feminine.bodyFatPercent == 24)
        #expect(state.estimate?.sourceIDs?.front == Self.photoID)
        #expect(state.estimate?.sourceIDs?.side == Self.otherIDs[0])
        #expect(state.consent?.acceptedAt != nil)
        #expect(state.remainingUploads == 6)
        let encoded = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(!encoded.contains("readings"))
        #expect(!encoded.contains("processing_result"))
        #expect(!encoded.contains("signup_origin"))
    }

    @Test("A missing number and disabled state are decoded without making up a mean")
    func decodesUnavailableAndUnusable() throws {
        let noMean = Self.stateJSON.replacingOccurrences(of: "\"usable\":true,\"body_fat_percent\":24", with: "\"usable\":false,\"reason\":\"out_of_range\"")
        let unusable = try JSONDecoder().decode(SignupBodyPhotoState.self, from: Data(noMean.utf8))
        #expect(unusable.estimate?.bySex.masculine.usable == false)
        #expect(unusable.estimate?.bySex.masculine.bodyFatPercent == nil)
        let disabled = try JSONDecoder().decode(SignupBodyPhotoState.self, from: Data("""
        {"available":false,"unavailable_reason":"disabled","minimum_age":18,"remaining_uploads":0,"consent":null,"estimate":null,"poses":[{"pose":"front","photo":null},{"pose":"side","photo":null},{"pose":"back","photo":null}]}
        """.utf8))
        #expect(!disabled.available)
        #expect(disabled.estimate == nil)
        #expect(disabled.poses.allSatisfy { $0.photo == nil })
    }

    @Test("State reads only the dedicated signup endpoint without a query or mutation key")
    func stateRequest() async throws {
        let spy = SignupPhotoTransportSpy(responseJSON: response(Self.stateJSON))
        let (stateValue, failure) = await result { try await MobileSignupBodyPhotoRepository(transport: spy).state() }
        #expect(failure == nil)
        let state = try #require(stateValue)
        let request = try #require(await spy.requests.first)
        #expect(request.path == "/api/mobile/v1/onboarding/body-photos")
        #expect(request.method == .get)
        #expect(request.body == nil)
        #expect(request.queryItems.isEmpty)
        #expect(request.idempotency == .notRequired)
        #expect(state.estimate?.bySex.masculine.bodyFatPercent == 24)
    }

    @Test("Consent puts only version, hash and civil birth date in the body; retry keeps its key")
    func consentRequest() async throws {
        let spy = SignupPhotoTransportSpy(responseJSON: response("{\"document_key\":\"body_photo_estimate_consent\",\"version\":\"test-v1\",\"accepted_at\":\"\(Self.date)\"}"))
        let repo = MobileSignupBodyPhotoRepository(transport: spy)
        let a = try attempt(SignupBodyPhotoConsentRequest(version: "test-v1", bodyHash: String(repeating: "a", count: 64), birthDate: "1990-05-20"))
        let (first, firstFailure) = await result { try await repo.consent(a) }
        #expect(firstFailure == nil)
        _ = try #require(first)
        let (replayed, replayFailure) = await result { try await repo.consent(a) }
        #expect(replayFailure == nil)
        _ = try #require(replayed)
        let requests = await spy.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.path == "/api/mobile/v1/onboarding/body-photos/consent")
            #expect(request.method == .post)
            #expect(request.queryItems.isEmpty)
            #expect(request.idempotency == .required(a.key))
            let body = try #require(request.body)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(Set(object.keys) == ["version", "body_hash", "birth_date"])
            #expect(object["birth_date"] == "1990-05-20")
        }
    }

    @Test("Creation declares pose, JPEG and size only, never the generic media kind")
    func createRequest() async throws {
        let spy = SignupPhotoTransportSpy(responseJSON: response("{\"photo\":\(photo("pending_upload")),\"upload\":null,\"replayed\":true}"))
        let a = try attempt(SignupBodyPhotoCreateRequest(pose: .front, mimeType: "image/jpeg", sizeBytes: 1200))
        let (created, failure) = await result { try await MobileSignupBodyPhotoRepository(transport: spy).create(a) }
        #expect(failure == nil)
        let receipt = try #require(created)
        let request = try #require(await spy.requests.first)
        #expect(request.path == "/api/mobile/v1/onboarding/body-photos")
        #expect(request.method == .post)
        #expect(request.idempotency == .required(a.key))
        let body = try #require(request.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(object.keys) == ["pose", "mime_type", "size_bytes"])
        #expect(object["pose"] as? String == "front")
        #expect(object["size_bytes"] as? Int == 1200)
        #expect(object["mime_type"] as? String == "image/jpeg")
        #expect(receipt.photo.pose == .front)
        #expect(receipt.upload == nil)
    }

    @Test("Complete uses the returned UUID; DELETE deletes the signup scope without a body")
    func completeAndDelete() async throws {
        let completeSpy = SignupPhotoTransportSpy(responseJSON: response("{\"photo\":\(photo("uploaded"))}"))
        let completion = try attempt(MediaAssetCommand(assetID: Self.photoID), operation: .mediaComplete)
        let (completeValue, completeFailure) = await result { try await MobileSignupBodyPhotoRepository(transport: completeSpy).complete(completion) }
        #expect(completeFailure == nil)
        _ = try #require(completeValue)
        let completed = try #require(await completeSpy.requests.first)
        #expect(completed.path == "/api/mobile/v1/onboarding/body-photos/\(Self.photoID)/complete")
        #expect(completed.method == .post)
        #expect(completed.body == nil)
        let deleteSpy = SignupPhotoTransportSpy(responseJSON: response("{\"deleted\":3}"))
        let deletion = try attempt(SignupBodyPhotoDeleteCommand(), operation: .mediaDelete)
        let (deletedValue, deleteFailure) = await result { try await MobileSignupBodyPhotoRepository(transport: deleteSpy).delete(deletion) }
        #expect(deleteFailure == nil)
        let deleted = try #require(deletedValue)
        let request = try #require(await deleteSpy.requests.first)
        #expect(request.path == "/api/mobile/v1/onboarding/body-photos")
        #expect(request.method == .delete)
        #expect(request.body == nil)
        #expect(deleted.deleted == 3)
    }

    @Test("Named server failures are preserved for the signup UI")
    func namedFailures() {
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.forbidden(code: "body_photo_consent_required", requestID: nil)) == .consentRequired)
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.forbidden(code: "body_photo_age_not_allowed", requestID: nil)) == .ageNotAllowed)
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.conflict(code: "onboarding_already_completed", requestID: nil)) == .signupCompleted)
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.conflict(code: "body_photo_reading_failed", requestID: nil)) == .readingFailed)
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.conflict(code: "media_upload_not_pending", requestID: nil)) == .uploadNotPending)
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.rateLimited(code: "body_photo_limit_reached", requestID: nil)) == .limitReached)
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.server(status: 503, code: "body_photo_cleanup_pending", requestID: nil)) == .cleanupPending)
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.network) == .offline)
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.sessionSuperseded) == .sessionChanged)
        #expect(SignupBodyPhotoFailure(MobileAPITransportError.http(status: 404, code: "body_photos_unavailable", requestID: nil)) == .unavailable)
    }

    private func sourcePhoto(width: Int, height: Int, type: String = UTType.jpeg.identifier, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, type as CFString, 1, nil
        ))
        let metadata: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 23.55,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 46.63,
                kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: "private note",
                kCGImagePropertyExifLensModel: "Patient phone lens",
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "MakerName",
                kCGImagePropertyTIFFModel: "ModelName",
            ],
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
    }

    @Test("Both signup camera and gallery stage only normalized JPEG pixels")
    func normalizedSignupPhoto() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signup-photo-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let input = try sourcePhoto(width: 4000, height: 3000)
        let stager = SignupBodyPhotoStager(staging: MediaStagingStore(temporaryDirectory: base))
        for channel in [MealSourceChannel.camera, .gallery] {
            var output: StagedMedia?
            var failure: SignupBodyPhotoFailure?
            do { output = try stager.stagePhoto(input, channel: channel) }
            catch { failure = SignupBodyPhotoFailure(error) }
            #expect(failure == nil)
            let media = try #require(output)
            let data = try Data(contentsOf: media.fileURL)
            let metadata = try properties(of: data)
            #expect(media.kind == .signupBodyPhoto)
            #expect(media.channel == channel)
            #expect(media.mimeType == "image/jpeg")
            #expect(media.sizeBytes == data.count && media.sizeBytes <= MealMediaLimits.maximumPhotoBytes)
            #expect(media.duration == nil)
            #expect(metadata[kCGImagePropertyPixelWidth] as? Int == 2048)
            #expect(metadata[kCGImagePropertyPixelHeight] as? Int == 1536)
            #expect(metadata[kCGImagePropertyGPSDictionary] == nil)
            let exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any]
            #expect(exif?[kCGImagePropertyExifUserComment] == nil)
            #expect(exif?[kCGImagePropertyExifLensModel] == nil)
            let tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
            #expect(tiff?[kCGImagePropertyTIFFModel] == nil)
            #expect(data.prefix(2) == Data([0xFF, 0xD8]))
            #expect(!String(decoding: data, as: UTF8.self).contains("private note"))
        }
    }

    @Test("A HEIC from the gallery is re-encoded as a small JPEG with private metadata removed")
    func normalizesHEIC() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signup-heic-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let input = try sourcePhoto(width: 800, height: 600, type: UTType.heic.identifier)
        let inputSource = try #require(CGImageSourceCreateWithData(input as CFData, nil))
        #expect(CGImageSourceGetType(inputSource) as String? == UTType.heic.identifier)
        #expect(try properties(of: input)[kCGImagePropertyGPSDictionary] != nil)
        let staged = try SignupBodyPhotoStager(staging: MediaStagingStore(temporaryDirectory: base)).stagePhoto(input, channel: .gallery)
        let output = try Data(contentsOf: staged.fileURL)
        let metadata = try properties(of: output)
        #expect(output.prefix(2) == Data([0xFF, 0xD8]))
        #expect(metadata[kCGImagePropertyPixelWidth] as? Int == 800)
        #expect(metadata[kCGImagePropertyPixelHeight] as? Int == 600)
        #expect(metadata[kCGImagePropertyGPSDictionary] == nil)
        #expect((metadata[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
        #expect((metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
    }

    @Test("Orientation is applied to the pixels before private metadata is discarded")
    func normalizesOrientation() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signup-orientation-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let input = try sourcePhoto(width: 800, height: 600, orientation: 6)
        #expect(try properties(of: input)[kCGImagePropertyOrientation] as? Int == 6)
        let staged = try SignupBodyPhotoStager(staging: MediaStagingStore(temporaryDirectory: base)).stagePhoto(input, channel: .camera)
        let metadata = try properties(of: Data(contentsOf: staged.fileURL))
        #expect(metadata[kCGImagePropertyPixelWidth] as? Int == 600)
        #expect(metadata[kCGImagePropertyPixelHeight] as? Int == 800)
        #expect(metadata[kCGImagePropertyOrientation] == nil || metadata[kCGImagePropertyOrientation] as? Int == 1)
    }

    @Test("Cancellation is preserved and never turned into an unavailable retry")
    func preservesCancellation() async {
        let repository = MobileSignupBodyPhotoRepository(transport: SignupPhotoCancelledTransport())
        await #expect(throws: CancellationError.self) { try await repository.state() }
    }

    @Test("Invalid image/channel and invalid request metadata are refused before upload")
    func invalidInputs() async throws {
        let stager = SignupBodyPhotoStager(staging: MediaStagingStore())
        #expect(throws: SignupBodyPhotoFailure.unreadableImage) { try stager.stagePhoto(Data("not an image".utf8), channel: .camera) }
        #expect(throws: SignupBodyPhotoFailure.invalidInput) { try stager.stagePhoto(Data(), channel: .audioImport) }
        let spy = SignupPhotoTransportSpy(responseJSON: Data())
        let repo = MobileSignupBodyPhotoRepository(transport: spy)
        await #expect(throws: SignupBodyPhotoFailure.invalidInput) { try await repo.complete(try attempt(MediaAssetCommand(assetID: "../another-account"), operation: .mediaComplete)) }
        await #expect(throws: SignupBodyPhotoFailure.invalidInput) { try await repo.create(try attempt(SignupBodyPhotoCreateRequest(pose: .front, mimeType: "audio/mp4", sizeBytes: 1200))) }
        #expect(await spy.requests.isEmpty)
    }

    @Test("The meal capture refuses signup body photos before any upload")
    func mealRejectsBodyPhoto() throws {
        let media = StagedMedia(fileURL: URL(fileURLWithPath: "/tmp/synthetic-not-opened.jpg"), kind: .signupBodyPhoto, mimeType: "image/jpeg", sizeBytes: 1200, duration: nil, channel: .camera)
        #expect(MealDraftModel.precheck(media) == .invalidInput)
    }
}

private actor SignupPhotoTransportSpy: MobileAPIEnvelopeExecuting {
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let body: Data?
        let queryItems: [URLQueryItem]
        let idempotency: MobileAPIIdempotency
    }
    private(set) var requests: [Recorded] = []
    private let responseJSON: Data
    init(responseJSON: Data) { self.responseJSON = responseJSON }

    func executeEnvelope<Response: Codable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> MobileResponse<Response> {
        requests.append(Recorded(method: request.method, path: request.path, body: request.body, queryItems: request.queryItems, idempotency: request.idempotency))
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: responseJSON)
    }
}

private struct SignupPhotoCancelledTransport: MobileAPIEnvelopeExecuting {
    func executeEnvelope<Response: Codable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> MobileResponse<Response> {
        throw CancellationError()
    }
}
