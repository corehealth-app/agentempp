import Foundation

enum SignupBodyPhotoPose: String, CaseIterable, Codable, Hashable, Sendable {
    case front, side, back
}

struct SignupBodyPhoto: Codable, Hashable, Sendable {
    let id: String
    let status: String
    let createdAt: APITimestamp

    enum CodingKeys: String, CodingKey {
        case id, status
        case createdAt = "created_at"
    }
}

struct SignupBodyPhotoSlot: Codable, Hashable, Sendable {
    let pose: SignupBodyPhotoPose
    let photo: SignupBodyPhoto?
}

struct SignupBodyPhotoConsent: Codable, Hashable, Sendable {
    let documentKey: String
    let version: String
    let locale: String
    let body: String
    let bodyHash: String
    let acceptedAt: APITimestamp?

    enum CodingKeys: String, CodingKey {
        case version, locale, body
        case documentKey = "document_key"
        case bodyHash = "body_hash"
        case acceptedAt = "accepted_at"
    }
}

struct SignupBodyPhotoSourceIDs: Codable, Hashable, Sendable {
    let front: String
    let side: String
    let back: String
}

struct SignupBodyPhotoEstimate: Codable, Hashable, Sendable {
    struct Reading: Codable, Hashable, Sendable {
        let pose: SignupBodyPhotoPose
        let bodyFatPercent: Decimal

        enum CodingKeys: String, CodingKey {
            case pose
            case bodyFatPercent = "body_fat_percent"
        }
    }
    struct Decision: Codable, Hashable, Sendable {
        let usable: Bool
        let bodyFatPercent: Decimal?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case usable, reason
            case bodyFatPercent = "body_fat_percent"
        }
    }
    struct Decisions: Codable, Hashable, Sendable {
        let masculine: Decision
        let feminine: Decision

        enum CodingKeys: String, CodingKey {
            case masculine = "masculino"
            case feminine = "feminino"
        }
    }

    let isEstimate: Bool
    let bySex: Decisions
    let sourceIDs: SignupBodyPhotoSourceIDs?
    let fingerprint: String?
    let readings: [Reading]?

    init(isEstimate: Bool, bySex: Decisions, sourceIDs: SignupBodyPhotoSourceIDs?, fingerprint: String?, readings: [Reading]? = nil) {
        self.isEstimate = isEstimate
        self.bySex = bySex
        self.sourceIDs = sourceIDs
        self.fingerprint = fingerprint
        self.readings = readings
    }

    enum CodingKeys: String, CodingKey {
        case fingerprint, readings
        case isEstimate = "is_estimate"
        case bySex = "by_sex"
        case sourceIDs = "source_ids"
    }
}

/// Public state only. It carries no raw model output, Storage path or session.
/// Older v1 snapshots omit individual readings; never substitute the joined mean.
struct SignupBodyPhotoState: Codable, Hashable, Sendable {
    let available: Bool
    let unavailableReason: String?
    let consent: SignupBodyPhotoConsent?
    let minimumAge: Int
    let poses: [SignupBodyPhotoSlot]
    let estimate: SignupBodyPhotoEstimate?
    let remainingUploads: Int

    enum CodingKeys: String, CodingKey {
        case available, consent, poses, estimate
        case unavailableReason = "unavailable_reason"
        case minimumAge = "minimum_age"
        case remainingUploads = "remaining_uploads"
    }
}

struct SignupBodyPhotoConsentRequest: Codable, Hashable, Sendable {
    let version: String
    let bodyHash: String
    /// Civil date supplied only in this request body, never in a path/query.
    let birthDate: String

    enum CodingKeys: String, CodingKey {
        case version
        case bodyHash = "body_hash"
        case birthDate = "birth_date"
    }
}

struct SignupBodyPhotoConsentReceipt: Codable, Hashable, Sendable {
    let documentKey: String
    let version: String
    let acceptedAt: APITimestamp

    enum CodingKeys: String, CodingKey {
        case version
        case documentKey = "document_key"
        case acceptedAt = "accepted_at"
    }
}

struct SignupBodyPhotoCreateRequest: Codable, Hashable, Sendable {
    let pose: SignupBodyPhotoPose
    let mimeType: String
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case pose
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
    }
}

struct SignupBodyPhotoCreateReceipt: Codable, Hashable, Sendable {
    let photo: SignupBodyPhotoOperationPhoto
    let upload: MediaUploadTicket?
    let replayed: Bool
}

struct SignupBodyPhotoCompleteReceipt: Codable, Hashable, Sendable {
    let photo: SignupBodyPhotoOperationPhoto
}

struct SignupBodyPhotoOperationPhoto: Codable, Hashable, Sendable {
    let id: String
    let pose: SignupBodyPhotoPose
    let status: String
    let createdAt: APITimestamp

    enum CodingKeys: String, CodingKey {
        case id, pose, status
        case createdAt = "created_at"
    }
}

/// The endpoint deletes the whole signup scope; no asset ID is put in its body.
struct SignupBodyPhotoDeleteCommand: Hashable, Sendable {}

struct SignupBodyPhotoDeleteReceipt: Codable, Hashable, Sendable {
    let deleted: Int
}

/// The official completion string, retained verbatim with its microseconds.
struct SignupBodyPhotoRepairCommand: Hashable, Sendable {
    let generation: String
}

enum SignupBodyPhotoFailure: Error, Hashable, Sendable {
    case unavailable
    case invalidInput
    case offline
    case consentRequired
    case ageNotAllowed
    case signupCompleted
    case readingFailed
    case uploadNotPending
    case limitReached
    case cleanupPending
    case sessionChanged
    case unreadableImage
    case fileTooLarge

    init(_ error: any Error) {
        if let failure = error as? Self {
            self = failure
            return
        }
        if let lifecycle = error as? SessionLifecycleError {
            switch lifecycle {
            case .missingSession, .sessionSuperseded: self = .sessionChanged
            case .refreshFailed, .localInvalidationFailed: self = .unavailable
            }
            return
        }
        if let media = error as? MealCaptureFailure {
            switch media {
            case .unreadableMedia: self = .unreadableImage
            case .fileTooLarge: self = .fileTooLarge
            case .invalidInput: self = .invalidInput
            case .offline: self = .offline
            default: self = .unavailable
            }
            return
        }
        guard let transport = error as? MobileAPITransportError else {
            self = .unavailable
            return
        }
        switch transport {
        case .network, .timeout: self = .offline
        case .missingSession, .sessionSuperseded, .unauthorized: self = .sessionChanged
        case let .forbidden(code, _), let .conflict(code, _),
             let .rateLimited(code, _), let .http(_, code, _), let .server(_, code, _):
            switch code {
            case "body_photo_consent_required", "body_photo_consent_version_stale": self = .consentRequired
            case "body_photo_age_not_allowed": self = .ageNotAllowed
            case "onboarding_already_completed": self = .signupCompleted
            case "body_photo_reading_failed": self = .readingFailed
            case "media_upload_not_pending": self = .uploadNotPending
            case "body_photo_limit_reached": self = .limitReached
            case "body_photo_cleanup_pending": self = .cleanupPending
            default: self = .unavailable
            }
        case .validation: self = .invalidInput
        default: self = .unavailable
        }
    }
}

protocol SignupBodyPhotosProviding: Sendable {
    func state() async throws -> SignupBodyPhotoState
    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws
        -> SignupBodyPhotoConsentReceipt
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws
        -> SignupBodyPhotoCreateReceipt
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws
        -> SignupBodyPhotoCompleteReceipt
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws
        -> SignupBodyPhotoDeleteReceipt
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws
        -> SignupBodyPhotoDeleteReceipt
}

extension SignupBodyPhotosProviding {
    // Older/synthetic providers have no authority to repair a real generation.
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws
        -> SignupBodyPhotoDeleteReceipt {
        throw SignupBodyPhotoFailure.unavailable
    }
}
