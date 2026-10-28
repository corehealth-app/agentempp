import Foundation
import Testing
@testable import BodyFlow

@Suite("Clinical FULL — actual returned scope and retained intentions")
struct ClinicalFullWorkflowTests {
    static let cycle = ClinicalFullFormTests.cycle
    static let previewID = "b3b01000-0000-4000-8000-000000004810"
    static func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    static func entry(_ kind: ClinicalFullKind) throws -> ClinicalFullEntry {
        try decode(ClinicalFullEntry.self, ["version":1,"availability":"available","unavailable_reason":NSNull(),"clock":["base_date":"2026-10-20","due_date":"2026-11-03","timezone":"America/Sao_Paulo"],"cycle":["id":cycle,"kind":kind.rawValue,"status":"open","revision":"9007199254740993"]]).validated()
    }
    static func form(_ scope: ClinicalFullScope) throws -> ClinicalFullQuestionnaire {
        var object = try #require(JSONSerialization.jsonObject(with: Data(ClinicalFullFormTests.json.utf8)) as? [String: Any])
        object["kind"] = scope.kind.rawValue; object["activity_purpose"] = "normal"
        object["cycle_id"] = scope.cycleID.map { $0 as Any } ?? NSNull()
        object["photo_requirement"] = ["required":scope.kind.requiresNewPhotos,"new_only":true,"poses":["front","side","back"]]
        if !scope.kind.requiresNewPhotos { object["body_fat"] = ["status":"not_required"] }
        var questions = try #require(object["questions"] as? [[String: Any]])
        questions.append(["key":"healthCheck","label":"Saúde","input_kind":"health_selection","unit":NSNull(),"opt_out_label":"Pular","options":[["value":"reduced_intake","label":"Comendo menos"],["value":"none","label":"Nenhuma"]],"min":NSNull(),"max":NSNull(),"preselected":NSNull(),"initially_confirmed":NSNull(),"hint":NSNull()])
        object["questions"] = questions
        return try decode(ClinicalFullQuestionnaire.self, object).validated()
    }
    static func assessment(health: Bool = false) throws -> ClinicalFullAssessment {
        try decode(ClinicalFullAssessment.self, ["version":1,"status":health ? "health_declaration_required" : "available","actions":health ? [] : [["choice":["kind":"keep"],"principal":"keep","phase":"recomposicao","targets":["calories_kcal":1599,"protein_g":126],"professional_assessment_recommended":false,"pause_weight_loss_guidance":false]],"preference":NSNull()]).validated()
    }
    static func preview(_ scope: ClinicalFullScope, choice: ClinicalFullChoice) throws -> ClinicalFullPreview {
        let choiceObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(choice))
        return try decode(ClinicalFullPreview.self, ["version":1,"status":"ready","preview_id":previewID,"kind":scope.kind.rawValue,"cycle_id":scope.cycleID ?? NSNull() as Any,"expires_at":"2026-11-03T12:15:00.000000Z","choice":choiceObject,"phase":"recomposicao","targets":["calories_kcal":1599,"protein_g":126],"professional_assessment_recommended":false,"pause_weight_loss_guidance":false]).validated()
    }
    static func confirmation(_ preview: ClinicalFullPreview) throws -> ClinicalFullConfirmation {
        try decode(ClinicalFullConfirmation.self, ["version":1,"review_id":preview.previewID,"kind":preview.kind.rawValue,"cycle_id":preview.cycleID ?? NSNull() as Any,"completed_at":"2026-10-26T12:01:00.000000Z","next_due_date":"2026-11-09"]).validated()
    }
    @MainActor fileprivate static func ready(_ source: FullWorkflowTestProvider) async throws -> ClinicalFullModel {
        let model = ClinicalFullModel(userID: "auth-A", provider: source, keyProvider: RandomIdempotencyKeyProvider())
        await model.loadEntry(); await model.start()
        let form = try #require(model.questionnaire)
        model.edit { $0.acceptBodyFat(from: form) }
        await model.assess()
        return model
    }
    @MainActor @Test func consumesTheReturnedEarlyScopeWithoutInventingRegularFromTheButton() async throws {
        let source = FullWorkflowTestProvider(kind: .early), model = try await Self.ready(source)
        #expect(model.scope?.kind == .early)
        #expect(model.questionnaire?.bodyFat.status == .notRequired)
        #expect(await source.startReasons == [nil])
        #expect(await source.describedScopes.first?.kind == .early)
    }
    @MainActor @Test func consumesTheReturnedTransitionAndPreservesItsRequiredPhotoAcceptance() async throws {
        let source = FullWorkflowTestProvider(kind: .transition), model = try await Self.ready(source)
        #expect(model.scope?.kind == .transition)
        #expect(model.questionnaire?.photoRequirement.required == true)
        #expect(model.draft?.acceptedBodyFat != nil)
        #expect(await source.startReasons == [nil])
        #expect(await source.describedScopes.first?.kind == .transition)
        #expect(model.entry?.canOfferEarlyFull == false)
    }
    @Test func anAvailableTransitionDoesNotOfferAnotherEarlyReviewOrInventAnElapsedFortnight() throws {
        let value = try Self.decode(ClinicalFullEntry.self, ["version":1,"availability":"available","unavailable_reason":NSNull(),"clock":["base_date":"2026-10-27","due_date":"2026-10-27","timezone":"America/Sao_Paulo"],"cycle":NSNull()]).validated()
        #expect(value.clock?.baseDate == value.clock?.dueDate && !value.canOfferEarlyFull)
        let waiting = try Self.decode(ClinicalFullEntry.self, ["version":1,"availability":"unavailable","unavailable_reason":"not_due","clock":["base_date":"2026-10-27","due_date":"2026-11-10","timezone":"America/Sao_Paulo"],"cycle":NSNull()]).validated()
        #expect(waiting.canOfferEarlyFull)
    }
    @MainActor @Test(arguments: [false, true]) func uncertainConfirmationFreezesTheWholeOriginalIntentionAndRetriesItsKey(cancel: Bool) async throws {
        let source = FullWorkflowTestProvider(), model = try await Self.ready(source)
        let choice = try #require(model.assessment?.actions.first?.choice)
        await model.prepare(choice)
        await source.failNextConfirm(cancel: cancel)
        await model.confirm()
        #expect((cancel || model.error == .offline) && model.hasUncertainMutation)
        let original = model.draft
        model.edit { $0.answers.weightKg = 60 }
        await model.prepare(choice)
        #expect(model.draft == original)
        #expect(await source.preparedInputs.count == 1)
        await source.rejectNextConfirmInput(); await model.confirm()
        #expect(model.error == .invalidInput && model.hasUncertainMutation)
        await model.confirm()
        let keys = await source.confirmKeys
        #expect(keys.count == 3 && keys[0] == keys[1] && keys[1] == keys[2])
        let intentions = await source.confirmedInputs
        #expect(intentions.count == 3 && intentions.allSatisfy { $0 == intentions.first })
        #expect(model.confirmation?.nextDueDate == "2026-11-09")
        #expect(await source.scopedOwners == ["auth-A"])
        model.closeCompleted()
        #expect(model.entry == nil && model.scope == nil && model.draft == nil && model.confirmation == nil)
        await model.loadEntry()
        #expect(model.entry != nil)
    }
    @MainActor @Test func uncertainPreparationRetainsInputChoiceAndKeyWithoutAllowingEdits() async throws {
        let source = FullWorkflowTestProvider(), model = try await Self.ready(source)
        let choice = try #require(model.assessment?.actions.first?.choice)
        await source.failNextPrepare(); await model.prepare(choice)
        #expect(model.hasUncertainMutation)
        let original = model.draft
        model.edit { $0.answers.weightKg = 60 }
        await model.prepare(choice)
        let attempts = await source.preparedInputs
        #expect(model.draft == original)
        #expect(attempts.count == 2 && attempts[0].draft == attempts[1].draft && attempts[0].key == attempts[1].key)
    }
    @MainActor @Test func selectingARiskRemainsLocalUntilTheExplicitDeclarationAction() async throws {
        let source = FullWorkflowTestProvider(), model = try await Self.ready(source)
        model.edit { $0.setHealthRisk(.reducedIntake, selected: true) }
        #expect(await source.declared.isEmpty)
        await source.requireHealthAdmission(); await model.assess()
        #expect(model.assessment?.status == .healthDeclarationRequired)
        await model.declareHealth()
        #expect(await source.declared == [[.reducedIntake]])
        #expect(model.healthReceipt != nil)
        #expect(model.draft?.answers.healthCheck == .risks([.reducedIntake]))
    }
    @MainActor @Test func anEndedOwnerCannotPublishALatePreviewOrSendAnotherMutation() async throws {
        let source = FullWorkflowTestProvider(), model = try await Self.ready(source)
        let choice = try #require(model.assessment?.actions.first?.choice)
        await source.holdNextPrepare()
        let pending = Task { await model.prepare(choice) }
        while await source.preparedInputs.isEmpty { await Task.yield() }
        model.invalidate(); await source.releasePrepare(); await pending.value
        await model.prepare(choice); await model.confirm(); await model.loadEntry()
        #expect(model.preview == nil && model.confirmation == nil)
        #expect(await source.preparedInputs.count == 1)
        #expect(await source.confirmKeys.isEmpty)
    }
    @MainActor @Test func invalidVisibleInputCannotBecomeAnOptOutDuringAssessment() async throws {
        let source = FullWorkflowTestProvider(), model = try await Self.ready(source)
        let question = try #require(model.questionnaire?.questions.first { $0.key == .weightKg })
        model.setText("70,",question:question,language:.portugueseBrazil)
        await model.assess()
        #expect(model.inputs.hasInvalidValues && model.inputs.text[.weightKg] == "70,")
        #expect(await source.assessed == 1)
        model.setText("",question:question,language:.portugueseBrazil)
        await model.assess()
        #expect(!model.inputs.hasInvalidValues && model.draft?.answers.weightKg == nil)
        #expect(await source.assessed == 2)
    }
}
private actor FullWorkflowTestProvider: ClinicalFullProviding {
    struct Prepared: Sendable { let scope: ClinicalFullScope; let draft: ClinicalFullDraft; let choice: ClinicalFullChoice; let key: IdempotencyKey }
    struct ConfirmationInput: Equatable, Sendable { let scope:ClinicalFullScope; let draft:ClinicalFullDraft; let choice:ClinicalFullChoice; let preview:ClinicalFullPreview; let key:IdempotencyKey }
    let kind: ClinicalFullKind
    var scopedOwners: [String] = []; var startReasons: [ClinicalFullStartReason?] = []; var describedScopes: [ClinicalFullScope] = []
    var preparedInputs: [Prepared] = []; var confirmKeys: [IdempotencyKey] = []; var declared: [[ClinicalFullHealthRisk]] = []
    var confirmedInputs:[ConfirmationInput] = []
    var assessed = 0
    private var failPrepare = false, failConfirm = false, rejectConfirm = false, healthRequired = false, hold = false
    private var cancelConfirm = false
    private var waiter: CheckedContinuation<Void,Never>?
    init(kind: ClinicalFullKind = .regular) { self.kind = kind }
    func scoped(for userID: String) async throws -> any ClinicalFullProviding { scopedOwners.append(userID); return self }
    func entry() async throws -> ClinicalFullEntry { try ClinicalFullWorkflowTests.entry(kind) }
    func start(reason: ClinicalFullStartReason?, key: IdempotencyKey) async throws -> ClinicalFullEntry { startReasons.append(reason); return try ClinicalFullWorkflowTests.entry(kind) }
    func describe(scope: ClinicalFullScope, purpose: ClinicalFullPurpose) async throws -> ClinicalFullQuestionnaire { describedScopes.append(scope); return try ClinicalFullWorkflowTests.form(scope) }
    func assess(scope: ClinicalFullScope, draft: ClinicalFullDraft) async throws -> ClinicalFullAssessment { assessed += 1; return try ClinicalFullWorkflowTests.assessment(health: healthRequired) }
    func prepare(scope: ClinicalFullScope, draft: ClinicalFullDraft, choice: ClinicalFullChoice, key: IdempotencyKey) async throws -> ClinicalFullPreview {
        preparedInputs.append(Prepared(scope:scope,draft:draft,choice:choice,key:key))
        if hold { await withCheckedContinuation { waiter = $0 } }
        if failPrepare { failPrepare = false; throw ClinicalFullFailure.offline }
        return try ClinicalFullWorkflowTests.preview(scope,choice:choice)
    }
    func confirm(scope: ClinicalFullScope, draft: ClinicalFullDraft, choice: ClinicalFullChoice, preview: ClinicalFullPreview, key: IdempotencyKey) async throws -> ClinicalFullConfirmation {
        confirmKeys.append(key)
        confirmedInputs.append(.init(scope:scope,draft:draft,choice:choice,preview:preview,key:key))
        if cancelConfirm { cancelConfirm = false; throw CancellationError() }
        if failConfirm { failConfirm = false; throw ClinicalFullFailure.offline }
        if rejectConfirm { rejectConfirm = false; throw ClinicalFullFailure.invalidInput }
        return try ClinicalFullWorkflowTests.confirmation(preview)
    }
    func declareHealth(items: [ClinicalFullHealthRisk], key: IdempotencyKey) async throws -> ClinicalFullHealthReceipt {
        declared.append(items); healthRequired = false
        return try ClinicalFullWorkflowTests.decode(ClinicalFullHealthReceipt.self,["version":1,"receipt_id":ClinicalFullWorkflowTests.previewID,"declared_at":"2026-10-26T12:01:00.000000Z"]).validated()
    }
    func publish(_ operation: @MainActor @Sendable () throws -> Void) async throws { try await operation() }
    func failNextConfirm(cancel: Bool = false) { if cancel { cancelConfirm = true } else { failConfirm = true } }; func failNextPrepare() { failPrepare = true }
    func rejectNextConfirmInput() { rejectConfirm = true }
    func requireHealthAdmission() { healthRequired = true }; func holdNextPrepare() { hold = true }
    func releasePrepare() { hold = false; waiter?.resume(); waiter = nil }
}
