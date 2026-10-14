import Foundation
import Testing

@testable import BodyFlow

@Suite("Progress Body Fat Origin")
struct ProgressBodyFatOriginTests {
    @Test("known photo origin is additive and preserves every official field")
    func decodesConfirmedOriginAndPreservesOfficialFields() throws {
        let response = try ProgressOriginFixture.response(originField: #""current_bf_origin":"signup_photos","#)
        let snapshot = try #require(response.data)
        #expect(snapshot.currentBodyFatOrigin == "signup_photos")
        #expect(snapshot.currentBodyFatPercent == 24)
        #expect(snapshot.xpTotal == 1_240)
        #expect(snapshot.level == 2)
        #expect(snapshot.currentStreak == 3)
        #expect(snapshot.longestStreak == 7)
        #expect(snapshot.blocksCompleted == 4)
        #expect(snapshot.deficitBlock == 3_120)
        #expect(snapshot.currentWeight == 80)
        #expect(snapshot.badgesEarned == ["badge-z"])
        #expect(snapshot.lastActiveDate == "2026-10-13")
        #expect(snapshot.nextReevaluation == "2026-10-28")
        #expect(snapshot.currentProtocol == "manutencao")
        #expect(snapshot.block7700Enabled == false)
        #expect(response.meta.requestID == "synthetic-progress-origin-unit")
        let encoded = try JSONEncoder().encode(snapshot)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["current_bf_origin"] as? String == "signup_photos")
        #expect(try JSONDecoder().decode(ProgressSnapshot.self, from: encoded) == snapshot)
    }

    @Test("absent null and future origins remain optional raw strings")
    func decodesCompatibleOriginsWithoutInference() throws {
        let absent = try #require(ProgressOriginFixture.response(originField: "").data)
        let manual = try #require(ProgressOriginFixture.response(originField: #""current_bf_origin":null,"#).data)
        let future = try #require(ProgressOriginFixture.response(originField: #""current_bf_origin":"future_origin","#).data)
        #expect(absent.currentBodyFatOrigin == nil)
        #expect(manual.currentBodyFatOrigin == nil)
        #expect(future.currentBodyFatOrigin == "future_origin")
        #expect(absent.currentBodyFatPercent == 24)
        #expect(manual.currentBodyFatPercent == 24)
        #expect(future.currentBodyFatPercent == 24)
        // Existing memberwise callers retain the same default, too.
        #expect(BodyFlowTestFixtures.progressSnapshot.currentBodyFatOrigin == nil)
    }

    @Test("a photo origin cannot invent a missing body fat measurement")
    func knownOriginWithNilBodyFatRemainsUnavailable() throws {
        let snapshot = try #require(ProgressOriginFixture.response(
            originField: #""current_bf_origin":"signup_photos","#, bodyFat: "null").data)
        #expect(snapshot.currentBodyFatOrigin == "signup_photos")
        #expect(snapshot.currentBodyFatPercent == nil)
        let pt = ProgressPresentation(snapshot: snapshot, language: .portugueseBrazil)
        let en = ProgressPresentation(snapshot: snapshot, language: .englishUnitedStates)
        #expect(pt.bodyFatText == "Não disponível")
        #expect(en.bodyFatText == "Not available")
        #expect(pt.bodyFatOriginText == nil)
        #expect(en.bodyFatOriginText == nil)
        #expect(pt.bodyFatText != "0%")
        #expect(en.bodyFatText != "0%")
    }

    @Test("photo origin is localized separately from the official numeric value")
    func photoOriginCopyIsLocalizedAndNumberRemainsIndependent() throws {
        let snapshot = try #require(ProgressOriginFixture.response(
            originField: #""current_bf_origin":"signup_photos","#).data)
        let pt = ProgressPresentation(snapshot: snapshot, language: .portugueseBrazil)
        let en = ProgressPresentation(snapshot: snapshot, language: .englishUnitedStates)
        #expect(pt.bodyFatText == "24%")
        #expect(en.bodyFatText == "24%")
        #expect(pt.bodyFatOriginText == "Estimativa por fotos")
        #expect(en.bodyFatOriginText == "Photo estimate")
        #expect(try AppLocalization.string("progress.metric.body-fat.photo-origin", for: .portugueseBrazil) == "Estimativa por fotos")
        #expect(try AppLocalization.string("progress.metric.body-fat.photo-origin", for: .englishUnitedStates) == "Photo estimate")
    }

    @Test("the same manual legacy or unknown 24 percent never proves photo origin")
    func sameOfficialValueWithoutKnownOriginHasNoPhotoLabel() throws {
        for field in ["", #""current_bf_origin":null,"#, #""current_bf_origin":"future_origin","#] {
            let snapshot = try #require(ProgressOriginFixture.response(originField: field).data)
            let pt = ProgressPresentation(snapshot: snapshot, language: .portugueseBrazil)
            let en = ProgressPresentation(snapshot: snapshot, language: .englishUnitedStates)
            #expect(pt.bodyFatText == "24%")
            #expect(en.bodyFatText == "24%")
            #expect(pt.bodyFatOriginText == nil)
            #expect(en.bodyFatOriginText == nil)
        }
    }

    @Test("known origin preserves existing fractional formatting in both languages")
    func fractionalBodyFatFormattingRemainsNumeric() throws {
        let snapshot = try #require(ProgressOriginFixture.response(
            originField: #""current_bf_origin":"signup_photos","#, bodyFat: "18.25").data)
        let pt = ProgressPresentation(snapshot: snapshot, language: .portugueseBrazil)
        let en = ProgressPresentation(snapshot: snapshot, language: .englishUnitedStates)
        #expect(pt.bodyFatText == "18,25%")
        #expect(en.bodyFatText == "18.25%")
        #expect(pt.bodyFatOriginText == "Estimativa por fotos")
        #expect(en.bodyFatOriginText == "Photo estimate")
    }

    @Test("official photo 24 survives offline then equal manual 24 clears origin")
    @MainActor
    func originFollowsTheActualSnapshotAcrossOfflineAndManualReplacement() async throws {
        let photo = try ProgressOriginFixture.response(originField: #""current_bf_origin":"signup_photos","#)
        let manual = try ProgressOriginFixture.response(originField: #""current_bf_origin":null,"#)
        let photoSnapshot = try #require(photo.data)
        let manualSnapshot = try #require(manual.data)
        let provider = ProgressOriginQueueProvider([.success(photo), .failure(.offline), .success(manual)])
        let model = ProgressViewModel(provider: provider)

        await model.load()
        #expect(model.state == .loaded(photoSnapshot))
        let loaded = try #require(model.state.presentation.value)
        #expect(ProgressPresentation(snapshot: loaded).bodyFatText == "24%")
        #expect(ProgressPresentation(snapshot: loaded).bodyFatOriginText == "Estimativa por fotos")

        await model.retry()
        #expect(model.state == .offline(previousValue: photoSnapshot))
        let stale = try #require(model.state.presentation.value)
        #expect(stale.currentBodyFatOrigin == "signup_photos")
        #expect(ProgressPresentation(snapshot: stale).bodyFatText == "24%")
        #expect(ProgressPresentation(snapshot: stale).bodyFatOriginText == "Estimativa por fotos")

        await model.retry()
        #expect(model.state == .loaded(manualSnapshot))
        let replaced = try #require(model.state.presentation.value)
        #expect(replaced.currentBodyFatPercent == 24)
        #expect(replaced.currentBodyFatOrigin == nil)
        #expect(ProgressPresentation(snapshot: replaced).bodyFatText == "24%")
        #expect(ProgressPresentation(snapshot: replaced).bodyFatOriginText == nil)
        #expect(await provider.calls == 3)
    }
}

private enum ProgressOriginFixture {
    static func response(originField: String, bodyFat: String = "24") throws -> ProgressResponse {
        // Literal API boundary fixture, independently specified from the
        // DEBUG UI provider. The number never derives the origin.
        let json = """
        {
          "data": {
            "xp_total": 1240, "level": 2,
            "current_streak": 3, "longest_streak": 7,
            "blocks_completed": 4, "deficit_block": 3120,
            "current_weight": 80, "current_bf_percent": \(bodyFat),
            \(originField)
            "badges_earned": ["badge-z"],
            "last_active_date": "2026-10-13", "next_reevaluation": "2026-10-28",
            "updated_at": "2026-10-14T12:00:00.000Z",
            "current_protocol": "manutencao", "block_7700_enabled": false
          },
          "meta": {"api_version":"v1", "request_id":"synthetic-progress-origin-unit"}
        }
        """
        return try JSONDecoder().decode(ProgressResponse.self, from: Data(json.utf8))
    }
}

private actor ProgressOriginQueueProvider: ProgressProviding {
    enum Outcome: Sendable { case success(ProgressResponse), failure(BodyFlowCapabilityError) }
    private var outcomes: [Outcome]
    private(set) var calls = 0
    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }
    func progress() async throws -> ProgressResponse {
        calls += 1
        guard !outcomes.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
        switch outcomes.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }
}
