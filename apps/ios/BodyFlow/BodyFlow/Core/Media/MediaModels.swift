import Foundation

/// Limits the app enforces before anything leaves the phone. The server and
/// the worker enforce the same ones again; these only spare a useless upload.
enum MealMediaLimits {
    static let maximumAudioDuration: TimeInterval = 180
    static let maximumAudioBytes = 25 * 1_024 * 1_024
    static let maximumPhotoBytes = 15 * 1_024 * 1_024
    static let maximumPhotoPixelSize = 2_048
    static let photoCompressionQuality = 0.8
    static let maximumTextLength = 2_000
    static let maximumPlanDocumentBytes = 20 * 1_024 * 1_024
}

enum MediaUploadKind: String, Codable, Hashable, Sendable {
    case mealPhoto = "meal_photo"
    case audioNote = "audio_note"
    case planDocument = "plan_document"
}

struct MediaUploadRequest: Codable, Hashable, Sendable {
    let kind: MediaUploadKind
    let mimeType: String
    let sizeBytes: Int
    /// Audio only: the length the app measured, a pre-filter for the server.
    let durationMS: Int?

    private enum CodingKeys: String, CodingKey {
        case kind
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case durationMS = "duration_ms"
    }
}

enum MediaAssetState: Hashable, Sendable {
    case pendingUpload
    case uploaded
    case processing
    case processed
    case failed(code: String?)
    case deleted
    case unknown
}

struct MediaAssetSnapshot: Codable, Hashable, Sendable {
    let id: String
    let kind: String
    let status: String
    let failureStage: String?
    let failureCode: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case status
        case failureStage = "failure_stage"
        case failureCode = "failure_code"
    }

    var state: MediaAssetState {
        switch status {
        case "pending_upload": .pendingUpload
        case "uploaded": .uploaded
        case "processing": .processing
        case "processed": .processed
        case "failed": .failed(code: failureCode)
        case "deleted": .deleted
        default: .unknown
        }
    }
}

/// The one-time capability to put the file in storage. It is a secret while
/// it lives: never logged, never persisted, never shown.
struct MediaUploadTicket: Codable, Hashable, Sendable {
    let signedURL: String
    let method: String
    let headers: [String: String]
    let expiresAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case signedURL = "signed_url"
        case method
        case headers
        case expiresAt = "expires_at"
    }
}

struct MediaCreateSnapshot: Codable, Hashable, Sendable {
    let asset: MediaAssetSnapshot
    let upload: MediaUploadTicket?
    let replayed: Bool
}

struct MediaAssetCommand: Hashable, Sendable {
    let assetID: String
}

/// A file staged on this phone, ready to upload.
struct StagedMedia: Hashable, Sendable {
    let fileURL: URL
    let kind: MediaUploadKind
    let mimeType: String
    let sizeBytes: Int
    let duration: TimeInterval?
    let channel: MealSourceChannel

    var uploadRequest: MediaUploadRequest {
        MediaUploadRequest(
            kind: kind,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            durationMS: duration.map { max(Int(($0 * 1_000).rounded()), 1) }
        )
    }
}

enum MealDraftRequest: Codable, Hashable, Sendable {
    case text(String)
    case media(assetID: String)

    private enum CodingKeys: String, CodingKey {
        case source
        case text
        case mediaAssetID = "media_asset_id"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .source) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "media":
            self = .media(assetID: try container.decode(String.self, forKey: .mediaAssetID))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .source,
                in: container,
                debugDescription: "unknown draft source"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .source)
            try container.encode(text, forKey: .text)
        case let .media(assetID):
            try container.encode("media", forKey: .source)
            try container.encode(assetID, forKey: .mediaAssetID)
        }
    }
}

/// One food the server read from the text, the recording or the photo. It is
/// a candidate for the patient to review: it carries no nutrition.
struct MealDraftCandidate: Codable, Hashable, Sendable, Identifiable {
    let candidateID: String
    let name: String
    /// nil when nothing said, seen or referenced gives a quantity.
    let quantityG: Decimal?
    let quantityBasis: String
    let count: Decimal?
    let unitLabel: String?
    let confidence: Decimal?
    let needsReview: Bool
    let reviewReason: String?

    var id: String { candidateID }

    private enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case name
        case quantityG = "quantity_g"
        case quantityBasis = "quantity_basis"
        case count
        case unitLabel = "unit_label"
        case confidence
        case needsReview = "needs_review"
        case reviewReason = "review_reason"
    }

    /// The basis as a proposal can carry it; nil for "missing" or a basis
    /// this app does not know.
    var requestBasis: MealQuantityBasis? {
        MealQuantityBasis(rawValue: quantityBasis)
    }
}

struct MealDraftNutritionLabel: Codable, Hashable, Sendable {
    let productName: String?
    let servingSizeG: Decimal?
    let appliesToCandidateID: String?

    private enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case servingSizeG = "serving_size_g"
        case appliesToCandidateID = "applies_to_candidate_id"
    }
}

struct MealDraftSnapshot: Codable, Hashable, Sendable {
    let source: String
    let mediaAssetID: String?
    let transcript: String?
    let contextNote: String?
    let items: [MealDraftCandidate]
    let nutritionLabel: MealDraftNutritionLabel?

    private enum CodingKeys: String, CodingKey {
        case source
        case mediaAssetID = "media_asset_id"
        case transcript
        case contextNote = "context_note"
        case items
        case nutritionLabel = "nutrition_label"
    }
}

/// What can stop a meal capture, in words the screen can say. Anything the
/// app cannot name is `.unavailable` with retry, never a made-up success.
enum MealCaptureFailure: Error, Hashable, Sendable {
    case offline
    case unavailable
    case subscriptionRequired
    case invalidInput
    case audioTooLong
    case fileTooLarge
    case unsupportedFile
    case unreadableMedia
    case nothingRecognized
    case processingFailed
    case processingTimedOut
    case uploadRejected
    case permissionDenied
    case captureUnavailable
}

extension MealCaptureFailure {
    init(_ error: any Error) {
        if let failure = error as? MealCaptureFailure {
            self = failure
            return
        }
        if let capability = error as? BodyFlowCapabilityError {
            self = MealCaptureFailure(capability: capability)
            return
        }
        guard let transport = error as? MobileAPITransportError else {
            self = .unavailable
            return
        }
        switch transport {
        case .network, .timeout:
            self = .offline
        case .validation(let code, _):
            switch code {
            case "audio_too_long": self = .audioTooLong
            case "meal_draft_empty": self = .nothingRecognized
            case "media_type_unsupported", "media_kind_not_supported": self = .unsupportedFile
            case "media_upload_mismatch", "media_upload_missing": self = .uploadRejected
            default: self = .invalidInput
            }
        case .http(let status, _, _):
            self = status == 402 ? .subscriptionRequired : .unavailable
        default:
            self = .unavailable
        }
    }

    private init(capability: BodyFlowCapabilityError) {
        switch capability {
        case .offline: self = .offline
        case .invalidInput: self = .invalidInput
        case .subscriptionRequired: self = .subscriptionRequired
        default: self = .unavailable
        }
    }
}

protocol MealMediaProviding: Sendable {
    func create(
        _ attempt: MutationAttempt<MediaUploadRequest>
    ) async throws -> MediaCreateSnapshot
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> MediaAssetSnapshot
    func requestProcessing(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot
    func asset(id: String) async throws -> MediaAssetSnapshot
    func delete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws
}

protocol MealDraftProviding: Sendable {
    func draft(_ attempt: MutationAttempt<MealDraftRequest>) async throws -> MealDraftSnapshot
}

protocol StorageUploading: Sendable {
    /// Puts the staged file where the ticket points. Throws
    /// `MealCaptureFailure`; never reports the ticket or the address.
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws
}
