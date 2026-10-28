import Foundation
import SwiftUI
import Testing
@testable import BodyFlow

@MainActor @Suite("Recurring capture — explicit consent and retained intentions")
struct ReevaluationPhotoModelTests {
    typealias Fixture = ReevaluationPhotoContractTests
    @Test func loadNeverAcceptsAndOnlyExplicitConsentAllowsAProducer() async throws {
        let f = RecurringCaptureFake(), model = f.model()
        await model.load()
        #expect(f.acceptKeys.isEmpty && !model.consentChecked && !model.canCapture)
        #expect(await model.beginProducer(pose:.front,channel:.gallery) == nil)
        model.setConsentChecked(true); await model.acceptConsent()
        #expect(f.acceptKeys.count == 1 && model.canCapture)
        let producer = try #require(await model.beginProducer(pose:.front,channel:.gallery))
        model.cancelProducer(producer.id)
        await model.receive(producer,data:Data([1,2,3]))
        #expect(f.stages == 0 && f.allocateKeys.isEmpty)
    }
    @Test func aProcessingRetryKeepsTheSameAssetBytesAndRequestKey() async throws {
        let f = RecurringCaptureFake(); f.failProcessOnce = true
        let model = f.model(); await f.accept(on:model)
        let producer = try #require(await model.beginProducer(pose:.front,channel:.gallery))
        await model.receive(producer,data:Data([1,2,3]))
        #expect(model.hasBlockingWork && f.processKeys.count == 1)
        await model.retry()
        #expect(f.stages == 1 && f.allocateKeys.count == 1 && f.uploads == 1 && f.completions == 1)
        #expect(f.processKeys.count == 2 && Set(f.processKeys).count == 1 && f.analyses == 1)
        #expect(f.localDeletes == 1 && !model.hasBlockingWork)
        #expect(model.snapshot?.photos.first(where:{ $0.pose == .front })?.asset?.status == .processed)
        await model.receive(producer,data:Data([9]))
        #expect(f.stages == 1 && f.allocateKeys.count == 1)
    }
    @Test func uncertainAllocationIsReplayedWithoutNewPhotoOrChangedInput() async throws {
        let f = RecurringCaptureFake(); f.failAllocateOnce = true
        let model = f.model(); await f.accept(on:model)
        let producer = try #require(await model.beginProducer(pose:.front,channel:.gallery))
        await model.receive(producer,data:Data([1]))
        #expect(model.hasBlockingWork && !model.canCapture)
        await model.retry()
        #expect(f.allocateKeys.count == 2 && Set(f.allocateKeys).count == 1 && f.newPhotos == 1)
        #expect(f.allocationInputs.first == f.allocationInputs.last && f.stages == 1)
        #expect(!model.hasBlockingWork && f.localDeletes == 1)
    }
    @Test func uncertainPutIsReconciledByCompletionWithoutAnotherAllocationOrPut() async throws {
        let f = RecurringCaptureFake(); f.failUploadOnce = true
        let model = f.model(); await f.accept(on:model)
        let producer = try #require(await model.beginProducer(pose:.front,channel:.gallery))
        await model.receive(producer,data:Data([1]))
        #expect(f.uploads == 1 && f.completions == 1 && f.allocateKeys.count == 1)
        #expect(f.processKeys.count == 1 && !model.hasBlockingWork)
    }
    @Test func missingPutBytesCanRetryOnlyTheSameAssetAfterFreshUploadAuthority() async throws {
        let f = RecurringCaptureFake(); f.failUploadOnce = true; f.missingCompletions = 2
        let model = f.model(); await f.accept(on:model)
        let producer = try #require(await model.beginProducer(pose:.front,channel:.gallery))
        await model.receive(producer,data:Data([1]))
        #expect(model.hasBlockingWork && f.uploads == 1 && f.newPhotos == 1)
        await model.retry()
        #expect(!model.hasBlockingWork && f.uploads == 2 && f.newPhotos == 1 && f.allocateKeys.count == 1)
        #expect(f.completions == 3 && Set(f.completionKeys).count == 1 && Set(f.uploadKeys).count == 1)
        #expect(f.stages == 1 && f.analyses == 1 && f.localDeletes == 1)
    }
    @Test func skippedProcessingKeepsItsOriginalAttemptAndDoesNotAutomaticallyStartAnother() async throws {
        let f = RecurringCaptureFake(); f.skipProcessOnce = true
        let model = f.model(); await f.accept(on:model)
        let producer = try #require(await model.beginProducer(pose:.front,channel:.gallery))
        await model.receive(producer,data:Data([1]))
        #expect(model.error == .busy && model.hasBlockingWork && f.analyses == 0 && f.processKeys.count == 1)
        await model.retry()
        #expect(!model.hasBlockingWork && f.analyses == 1 && Set(f.processKeys).count == 1 && f.uploads == 1)
    }
    @Test func aChangedConsentCannotBeAcceptedAgainWithoutShowingAndCheckingIt() async throws {
        let f = RecurringCaptureFake(); f.changeConsentOnAccept = true
        let model = f.model(); await model.load(); model.setConsentChecked(true); await model.acceptConsent()
        #expect(model.consent == nil && !model.consentChecked && f.acceptKeys.count == 1)
        await model.retry()
        #expect(model.consent?.document?.version == "pt-2" && !model.consentChecked && !model.canCapture)
        await model.acceptConsent(); #expect(f.acceptKeys.count == 1)
        model.setConsentChecked(true); await model.acceptConsent()
        #expect(model.canCapture && f.acceptKeys.count == 2 && Set(f.acceptKeys).count == 2)
    }
    @Test func aVerifiedQuotaRefusalDoesNotTrapOrDiscardAlreadySelectedPhotos() async throws {
        let f = RecurringCaptureFake(), model = f.model(); await f.accept(on:model)
        f.status = .processed; await model.load(); f.quotaNextAllocation = true
        let producer = try #require(await model.beginProducer(pose:.front,channel:.gallery))
        await model.receive(producer,data:Data([1]))
        #expect(model.error == .quota && !model.hasBlockingWork && !model.canCapture)
        #expect(f.newPhotos == 0 && f.localDeletes == 1 && f.discardKeys.isEmpty)
        #expect(model.snapshot?.photos.first(where:{ $0.pose == .front })?.asset?.status == .processed)
        await model.retry(); #expect(model.canCapture && f.newPhotos == 0)
    }
    @Test func discardRetriesTheOriginalAcceptanceRevisionAndShowsWaitingHonestly() async throws {
        let f = RecurringCaptureFake(); f.failDiscardOnce = true
        let model = f.model(); await f.accept(on:model)
        await model.discard()
        #expect(model.hasBlockingWork)
        await model.retry()
        #expect(f.discardInputs.count == 2 && f.discardInputs.first == f.discardInputs.last)
        #expect(Set(f.discardKeys).count == 1)
        #expect(model.lastDiscard?.deletion == .waiting && !model.consentChecked)
        #expect(!model.hasBlockingWork && !model.canCapture)
    }
    @Test func modelInvalidationDuringStagingRemovesItsFileAndCannotAllocateOrPublishLate() async throws {
        let f = RecurringCaptureFake(); f.holdStage = true
        let model = f.model(); await f.accept(on:model)
        let producer = try #require(await model.beginProducer(pose:.front,channel:.gallery))
        let task = Task { await model.receive(producer,data:Data([1])) }
        await f.waitStage(); model.invalidate(); f.releaseStage(); await task.value
        #expect(f.localDeletes == 1 && f.allocateKeys.isEmpty)
        #expect(model.consent == nil && model.snapshot == nil && model.producer == nil && !model.canCapture)
    }
    @Test func aPermissionAnswerAfterLeavingTheProducerCannotOpenTheCamera() async throws {
        let f = RecurringCaptureFake(), gate = RecurringPermissionGate()
        f.camera = MealCameraAccess(origin:.device,isAvailable:{ true },permission:{ .notAsked },requestAccess:{ await gate.wait() })
        let model = f.model(); await f.accept(on:model)
        let task = Task { await model.beginProducer(pose:.front,channel:.camera) }
        await gate.started()
        model.cancelProducer(try #require(model.producer?.id)); await gate.release()
        #expect(await task.value == nil && model.producer == nil && f.stages == 0)
    }
    @Test func aLateLibraryReplyCannotConsumeOrCancelTheNextProducer() async throws {
        let f = RecurringCaptureFake(), gate = RecurringPermissionGate()
        let model = f.model(); await f.accept(on:model)
        let old = try #require(await model.beginProducer(pose:.front,channel:.gallery))
        let task = Task { await model.receivePicked(old) { _ = await gate.wait(); return Data([1]) } }
        await gate.started(); model.cancelProducer(old.id)
        let next = try #require(await model.beginProducer(pose:.side,channel:.gallery))
        await gate.release(); await task.value
        #expect(model.producer == next && f.stages == 0 && f.allocateKeys.isEmpty)
    }
    @Test func hostedConsentIsLiteralAndRenderingDoesNotAcceptOrAllocate() async throws {
        let f = RecurringCaptureFake(), model = f.model(); await model.load()
        let before = (f.consentReads,f.snapshotReads)
        let nodes = SignUpRenderingProbe.nodes(ReevaluationPhotosView(model:model).content,width:393,height:2500)
        #expect(nodes.contains { $0.identifier == "reeval.photos.consent.body" && $0.label == Fixture.body })
        #expect(nodes.first { $0.identifier == "reeval.photos.consent.accept" }?.isEnabled == false)
        #expect(f.acceptKeys.isEmpty && f.allocateKeys.isEmpty && f.consentReads == before.0 && f.snapshotReads == before.1)
        model.setConsentChecked(true)
        let checked = SignUpRenderingProbe.nodes(ReevaluationPhotosView(model:model).content,width:393,height:2500)
        #expect(checked.first { $0.identifier == "reeval.photos.consent.accept" }?.isEnabled == true)
    }
    @Test func hostedCaptureShowsThreePosesAndNoNumericBodyFatOrPerItemConfirmation() async throws {
        let f = RecurringCaptureFake(), model = f.model(); await f.accept(on:model)
        let before = (f.consentReads,f.snapshotReads)
        let nodes = SignUpRenderingProbe.nodes(ReevaluationPhotosView(model:model).content,width:393,height:3000)
        let choices = nodes.filter { $0.identifier.hasPrefix("reeval.photos.library.") && $0.isButton }
        #expect(choices.count == 3 && choices.allSatisfy(\.isEnabled))
        #expect(nodes.filter { $0.identifier.hasPrefix("reeval.photos.status.") }.count == 3)
        #expect(!nodes.contains { $0.label.contains("22%") || $0.label.contains("Confirme este item") })
        #expect(f.consentReads == before.0 && f.snapshotReads == before.1 && f.allocateKeys.isEmpty)
    }
    @Test(arguments:["pt-BR","en-US"]) func hostedConsentActionsMatchTheApprovedAuthorization(locale:String) async throws {
        let f = RecurringCaptureFake(); f.locale = locale
        let model = f.model(); await model.load()
        let nodes = SignUpRenderingProbe.nodes(ReevaluationPhotosView(model:model).content,width:393,height:3000)
        let expected = locale == "pt-BR"
            ? "Autorizo o envio e o processamento destas fotos para estimar meu percentual de gordura nesta reavaliação, conforme explicado acima."
            : "I authorize these photos to be uploaded and processed to estimate my body fat percentage for this reassessment, as explained above."
        #expect(nodes.contains { $0.identifier == "reeval.photos.consent.check" && $0.label.contains(expected) })
        #expect(nodes.contains { $0.identifier == "reeval.photos.consent.accept" && $0.label == (locale == "pt-BR" ? "Autorizar e continuar":"Authorize and continue") && !$0.isEnabled })
        #expect(nodes.contains { $0.identifier == "reeval.photos.back" && $0.label == (locale == "pt-BR" ? "Agora não":"Not now") && $0.isEnabled })
        #expect(f.acceptKeys.isEmpty && f.allocateKeys.isEmpty)
    }
    @Test(arguments:[ClinicalFullKind.regular,.transition]) func fullFormRetainsThePhotoChildAndBlocksStaleClinicalAcceptanceWhileRetrying(kind:ClinicalFullKind) async throws {
        let f = RecurringCaptureFake(), source = RecurringFullTestProvider(kind:kind)
        let full = ClinicalFullModel(userID:"auth-A",provider:source,keyProvider:RandomIdempotencyKeyProvider(),photoCapability:f.capability())
        await full.start()
        let photos = try #require(full.photos)
        await f.accept(on:photos)
        let form = try #require(full.questionnaire)
        full.edit { $0.acceptBodyFat(from:form) }
        #expect(full.draft?.acceptedBodyFat != nil)
        f.failProcessOnce = true
        let producer = try #require(await photos.beginProducer(pose:.front,channel:.gallery))
        await photos.receive(producer,data:Data([1]))
        #expect(full.photos === photos && full.draft?.acceptedBodyFat == nil && !full.canEdit && full.canOpenPhotos)
        let assessments = source.assessments; await full.assess(); #expect(source.assessments == assessments)
        await photos.retry()
        #expect(full.photos === photos && full.canEdit && full.draft?.acceptedBodyFat == nil)
        #expect(source.descriptions >= 3)
        full.invalidate(); #expect(full.photos == nil && photos.consent == nil)
    }
    @Test(arguments:["pt-BR","en-US"]) func hostedProcessedReadingsUseTheConsentLanguageWithoutAddingConfirmation(locale:String) async throws {
        let f = RecurringCaptureFake(); f.locale = locale; f.readings = [22.25,24.5,26.75]
        let model = f.model(); await f.accept(on:model)
        #expect(model.consent?.availability == .available)
        #expect(model.snapshot?.photos.compactMap { $0.asset?.estimatedBodyFatPercent } == [Decimal(string:"22.25")!,Decimal(string:"24.5")!,Decimal(string:"26.75")!])
        let before = (f.consentReads,f.snapshotReads)
        let nodes = SignUpRenderingProbe.nodes(ReevaluationPhotosView(model:model).content,width:393,height:3400)
        let labels = ["front","side","back"].compactMap { pose in nodes.first { $0.identifier == "reeval.photos.reading."+pose }?.label }
        #expect(labels == (locale == "pt-BR"
            ? ["Estimativa desta foto: 22,25%","Estimativa desta foto: 24,5%","Estimativa desta foto: 26,75%"]
            : ["Estimate from this photo: 22.25%","Estimate from this photo: 24.5%","Estimate from this photo: 26.75%"]))
        #expect(!nodes.contains { $0.label.contains("Confirme este item") || $0.label.contains("Confirm this item") })
        #expect(f.consentReads == before.0 && f.snapshotReads == before.1 && f.allocateKeys.isEmpty && f.processKeys.isEmpty)
    }
    @Test(arguments:[false,true]) func anOldFullSessionCannotBindPhotosToANewSessionOfA(duringBinding:Bool) async throws {
        let f = RecurringCaptureFake(), source = RecurringFullTestProvider()
        let full = ClinicalFullModel(userID:"auth-A",provider:source,keyProvider:RandomIdempotencyKeyProvider(),photoCapability:f.capability())
        await full.start(); let photos = try #require(full.photos)
        if duringBinding {
            f.holdScope = true
            let task = Task { await photos.load() }; await f.waitScope(); source.active = false; f.releaseScope(); await task.value
            #expect(f.scopes == 1)
        } else { source.active = false; await photos.load(); #expect(f.scopes == 0) }
        #expect(photos.consent == nil && f.consentReads == 0 && f.snapshotReads == 0)
    }
}
private actor RecurringPermissionGate {
    private var reply:CheckedContinuation<Bool,Never>?, start:CheckedContinuation<Void,Never>?
    private var didStart = false
    func wait() async -> Bool { didStart = true; start?.resume(); start = nil; return await withCheckedContinuation { reply = $0 } }
    func started() async { if !didStart { await withCheckedContinuation { start = $0 } } }
    func release() { reply?.resume(returning:true); reply = nil }
}

@MainActor private final class RecurringCaptureFake: ReevaluationPhotosProviding {
    typealias Fixture = ReevaluationPhotoContractTests
    var accepted = false, revision = "1", status:ReevaluationPhotoStatus?
    var acceptKeys:[String] = [], allocateKeys:[String] = [], processKeys:[String] = [], discardKeys:[String] = []
    var completionKeys:[String] = [], uploadKeys:[String] = [], missingCompletions = 0
    var allocationInputs:[ReevaluationPhotoAllocationInput] = [], discardInputs:[ReevaluationPhotoDiscardInput] = []
    var stages = 0, uploads = 0, completions = 0, newPhotos = 0, analyses = 0, localDeletes = 0
    var consentReads = 0, snapshotReads = 0, scopes = 0, holdScope = false
    var failProcessOnce = false, failAllocateOnce = false, failUploadOnce = false, failDiscardOnce = false
    var skipProcessOnce = false, changeConsentOnAccept = false, documentVersion = "pt-1"
    var quotaNextAllocation = false
    var locale = "pt-BR", readings:[Double]?
    var holdStage = false
    var camera = MealCameraAccess.unavailable
    private var stageHeld:CheckedContinuation<Void,Never>?, stageStarted:CheckedContinuation<Void,Never>?
    private var scopeHeld:CheckedContinuation<Void,Never>?, scopeStarted:CheckedContinuation<Void,Never>?
    private var allocatedKeys:Set<String> = [], analyzedKeys:Set<String> = []
    func model() -> ReevaluationPhotoModel {
        ReevaluationPhotoModel(userID:"auth-A",cycleID:Fixture.cycle,capability:capability(),keys:RandomIdempotencyKeyProvider())
    }
    func capability() -> ReevaluationPhotoCaptureCapability {
        ReevaluationPhotoCaptureCapability { [self] user,cycle in
            await bindScope()
            return ReevaluationPhotoCaptureScope(userID:user,cycleID:cycle,photos:self,camera:await camera,validateSession:{},
                stagePhoto:{ [self] _,channel in
                    await recordStage()
                    return StagedMedia(fileURL:URL(fileURLWithPath:"/synthetic-owned-capture/photo.jpg"),kind:.signupBodyPhoto,mimeType:"image/jpeg",sizeBytes:1200,duration:nil,channel:channel)
                }, upload:{ [self] _,_ in try await uploadPhoto() },discardStaged:{ [self] _ in await deleted() })
        }
    }
    func bindScope() async { scopes += 1; scopeStarted?.resume(); scopeStarted = nil; if holdScope { await withCheckedContinuation { scopeHeld = $0 } } }
    func waitScope() async { if scopes == 0 { await withCheckedContinuation { scopeStarted = $0 } } }
    func releaseScope() { holdScope = false; scopeHeld?.resume(); scopeHeld = nil }
    func accept(on model:ReevaluationPhotoModel) async { await model.load(); model.setConsentChecked(true); await model.acceptConsent() }
    func recordStage() async { stages += 1; stageStarted?.resume(); stageStarted = nil; if holdStage { await withCheckedContinuation { stageHeld = $0 } } }
    func waitStage() async { if stages == 0 { await withCheckedContinuation { stageStarted = $0 } } }
    func releaseStage() { holdStage = false; stageHeld?.resume(); stageHeld = nil }
    func uploadPhoto() throws { uploads += 1; if failUploadOnce { failUploadOnce = false; throw MealCaptureFailure.offline } }
    func deleted() { localDeletes += 1 }
    func consent() async throws -> ReevaluationPhotoConsent {
        consentReads += 1
        var raw = Fixture.consent(accepted); raw["cycle_revision"] = revision
        if var document = raw["document"] as? [String:Any] { document["version"] = documentVersion; document["locale"] = locale; raw["document"] = document }
        if var acceptance = raw["acceptance"] as? [String:Any] { acceptance["version"] = documentVersion; acceptance["locale"] = locale; raw["acceptance"] = acceptance }
        return try Fixture.decode(ReevaluationPhotoConsent.self,raw).validated(cycleID:Fixture.cycle)
    }
    func accept(_ input:ReevaluationPhotoConsentInput,key:IdempotencyKey) async throws -> ReevaluationPhotoConsent {
        acceptKeys.append(key.value)
        if changeConsentOnAccept { changeConsentOnAccept = false; documentVersion = "pt-2"; throw ReevaluationPhotoFailure.changed }
        accepted = true; revision = "2"; return try await consent()
    }
    func snapshot() async throws -> ReevaluationPhotoSnapshot {
        snapshotReads += 1
        guard accepted else { throw ReevaluationPhotoFailure.changed }
        var raw = MobileReevaluationPhotoRepositoryTests.snapshot(); raw["cycle_revision"] = revision
        raw["acceptance_id"] = accepted ? Fixture.acceptance : NSNull()
        raw["photos"] = ["front","side","back"].enumerated().map { index,pose in
            if accepted, let readings {
                return ["pose":pose,"asset":["id":"b3b01000-0000-4000-8000-00000000560\(index+5)","status":"processed","estimated_body_fat_percent":readings[index]]] as [String:Any]
            }
            return ["pose":pose,"asset":pose == "front" && status != nil ? ["id":Fixture.asset,"status":status!.rawValue] : NSNull()] as [String:Any]
        }
        return try Fixture.decode(ReevaluationPhotoSnapshot.self,raw).validated(cycleID:Fixture.cycle)
    }
    func allocate(_ input:ReevaluationPhotoAllocationInput,key:IdempotencyKey) async throws -> ReevaluationPhotoAllocation {
        allocateKeys.append(key.value); allocationInputs.append(input)
        if quotaNextAllocation { quotaNextAllocation = false; throw ReevaluationPhotoFailure.quota }
        if allocatedKeys.insert(key.value).inserted { newPhotos += 1 }
        if failAllocateOnce { failAllocateOnce = false; throw ReevaluationPhotoFailure.offline }
        return try Fixture.decode(ReevaluationPhotoAllocation.self,["version":1,"cycle_id":Fixture.cycle,"cycle_revision":revision,"asset":Fixture.photo(),"quota":["max_new_photos":6,"window_seconds":86400]]).validated(cycleID:Fixture.cycle,input:input)
    }
    func issueUpload(assetID:String,acceptanceID:String,key:IdempotencyKey) async throws -> ReevaluationPhotoUpload {
        uploadKeys.append(key.value)
        return try Fixture.decode(ReevaluationPhotoUpload.self,["version":1,"cycle_id":Fixture.cycle,"asset":Fixture.photo(),"upload":["signed_url":"https://owned.supabase.co/storage/v1/object/upload/sign/body-checkin-photos/\(Fixture.document)/\(Fixture.asset).jpg?token=synthetic","method":"PUT","headers":["Content-Type":"image/jpeg","x-upsert":"false"],"expires_at":"2026-10-27T14:00:00.000Z"]]).validated(cycleID:Fixture.cycle,assetID:assetID,acceptanceID:acceptanceID)
    }
    func complete(assetID:String,acceptanceID:String,key:IdempotencyKey) async throws -> ReevaluationPhotoCompletion {
        completions += 1; completionKeys.append(key.value)
        if missingCompletions > 0 { missingCompletions -= 1; throw ReevaluationPhotoFailure.changed }
        revision = "3"; status = .uploaded
        return try Fixture.decode(ReevaluationPhotoCompletion.self,["version":1,"cycle_id":Fixture.cycle,"cycle_revision":revision,"source_revision":"2","asset":Fixture.photo(status:"uploaded")]).validated(cycleID:Fixture.cycle,assetID:assetID,acceptanceID:acceptanceID)
    }
    func process(assetID:String,key:IdempotencyKey) async throws -> ReevaluationPhotoProcessing {
        processKeys.append(key.value)
        if skipProcessOnce { skipProcessOnce = false; return try Fixture.decode(ReevaluationPhotoProcessing.self,["version":1,"cycle_id":Fixture.cycle,"asset_id":assetID,"status":"skipped"]).validated(cycleID:Fixture.cycle,assetID:assetID) }
        if analyzedKeys.insert(key.value).inserted { analyses += 1 }; status = .processed
        if failProcessOnce { failProcessOnce = false; throw ReevaluationPhotoFailure.offline }
        return try Fixture.decode(ReevaluationPhotoProcessing.self,["version":1,"cycle_id":Fixture.cycle,"asset_id":assetID,"status":"processed"]).validated(cycleID:Fixture.cycle,assetID:assetID)
    }
    func discard(_ input:ReevaluationPhotoDiscardInput,key:IdempotencyKey) async throws -> ReevaluationPhotoDiscard {
        discardKeys.append(key.value); discardInputs.append(input)
        if failDiscardOnce { failDiscardOnce = false; throw ReevaluationPhotoFailure.offline }
        accepted = false; revision = "4"; status = nil
        return try Fixture.decode(ReevaluationPhotoDiscard.self,["version":1,"cycle_id":Fixture.cycle,"acceptance_id":input.acceptanceId,"status":"discard_requested","deletion":"waiting"]).validated(cycleID:Fixture.cycle,acceptanceID:input.acceptanceId)
    }
    func publish(_ operation:@MainActor @Sendable () throws -> Void) async throws { try operation() }
}

@MainActor private final class RecurringFullTestProvider:ClinicalFullProviding {
    let kind:ClinicalFullKind
    init(kind:ClinicalFullKind = .regular) { self.kind = kind }
    var active = true, descriptions = 0, assessments = 0
    func scoped(for userID:String) async throws -> any ClinicalFullProviding { self }
    func entry() async throws -> ClinicalFullEntry {
        try ClinicalFullWorkflowTests.decode(ClinicalFullEntry.self,["version":1,"availability":"available","unavailable_reason":NSNull(),"clock":["base_date":"2026-10-20","due_date":"2026-11-03","timezone":"America/Sao_Paulo"],"cycle":["id":ReevaluationPhotoContractTests.cycle,"kind":kind.rawValue,"status":"open","revision":"1"]]).validated()
    }
    func start(reason:ClinicalFullStartReason?,key:IdempotencyKey) async throws -> ClinicalFullEntry { try await entry() }
    func describe(scope:ClinicalFullScope,purpose:ClinicalFullPurpose) async throws -> ClinicalFullQuestionnaire { descriptions += 1; return try ClinicalFullWorkflowTests.form(scope) }
    func assess(scope:ClinicalFullScope,draft:ClinicalFullDraft) async throws -> ClinicalFullAssessment { assessments += 1; return try ClinicalFullWorkflowTests.assessment() }
    func prepare(scope:ClinicalFullScope,draft:ClinicalFullDraft,choice:ClinicalFullChoice,key:IdempotencyKey) async throws -> ClinicalFullPreview { try ClinicalFullWorkflowTests.preview(scope,choice:choice) }
    func confirm(scope:ClinicalFullScope,draft:ClinicalFullDraft,choice:ClinicalFullChoice,preview:ClinicalFullPreview,key:IdempotencyKey) async throws -> ClinicalFullConfirmation { try ClinicalFullWorkflowTests.confirmation(preview) }
    func declareHealth(items:[ClinicalFullHealthRisk],key:IdempotencyKey) async throws -> ClinicalFullHealthReceipt { throw ClinicalFullFailure.unavailable }
    func publish(_ operation:@MainActor @Sendable () throws -> Void) async throws {
        guard active else { throw SessionLifecycleError.sessionSuperseded }; try operation()
    }
}

@MainActor @Suite("Recurring capture — consent admission before snapshot")
struct ReevaluationPhotoConsentAdmissionRegressionTests {
    @Test func requiredConsentIsShownBeforeTheServerAllowsReadingPhotos() async throws {
        let f = RecurringCaptureFake(), model = f.model()
        await model.load()
        #expect(model.error == nil)
        #expect(model.consent?.document != nil && model.consent?.acceptance == nil)
        #expect(model.snapshot == nil && f.snapshotReads == 0)
        #expect(!model.canCapture && f.acceptKeys.isEmpty && f.allocateKeys.isEmpty)
        model.setConsentChecked(true)
        await model.acceptConsent()
        #expect(model.error == nil && model.canCapture)
        #expect(f.acceptKeys.count == 1 && f.snapshotReads == 1)
    }
    @Test func renewedConsentRemovesPreviouslyAuthorizedPhotoStateUntilAccepted() async throws {
        let f = RecurringCaptureFake(), model = f.model()
        await f.accept(on:model)
        #expect(model.snapshot != nil && model.canCapture)
        let reads = f.snapshotReads
        f.accepted = false; f.documentVersion = "pt-2"; f.revision = "4"
        await model.load()
        #expect(model.error == nil && model.consent?.document?.version == "pt-2")
        #expect(model.consent?.acceptance == nil && model.snapshot == nil)
        #expect(!model.consentChecked && !model.canCapture && f.snapshotReads == reads)
        #expect(f.acceptKeys.count == 1 && f.allocateKeys.isEmpty)
    }
}
