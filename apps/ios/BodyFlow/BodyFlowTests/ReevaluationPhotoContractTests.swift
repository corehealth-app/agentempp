import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

@Suite("Recurring photos — public contract and exact legal identity")
struct ReevaluationPhotoContractTests {
    static let cycle = "b3b01000-0000-4000-8000-000000005601"
    static let asset = "b3b01000-0000-4000-8000-000000005602"
    static let acceptance = "b3b01000-0000-4000-8000-000000005603"
    static let document = "b3b01000-0000-4000-8000-000000005604"
    static let body = "Texto exato.\nFotos privadas.  "
    static let hash = SHA256.hash(data: Data(body.utf8)).map { String(format:"%02x",$0) }.joined()
    static func decode<T:Decodable>(_ type:T.Type,_ object:[String:Any]) throws -> T {
        try JSONDecoder().decode(type,from:JSONSerialization.data(withJSONObject:object))
    }
    static func consent(_ accepted:Bool = false) -> [String:Any] {
        ["version":1,"cycle_id":cycle,"cycle_revision":accepted ? "2":"1","availability":accepted ? "available":"unavailable",
         "unavailable_reason":accepted ? NSNull():"consent_required",
         "document":["id":document,"document_key":"body_photo_reevaluation_consent","version":"pt-1","locale":"pt-BR","body":body,"body_hash":hash,"required_from":"2026-10-01T12:00:00.000000Z","idle_timeout_seconds":86400],
         "acceptance":accepted ? ["acceptance_id":acceptance,"document_id":document,"document_key":"body_photo_reevaluation_consent","version":"pt-1","locale":"pt-BR","body_hash":hash,"accepted_at":"2026-10-27T12:00:00.000000Z","idle_expires_at":"2026-10-28T12:00:00.000000Z"]:NSNull()]
    }
    static func photo(status:String = "pending_upload") -> [String:Any] {
        ["id":asset,"cycle_id":cycle,"acceptance_id":acceptance,"pose":"front","mime_type":"image/jpeg","size_bytes":1200,"status":status,"created_at":"2026-10-27T12:00:00.000000Z","retention_until":"2026-10-28T12:00:00.000000Z"]
    }
    @Test func exactConsentTextAndBigintRevisionSurviveWithoutAutomaticAcceptance() throws {
        var raw = Self.consent(); raw["cycle_revision"] = "9223372036854775807"
        let state = try Self.decode(ReevaluationPhotoConsent.self,raw).validated(cycleID:Self.cycle)
        #expect(state.document?.body == Self.body)
        #expect(state.cycleRevision == "9223372036854775807")
        #expect(state.acceptance == nil && state.availability == .unavailable)
        #expect(throws:(any Error).self) { try state.validated(cycleID:Self.asset) }
    }
    @Test func changedBodyUnapprovedRetentionAndMismatchedAcceptanceAreRejected() throws {
        var raw = Self.consent(true), doc = try #require(raw["document"] as? [String:Any])
        doc["body"] = Self.body.trimmingCharacters(in:.whitespacesAndNewlines); raw["document"] = doc
        #expect(throws:(any Error).self) { try Self.decode(ReevaluationPhotoConsent.self,raw).validated(cycleID:Self.cycle) }
        doc["body"] = Self.body; doc["idle_timeout_seconds"] = 60; raw["document"] = doc
        #expect(throws:(any Error).self) { try Self.decode(ReevaluationPhotoConsent.self,raw).validated(cycleID:Self.cycle) }
        raw = Self.consent(true); var acceptance = try #require(raw["acceptance"] as? [String:Any]); acceptance["body_hash"] = String(repeating:"0",count:64); raw["acceptance"] = acceptance
        #expect(throws:(any Error).self) { try Self.decode(ReevaluationPhotoConsent.self,raw).validated(cycleID:Self.cycle) }
    }
    @Test func requestContainsShownIdentityAndNoOwnerClockOrClinicalValues() throws {
        let state = try Self.decode(ReevaluationPhotoConsent.self,Self.consent()).validated(cycleID:Self.cycle)
        let input = try ReevaluationPhotoConsentInput(state:state)
        let object = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(input)) as? [String:Any])
        #expect(Set(object.keys) == ["expectedRevision","document"])
        let doc = try #require(object["document"] as? [String:Any])
        #expect(Set(doc.keys) == ["id","documentKey","version","locale","bodyHash"])
        #expect(doc["bodyHash"] as? String == Self.hash)
    }
    @Test func snapshotsRequireThreeDistinctPosesAndBoundAcceptance() throws {
        let poses = ["front","side","back"]
        var raw:[String:Any] = ["version":1,"cycle_id":Self.cycle,"cycle_revision":"2","acceptance_id":Self.acceptance,"photos":poses.map { ["pose":$0,"asset":NSNull()] as [String:Any] },"quota":["max_new_photos":6,"window_seconds":86400]]
        #expect(try Self.decode(ReevaluationPhotoSnapshot.self,raw).validated(cycleID:Self.cycle).photos.count == 3)
        raw["photos"] = ["front","front","back"].map { ["pose":$0,"asset":NSNull()] as [String:Any] }
        #expect(throws:(any Error).self) { try Self.decode(ReevaluationPhotoSnapshot.self,raw).validated(cycleID:Self.cycle) }
    }
    @Test func uploadCapabilityMustMatchAssetMimeAndExactPutShape() throws {
        let path = "/storage/v1/object/upload/sign/body-checkin-photos/\(Self.document)/\(Self.asset).jpg"
        var raw:[String:Any] = ["version":1,"cycle_id":Self.cycle,"asset":Self.photo(),"upload":["signed_url":"https://owned.supabase.co\(path)?token=synthetic","method":"PUT","headers":["Content-Type":"image/jpeg","x-upsert":"false"],"expires_at":"2026-10-27T14:00:00.000Z"]]
        let value = try Self.decode(ReevaluationPhotoUpload.self,raw).validated(cycleID:Self.cycle,assetID:Self.asset,acceptanceID:Self.acceptance)
        #expect(value.asset.pose == .front)
        var ticket = try #require(raw["upload"] as? [String:Any]); ticket["headers"] = ["Content-Type":"image/jpeg","x-upsert":"false","Authorization":"synthetic-private-marker"]; raw["upload"] = ticket
        #expect(throws:(any Error).self) { try Self.decode(ReevaluationPhotoUpload.self,raw).validated(cycleID:Self.cycle,assetID:Self.asset,acceptanceID:Self.acceptance) }
        ticket["headers"] = ["Content-Type":"image/jpeg","x-upsert":"false"]; ticket["signed_url"] = "https://owned.supabase.co\(path.replacingOccurrences(of:Self.asset,with:Self.acceptance))?token=synthetic"; raw["upload"] = ticket
        #expect(throws:(any Error).self) { try Self.decode(ReevaluationPhotoUpload.self,raw).validated(cycleID:Self.cycle,assetID:Self.asset,acceptanceID:Self.acceptance) }
    }
    @Test(arguments:[("processed",2.99),("processed",60.01),("processing",22.5),("failed",22.5)])
    func snapshotRejectsAnUnusableDisplayReading(status:String,percent:Double) throws {
        var raw = MobileReevaluationPhotoRepositoryTests.snapshot()
        raw["acceptance_id"] = Self.acceptance
        raw["photos"] = ["front","side","back"].map { pose in
            ["pose":pose,"asset":pose == "front" ? ["id":Self.asset,"status":status,"estimated_body_fat_percent":percent]:NSNull()] as [String:Any]
        }
        #expect(throws:(any Error).self) { try Self.decode(ReevaluationPhotoSnapshot.self,raw).validated(cycleID:Self.cycle) }
    }
    @Test func optionalReadingsDecodeExactlyAndPreserveOlderSnapshots() throws {
        for reading:Any in [NSNull(),3,22.25,60] {
            var raw = MobileReevaluationPhotoRepositoryTests.snapshot()
            raw["acceptance_id"] = Self.acceptance
            raw["photos"] = ["front","side","back"].map { pose in
                ["pose":pose,"asset":pose == "front" ? ["id":Self.asset,"status":"processed","estimated_body_fat_percent":reading]:NSNull()] as [String:Any]
            }
            let value = try Self.decode(ReevaluationPhotoSnapshot.self,raw).validated(cycleID:Self.cycle)
            let asset = try #require(value.photos.first?.asset)
            #expect(asset.estimatedBodyFatPercent == (reading is NSNull ? nil:Decimal(string:String(describing:reading))))
            raw["photos"] = [["pose":"front","asset":["id":Self.asset,"status":"processed"]], ["pose":"side","asset":NSNull()], ["pose":"back","asset":NSNull()]]
            #expect(try Self.decode(ReevaluationPhotoSnapshot.self,raw).validated(cycleID:Self.cycle).photos.first?.asset?.estimatedBodyFatPercent == nil)
        }
        var raw = MobileReevaluationPhotoRepositoryTests.snapshot(); raw["acceptance_id"] = Self.acceptance
        raw["photos"] = [["pose":"front","asset":["id":Self.asset,"status":"processed","estimated_body_fat_percent":"22%"]], ["pose":"side","asset":NSNull()], ["pose":"back","asset":NSNull()]]
        #expect(throws:(any Error).self) { try Self.decode(ReevaluationPhotoSnapshot.self,raw).validated(cycleID:Self.cycle) }
    }
    @Test func processingNeverCarriesAnOfficialMeanAndDiscardDoesNotInventRevision() throws {
        let processed = try Self.decode(ReevaluationPhotoProcessing.self,["version":1,"cycle_id":Self.cycle,"asset_id":Self.asset,"status":"processed"]).validated(cycleID:Self.cycle,assetID:Self.asset)
        #expect(processed.status == .processed)
        #expect(throws:(any Error).self) { try Self.decode(ReevaluationPhotoProcessing.self,["version":1,"cycle_id":Self.cycle,"asset_id":Self.asset,"status":"failed"]).validated(cycleID:Self.cycle,assetID:Self.asset) }
        let discarded = try Self.decode(ReevaluationPhotoDiscard.self,["version":1,"cycle_id":Self.cycle,"acceptance_id":Self.acceptance,"status":"discard_requested","deletion":"waiting"]).validated(cycleID:Self.cycle,acceptanceID:Self.acceptance)
        #expect(discarded.deletion == .waiting)
    }
}
