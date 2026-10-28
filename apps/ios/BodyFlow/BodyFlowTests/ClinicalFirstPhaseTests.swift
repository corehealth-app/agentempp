import Foundation
import Testing
@testable import BodyFlow

@Suite("First phase — official contracts and retained intentions")
struct ClinicalFirstPhaseTests {
    static let choicesJSON = #"{"version":1,"availability":"available","date":"2026-10-26","effective_date":"2026-10-26","professional_assessment_recommended":false,"missing":[],"options":[{"phase":"recomposicao","status":"available","reasons":[]},{"phase":"manutencao","status":"available","reasons":[]}]}"#
    static let previewJSON = #"{"version":1,"preview_id":"b3b01000-0000-4000-8000-000000003970","phase":"recomposicao","effective_date":"2026-10-26","expires_at":"2026-10-26T12:15:00.000000Z","targets":{"calories_kcal":1413,"protein_g":121.5}}"#
    static let confirmationJSON = #"{"version":1,"confirmation_id":"b3b01000-0000-4000-8000-000000003970","phase":"recomposicao","effective_date":"2026-10-26","confirmed_at":"2026-10-26T12:01:00.000000Z"}"#
    static func preview() throws -> ClinicalFirstPhasePreview { try JSONDecoder().decode(ClinicalFirstPhasePreview.self, from: Data(previewJSON.utf8)).validated() }
    @Test func officialValuesAreRetained() throws {
        let value = try Self.preview()
        #expect(value.phase == .bodyRecomposition)
        #expect(value.targets.caloriesKcal == 1413)
        #expect(value.targets.proteinG == Decimal(string: "121.5"))
        #expect(value.effectiveDate == "2026-10-26")
    }
    @Test(arguments: ["2026-02-30", "2026-2-01", "0000-01-01"])
    func impossibleEffectiveDatesFail(_ date: String) throws {
        let input = Self.previewJSON.replacingOccurrences(of: "2026-10-26", with: date)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ClinicalFirstPhasePreview.self, from: Data(input.utf8)).validated() }
    }
    @Test func changedVersionAndOpaqueIdentifierFail() throws {
        for input in [Self.previewJSON.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"), Self.previewJSON.replacingOccurrences(of: "b3b01000-0000-4000-8000-000000003970", with: "another/patient")] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(ClinicalFirstPhasePreview.self, from: Data(input.utf8)).validated() }
        }
    }
    @MainActor @Test func uncertainConfirmationRetriesTheSameIntentionAndNeverRecalculates() async throws {
        let source = FirstPhaseTestProvider(), model = ClinicalFirstPhaseModel(userID: "auth-A", provider: source, keyProvider: RandomIdempotencyKeyProvider())
        await model.load(); await model.prepare(.bodyRecomposition)
        #expect(model.preview?.targets.caloriesKcal == 1413)
        await source.failNextConfirmation()
        await model.confirm()
        #expect(model.error == .offline)
        #expect(model.hasPendingConfirmation)
        await model.prepare(.maintenance)
        #expect(await source.prepareCalls.count == 1)
        await model.confirm()
        let keys = await source.confirmKeys
        #expect(keys.count == 2 && keys[0] == keys[1])
        #expect(model.confirmation?.phase == .bodyRecomposition)
        #expect(await source.prepareCalls.count == 1)
    }
    @MainActor @Test func endedOwnerCannotPublishOrSendAnotherMutation() async {
        let source = FirstPhaseTestProvider(), model = ClinicalFirstPhaseModel(userID: "auth-A", provider: source, keyProvider: RandomIdempotencyKeyProvider())
        await source.holdNextPreview()
        await model.load()
        let pending = Task { await model.prepare(.bodyRecomposition) }
        while await source.prepareCalls.isEmpty { await Task.yield() }
        model.invalidate(); await source.releasePreview(); await pending.value
        await model.prepare(.maintenance); await model.confirm(); await model.load()
        #expect(model.preview == nil && model.confirmation == nil)
        #expect(await source.prepareCalls.count == 1)
        #expect(await source.confirmKeys.isEmpty)
        #expect(await source.scopedOwners == ["auth-A"])
    }
}

private actor FirstPhaseTestProvider: ClinicalFirstPhaseProviding {
    var scopedOwners: [String] = []
    var prepareCalls: [BodyFlowObjective] = []
    var confirmKeys: [IdempotencyKey] = []
    private var failConfirm = false
    private var hold = false
    private var waiter: CheckedContinuation<Void, Never>?
    func scoped(for userID: String) async throws -> any ClinicalFirstPhaseProviding { scopedOwners.append(userID); return self }
    func choices() async throws -> ClinicalFirstPhaseChoices { try JSONDecoder().decode(ClinicalFirstPhaseChoices.self, from: Data(ClinicalFirstPhaseTests.choicesJSON.utf8)).validated() }
    func prepare(phase: BodyFlowObjective, key: IdempotencyKey) async throws -> ClinicalFirstPhasePreview {
        prepareCalls.append(phase)
        if hold { await withCheckedContinuation { waiter = $0 } }
        return try ClinicalFirstPhaseTests.preview()
    }
    func confirm(preview: ClinicalFirstPhasePreview, key: IdempotencyKey) async throws -> ClinicalFirstPhaseConfirmation {
        confirmKeys.append(key)
        if failConfirm { failConfirm = false; throw ClinicalFirstPhaseFailure.offline }
        return try JSONDecoder().decode(ClinicalFirstPhaseConfirmation.self, from: Data(ClinicalFirstPhaseTests.confirmationJSON.utf8)).validated()
    }
    func publish(_ operation: @MainActor @Sendable () throws -> Void) async throws { try await operation() }
    func failNextConfirmation() { failConfirm = true }
    func holdNextPreview() { hold = true }
    func releasePreview() { hold = false; waiter?.resume(); waiter = nil }
}
