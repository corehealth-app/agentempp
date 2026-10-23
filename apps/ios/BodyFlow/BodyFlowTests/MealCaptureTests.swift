import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BodyFlow

// MARK: - Fixtures

private enum CaptureFixtures {
    static let assetID = "0a0a0a0a-1111-4222-8333-444455556666"
    static let storageOrigin = URL(string: "https://project.supabase.co/")!
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func ticket(
        url: String = "https://project.supabase.co/storage/v1/object/upload/sign/meal-photos/u/a.jpg?token=abc",
        method: String = "PUT",
        headers: [String: String] = ["Content-Type": "image/jpeg", "x-upsert": "false"],
        expiresAt: Date = now.addingTimeInterval(600)
    ) -> MediaUploadTicket {
        MediaUploadTicket(
            signedURL: url,
            method: method,
            headers: headers,
            expiresAt: APITimestamp(value: expiresAt)
        )
    }

    static func photo(
        at url: URL = URL(fileURLWithPath: "/tmp/none.jpg"),
        size: Int = 1_000,
        channel: MealSourceChannel = .gallery
    ) -> StagedMedia {
        StagedMedia(
            fileURL: url, kind: .mealPhoto, mimeType: "image/jpeg",
            sizeBytes: size, duration: nil, channel: channel
        )
    }

    static func audio(
        at url: URL = URL(fileURLWithPath: "/tmp/none.m4a"),
        duration: TimeInterval? = 12.4,
        size: Int = 40_000
    ) -> StagedMedia {
        StagedMedia(
            fileURL: url, kind: .audioNote, mimeType: "audio/mp4",
            sizeBytes: size, duration: duration, channel: .audioRecording
        )
    }

    static func asset(_ status: String, failureCode: String? = nil) -> MediaAssetSnapshot {
        MediaAssetSnapshot(
            id: assetID, kind: "meal_photo", status: status,
            failureStage: failureCode == nil ? nil : "processing", failureCode: failureCode
        )
    }

    static func candidate(
        _ id: String,
        _ name: String,
        grams: Decimal?,
        basis: String,
        count: Decimal? = nil,
        unit: String? = nil,
        reason: String? = nil
    ) -> MealDraftCandidate {
        MealDraftCandidate(
            candidateID: id, name: name, quantityG: grams, quantityBasis: basis,
            count: count, unitLabel: unit, confidence: nil,
            needsReview: reason != nil, reviewReason: reason
        )
    }

    /// "2 ovos mexidos e 1 pão francês", as docs/mobile/api-v1.md answers it.
    static let eggsAndBread = MealDraftSnapshot(
        source: "text", mediaAssetID: nil, transcript: nil, contextNote: nil,
        items: [
            candidate("c1-0a1b2c3d", "ovos mexidos", grams: 100, basis: "portion_reference",
                      count: 2, unit: "unidade", reason: "estimated_quantity"),
            candidate("c2-1b2c3d4e", "pão francês", grams: 50, basis: "portion_reference",
                      count: 1, unit: "unidade", reason: "estimated_quantity"),
        ],
        nutritionLabel: nil
    )

    static let photoWithLabel = MealDraftSnapshot(
        source: "photo", mediaAssetID: assetID, transcript: nil,
        contextNote: "Prato com iogurte",
        items: [
            candidate("c1-aaaaaaaa", "iogurte natural", grams: 170, basis: "visual_estimate",
                      reason: "estimated_quantity"),
            candidate("c2-bbbbbbbb", "granola", grams: nil, basis: "missing",
                      reason: "missing_quantity"),
        ],
        nutritionLabel: MealDraftNutritionLabel(
            productName: "Iogurte Natural", servingSizeG: 170,
            appliesToCandidateID: "c1-aaaaaaaa"
        )
    )
}

// MARK: - Upload transport

@Suite("Storage upload transport")
struct StorageUploadTransportTests {
    private func request(
        _ ticket: MediaUploadTicket,
        media: StagedMedia = CaptureFixtures.photo()
    ) throws -> URLRequest {
        try StorageUploadTransport.request(
            for: media, ticket: ticket,
            storageOrigin: CaptureFixtures.storageOrigin, now: CaptureFixtures.now
        )
    }

    // Staging 2026-09-30: a second upload reused a QUIC connection idle for
    // 162 s, stalled 60 s and showed "Sem conexão". Each upload now opens its
    // own session (a new connection) and releases it.
    @Test("every upload runs on its own new session")
    func eachUploadUsesAFreshSession() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).jpg")
        try Data(repeating: 1, count: 16).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let made = SessionCounter()
        let transport = StorageUploadTransport(
            storageOrigin: CaptureFixtures.storageOrigin,
            now: { CaptureFixtures.now },
            makeSession: { configuration in
                configuration.protocolClasses = [AcceptingUploadProtocol.self]
                made.increment()
                return URLSession(configuration: configuration)
            }
        )

        try await transport.upload(CaptureFixtures.photo(at: file), with: CaptureFixtures.ticket())
        try await transport.upload(CaptureFixtures.photo(at: file), with: CaptureFixtures.ticket())

        #expect(made.count == 2)
    }

    @Test("A valid ticket becomes a PUT with the ticket's headers and nothing else")
    func validTicket() throws {
        let request = try request(CaptureFixtures.ticket())

        #expect(request.httpMethod == "PUT")
        #expect(request.url?.host == "project.supabase.co")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(request.value(forHTTPHeaderField: "x-upsert") == "false")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "apikey") == nil)
        #expect(request.allHTTPHeaderFields?.count == 2)
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test(
        "An address that is not the app's signed upload is refused",
        arguments: [
            "http://project.supabase.co/storage/v1/object/upload/sign/b/u/a.jpg?token=abc",
            "https://evil.example/storage/v1/object/upload/sign/b/u/a.jpg?token=abc",
            "https://project.supabase.co.evil.example/storage/v1/object/upload/sign/b/u/a.jpg?token=abc",
            "https://project.supabase.co:8443/storage/v1/object/upload/sign/b/u/a.jpg?token=abc",
            "https://user:pw@project.supabase.co/storage/v1/object/upload/sign/b/u/a.jpg?token=abc",
            "https://project.supabase.co/storage/v1/object/b/u/a.jpg?token=abc",
            "https://project.supabase.co/storage/v1/object/upload/sign/../../auth/v1/token?token=abc",
            "https://project.supabase.co/storage/v1/object/upload/sign/b/%2e%2e/a.jpg?token=abc",
            "https://project.supabase.co/storage/v1/object/upload/sign/b?token=abc",
            "https://project.supabase.co/storage/v1/object/upload/sign/b/u/a.jpg",
            "https://project.supabase.co/storage/v1/object/upload/sign/b/u/a.jpg?token=",
            "https://project.supabase.co/storage/v1/object/upload/sign/b/u/a.jpg?token=abc#x",
            "not a url",
        ]
    )
    func refusesForeignAddress(url: String) {
        #expect(throws: MealCaptureFailure.uploadRejected) {
            try request(CaptureFixtures.ticket(url: url))
        }
    }

    @Test("A ticket asking for the bearer or any other header is refused")
    func refusesExtraHeaders() {
        for headers in [
            ["Content-Type": "image/jpeg", "Authorization": "Bearer x"],
            ["Content-Type": "image/jpeg", "apikey": "x"],
            ["Content-Type": "image/jpeg", "Cookie": "a=b"],
            ["Content-Type": "image/jpeg", "content-type": "image/png"],
            ["Content-Type": "image/jpeg", "x-upsert": "false\r\nX-Evil: 1"],
        ] {
            #expect(throws: MealCaptureFailure.uploadRejected) {
                try request(CaptureFixtures.ticket(headers: headers))
            }
        }
    }

    @Test("The file only goes as the type it was declared to be")
    func refusesTypeMismatch() {
        #expect(throws: MealCaptureFailure.uploadRejected) {
            try request(CaptureFixtures.ticket(headers: ["Content-Type": "image/png"]))
        }
        #expect(throws: MealCaptureFailure.uploadRejected) {
            try request(CaptureFixtures.ticket(headers: ["x-upsert": "false"]))
        }
    }

    @Test("An expired ticket or another method is refused")
    func refusesExpiredOrOtherMethod() {
        #expect(throws: MealCaptureFailure.uploadRejected) {
            try request(CaptureFixtures.ticket(expiresAt: CaptureFixtures.now))
        }
        #expect(throws: MealCaptureFailure.uploadRejected) {
            try request(CaptureFixtures.ticket(method: "POST"))
        }
    }

    @Test("A refusal carries nothing of the ticket")
    func refusalHidesTicket() {
        let secret = "https://evil.example/storage/v1/object/upload/sign/b/u/a.jpg?token=SECRET-TOKEN"
        do {
            _ = try request(CaptureFixtures.ticket(url: secret))
            Issue.record("expected a refusal")
        } catch {
            let described = String(describing: error) + String(reflecting: error)
                + error.localizedDescription
            #expect(!described.contains("SECRET-TOKEN"))
            #expect(!described.contains("evil.example"))
        }
    }
}

// MARK: - Staging

@Suite("Media staging store")
struct MediaStagingStoreTests {
    private func makeStore() -> (MediaStagingStore, URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("staging-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return (MediaStagingStore(temporaryDirectory: base), base)
    }

    @Test("A capture is staged in its own folder under tmp/performe-media")
    func stagesInOwnFolder() throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }

        let first = try store.stage(Data([1, 2, 3]), fileExtension: "jpg")
        let second = try store.stage(Data([4]), fileExtension: "m4a")

        #expect(first.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            == "performe-media")
        #expect(UUID(uuidString: first.deletingLastPathComponent().lastPathComponent) != nil)
        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
        #expect(try Data(contentsOf: first) == Data([1, 2, 3]))
    }

    @Test("Removing a capture removes its folder and nothing else")
    func removesOnlyOwnFolder() throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let first = try store.stage(Data([1]), fileExtension: "jpg")
        let second = try store.stage(Data([2]), fileExtension: "jpg")
        let outside = base.appendingPathComponent("keep.txt")
        try Data([9]).write(to: outside)

        store.remove(first)
        store.remove(outside)

        #expect(!FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("Launch and sign-out empty the staging area")
    func purgeEmptiesEverything() async throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let first = try store.stage(Data([1]), fileExtension: "jpg")
        let second = try store.stage(Data([2]), fileExtension: "m4a")

        await MediaStagingSessionClearer(staging: store).clearSensitiveState()

        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(!FileManager.default.fileExists(atPath: store.root.path))
        // The area is usable again after a purge.
        #expect(FileManager.default.fileExists(
            atPath: try store.stage(Data([3]), fileExtension: "jpg").path
        ))
    }

    @Test("Only known capture types are staged")
    func refusesUnknownExtension() {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(throws: MealCaptureFailure.unsupportedFile) {
            try store.stage(Data([1]), fileExtension: "../x")
        }
    }
}

// MARK: - Photo

@Suite("Meal photo normalizer")
struct MealPhotoNormalizerTests {
    private func sourcePhoto(width: Int, height: Int) throws -> Data {
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
            output, UTType.jpeg.identifier as CFString, 1, nil
        ))
        let metadata: [CFString: Any] = [
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

    @Test("The photo leaves at most 2048 px, as JPEG, without location or device data")
    func normalizes() throws {
        let original = try sourcePhoto(width: 4_000, height: 3_000)
        #expect(try properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let normalized = try MealPhotoNormalizer.normalizedJPEG(from: original)
        let result = try properties(of: normalized)

        #expect(result[kCGImagePropertyPixelWidth] as? Int == 2_048)
        #expect(result[kCGImagePropertyPixelHeight] as? Int == 1_536)
        #expect(result[kCGImagePropertyGPSDictionary] == nil)
        let exif = result[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifUserComment] == nil)
        #expect(exif?[kCGImagePropertyExifLensModel] == nil)
        let tiff = result[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff?[kCGImagePropertyTIFFModel] == nil)
        #expect(normalized.prefix(2) == Data([0xFF, 0xD8]))
        let text = String(decoding: normalized, as: UTF8.self)
        #expect(!text.contains("private note"))
        #expect(!text.contains("MakerName"))
    }

    @Test("A small photo is not enlarged")
    func keepsSmallPhoto() throws {
        let normalized = try MealPhotoNormalizer.normalizedJPEG(
            from: try sourcePhoto(width: 800, height: 600)
        )
        let result = try properties(of: normalized)
        #expect(result[kCGImagePropertyPixelWidth] as? Int == 800)
        #expect(result[kCGImagePropertyPixelHeight] as? Int == 600)
    }

    @Test("Bytes that are not an image are refused")
    func refusesGarbage() {
        #expect(throws: MealCaptureFailure.unreadableMedia) {
            try MealPhotoNormalizer.normalizedJPEG(from: Data("not an image".utf8))
        }
    }

    @Test("Staging a photo writes the normalized file and declares its real size")
    func stagesNormalizedPhoto() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let stager = MealMediaStager(staging: MediaStagingStore(temporaryDirectory: base))

        let staged = try stager.stagePhoto(
            try sourcePhoto(width: 3_000, height: 3_000), channel: .camera
        )

        #expect(staged.kind == .mealPhoto)
        #expect(staged.mimeType == "image/jpeg")
        #expect(staged.channel == .camera)
        #expect(staged.sizeBytes == (try Data(contentsOf: staged.fileURL)).count)
        #expect(staged.uploadRequest.durationMS == nil)
        #expect(throws: MealCaptureFailure.invalidInput) {
            try stager.stagePhoto(Data(), channel: .audioImport)
        }
    }
}

// MARK: - Audio

@Suite("Meal audio limits")
struct MealAudioLimitTests {
    @Test("The recorder writes mono AAC and the limit is 180 seconds")
    @MainActor
    func recorderSettings() {
        #expect(MealMediaLimits.maximumAudioDuration == 180)
        // The recorder stops just before the limit, so a recording that ran
        // to the end is never refused as too long.
        #expect(MealAudioRecorder.recordingLimit == 179.5)
        #expect(MealAudioRecorder.settings[AVFormatIDKeyName] as? Int == 1_633_772_320)
        #expect(MealAudioRecorder.settings[AVNumberOfChannelsKeyName] as? Int == 1)
    }

    private let AVFormatIDKeyName = "AVFormatIDKey"
    private let AVNumberOfChannelsKeyName = "AVNumberOfChannelsKey"

    @Test("Only audio types the server accepts are described")
    func acceptedTypes() async {
        #expect(MealAudioInspector.stagedExtension(for: "M4A") == "m4a")
        #expect(MealAudioInspector.stagedExtension(for: "mp4") == "m4a")
        #expect(MealAudioInspector.stagedExtension(for: "mp3") == "mp3")
        #expect(MealAudioInspector.stagedExtension(for: "flac") == nil)
        #expect(MealAudioInspector.mimeTypesByExtension["m4a"] == "audio/mp4")
        await #expect(throws: MealCaptureFailure.unsupportedFile) {
            try await MealAudioInspector.describe(URL(fileURLWithPath: "/tmp/a.flac"))
        }
        await #expect(throws: MealCaptureFailure.unreadableMedia) {
            try await MealAudioInspector.describe(URL(fileURLWithPath: "/tmp/missing-\(UUID()).m4a"))
        }
    }

    @Test("A capture outside the limits never reaches the server")
    func precheck() {
        #expect(MealDraftModel.precheck(CaptureFixtures.audio(duration: 180)) == nil)
        #expect(MealDraftModel.precheck(CaptureFixtures.audio(duration: 180.01)) == .audioTooLong)
        #expect(MealDraftModel.precheck(CaptureFixtures.audio(duration: nil)) == .unreadableMedia)
        #expect(MealDraftModel.precheck(CaptureFixtures.audio(duration: 0)) == .unreadableMedia)
        #expect(MealDraftModel.precheck(
            CaptureFixtures.audio(size: 25 * 1_024 * 1_024 + 1)
        ) == .fileTooLarge)
        #expect(MealDraftModel.precheck(
            CaptureFixtures.photo(size: 15 * 1_024 * 1_024 + 1)
        ) == .fileTooLarge)
        #expect(MealDraftModel.precheck(CaptureFixtures.photo(size: 0)) == .unreadableMedia)
        #expect(MealDraftModel.precheck(CaptureFixtures.photo(channel: .audioImport)) == .invalidInput)
    }

    @Test("The declared duration is the measured one, in milliseconds")
    func declaredDuration() {
        #expect(CaptureFixtures.audio(duration: 12.4).uploadRequest.durationMS == 12_400)
        #expect(CaptureFixtures.audio(duration: 0.0001).uploadRequest.durationMS == 1)
    }
}

// MARK: - Repositories

@Suite("Mobile media and draft repositories")
struct MobileMediaRepositoryTests {
    private static let createJSON = Data("""
    {"data":{"asset":{"id":"0a0a0a0a-1111-4222-8333-444455556666","kind":"audio_note",
       "mime_type":"audio/mp4","size_bytes":40000,"status":"pending_upload","failure_stage":null,
       "failure_code":null,"has_context":false,"retention_until":null,"uploaded_at":null,
       "processed_at":null,"deleted_at":null,"result":null,
       "created_at":"2026-09-28T12:00:00.000Z","updated_at":"2026-09-28T12:00:00.000Z"},
      "upload":{"signed_url":"https://project.supabase.co/storage/v1/object/upload/sign/b/u/a.m4a?token=t",
       "method":"PUT","headers":{"Content-Type":"audio/mp4","x-upsert":"false"},
       "expires_at":"2026-09-28T12:10:00.000Z"},
      "replayed":false},
     "meta":{"api_version":"v1","request_id":"req-media-1"}}
    """.utf8)

    private static let assetJSON = Data("""
    {"data":{"id":"0a0a0a0a-1111-4222-8333-444455556666","kind":"audio_note","status":"failed",
       "failure_stage":"processing","failure_code":"audio_too_long",
       "result":{"text":"ignored","nested":[1,2,{"a":null}]},"download":null},
     "meta":{"api_version":"v1","request_id":"req-media-2"}}
    """.utf8)

    private static let draftJSON = Data("""
    {"data":{"source":"text","media_asset_id":null,"transcript":null,"context_note":null,
      "items":[{"candidate_id":"c1-0a1b2c3d","name":"ovos mexidos","quantity_g":100,
        "quantity_basis":"portion_reference","count":2,"unit_label":"unidade","confidence":null,
        "needs_review":true,"review_reason":"estimated_quantity"},
       {"candidate_id":"c2-1b2c3d4e","name":"granola","quantity_g":null,
        "quantity_basis":"missing","count":null,"unit_label":null,"confidence":0.4,
        "needs_review":true,"review_reason":"missing_quantity"}],
      "nutrition_label":null,"extraction":{"method":"deterministic","model":null}},
     "meta":{"api_version":"v1","request_id":"req-draft-1"}}
    """.utf8)

    private func attempt<Payload: Hashable & Sendable>(
        _ operation: MutationOperation, _ payload: Payload, key: String
    ) throws -> MutationAttempt<Payload> {
        MutationAttempt(
            operation: operation, key: try IdempotencyKey(validating: key),
            payload: payload, createdAt: CaptureFixtures.now
        )
    }

    @Test("Creating an asset declares kind, type, size and measured duration")
    func create() async throws {
        let spy = CaptureTransportSpy(responseJSON: Self.createJSON)
        let created = try await MobileMediaRepository(transport: spy).create(
            try attempt(.mediaCreate, CaptureFixtures.audio().uploadRequest, key: "media-key-1")
        )

        let request = try #require(await spy.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/api/mobile/v1/media")
        #expect(request.idempotency == .required(try IdempotencyKey(validating: "media-key-1")))
        let body = try #require(request.body.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        #expect(body["kind"] as? String == "audio_note")
        #expect(body["mime_type"] as? String == "audio/mp4")
        #expect(body["size_bytes"] as? Int == 40_000)
        #expect(body["duration_ms"] as? Int == 12_400)
        #expect(body.count == 4)
        #expect(created.asset.state == .pendingUpload)
        #expect(created.upload?.headers["Content-Type"] == "audio/mp4")
    }

    @Test("A photo declares no duration")
    func photoHasNoDuration() async throws {
        let spy = CaptureTransportSpy(responseJSON: Self.createJSON)
        _ = try await MobileMediaRepository(transport: spy).create(
            try attempt(.mediaCreate, CaptureFixtures.photo().uploadRequest, key: "media-key-2")
        )
        let body = try #require(await spy.requests.first?.body.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        #expect(body["duration_ms"] == nil)
        #expect(body["kind"] as? String == "meal_photo")
    }

    @Test("Complete, process, read and delete address the asset by id")
    func assetOperations() async throws {
        let spy = CaptureTransportSpy(responseJSON: Self.assetJSON)
        let repository = MobileMediaRepository(transport: spy)
        let command = MediaAssetCommand(assetID: CaptureFixtures.assetID)

        _ = try await repository.complete(try attempt(.mediaComplete, command, key: "media-key-3"))
        _ = try await repository.requestProcessing(
            try attempt(.mediaProcess, command, key: "media-key-4")
        )
        let asset = try await repository.asset(id: CaptureFixtures.assetID)
        try await repository.delete(try attempt(.mediaDelete, command, key: "media-key-5"))

        let base = "/api/mobile/v1/media/\(CaptureFixtures.assetID)"
        #expect(await spy.requests.map(\.path) == [
            "\(base)/complete", "\(base)/process", base, base,
        ])
        #expect(await spy.requests.map(\.method) == [.post, .post, .get, .delete])
        #expect(asset.state == .failed(code: "audio_too_long"))
    }

    @Test("An id that is not an identifier never becomes a path")
    func refusesForeignID() async {
        let spy = CaptureTransportSpy(responseJSON: Self.assetJSON)
        await #expect(throws: MealCaptureFailure.self) {
            try await MobileMediaRepository(transport: spy).asset(id: "../me")
        }
        #expect(await spy.requests.isEmpty)
    }

    @Test("A draft is asked from text or from a processed asset, never both")
    func draftRequests() async throws {
        let spy = CaptureTransportSpy(responseJSON: Self.draftJSON)
        let repository = MobileMealDraftRepository(transport: spy)

        let draft = try await repository.draft(
            try attempt(.mealDraft, MealDraftRequest.text("2 ovos mexidos e 1 pão francês"),
                        key: "draft-key-1")
        )
        _ = try await repository.draft(
            try attempt(.mealDraft, MealDraftRequest.media(assetID: CaptureFixtures.assetID),
                        key: "draft-key-2")
        )

        let bodies = await spy.requests.compactMap { request in
            request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        }
        #expect(bodies == [
            ["source": "text", "text": "2 ovos mexidos e 1 pão francês"],
            ["source": "media", "media_asset_id": CaptureFixtures.assetID],
        ])
        #expect(await spy.requests.allSatisfy { $0.path == "/api/mobile/v1/meal-drafts" })
        #expect(draft.items.map(\.candidateID) == ["c1-0a1b2c3d", "c2-1b2c3d4e"])
        #expect(draft.items[0].quantityG == 100)
        #expect(draft.items[0].requestBasis == .portionReference)
        #expect(draft.items[1].quantityG == nil)
        #expect(draft.items[1].requestBasis == nil)
    }

    @Test("Server refusals are named for the screen")
    func failureMapping() {
        func failure(_ error: MobileAPITransportError) -> MealCaptureFailure {
            MealCaptureFailure(error)
        }
        #expect(failure(.validation(code: "audio_too_long", requestID: nil)) == .audioTooLong)
        #expect(failure(.validation(code: "meal_draft_empty", requestID: nil)) == .nothingRecognized)
        #expect(failure(.validation(code: "media_upload_mismatch", requestID: nil)) == .uploadRejected)
        #expect(failure(.validation(code: "media_type_unsupported", requestID: nil)) == .unsupportedFile)
        #expect(failure(.validation(code: "other", requestID: nil)) == .invalidInput)
        #expect(failure(.http(status: 402, code: "subscription_required", requestID: nil))
            == .subscriptionRequired)
        #expect(failure(.network) == .offline)
        #expect(failure(.timeout) == .offline)
        #expect(failure(.server(status: 502, code: "meal_extraction_failed", requestID: nil))
            == .unavailable)
        #expect(failure(.conflict(code: "media_not_processed", requestID: nil)) == .unavailable)
    }
}

private actor CaptureTransportSpy: MobileAPIEnvelopeExecuting {
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }

    private(set) var requests: [Recorded] = []
    private let responseJSON: Data

    init(responseJSON: Data) {
        self.responseJSON = responseJSON
    }

    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        requests.append(Recorded(
            method: request.method, path: request.path,
            body: request.body, idempotency: request.idempotency
        ))
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: responseJSON)
    }
}

// MARK: - Review

@Suite("Meal draft review")
struct MealDraftReviewTests {
    private func review(
        _ draft: MealDraftSnapshot = CaptureFixtures.eggsAndBread,
        channel: MealSourceChannel = .text,
        assetID: String? = nil
    ) throws -> MealDraftReview {
        MealDraftReview(
            draft: draft,
            source: try #require(MealProposalSource(channel: channel, mediaAssetID: assetID)),
            mealType: .breakfast
        )
    }

    @Test("Reference portions remain estimates without repeated acknowledgments before calculation")
    func approximatePortionsKeepTheirBasis() throws {
        let review = try review()
        #expect(review.items.allSatisfy { $0.hasApproximateQuantity })
        #expect(review.blocker(language: .portugueseBrazil) == nil)
        let request = try #require(review.request(language: .portugueseBrazil))
        #expect(request.mealType == .breakfast)
        #expect(request.source == MealProposalSource(channel: .text, mediaAssetID: nil))
        #expect(request.consumedAt == nil)
        #expect(request.items == [
            MealProposalItemRequest(
                foodName: "ovos mexidos", quantityG: 100, userKcal: nil,
                quantityBasis: .portionReference, candidateID: "c1-0a1b2c3d"
            ),
            MealProposalItemRequest(
                foodName: "pão francês", quantityG: 50, userKcal: nil,
                quantityBasis: .portionReference, candidateID: "c2-1b2c3d4e"
            ),
        ])
    }

    @Test("A quantity the patient types is theirs and needs no further confirmation")
    func typedQuantityIsStated() throws {
        var review = try review()
        review.items[0].quantityText = "120,5"

        let request = try #require(review.request(language: .portugueseBrazil))

        #expect(request.items[0].quantityG == Decimal(string: "120.5"))
        #expect(request.items[0].quantityBasis == .stated)
        #expect(request.items[1].quantityBasis == .portionReference)
    }

    @Test("A candidate without quantity blocks until the patient gives one")
    func missingQuantityBlocks() throws {
        var review = try review(
            CaptureFixtures.photoWithLabel, channel: .gallery, assetID: CaptureFixtures.assetID
        )

        #expect(review.blocker(language: .portugueseBrazil) == .missingQuantity(id: "c2-bbbbbbbb"))

        for invalid in ["", "0", "abc", "10000", "1.234", "-5"] {
            review.items[1].quantityText = invalid
            #expect(
                review.blocker(language: .portugueseBrazil) == .invalidQuantity(id: "c2-bbbbbbbb"),
                "\(invalid)"
            )
        }
        review.items[1].quantityText = "30"
        let request = try #require(review.request(language: .portugueseBrazil))
        #expect(request.items[1].quantityG == 30)
        #expect(request.items[1].quantityBasis == .stated)
        #expect(request.items[0].quantityBasis == .visualEstimate)
        #expect(request.source?.channel == .gallery)
        #expect(request.source?.mediaAssetID == CaptureFixtures.assetID)
    }

    @Test("A name read with doubt keeps its warning and can be corrected without a repeated acknowledgment")
    func doubtfulName() throws {
        let draft = MealDraftSnapshot(
            source: "audio", mediaAssetID: CaptureFixtures.assetID,
            transcript: "comi um negócio lá", contextNote: nil,
            items: [CaptureFixtures.candidate(
                "c1-cccccccc", "negócio", grams: 80, basis: "stated", reason: "ambiguous"
            )],
            nutritionLabel: nil
        )
        var review = try review(draft, channel: .audioRecording, assetID: CaptureFixtures.assetID)

        #expect(review.items[0].hasDoubtfulName)
        #expect(review.blocker(language: .portugueseBrazil) == nil)
        review.items[0].name = "  tapioca  "
        let request = try #require(review.request(language: .portugueseBrazil))
        #expect(request.items[0].foodName == "tapioca")
        #expect(request.items[0].quantityBasis == .stated)

        review.items[0].name = "   "
        #expect(review.blocker(language: .portugueseBrazil) == .invalidName(id: "c1-cccccccc"))
        review.items[0].name = String(repeating: "a", count: 161)
        #expect(review.blocker(language: .portugueseBrazil) == .invalidName(id: "c1-cccccccc"))
    }

    @Test("The label is never preselected and belongs to one item at most")
    func labelSelection() throws {
        var review = try review(
            CaptureFixtures.photoWithLabel, channel: .camera, assetID: CaptureFixtures.assetID
        )
        review.items[1].quantityText = "30"

        #expect(review.offersNutritionLabel)
        #expect(review.suggestedLabelItemID == "c1-aaaaaaaa")
        #expect(try #require(review.request(language: .portugueseBrazil))
            .items.allSatisfy { !$0.usesNutritionLabel })

        review.setUsesNutritionLabel(true, for: "c1-aaaaaaaa")
        review.setUsesNutritionLabel(true, for: "c2-bbbbbbbb")
        var request = try #require(review.request(language: .portugueseBrazil))
        #expect(request.items.map(\.usesNutritionLabel) == [false, true])

        review.remove("c2-bbbbbbbb")
        request = try #require(review.request(language: .portugueseBrazil))
        #expect(request.items.map(\.usesNutritionLabel) == [false])
        review.setUsesNutritionLabel(true, for: "unknown")
        #expect(!review.usesNutritionLabel("unknown"))
    }

    @Test("A quantity on an unknown basis stays approximate and travels without invented basis")
    func unknownBasisFailsClosed() throws {
        let draft = MealDraftSnapshot(
            source: "text", mediaAssetID: nil, transcript: nil, contextNote: nil,
            items: [CaptureFixtures.candidate(
                "c1-dddddddd", "arroz", grams: 120, basis: "model_guess"
            )],
            nutritionLabel: nil
        )
        let review = try review(draft)

        #expect(review.items[0].hasApproximateQuantity)
        #expect(review.blocker(language: .portugueseBrazil) == nil)
        let request = try #require(review.request(language: .portugueseBrazil))
        #expect(request.items[0].quantityBasis == nil)
    }

    @Test("Typing and erasing, or typing the same figure, is not a statement of the patient")
    func untouchedQuantityStaysApproximate() throws {
        var review = try review()
        let language = SupportedAppLanguage.portugueseBrazil

        review.items[0].setQuantityText("1", language: language)
        #expect(review.items[0].hasTypedQuantity)
        review.items[0].setQuantityText("100", language: language)

        #expect(!review.items[0].hasTypedQuantity)
        #expect(review.items[0].hasApproximateQuantity)
        #expect(review.items[0].basis == .portionReference)
        #expect(review.blocker(language: language) == nil)

        // Erased: the field is empty and the quantity is missing, not zero.
        review.items[0].setQuantityText("", language: language)
        #expect(review.blocker(language: language) == .invalidQuantity(id: "c1-0a1b2c3d"))
    }

    @Test("A quantity from the server outside the accepted range is treated as missing")
    func serverQuantityIsValidated() throws {
        for grams in [Decimal(0), -5, 10_000] {
            let draft = MealDraftSnapshot(
                source: "text", mediaAssetID: nil, transcript: nil, contextNote: nil,
                items: [CaptureFixtures.candidate("c1-eeeeeeee", "arroz", grams: grams, basis: "stated")],
                nutritionLabel: nil
            )
            let review = try review(draft)
            #expect(review.blocker(language: .portugueseBrazil)
                == .missingQuantity(id: "c1-eeeeeeee"), "\(grams)")
            #expect(review.request(language: .portugueseBrazil) == nil)
        }
    }

    @Test("The server asking for a second look keeps a notice without blocking a valid stated quantity")
    func needsReviewIsHonoured() throws {
        let draft = MealDraftSnapshot(
            source: "text", mediaAssetID: nil, transcript: nil, contextNote: nil,
            items: [CaptureFixtures.candidate(
                "c1-ffffffff", "arroz", grams: 120, basis: "stated", reason: "future_reason"
            )],
            nutritionLabel: nil
        )
        var review = try review(draft)
        #expect(review.items[0].hasReviewNotice)
        #expect(review.blocker(language: .portugueseBrazil) == nil)
        review.items[0].setQuantityText("130", language: .portugueseBrazil)
        #expect(!review.items[0].hasReviewNotice)
        #expect(review.blocker(language: .portugueseBrazil) == nil)
    }

    @Test("A repeated candidate becomes one row")
    func duplicatedCandidates() throws {
        let item = CaptureFixtures.candidate("c1-aaaaaaaa", "arroz", grams: 120, basis: "stated")
        let review = try review(MealDraftSnapshot(
            source: "text", mediaAssetID: nil, transcript: nil, contextNote: nil,
            items: [item, item], nutritionLabel: nil
        ))
        #expect(review.items.count == 1)
    }

    @Test("A label read from audio or text is never offered")
    func labelOnlyFromPhoto() throws {
        let review = try review(
            CaptureFixtures.photoWithLabel, channel: .audioImport, assetID: CaptureFixtures.assetID
        )
        #expect(!review.offersNutritionLabel)
    }

    @Test("Removing every item blocks the proposal")
    func noItems() throws {
        var review = try review()
        review.remove("c1-0a1b2c3d")
        review.remove("c2-1b2c3d4e")
        #expect(review.blocker(language: .portugueseBrazil) == .noItems)
    }

    @Test("Only the server's candidate id shape travels")
    func candidateIDShape() {
        #expect(MealDraftReview.isCandidateID("c1-0a1b2c3d"))
        #expect(MealDraftReview.isCandidateID("c30-ffffffff"))
        #expect(!MealDraftReview.isCandidateID("c100-0a1b2c3d"))
        #expect(!MealDraftReview.isCandidateID("c1-0A1B2C3D"))
        #expect(!MealDraftReview.isCandidateID("x1-0a1b2c3d"))
    }
}

// MARK: - Request contract

@Suite("Meal proposal origin contract")
struct MealProposalOriginContractTests {
    private func json(_ request: RegistrationProposalRequest) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(request)) as? [String: Any]
        )
    }

    @Test("Origin, basis, candidate and label choice travel as the BFF reads them")
    func encodesOrigin() throws {
        let body = try json(.meal(MealProposalRequest(
            mealType: .snack,
            items: [
                MealProposalItemRequest(
                    foodName: "iogurte natural", quantityG: 170, userKcal: nil,
                    quantityBasis: .visualEstimate, candidateID: "c1-0a1b2c3d",
                    usesNutritionLabel: true
                ),
                MealProposalItemRequest(foodName: "granola", quantityG: 30, userKcal: nil,
                                        quantityBasis: .stated),
            ],
            consumedAt: nil,
            source: MealProposalSource(channel: .gallery, mediaAssetID: CaptureFixtures.assetID)
        )))

        let source = try #require(body["source"] as? [String: Any])
        #expect(source["channel"] as? String == "gallery")
        #expect(source["media_asset_id"] as? String == CaptureFixtures.assetID)
        #expect(source.count == 2)
        let items = try #require(body["items"] as? [[String: Any]])
        #expect(items[0]["quantity_basis"] as? String == "visual_estimate")
        #expect(items[0]["candidate_id"] as? String == "c1-0a1b2c3d")
        #expect(items[0]["use_nutrition_label"] as? Bool == true)
        #expect(items[1]["quantity_basis"] as? String == "stated")
        #expect(items[1]["candidate_id"] == nil)
        #expect(items[1]["use_nutrition_label"] == nil)
        // The client never sends nutrition with a candidate.
        #expect(items.allSatisfy { $0["kcal"] == nil && $0["user_kcal"] == nil })
    }

    @Test("A request without origin is byte-compatible with the earlier contract")
    func omitsOriginWhenAbsent() throws {
        let body = try json(.meal(MealProposalRequest(
            mealType: .lunch,
            items: [MealProposalItemRequest(foodName: "arroz", quantityG: 120, userKcal: nil)],
            consumedAt: nil
        )))
        #expect(Set(body.keys) == ["kind", "meal_type", "items"])
        #expect(Set(try #require((body["items"] as? [[String: Any]])?.first).keys)
            == ["food_name", "quantity_g"])
    }

    @Test("Channel and asset must match: text has none, media needs one")
    func sourcePairing() {
        #expect(MealProposalSource(channel: .text, mediaAssetID: nil) != nil)
        #expect(MealProposalSource(channel: .text, mediaAssetID: CaptureFixtures.assetID) == nil)
        for channel in [MealSourceChannel.camera, .gallery, .audioRecording, .audioImport] {
            #expect(MealProposalSource(channel: channel, mediaAssetID: nil) == nil)
            #expect(MealProposalSource(channel: channel, mediaAssetID: CaptureFixtures.assetID) != nil)
        }
    }

    @Test("Editing a proposal keeps its origin, its bases and its label")
    func editKeepsOrigin() throws {
        let snapshot = try JSONDecoder().decode(RegistrationSnapshot.self, from: Data("""
        {"id":"7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c","status":"pending",
         "created_at":"2026-09-28T12:00:00.000000+00:00","expires_at":"2026-09-29T12:00:00.000000+00:00",
         "resolved_at":null,
         "proposal":{"kind":"meal","meal_type":"lanche",
          "items":[
           {"name":"iogurte natural","quantity_g":170,"kcal":105,"protein_g":6,"carbs_g":8,"fat_g":5,
            "user_kcal":null,"nutrition_source":"product_label","resolution":"resolved",
            "preparation_options":null,"quantity_basis":"visual_estimate"},
           {"name":"granola","quantity_g":30,"kcal":130,"protein_g":3,"carbs_g":20,"fat_g":4,
            "user_kcal":null,"nutrition_source":"taco","resolution":"resolved",
            "preparation_options":null,"quantity_basis":"stated"}],
          "totals":{"kcal":235,"protein_g":9,"carbs_g":28,"fat_g":9},
          "source":{"channel":"gallery","media_asset_id":"0a0a0a0a-1111-4222-8333-444455556666"},
          "warnings":[]}}
        """.utf8))
        var draft = MealProposalEditorDraft(seed: MealProposalEditorSeed(
            registration: snapshot, initialConsumedAt: CaptureFixtures.now, editedIndex: 1
        ))
        draft.quantityText = "45"

        let request = try #require(draft.request(language: .portugueseBrazil))

        #expect(request.source == MealProposalSource(
            channel: .gallery, mediaAssetID: CaptureFixtures.assetID
        ))
        #expect(request.items[0].quantityBasis == .visualEstimate)
        #expect(request.items[0].usesNutritionLabel)
        #expect(request.items[1].quantityG == 45)
        #expect(request.items[1].quantityBasis == .stated)
        #expect(!request.items[1].usesNutritionLabel)
    }

    @Test("A proposal created elsewhere sends no origin back")
    func foreignChannelIsNotEchoed() {
        #expect(MealProposalSourceSnapshot(channel: "mobile", mediaAssetID: nil).requestSource == nil)
        #expect(MealProposalSourceSnapshot(channel: "whatsapp", mediaAssetID: nil).requestSource == nil)
        #expect(MealProposalSourceSnapshot(channel: "text", mediaAssetID: nil).requestSource
            == MealProposalSource(channel: .text, mediaAssetID: nil))
    }
}

private final class SessionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

/// Answers every upload 200 without touching the network.
private final class AcceptingUploadProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
