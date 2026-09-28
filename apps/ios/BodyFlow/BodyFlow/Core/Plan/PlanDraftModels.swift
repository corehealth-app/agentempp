import Foundation

enum PlanDraftDomain: String, Codable, Hashable, Sendable, CaseIterable {
    case training
    case nutrition
}

enum PlanDraftStatus: String, Hashable, Sendable {
    case extracting
    case generating
    case needsCompletion = "needs_completion"
    case readyForReview = "ready_for_review"
    case confirmed
    case discarded
    case expired
    case failed
    case unknown

    init(serverValue: String) {
        self = PlanDraftStatus(rawValue: serverValue) ?? .unknown
    }

    /// Still being read or generated; the content does not exist yet.
    var isInProgress: Bool { self == .extracting || self == .generating }

    var isReviewable: Bool { self == .needsCompletion || self == .readyForReview }
}

struct PlanDraftUncertainField: Codable, Hashable, Sendable {
    let pointer: String
    let reason: String
}

struct PlanDraftSummary: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let domain: PlanDraftDomain
    let origin: String
    let status: String
    let payloadVersion: Int
    let createdAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case id, domain, origin, status
        case payloadVersion = "payload_version"
        case createdAt = "created_at"
    }

    var state: PlanDraftStatus { PlanDraftStatus(serverValue: status) }
    var isImported: Bool { origin != "flow_generated" }
}

struct PlanDraftList: Codable, Hashable, Sendable {
    let items: [PlanDraftSummary]
}

/// A plan waiting for the patient. It is never the patient's plan: only the
/// confirmation turns it into one, and the patient's confirmation is not a
/// professional review.
struct PlanDraftSnapshot: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let domain: PlanDraftDomain
    let origin: String
    let status: String
    let payloadVersion: Int
    let payload: JSONValue?
    let uncertainFields: [PlanDraftUncertainField]
    let unrecognizedSegments: [String]
    let replacesCurrentPlan: Bool
    let canConfirm: Bool
    let notices: [String]
    let failureCode: String?
    let confirmedPlanID: String?
    let alreadyConfirmed: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, domain, origin, status, payload, notices
        case payloadVersion = "payload_version"
        case uncertainFields = "uncertain_fields"
        case unrecognizedSegments = "unrecognized_segments"
        case replacesCurrentPlan = "replaces_current_plan"
        case canConfirm = "can_confirm"
        case failureCode = "failure_code"
        case confirmedPlanID = "confirmed_plan_id"
        case alreadyConfirmed = "already_confirmed"
    }

    var state: PlanDraftStatus { PlanDraftStatus(serverValue: status) }
    var isImported: Bool { origin != "flow_generated" }
    var mentionsMedications: Bool { notices.contains("medications_not_imported") }
}

struct PlanDraftEdit: Encodable, Hashable, Sendable {
    /// Addresses the request; it is not part of the body.
    let draftID: String
    let payloadVersion: Int
    let payload: JSONValue

    private enum CodingKeys: String, CodingKey {
        case payloadVersion = "payload_version"
        case payload
    }
}

struct PlanDraftConfirmation: Hashable, Sendable {
    let draftID: String
    /// The version the patient saw on screen when confirming.
    let payloadVersion: Int
}

struct PlanDraftCommand: Hashable, Sendable {
    let draftID: String
}

struct PlanImportRequest: Codable, Hashable, Sendable {
    let mediaAssetID: String
    let domain: PlanDraftDomain

    private enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case domain
    }
}

struct PlanImportReceipt: Codable, Hashable, Sendable {
    let draftID: String
    let status: String

    private enum CodingKeys: String, CodingKey {
        case draftID = "draft_id"
        case status
    }
}

/// What can stop a plan draft operation, in words the screen can say.
enum PlanDraftFailure: Error, Hashable, Sendable {
    case offline
    case unavailable
    case subscriptionRequired
    case notFound
    /// The draft changed since it was read; the screen reloads it.
    case draftChanged
    /// The plan in force changed while this draft was under review.
    case planChangedDuringReview
    case prescribedPlanProtected
    case incomplete
    case notReviewable
    case expired
    case tooManyDrafts
    case documentAlreadyImported
    case documentAlreadyRead
    case invalidInput
}

extension PlanDraftFailure {
    init(_ error: any Error) {
        if let failure = error as? PlanDraftFailure {
            self = failure
            return
        }
        if let capture = error as? MealCaptureFailure {
            switch capture {
            case .offline: self = .offline
            case .subscriptionRequired: self = .subscriptionRequired
            case .invalidInput: self = .invalidInput
            default: self = .unavailable
            }
            return
        }
        guard let transport = error as? MobileAPITransportError else {
            self = .unavailable
            return
        }
        switch transport {
        case .network, .timeout:
            self = .offline
        case .conflict(let code, _):
            switch code {
            case "draft_changed": self = .draftChanged
            case "plan_changed_during_review": self = .planChangedDuringReview
            case "prescribed_plan_protected": self = .prescribedPlanProtected
            case "plan_draft_not_reviewable": self = .notReviewable
            case "plan_document_already_imported": self = .documentAlreadyImported
            case "plan_document_already_read": self = .documentAlreadyRead
            default: self = .unavailable
            }
        case .validation(let code, _):
            self = code == "plan_draft_incomplete" ? .incomplete : .invalidInput
        case .rateLimited(let code, _):
            self = code == "plan_draft_limit_reached" ? .tooManyDrafts : .unavailable
        case .http(let status, _, _):
            switch status {
            case 402: self = .subscriptionRequired
            case 404: self = .notFound
            case 410: self = .expired
            default: self = .unavailable
            }
        default:
            self = .unavailable
        }
    }
}

protocol PlanDraftProviding: Sendable {
    func openDrafts() async throws -> [PlanDraftSummary]
    func draft(id: String) async throws -> PlanDraftSnapshot
    func update(_ attempt: MutationAttempt<PlanDraftEdit>) async throws -> PlanDraftSnapshot
    func confirm(
        _ attempt: MutationAttempt<PlanDraftConfirmation>
    ) async throws -> PlanDraftSnapshot
    func discard(_ attempt: MutationAttempt<PlanDraftCommand>) async throws -> PlanDraftSnapshot
    func startImport(
        _ attempt: MutationAttempt<PlanImportRequest>
    ) async throws -> PlanImportReceipt
}

/// What the plan drafts need from the outside.
struct PlanDraftCapability: Sendable {
    let drafts: any PlanDraftProviding
    /// Sending documents; nil where only Flow proposals are reviewed.
    let media: (any MealMediaProviding)?
    let uploader: (any StorageUploading)?
    let staging: MediaStagingStore

    var supportsImport: Bool { media != nil && uploader != nil }
}
