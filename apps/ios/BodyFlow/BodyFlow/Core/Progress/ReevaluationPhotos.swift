import CryptoKit
import Foundation

enum ReevaluationPhotoFailure: Error, Equatable, Sendable {
    case invalidInput, invalidResponse, sessionEnded, changed, quota, offline, unavailable, busy
}
enum ReevaluationPhotoPose: String, Codable, CaseIterable, Sendable { case front, side, back }
enum ReevaluationPhotoStatus: String, Decodable, Sendable {
    case pendingUpload = "pending_upload", uploaded, processing, processed, failed, deleted
}
enum ReevaluationPhotoValidation {
    static func revision(_ value:String) -> Bool {
        guard let number = UInt64(value) else { return false }
        return number > 0 && number <= UInt64(Int64.max) && String(number) == value
    }
    static func id(_ value:String) -> Bool { ClinicalFirstPhaseChoices.validID(value) }
    static func same(_ left:String,_ right:String) -> Bool { left.lowercased() == right.lowercased() }
    static func hash(_ value:String) -> Bool { value.count == 64 && value.allSatisfy { $0.isASCII && ("0123456789abcdef".contains($0)) } }
}
struct ReevaluationPhotoDocument: Decodable, Equatable, Sendable {
    let id:String; let documentKey:String; let version:String; let locale:String; let body:String; let bodyHash:String
    let requiredFrom:APITimestamp; let idleTimeoutSeconds:Int
    private enum CodingKeys:String,CodingKey { case id,version,locale,body; case documentKey = "document_key", bodyHash = "body_hash", requiredFrom = "required_from", idleTimeoutSeconds = "idle_timeout_seconds" }
    func validate() throws {
        let digest = SHA256.hash(data:Data(body.utf8)).map { String(format:"%02x",$0) }.joined()
        guard ReevaluationPhotoValidation.id(id), documentKey == "body_photo_reevaluation_consent",
              !version.isEmpty, version.count <= 64, version.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }),
              ["pt-BR","en-US"].contains(locale), !body.isEmpty, body.count <= 16384,
              idleTimeoutSeconds == 86400, ReevaluationPhotoValidation.hash(bodyHash), digest == bodyHash else { throw ReevaluationPhotoFailure.invalidResponse }
    }
}
struct ReevaluationPhotoAcceptance: Decodable, Equatable, Sendable {
    let acceptanceID:String; let documentID:String; let documentKey:String; let version:String; let locale:String; let bodyHash:String
    let acceptedAt:APITimestamp; let idleExpiresAt:APITimestamp
    private enum CodingKeys:String,CodingKey { case version,locale; case acceptanceID = "acceptance_id", documentID = "document_id", documentKey = "document_key", bodyHash = "body_hash", acceptedAt = "accepted_at", idleExpiresAt = "idle_expires_at" }
    func matches(_ document:ReevaluationPhotoDocument) -> Bool {
        ReevaluationPhotoValidation.id(acceptanceID) && ReevaluationPhotoValidation.same(documentID,document.id)
            && documentKey == document.documentKey && version == document.version && locale == document.locale && bodyHash == document.bodyHash
            && acceptedAt.value < idleExpiresAt.value
    }
}
struct ReevaluationPhotoConsent: Decodable, Equatable, Sendable {
    enum Availability:String,Decodable,Sendable { case available, unavailable }
    enum Reason:String,Decodable,Sendable { case policyUnavailable = "policy_unavailable", consentRequired = "consent_required", consentChanged = "consent_changed", consentExpired = "consent_expired" }
    let version:Int; let cycleID:String; let cycleRevision:String; let availability:Availability; let unavailableReason:Reason?
    let document:ReevaluationPhotoDocument?; let acceptance:ReevaluationPhotoAcceptance?
    private enum CodingKeys:String,CodingKey { case version,availability,document,acceptance; case cycleID = "cycle_id", cycleRevision = "cycle_revision", unavailableReason = "unavailable_reason" }
    func validated(cycleID:String) throws -> Self {
        guard version == 1, ReevaluationPhotoValidation.id(self.cycleID), ReevaluationPhotoValidation.same(self.cycleID,cycleID),
              ReevaluationPhotoValidation.revision(cycleRevision), (availability == .available) == (unavailableReason == nil),
              (availability == .available) == (acceptance != nil), (document == nil) == (unavailableReason == .policyUnavailable) else { throw ReevaluationPhotoFailure.invalidResponse }
        if let document { try document.validate(); if let acceptance { guard acceptance.matches(document) else { throw ReevaluationPhotoFailure.invalidResponse } } }
        return self
    }
}
struct ReevaluationPhotoConsentInput: Encodable, Equatable, Sendable {
    struct Document:Encodable,Equatable,Sendable { let id:String; let documentKey:String; let version:String; let locale:String; let bodyHash:String }
    let expectedRevision:String; let document:Document
    init(state:ReevaluationPhotoConsent) throws {
        _ = try state.validated(cycleID:state.cycleID)
        guard let shown = state.document else { throw ReevaluationPhotoFailure.invalidInput }
        expectedRevision = state.cycleRevision
        document = Document(id:shown.id,documentKey:shown.documentKey,version:shown.version,locale:shown.locale,bodyHash:shown.bodyHash)
    }
}
struct ReevaluationPhotoQuota: Decodable, Equatable, Sendable {
    let maximumNewPhotos:Int; let windowSeconds:Int
    private enum CodingKeys:String,CodingKey { case maximumNewPhotos = "max_new_photos", windowSeconds = "window_seconds" }
    var isApproved:Bool { maximumNewPhotos == 6 && windowSeconds == 86400 }
}
struct ReevaluationPhotoSnapshot: Decodable, Equatable, Sendable {
    struct Slot:Decodable,Equatable,Sendable {
        struct Asset:Decodable,Equatable,Sendable {
            let id:String; let status:ReevaluationPhotoStatus; let estimatedBodyFatPercent:Decimal?
            private enum CodingKeys:String,CodingKey { case id,status; case estimatedBodyFatPercent = "estimated_body_fat_percent" }
            var hasValidDisplayReading:Bool {
                guard let percent = estimatedBodyFatPercent else { return true }
                return status == .processed && !percent.isNaN && percent >= 3 && percent <= 60
            }
        }
        let pose:ReevaluationPhotoPose; let asset:Asset?
    }
    let version:Int; let cycleID:String; let cycleRevision:String; let acceptanceID:String?; let photos:[Slot]; let quota:ReevaluationPhotoQuota
    private enum CodingKeys:String,CodingKey { case version,photos,quota; case cycleID = "cycle_id", cycleRevision = "cycle_revision", acceptanceID = "acceptance_id" }
    func validated(cycleID:String) throws -> Self {
        let ids = photos.compactMap { $0.asset?.id.lowercased() }
        guard version == 1, ReevaluationPhotoValidation.id(self.cycleID), ReevaluationPhotoValidation.same(self.cycleID,cycleID),
              ReevaluationPhotoValidation.revision(cycleRevision), quota.isApproved, photos.count == 3,
              Set(photos.map(\.pose)) == Set(ReevaluationPhotoPose.allCases), Set(ids).count == ids.count,
              ids.allSatisfy(ReevaluationPhotoValidation.id), acceptanceID == nil || ReevaluationPhotoValidation.id(acceptanceID!),
              acceptanceID != nil || ids.isEmpty,
              photos.allSatisfy({ $0.asset?.hasValidDisplayReading != false }) else { throw ReevaluationPhotoFailure.invalidResponse }
        return self
    }
}
struct ReevaluationPhotoAsset: Decodable, Equatable, Sendable {
    let id:String; let cycleID:String; let acceptanceID:String; let pose:ReevaluationPhotoPose; let mimeType:String; let sizeBytes:Int
    let status:ReevaluationPhotoStatus; let createdAt:APITimestamp; let retentionUntil:APITimestamp
    private enum CodingKeys:String,CodingKey { case id,pose,status; case cycleID = "cycle_id", acceptanceID = "acceptance_id", mimeType = "mime_type", sizeBytes = "size_bytes", createdAt = "created_at", retentionUntil = "retention_until" }
    var fileExtension:String? { ["image/jpeg":"jpg","image/png":"png","image/webp":"webp","image/heic":"heic","image/heif":"heif"][mimeType] }
    func validate(cycleID:String,assetID:String? = nil,acceptanceID:String) throws {
        guard ReevaluationPhotoValidation.id(id), ReevaluationPhotoValidation.id(self.cycleID), ReevaluationPhotoValidation.same(self.cycleID,cycleID),
              assetID == nil || ReevaluationPhotoValidation.same(id,assetID!), ReevaluationPhotoValidation.id(self.acceptanceID),
              ReevaluationPhotoValidation.same(self.acceptanceID,acceptanceID), fileExtension != nil,
              (1...MealMediaLimits.maximumPhotoBytes).contains(sizeBytes), createdAt.value < retentionUntil.value else { throw ReevaluationPhotoFailure.invalidResponse }
    }
}
struct ReevaluationPhotoAllocationInput: Encodable, Equatable, Sendable {
    let expectedRevision:String; let acceptanceId:String; let pose:ReevaluationPhotoPose; let mimeType:String; let sizeBytes:Int
    func validate() throws {
        guard ReevaluationPhotoValidation.revision(expectedRevision), ReevaluationPhotoValidation.id(acceptanceId), mimeType == "image/jpeg",
              (1...MealMediaLimits.maximumPhotoBytes).contains(sizeBytes) else { throw ReevaluationPhotoFailure.invalidInput }
    }
}
struct ReevaluationPhotoAllocation: Decodable, Equatable, Sendable {
    let version:Int; let cycleID:String; let cycleRevision:String; let asset:ReevaluationPhotoAsset; let quota:ReevaluationPhotoQuota
    private enum CodingKeys:String,CodingKey { case version,asset,quota; case cycleID = "cycle_id", cycleRevision = "cycle_revision" }
    func validated(cycleID:String,input:ReevaluationPhotoAllocationInput) throws -> Self {
        try input.validate(); try asset.validate(cycleID:cycleID,acceptanceID:input.acceptanceId)
        guard version == 1, ReevaluationPhotoValidation.same(self.cycleID,cycleID), ReevaluationPhotoValidation.revision(cycleRevision),
              UInt64(cycleRevision)! >= UInt64(input.expectedRevision)!, quota.isApproved, asset.pose == input.pose,
              asset.mimeType == input.mimeType, asset.sizeBytes == input.sizeBytes, asset.status != .deleted else { throw ReevaluationPhotoFailure.invalidResponse }
        return self
    }
}
struct ReevaluationPhotoUpload: Decodable, Equatable, Sendable {
    let version:Int; let cycleID:String; let asset:ReevaluationPhotoAsset; let upload:MediaUploadTicket
    private enum CodingKeys:String,CodingKey { case version,asset,upload; case cycleID = "cycle_id" }
    func validated(cycleID:String,assetID:String,acceptanceID:String) throws -> Self {
        try asset.validate(cycleID:cycleID,assetID:assetID,acceptanceID:acceptanceID)
        guard version == 1, ReevaluationPhotoValidation.same(self.cycleID,cycleID), asset.status == .pendingUpload,
              let url = URLComponents(string:upload.signedURL), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.fragment == nil,
              upload.method == "PUT", upload.headers == ["Content-Type":asset.mimeType,"x-upsert":"false"],
              url.queryItems?.count == 1, url.queryItems?.first?.name == "token", url.queryItems?.first?.value?.isEmpty == false else { throw ReevaluationPhotoFailure.invalidResponse }
        let parts = url.percentEncodedPath.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count == 9, parts.prefix(7).map(String.init) == ["","storage","v1","object","upload","sign","body-checkin-photos"],
              ReevaluationPhotoValidation.id(String(parts[7])), parts[8] == "\(asset.id).\(asset.fileExtension!)" else { throw ReevaluationPhotoFailure.invalidResponse }
        return self
    }
}
struct ReevaluationPhotoCompletion: Decodable, Equatable, Sendable {
    let version:Int; let cycleID:String; let cycleRevision:String; let sourceRevision:String; let asset:ReevaluationPhotoAsset
    private enum CodingKeys:String,CodingKey { case version,asset; case cycleID = "cycle_id", cycleRevision = "cycle_revision", sourceRevision = "source_revision" }
    func validated(cycleID:String,assetID:String,acceptanceID:String) throws -> Self {
        try asset.validate(cycleID:cycleID,assetID:assetID,acceptanceID:acceptanceID)
        guard version == 1, ReevaluationPhotoValidation.same(self.cycleID,cycleID), ReevaluationPhotoValidation.revision(cycleRevision),
              ReevaluationPhotoValidation.revision(sourceRevision), [.uploaded,.processing,.processed].contains(asset.status) else { throw ReevaluationPhotoFailure.invalidResponse }
        return self
    }
}
struct ReevaluationPhotoProcessing: Decodable, Equatable, Sendable {
    enum Status:String,Decodable,Sendable { case processed, skipped, failed }
    enum Reason:String,Decodable,Sendable { case storageUnavailable = "storage_unavailable", invalidBytes = "invalid_bytes", providerUnavailable = "provider_unavailable", invalidAnalysis = "invalid_analysis" }
    let version:Int; let cycleID:String; let assetID:String; let status:Status; let reason:Reason?
    private enum CodingKeys:String,CodingKey { case version,status,reason; case cycleID = "cycle_id", assetID = "asset_id" }
    func validated(cycleID:String,assetID:String) throws -> Self {
        guard version == 1, ReevaluationPhotoValidation.id(self.cycleID), ReevaluationPhotoValidation.id(self.assetID),
              ReevaluationPhotoValidation.same(self.cycleID,cycleID), ReevaluationPhotoValidation.same(self.assetID,assetID),
              (status == .failed) == (reason != nil) else { throw ReevaluationPhotoFailure.invalidResponse }
        return self
    }
}
struct ReevaluationPhotoDiscardInput: Encodable, Equatable, Sendable { let acceptanceId:String; let expectedRevision:String }
struct ReevaluationPhotoDiscard: Decodable, Equatable, Sendable {
    enum Deletion:String,Decodable,Sendable { case pending, waiting, settled }
    let version:Int; let cycleID:String; let acceptanceID:String; let status:String; let deletion:Deletion
    private enum CodingKeys:String,CodingKey { case version,status,deletion; case cycleID = "cycle_id", acceptanceID = "acceptance_id" }
    func validated(cycleID:String,acceptanceID:String) throws -> Self {
        guard version == 1, ReevaluationPhotoValidation.id(self.cycleID), ReevaluationPhotoValidation.id(self.acceptanceID),
              ReevaluationPhotoValidation.same(self.cycleID,cycleID), ReevaluationPhotoValidation.same(self.acceptanceID,acceptanceID), status == "discard_requested" else { throw ReevaluationPhotoFailure.invalidResponse }
        return self
    }
}

protocol ReevaluationPhotosProviding: Sendable {
    func consent() async throws -> ReevaluationPhotoConsent
    func accept(_ input:ReevaluationPhotoConsentInput,key:IdempotencyKey) async throws -> ReevaluationPhotoConsent
    func snapshot() async throws -> ReevaluationPhotoSnapshot
    func allocate(_ input:ReevaluationPhotoAllocationInput,key:IdempotencyKey) async throws -> ReevaluationPhotoAllocation
    func issueUpload(assetID:String,acceptanceID:String,key:IdempotencyKey) async throws -> ReevaluationPhotoUpload
    func complete(assetID:String,acceptanceID:String,key:IdempotencyKey) async throws -> ReevaluationPhotoCompletion
    func process(assetID:String,key:IdempotencyKey) async throws -> ReevaluationPhotoProcessing
    func discard(_ input:ReevaluationPhotoDiscardInput,key:IdempotencyKey) async throws -> ReevaluationPhotoDiscard
    func publish(_ operation:@MainActor @Sendable () throws -> Void) async throws
}
