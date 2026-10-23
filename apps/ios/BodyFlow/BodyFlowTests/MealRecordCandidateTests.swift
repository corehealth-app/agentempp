import Foundation
import Testing
@testable import BodyFlow

// Synthetic DTO/transport/ownership fixtures, no SQL/nutrition proof,
// no actual patient screenshot and no real API connection.
@MainActor
@Suite("C11 confirmed meal candidate")
struct MealRecordCandidateTests {
    @Test("retry keeps the same version, single anchor body, key and typed attempt")
    func exactAttemptRetry() async throws {
        let service = MealRecordServiceStub()
        await service.failNextPatch(.capability(.offline))
        let keys = C11FixtureKeys()
        let center = FeatureInvalidationCenter()
        let model = makeModel(service, keys: keys, center: center)
        await model.load()
        model.draft?.items[0].quantityText = "25"
        await model.save(language: .portugueseBrazil)
        let retained = try #require(model.retainedAttempt)
        #expect(model.failure == .capability(.offline))
        #expect(model.draft?.items[0].quantityText == "25")
        await model.retry()
        let calls = await service.calls
        let patches = calls.compactMap { call -> MutationAttempt<MealRecordPatchCommand>? in
            if case let .patch(value) = call { return value }
            return nil
        }
        #expect(patches.count == 2)
        #expect(patches[0] == patches[1])
        #expect(retained == .patch(patches[0]))
        #expect(keys.count == 1)
        #expect(patches[0].payload.body.expectedVersion == "opaque-fixture-version")
        #expect(patches[0].payload.body.itemIDs == [C11RecordFixtures.a])
        #expect(patches[0].payload.body.items.count == 1)
        #expect(patches[0].payload.body.items[0].quantityG == 25)
        #expect(patches[0].payload.body.items[0].userKcal == nil)
        #expect(model.draft?.items[1].original == C11RecordFixtures.items[1])
        #expect(model.confirmedReceipt?.data.newItemIDs.count == 3)
        #expect(model.confirmedReceipt?.data.nextRecordID == C11RecordFixtures.newSiblingID)
        #expect(center.revision(for: .today) == 1)
        #expect(center.revision(for: .history) == 1)
    }

    @Test("committed receipt survives failed recovery GET and cannot POST/PATCH again")
    func committedReadFailure() async throws {
        let service = MealRecordServiceStub()
        let model = makeModel(service)
        await model.load()
        await model.save(language: .englishUnitedStates)
        let receipt = try #require(model.confirmedReceipt)
        await service.failReads()
        await model.load()
        await model.retry()
        await model.save(language: .englishUnitedStates)
        #expect(model.confirmedReceipt == receipt)
        #expect(model.readFailure == .capability(.offline))
        #expect(model.retainedAttempt == nil)
        #expect(await service.calls.count == 3)
        #expect(await service.calls.last == .get(C11RecordFixtures.newSiblingID))
    }

    @Test("unknown interruption forbids fresh command/rebase and retains form")
    func unknownAttemptCannotBecomeNewCommand() async throws {
        let service = MealRecordServiceStub()
        await service.failNextPatch(.interruptedUnknown)
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await model.load()
        await model.save(language: .portugueseBrazil)
        let retained = try #require(model.retainedAttempt)
        await model.load()
        model.reviewLatest()
        await model.delete()
        #expect(model.retainedAttempt == retained)
        #expect(keys.count == 1)
        #expect(await service.calls.count == 3)
    }

    @Test("server closed-day eligibility refuses PATCH and DELETE without keys")
    func closedDayHasNoCommand() async {
        let service = MealRecordServiceStub(detail: C11RecordFixtures.closed)
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await model.load()
        await model.save(language: .portugueseBrazil)
        await model.delete()
        #expect(!model.canStartMutation)
        #expect(keys.count == 0)
        #expect(await service.calls == [.get(C11RecordFixtures.a)])
    }

    @Test("DELETE retries the original scope and retains zero server totals without a replacement item")
    func deleteRetryAndPersistedZero() async throws {
        let service = MealRecordServiceStub()
        await service.failNextDelete(.capability(.offline))
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await model.load()
        model.selectForDeletion(id: C11RecordFixtures.b, selected: true)
        await model.delete()
        let retained = try #require(model.retainedAttempt)
        await model.retry()
        let calls = await service.calls
        let deletes = calls.compactMap { call -> MutationAttempt<MealRecordDeleteCommand>? in
            if case let .delete(value) = call { return value }
            return nil
        }
        #expect(deletes.count == 2)
        #expect(deletes[0] == deletes[1])
        #expect(retained == .delete(deletes[0]))
        #expect(deletes[0].payload.body.itemIDs == [C11RecordFixtures.a, C11RecordFixtures.b])
        #expect(model.confirmedReceipt?.data.newItemIDs == [])
        #expect(model.confirmedReceipt?.data.snapshot.caloriesConsumed == 0)
        #expect(model.draft != nil)
        #expect(keys.count == 1)
        await model.load()
        #expect(await service.calls.count == 3)
    }

    @Test("a malformed success retains the original attempt as unknown")
    func malformedSuccessDoesNotCreateAnotherCommand() async throws {
        let service = MealRecordServiceStub(patchReceipt: C11RecordFixtures.receipt(.deleted))
        let keys = C11FixtureKeys()
        let center = FeatureInvalidationCenter()
        let model = makeModel(service, keys: keys, center: center)
        await model.load()
        await model.save(language: .portugueseBrazil)
        let retained = try #require(model.retainedAttempt)
        #expect(model.failure == .interruptedUnknown)
        #expect(model.confirmedReceipt == nil)
        await model.load()
        model.reviewLatest()
        await model.delete()
        #expect(model.retainedAttempt == retained)
        #expect(keys.count == 1)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
    }

    @Test("known conflict keeps form, needs fresh GET and explicit new review")
    func conflictDoesNotSilentlyRebase() async throws {
        let service = MealRecordServiceStub()
        await service.failNextPatch(.versionChanged)
        let model = makeModel(service)
        await model.load()
        model.draft?.items[0].quantityText = "25"
        await model.save(language: .portugueseBrazil)
        let attempt = try #require(model.retainedAttempt)
        model.reviewLatest()
        #expect(model.retainedAttempt == attempt)
        await model.load()
        #expect(model.draft?.items[0].quantityText == "25")
        model.reviewLatest()
        #expect(model.archivedDraft?.items[0].quantityText == "25")
        #expect(model.retainedAttempt == nil)
        #expect(model.failure == nil)
    }

    @Test("late A mutation response cannot publish after session invalidation")
    func lateResponseAfterSessionEnd() async {
        let service = C11DeferredProvider()
        let center = FeatureInvalidationCenter()
        let model = makeModel(service, center: center)
        await model.load()
        let saving = Task { await model.save(language: .portugueseBrazil) }
        await service.waitUntilPatchStarted()
        model.endSession()
        await service.resolve()
        await saving.value
        #expect(model.detail == nil)
        #expect(model.draft == nil)
        #expect(model.retainedAttempt == nil)
        #expect(model.confirmedReceipt == nil)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
    }

    @Test("owner gate suppresses late result and prevents capability use after close")
    func authenticatedOwnerGate() async throws {
        let service = C11DeferredProvider()
        let gate = Prompt14SessionOperationGate()
        let capability = MealRecordSessionCapability(provider: service, gate: gate)
        let body = try #require(MealRecordEditDraft(C11RecordFixtures.open.data)
            .patchBody(language: .portugueseBrazil))
        let attempt = MutationAttempt(operation: .mealRecordPatch,
            key: try IdempotencyKey(validating: "c11-gate-fixture-key"),
            payload: MealRecordPatchCommand(recordID: C11RecordFixtures.a, body: body,
                originalGroupItemIDs: [C11RecordFixtures.a, C11RecordFixtures.b],
                expectedLocalDate: "2026-10-09"),
            createdAt: C11RecordFixtures.date)
        let request = Task {
            do { _ = try await capability.patch(attempt); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        await service.waitUntilPatchStarted()
        gate.close()
        await service.resolve()
        #expect(await request.value)
        await gate.drain()
        capability.release()
        #expect(!capability.hasRetainedCapability)
        await #expect(throws: CancellationError.self) { _ = try await capability.patch(attempt) }
        #expect(await service.patchCount == 1)
    }

    @Test("PT/EN quantity parsing sends only the anchor and never sends macros")
    func draftUsesExistingStrictParser() throws {
        for language in SupportedAppLanguage.allCases {
            var draft = MealRecordEditDraft(C11RecordFixtures.open.data)
            draft.items[0].quantityText = "25,5"
            let body = try #require(draft.patchBody(language: language))
            #expect(body.items[0].quantityG == Decimal(string: "25.5"))
            #expect(body.itemIDs == [C11RecordFixtures.a])
            #expect(body.items.count == 1)
            #expect(draft.items[1].original == C11RecordFixtures.items[1])
            let encoded = try JSONEncoder().encode(body)
            let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(Set(json.keys) == Set(["expected_version", "item_ids", "items"]))
            let items = try #require(json["items"] as? [[String: Any]])
            #expect(items.allSatisfy { $0["protein_g"] == nil && $0["carbs_g"] == nil && $0["fat_g"] == nil && $0["kcal"] == nil })
        }
    }

    @Test("quantity-only edits of label/NULL/legacy sources omit old kcal and delegate provenance to the server")
    func quantityOnlyPreservesServerAuthority() throws {
        let original = C11RecordFixtures.items[0]
        let sources: [String?] = [nil, "manual", "product_label", "user_kcal"]
        for source in sources {
            let item = MealRecordItemSnapshot(id: original.id, foodName: original.foodName,
                quantityG: original.quantityG, kcal: original.kcal,
                proteinG: original.proteinG, carbsG: original.carbsG, fatG: original.fatG,
                source: source, consumedAt: original.consumedAt, mealType: original.mealType)
            for language in SupportedAppLanguage.allCases {
                var draft = MealRecordEditItem(item)
                draft.quantityText = "25"
                let request = try #require(draft.request(language: language))
                #expect(request.foodName == original.foodName)
                #expect(request.quantityG == 25)
                #expect(request.userKcal == nil)
                #expect(!request.usesNutritionLabel)
                let data = try JSONEncoder().encode(request)
                let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(json["user_kcal"] == nil)
                #expect(json["source"] == nil)
                #expect(json["kcal"] == nil)
            }
        }
    }

    @Test("explicit new kcal is sent, while clearing the optional override omits it without a reset command")
    func explicitCalorieOverrideOnly() throws {
        var draft = MealRecordEditItem(C11RecordFixtures.items[1])
        draft.quantityText = "60"
        #expect(draft.manualKcalDisplay(language: .portugueseBrazil) == "")
        #expect(draft.request(language: .portugueseBrazil)?.userKcal == nil)
        draft.manualKcalText = "35,5"
        #expect(draft.request(language: .portugueseBrazil)?.userKcal == Decimal(string: "35.5"))
        draft.manualKcalText = "0"
        #expect(draft.request(language: .englishUnitedStates)?.userKcal == 0)
        draft.manualKcalText = ""
        let request = try #require(draft.request(language: .portugueseBrazil))
        let encoded = try JSONEncoder().encode(request)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["user_kcal"] == nil)
    }

    @Test("partial DELETE preserves the receipt and follows the official remaining next_record_id by GET only")
    func partialDeleteRecovery() async throws {
        let service = MealRecordServiceStub()
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await model.load()
        #expect(model.deletionSelection == [C11RecordFixtures.a])
        await model.delete()
        let receipt = try #require(model.confirmedReceipt)
        #expect(receipt.data.removedItemIDs == [C11RecordFixtures.a])
        #expect(receipt.data.newItemIDs.isEmpty)
        #expect(receipt.data.nextRecordID == C11RecordFixtures.b)
        await service.failReads()
        await model.load()
        await model.retry()
        await model.delete()
        #expect(model.confirmedReceipt == receipt)
        #expect(await service.calls.last == .get(C11RecordFixtures.b))
        #expect(await service.calls.count == 3)
        #expect(keys.count == 1)
    }

    @Test("repository uses GET without a key and exact PATCH/DELETE body with the supplied key")
    func repositoryRequests() async throws {
        let transport = C11TransportStub()
        let repository = MobileMealRecordRepository(transport: transport)
        _ = try await repository.mealRecord(id: C11RecordFixtures.a)
        let key = try IdempotencyKey(validating: "c11-repository-fixture-key")
        let deleteKey = try IdempotencyKey(validating: "c11-repository-delete-fixture-key")
        let body = try #require(MealRecordEditDraft(C11RecordFixtures.open.data)
            .patchBody(language: .portugueseBrazil))
        let attempt = MutationAttempt(operation: .mealRecordPatch, key: key,
            payload: MealRecordPatchCommand(recordID: C11RecordFixtures.a, body: body,
                originalGroupItemIDs: [C11RecordFixtures.a, C11RecordFixtures.b],
                expectedLocalDate: "2026-10-09"),
            createdAt: C11RecordFixtures.date)
        _ = try await repository.patch(attempt)
        _ = try await repository.patch(attempt)
        _ = try await repository.delete(MutationAttempt(operation: .mealRecordDelete, key: deleteKey,
            payload: MealRecordDeleteCommand(recordID: C11RecordFixtures.a,
                body: MealRecordDeleteBody(expectedVersion: body.expectedVersion, itemIDs: body.itemIDs),
                originalGroupItemIDs: [C11RecordFixtures.a, C11RecordFixtures.b],
                expectedLocalDate: "2026-10-09"),
            createdAt: C11RecordFixtures.date))
        let calls = await transport.requests
        #expect(calls.map(\.method) == [.get, .patch, .patch, .delete])
        #expect(calls.allSatisfy { $0.path == "/api/mobile/v1/meal-records/\(C11RecordFixtures.a)" })
        #expect(calls[0].idempotency == .notRequired)
        #expect(calls[0].body == nil)
        #expect(calls[1].idempotency == .required(key))
        #expect(calls[2].idempotency == .required(key))
        #expect(calls[3].idempotency == .required(deleteKey))
        #expect(calls[1].body == calls[2].body)
        let patchData = try #require(calls[1].body)
        #expect(try JSONDecoder().decode(MealRecordPatchBody.self, from: patchData) == body)
        let deleteData = try #require(calls[3].body)
        let deleted = try JSONDecoder().decode(MealRecordDeleteBody.self, from: deleteData)
        #expect(deleted.expectedVersion == body.expectedVersion)
        #expect(deleted.itemIDs == body.itemIDs)
    }

    @Test("repository distinguishes version conflict and session supersession without another request")
    func repositoryFailures() async throws {
        let transport = C11TransportStub()
        let repository = MobileMealRecordRepository(transport: transport)
        await transport.fail(.conflict(code: "MEAL_VERSION_CONFLICT", requestID: "c11-fixture-conflict"))
        await #expect(throws: MealRecordFailure.versionChanged) {
            _ = try await repository.mealRecord(id: C11RecordFixtures.a)
        }
        await transport.fail(.sessionSuperseded)
        await #expect(throws: CancellationError.self) {
            _ = try await repository.mealRecord(id: C11RecordFixtures.a)
        }
        #expect(await transport.requests.count == 2)
    }

    @Test("required nullable receipt fields preserve explicit null and reject missing keys or unknown operations")
    func requiredNullableReceiptFields() throws {
        let receipt = C11RecordFixtures.receipt(.deleted)
        let snapshot = receipt.data.snapshot
        let nullable = MealRecordMutationSnapshot(recordID: receipt.data.recordID,
            operation: .deleted, newItemIDs: [], removedItemIDs: receipt.data.removedItemIDs,
            nextRecordID: nil,
            snapshot: MealRecordPersistedSnapshot(id: snapshot.id, date: snapshot.date,
                caloriesConsumed: snapshot.caloriesConsumed, proteinG: snapshot.proteinG,
                carbsG: snapshot.carbsG, fatG: snapshot.fatG, dailyBalance: nil))
        let encoded = try JSONEncoder().encode(nullable)
        #expect(try JSONDecoder().decode(MealRecordMutationSnapshot.self, from: encoded) == nullable)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["next_record_id"] is NSNull)
        let persisted = try #require(json["snapshot"] as? [String: Any])
        #expect(persisted["daily_balance"] is NSNull)

        var missingNext = json
        missingNext.removeValue(forKey: "next_record_id")
        let missingNextData = try JSONSerialization.data(withJSONObject: missingNext)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(MealRecordMutationSnapshot.self, from: missingNextData)
        }
        var missingBalance = json
        var incompleteSnapshot = persisted
        incompleteSnapshot.removeValue(forKey: "daily_balance")
        missingBalance["snapshot"] = incompleteSnapshot
        let missingBalanceData = try JSONSerialization.data(withJSONObject: missingBalance)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(MealRecordMutationSnapshot.self, from: missingBalanceData)
        }
        var unknownOperation = json
        unknownOperation["operation"] = "unknown"
        let unknownOperationData = try JSONSerialization.data(withJSONObject: unknownOperation)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(MealRecordMutationSnapshot.self, from: unknownOperationData)
        }
    }

    @Test("backend R2 validation errors remain typed without issuing another HTTP request")
    func backendR2ValidationFailures() async throws {
        let transport = C11TransportStub()
        let repository = MobileMealRecordRepository(transport: transport)
        let failures: [(String, MealRecordFailure)] = [
            ("MEAL_QUANTITY_NOT_REPRESENTABLE", .quantityNotRepresentable),
            ("MEAL_NUTRITION_UNRESOLVED", .nutritionUnresolved),
            ("MEAL_GROUP_LIMIT_EXCEEDED", .groupLimitExceeded),
        ]
        for (code, expected) in failures {
            await transport.fail(.validation(code: code, requestID: "c11-synthetic-validation"))
            await #expect(throws: expected) {
                _ = try await repository.mealRecord(id: C11RecordFixtures.a)
            }
        }
        #expect(await transport.requests.count == failures.count)
    }

    @Test("deleting only B preserves the receipt and explicit reopening of surviving A allows a new command")
    func explicitReopeningOfSurvivingAnchor() async throws {
        let service = MealRecordServiceStub()
        let keys = C11FixtureKeys()
        let center = FeatureInvalidationCenter()
        let model = makeModel(service, keys: keys, center: center)
        await model.load()
        model.selectForDeletion(id: C11RecordFixtures.a, selected: false)
        model.selectForDeletion(id: C11RecordFixtures.b, selected: true)
        await model.delete()
        let receipt = try #require(model.confirmedReceipt)
        #expect(receipt.data.recordID == C11RecordFixtures.a)
        #expect(receipt.data.removedItemIDs == [C11RecordFixtures.b])
        #expect(receipt.data.newItemIDs.isEmpty)
        #expect(receipt.data.nextRecordID == C11RecordFixtures.a)
        await service.replaceDetail(C11RecordFixtures.singleOpen)
        await model.load()
        #expect(!model.canStartMutation)
        model.beginPresentation()
        model.beginPresentation()
        #expect(!model.canStartMutation)
        #expect(keys.count == 1)
        model.discardPresentation()
        model.beginPresentation()
        #expect(!model.canStartMutation)
        await model.load()
        try #require(model.canStartMutation)
        #expect(model.confirmedReceipt == receipt)
        #expect(model.completedMutations.map(\.receipt) == [receipt])
        #expect(await service.calls.count == 4)
        await model.save(language: .portugueseBrazil)
        #expect(keys.count == 2)
        #expect(model.attemptHistory.count == 2)
        try #require(model.completedMutations.count == 2)
        #expect(model.completedMutations[0].receipt == receipt)
        #expect(center.revision(for: .today) == 2)
        #expect(center.revision(for: .history) == 2)
        let calls = await service.calls
        let deletes = calls.compactMap { call -> MutationAttempt<MealRecordDeleteCommand>? in
            if case let .delete(value) = call { return value }; return nil
        }
        try #require(deletes.count == 1)
        #expect(deletes[0].payload.body.itemIDs == [C11RecordFixtures.b])
        let patches = calls.compactMap { call -> MutationAttempt<MealRecordPatchCommand>? in
            if case let .patch(value) = call { return value }; return nil
        }
        try #require(patches.count == 1)
        #expect(patches[0].key != deletes[0].key)
    }

    @Test("definitive quantity422 permits explicit correction, but unchanged intent never gets a fresh key")
    func definitiveQuantityCorrection() async throws {
        let service = MealRecordServiceStub(detail: C11RecordFixtures.quantity85)
        await service.failNextPatch(.quantityNotRepresentable)
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await model.load()
        model.draft?.items[0].quantityText = "170.001"
        await model.save(language: .englishUnitedStates)
        let original = try #require(model.retainedAttempt)
        #expect(model.failure == .quantityNotRepresentable)
        #expect(!model.canEditDraft)
        model.beginCorrectingRejectedInput()
        try #require(model.canEditDraft)
        #expect(model.draft?.items[0].quantityText == "170.001")
        await model.save(language: .englishUnitedStates)
        model.draft?.items[0].quantityText = "170.0010"
        await model.save(language: .englishUnitedStates)
        #expect(model.retainedAttempt == original)
        #expect(keys.count == 1)
        #expect(await service.calls.count == 2)
        model.draft?.items[0].quantityText = "170.00"
        await model.save(language: .englishUnitedStates)
        let calls = await service.calls
        let patches = calls.compactMap { call -> MutationAttempt<MealRecordPatchCommand>? in
            if case let .patch(value) = call { return value }; return nil
        }
        try #require(patches.count == 2)
        #expect(patches[0].key != patches[1].key)
        #expect(patches[0].payload.body.items[0].quantityG == Decimal(string: "170.001"))
        #expect(patches[1].payload.body.items[0].quantityG == 170)
        #expect(patches[0].payload.body.expectedVersion == patches[1].payload.body.expectedVersion)
        #expect(model.attemptHistory == [.patch(patches[0]), .patch(patches[1])])
        #expect(model.archivedDraft?.items[0].quantityText == "170.001")
        #expect(model.confirmedReceipt != nil)
        #expect(keys.count == 2)
    }

    @Test("409 requires fresh GET and explicit review before recovering attempted fields onto the official version")
    func conflictRecoverableDraft() async throws {
        let service = MealRecordServiceStub()
        await service.failNextPatch(.versionChanged)
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await model.load()
        model.draft?.items[0].quantityText = "25"
        await model.save(language: .portugueseBrazil)
        let original = try #require(model.retainedAttempt)
        model.beginCorrectingRejectedInput()
        model.reviewLatest()
        model.restoreArchivedFields()
        #expect(model.retainedAttempt == original)
        #expect(!model.canEditDraft)
        await service.replaceDetail(C11RecordFixtures.singleOpen)
        await model.load()
        #expect(model.retainedAttempt == original)
        #expect(model.draft?.items[0].quantityText == "25")
        model.reviewLatest()
        #expect(model.retainedAttempt == nil)
        #expect(model.draft?.expectedVersion == "opaque-single-version")
        #expect(model.draft?.items[0].quantityText == nil)
        #expect(model.canRestoreArchivedFields)
        model.restoreArchivedFields()
        #expect(model.draft?.items[0].quantityText == "25")
        #expect(model.draft?.itemIDs == [C11RecordFixtures.a])
        #expect(model.draft?.expectedVersion == "opaque-single-version")
        #expect(model.draft?.items[0].original == C11RecordFixtures.items[0])
        #expect(keys.count == 1)
        await model.save(language: .portugueseBrazil)
        #expect(keys.count == 2)
        #expect(model.attemptHistory.count == 2)
    }

    @Test("unknown, timeout and in-progress dismissals reopen with the original immutable attempt")
    func uncertainReopeningKeepsAttempt() async throws {
        let failures: [MealRecordFailure] = [.interruptedUnknown, .capability(.offline), .requestInProgress]
        for failure in failures {
            let service = MealRecordServiceStub()
            await service.failNextPatch(failure)
            let keys = C11FixtureKeys()
            let model = makeModel(service, keys: keys)
            await model.load()
            model.draft?.items[0].quantityText = "25"
            await model.save(language: .portugueseBrazil)
            let original = try #require(model.retainedAttempt)
            let draft = model.draft
            model.beginCorrectingRejectedInput()
            #expect(!model.canEditDraft)
            model.discardPresentation()
            model.beginPresentation()
            await model.load()
            model.reviewLatest()
            model.restoreArchivedFields()
            await model.save(language: .portugueseBrazil)
            #expect(model.retainedAttempt == original)
            #expect(model.draft == draft)
            #expect(model.attemptHistory == [original])
            #expect(keys.count == 1)
            await model.retry()
            let calls = await service.calls
            let patches = calls.compactMap { call -> MutationAttempt<MealRecordPatchCommand>? in
                if case let .patch(value) = call { return value }; return nil
            }
            #expect(patches.count == 2)
            #expect(patches[0] == patches[1])
            #expect(keys.count == 1)
        }
    }

    @Test("a prior completed receipt remains visible while a subsequent definitively rejected command is corrected")
    func priorReceiptSurvivesCorrection() async throws {
        let service = MealRecordServiceStub()
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await model.load()
        model.selectForDeletion(id: C11RecordFixtures.a, selected: false)
        model.selectForDeletion(id: C11RecordFixtures.b, selected: true)
        await model.delete()
        let receipt = try #require(model.confirmedReceipt)
        await service.replaceDetail(C11RecordFixtures.singleOpen)
        model.discardPresentation()
        model.beginPresentation()
        await model.load()
        await service.failNextPatch(.quantityNotRepresentable)
        model.draft?.items[0].quantityText = "170.001"
        await model.save(language: .englishUnitedStates)
        #expect(model.confirmedReceipt == receipt)
        #expect(model.completedMutations.count == 1)
        model.beginCorrectingRejectedInput()
        model.draft?.items[0].quantityText = "170"
        #expect(model.confirmedReceipt == receipt)
        await model.save(language: .englishUnitedStates)
        try #require(model.completedMutations.count == 2)
        #expect(model.completedMutations[0].receipt == receipt)
        #expect(model.attemptHistory.count == 3)
        #expect(keys.count == 3)
    }

    @Test("old A completion after B and fresh A cannot publish through its closed owner gate")
    func ownerABAWithLateCompletion() async throws {
        let deferred = C11DeferredProvider()
        let oldGate = Prompt14SessionOperationGate()
        let oldCapability = MealRecordSessionCapability(provider: deferred, gate: oldGate)
        let keys = C11FixtureKeys()
        let center = FeatureInvalidationCenter()
        let oldA = makeModel(oldCapability, keys: keys, center: center)
        await oldA.load()
        let oldSaving = Task { await oldA.save(language: .portugueseBrazil) }
        await deferred.waitUntilPatchStarted()
        oldGate.close()
        oldA.endSession()
        let ownerB = makeModel(MealRecordServiceStub(), keys: keys, center: center)
        await ownerB.load()
        ownerB.endSession()
        let freshA = makeModel(MealRecordServiceStub(), keys: keys, center: center)
        await freshA.load()
        await deferred.resolve()
        await oldSaving.value
        await oldGate.drain()
        oldCapability.release()
        #expect(oldA.confirmedReceipt == nil)
        #expect(oldA.attemptHistory.isEmpty)
        #expect(freshA.confirmedReceipt == nil)
        #expect(freshA.retainedAttempt == nil)
        #expect(center.revision(for: .today) == 0)
        await freshA.save(language: .portugueseBrazil)
        #expect(freshA.confirmedReceipt != nil)
        #expect(center.revision(for: .today) == 1)
        #expect(keys.count == 2)
    }

    @Test("GET review and archived-field recovery cannot mint a fresh key for the same rejected body")
    func rejectedIntentSurvivesExplicitReview() async throws {
        let service = MealRecordServiceStub(detail: C11RecordFixtures.quantity85)
        await service.failNextPatch(.quantityNotRepresentable)
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await model.load()
        model.draft?.items[0].quantityText = "170.001"
        await model.save(language: .englishUnitedStates)
        let original = try #require(model.retainedAttempt)
        await model.load()
        model.reviewLatest()
        model.restoreArchivedFields()
        #expect(model.retainedAttempt == nil)
        #expect(model.draft?.items[0].quantityText == "170.001")
        await model.save(language: .englishUnitedStates)
        #expect(keys.count == 1)
        #expect(await service.calls.count == 3)
        #expect(model.attemptHistory == [original])
        model.draft?.items[0].quantityText = "170.00"
        await model.save(language: .englishUnitedStates)
        #expect(keys.count == 2)
        #expect(model.attemptHistory.count == 2)
        #expect(model.confirmedReceipt != nil)
    }

    @Test("a new official version cannot make unchanged rejected meal fields eligible for a fresh key")
    func rejectedFieldsIgnoreVersionChanges() async throws {
        let service = MealRecordServiceStub(detail: C11RecordFixtures.quantity85)
        await service.failNextPatch(.quantityNotRepresentable)
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await model.load()
        model.draft?.items[0].quantityText = "170.001"
        await model.save(language: .englishUnitedStates)
        let original = try #require(model.retainedAttempt)
        let official = C11RecordFixtures.quantity85.data
        await service.replaceDetail(MealRecordResponse(data: MealRecordSnapshot(recordID: official.recordID,
            scope: .group, expectedVersion: "opaque-85g-version-v2", itemIDs: [official.recordID],
            items: [official.items[0]], editable: true, dayClosed: false, localDate: official.localDate,
            timezone: official.timezone, editBlockReason: nil), meta: C11RecordFixtures.meta))
        await model.load()
        model.reviewLatest()
        model.restoreArchivedFields()
        #expect(model.draft?.expectedVersion == "opaque-85g-version-v2")
        #expect(model.draft?.items[0].quantityText == "170.001")
        await model.save(language: .englishUnitedStates)
        #expect(keys.count == 1)
        #expect(await service.calls.count == 3)
        #expect(model.attemptHistory == [original])
        model.draft?.items[0].quantityText = "170.0010"
        await model.save(language: .englishUnitedStates)
        #expect(keys.count == 1)
        #expect(await service.calls.count == 3)
        model.draft?.items[0].quantityText = "170.00"
        await model.save(language: .englishUnitedStates)
        #expect(keys.count == 2)
        let calls = await service.calls
        let patches = calls.compactMap { call -> MutationAttempt<MealRecordPatchCommand>? in
            if case let .patch(value) = call { return value }; return nil
        }
        try #require(patches.count == 2)
        #expect(patches[0].key != patches[1].key)
        #expect(patches[1].payload.body.expectedVersion == "opaque-85g-version-v2")
        #expect(patches[1].payload.body.items[0].quantityG == 170)
        #expect(model.completedMutations.count == 1)
    }

    @Test("the same group-limit code keeps its HTTP409 or422 recovery policy in the repository")
    func groupLimitStatusMapping() async throws {
        let transport = C11TransportStub()
        let repository = MobileMealRecordRepository(transport: transport)
        let body = try #require(MealRecordEditDraft(C11RecordFixtures.open.data)
            .patchBody(language: .portugueseBrazil))
        let attempt = MutationAttempt(operation: .mealRecordPatch,
            key: try IdempotencyKey(validating: "c11-group-status-fixture-key"),
            payload: MealRecordPatchCommand(recordID: C11RecordFixtures.a, body: body,
                originalGroupItemIDs: [C11RecordFixtures.a, C11RecordFixtures.b],
                expectedLocalDate: "2026-10-09"), createdAt: C11RecordFixtures.date)
        await transport.fail(.conflict(code: "MEAL_GROUP_LIMIT_EXCEEDED", requestID: "c11-synthetic409"))
        await #expect(throws: MealRecordFailure.groupLimitChanged) { _ = try await repository.patch(attempt) }
        await transport.fail(.validation(code: "MEAL_GROUP_LIMIT_EXCEEDED", requestID: "c11-synthetic422"))
        await #expect(throws: MealRecordFailure.groupLimitExceeded) { _ = try await repository.patch(attempt) }
        #expect(await transport.requests.count == 2)
    }

    @Test("group-limit409 requires official read and review, while422 allows explicit changed-input correction")
    func groupLimitRecoveryPolicies() async throws {
        let conflictService = MealRecordServiceStub()
        await conflictService.failNextPatch(.groupLimitChanged)
        let conflictKeys = C11FixtureKeys()
        let conflict = makeModel(conflictService, keys: conflictKeys)
        await conflict.load()
        conflict.draft?.items[0].quantityText = "25"
        await conflict.save(language: .portugueseBrazil)
        let original = try #require(conflict.retainedAttempt)
        conflict.beginCorrectingRejectedInput()
        conflict.reviewLatest()
        #expect(!conflict.canCorrectRejectedInput)
        #expect(!conflict.canEditDraft)
        #expect(conflict.retainedAttempt == original)
        #expect(conflictKeys.count == 1)
        await conflictService.replaceDetail(C11RecordFixtures.singleOpen)
        await conflict.load()
        #expect(conflict.retainedAttempt == original)
        conflict.reviewLatest()
        conflict.restoreArchivedFields()
        await conflict.save(language: .portugueseBrazil)
        #expect(conflictKeys.count == 2)
        #expect(conflict.attemptHistory.count == 2)

        let validationService = MealRecordServiceStub()
        await validationService.failNextPatch(.groupLimitExceeded)
        let validationKeys = C11FixtureKeys()
        let validation = makeModel(validationService, keys: validationKeys)
        await validation.load()
        validation.draft?.items[0].quantityText = "25"
        await validation.save(language: .portugueseBrazil)
        validation.beginCorrectingRejectedInput()
        try #require(validation.canEditDraft)
        await validation.save(language: .portugueseBrazil)
        #expect(validationKeys.count == 1)
        validation.draft?.items[0].quantityText = "26"
        await validation.save(language: .portugueseBrazil)
        #expect(validationKeys.count == 2)
        #expect(validation.attemptHistory.count == 2)

        let unavailableService = MealRecordServiceStub()
        await unavailableService.failNextPatch(.groupLimitChanged)
        let unavailableKeys = C11FixtureKeys()
        let unavailable = makeModel(unavailableService, keys: unavailableKeys)
        await unavailable.load()
        await unavailable.save(language: .portugueseBrazil)
        let unavailableOriginal = try #require(unavailable.retainedAttempt)
        await unavailableService.failReads()
        await unavailable.load()
        unavailable.reviewLatest()
        unavailable.beginCorrectingRejectedInput()
        await unavailable.save(language: .portugueseBrazil)
        #expect(unavailable.readFailure == .capability(.offline))
        #expect(unavailable.retainedAttempt == unavailableOriginal)
        #expect(!unavailable.canEditDraft)
        #expect(unavailableKeys.count == 1)
    }

    @Test("automatic-read outcome settles published success or error and keeps explicit read retry")
    func presentationLoadOutcomeSettlesPublishedReadAndFailure() async {
        let provider = C11PresentationReadProvider(results: [.success, .offline, .success])
        let keys = C11FixtureKeys()
        let center = FeatureInvalidationCenter()
        let model = makeModel(provider, keys: keys, center: center)
        #expect(await model.load() == .settled)
        #expect(model.detail == C11RecordFixtures.open)
        model.draft?.items[0].foodName = "Synthetic retained typed fields"
        let draft = model.draft
        #expect(await model.load() == .settled)
        #expect(model.readFailure == .capability(.offline))
        #expect(model.detail == C11RecordFixtures.open)
        #expect(model.draft == draft)
        #expect(!model.isLoading)
        // Explicit Retry still calls load; the presentation hint does not turn
        // the Model into a cache that blocks this official read.
        #expect(await model.load() == .settled)
        #expect(model.readFailure == nil)
        #expect(model.draft == draft)
        #expect(await provider.reads == [C11RecordFixtures.a, C11RecordFixtures.a, C11RecordFixtures.a])
        #expect(keys.count == 0)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
    }

    @Test("ineligible read returns not-started without completing a presentation or disturbing a command")
    func presentationLoadOutcomeNotStartedForEachAdmissionGuard() async {
        let provider = C11PresentationReadProvider(results: [.success])
        let eligibility = C11PresentationReadEligibility()
        eligibility.active = false
        let model = MealRecordModel(recordID: C11RecordFixtures.a, provider: provider,
            time: C11FixtureTime(), keys: C11FixtureKeys(), invalidation: FeatureInvalidationCenter(),
            isSessionActive: { eligibility.active })
        #expect(await model.load() == .notStarted)
        #expect(await provider.reads.isEmpty)
        #expect(model.detail == nil && model.readFailure == nil && !model.isLoading)
        eligibility.active = true
        #expect(await model.load() == .settled)
        // endSession clears recoveryID while the separate eligibility closure
        // stays true, so this covers the nil-ID guard independently.
        model.endSession()
        #expect(await model.load() == .notStarted)
        #expect(await provider.reads == [C11RecordFixtures.a])
        #expect(model.detail == nil && model.draft == nil && !model.isLoading)

        let busyProvider = C11DeferredProvider()
        let busyKeys = C11FixtureKeys()
        let busyModel = makeModel(busyProvider, keys: busyKeys)
        #expect(await busyModel.load() == .settled)
        let saving = Task { await busyModel.save(language: .portugueseBrazil) }
        await busyProvider.waitUntilPatchStarted()
        let attempt = busyModel.retainedAttempt
        #expect(busyModel.isSubmitting && attempt != nil)
        #expect(await busyModel.load() == .notStarted)
        #expect(busyModel.isSubmitting)
        #expect(busyModel.retainedAttempt == attempt)
        #expect(busyModel.detail == C11RecordFixtures.open)
        #expect(busyKeys.count == 1)
        await busyProvider.resolve()
        await saving.value
        #expect(busyModel.confirmedReceipt != nil)
        #expect(busyKeys.count == 1)
    }

    @Test("provider CancellationError without cancelling the parent never settles the automatic read")
    func presentationLoadOutcomeProviderCancellationDoesNotSettle() async {
        let provider = C11PresentationReadProvider(results: [.cancelled, .success])
        let keys = C11FixtureKeys()
        let model = makeModel(provider, keys: keys)
        #expect(!Task.isCancelled)
        #expect(await model.load() == .cancelled)
        #expect(!Task.isCancelled)
        #expect(model.detail == nil && model.draft == nil && model.readFailure == nil)
        #expect(!model.isLoading)
        #expect(await model.load() == .settled)
        #expect(model.detail == C11RecordFixtures.open && model.canStartMutation)
        #expect(await provider.reads == [C11RecordFixtures.a, C11RecordFixtures.a])
        #expect(keys.count == 0)
    }

    @Test("a held initial read cancelled on disappearance stays eligible for a fresh read")
    func presentationLoadOutcomeCancelledInitialReadCanReadAgain() async {
        let provider = C11PresentationReadProvider(results: [.success, .success], holdFirstRead: true)
        let keys = C11FixtureKeys()
        let model = makeModel(provider, keys: keys)
        let pending = Task {
            let outcome = await model.load()
            return (outcome, Task.isCancelled)
        }
        await provider.waitForHeldRead()
        pending.cancel()
        model.discardPresentation()
        // The provider deliberately ignores cancellation until released. Its
        // old result must not turn a cancelled appearance into a settled one.
        await provider.releaseHeldRead()
        let finished = await pending.value
        #expect(finished.0 == .cancelled && finished.1)
        #expect(model.detail == nil && model.draft == nil && model.readFailure == nil)
        #expect(!model.isLoading)
        model.beginPresentation()
        #expect(await model.load() == .settled)
        #expect(model.detail == C11RecordFixtures.open && model.canStartMutation)
        #expect(await provider.reads == [C11RecordFixtures.a, C11RecordFixtures.a])
        #expect(keys.count == 0)
    }

    @Test("a discarded held success or error cannot settle without publication even if the parent is not cancelled",
          arguments: [false, true])
    func presentationLoadOutcomeSupersededReadDoesNotSettle(returnsError: Bool) async {
        let provider = C11PresentationReadProvider(
            results: [returnsError ? .offline : .success, .success], holdFirstRead: true)
        let keys = C11FixtureKeys()
        let model = makeModel(provider, keys: keys)
        let pending = Task {
            let outcome = await model.load()
            return (outcome, Task.isCancelled)
        }
        await provider.waitForHeldRead()
        model.discardPresentation() // Invalidate actual Model publication, not the parent Task.
        await provider.releaseHeldRead()
        let finished = await pending.value
        #expect(finished.0 == .superseded && !finished.1)
        #expect(model.detail == nil && model.draft == nil && model.readFailure == nil)
        #expect(!model.isLoading)
        model.beginPresentation()
        #expect(await model.load() == .settled)
        #expect(model.detail == C11RecordFixtures.open && model.canStartMutation)
        #expect(await provider.reads == [C11RecordFixtures.a, C11RecordFixtures.a])
        #expect(keys.count == 0)
    }

    @Test("Restoring archived grams after409 and official review never reinterprets them as scoops or mL", arguments: ["whey", "leite"])
    func householdConflictRestoresOriginalInputUnit(_ name: String) async throws {
        let initial = try householdDetail(name: name, version: "household-v1")
        let service = MealRecordServiceStub(detail: initial)
        let keys = C11FixtureKeys()
        let model = makeModel(service, keys: keys)
        await service.failNextPatch(.versionChanged)
        await model.load()
        model.draft?.items[0].toggleQuantityUnit(language: .englishUnitedStates)
        model.draft?.items[0].setQuantityText("25", language: .englishUnitedStates)
        await model.save(language: .englishUnitedStates)
        await service.replaceDetail(try householdDetail(name: name, version: "household-v2"))
        await model.load()
        model.reviewLatest()
        #expect(model.canRestoreArchivedFields)
        model.restoreArchivedFields()
        let body = try #require(model.draft?.patchBody(language: .englishUnitedStates))
        #expect(body.expectedVersion == "household-v2")
        #expect(body.itemIDs == [C11RecordFixtures.a])
        #expect(body.items[0].quantityG == 25)
        #expect(model.draft?.items[0].quantityPresentation.unit == "g")
        await model.save(language: .englishUnitedStates)
        let patches = await service.calls.compactMap { call -> MutationAttempt<MealRecordPatchCommand>? in
            if case let .patch(attempt) = call { return attempt }; return nil
        }
        #expect(patches.count == 2)
        #expect(patches.last?.payload.body.items[0].quantityG == 25)
        #expect(keys.count == 2)
    }

    @Test("Restoring a typed reference after the official reference disappears blocks instead of reinterpreting grams")
    func householdConflictDoesNotRestoreIncompatibleReference() async throws {
        let service = MealRecordServiceStub(detail: try householdDetail(name: "whey", version: "household-v1"))
        let model = makeModel(service)
        await service.failNextPatch(.versionChanged)
        await model.load()
        model.draft?.items[0].setQuantityText("2", language: .englishUnitedStates)
        await model.save(language: .englishUnitedStates)
        await service.replaceDetail(try householdDetail(name: "whey", version: "household-v2", includeReference: false))
        await model.load()
        model.reviewLatest()
        model.restoreArchivedFields()
        #expect(model.draft?.expectedVersion == "household-v2")
        #expect(model.draft?.patchBody(language: .englishUnitedStates) == nil)
    }

    private func householdDetail(name: String, version: String, includeReference: Bool = true) throws -> MealRecordResponse {
        let reference = name == "whey"
            ? #"{"unit":"scoop","grams_per_unit":30,"reference_id":"app-household-whey-scoop-v1","estimated":true}"#
            : #"{"unit":"mL","grams_per_unit":1.03,"reference_id":"fao-infoods-v2-whole-milk-tb","estimated":true}"#
        var item = MealRecordItemSnapshot(id: C11RecordFixtures.a, foodName: name, quantityG: 30, kcal: 100,
            proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact", consumedAt: APITimestamp(value: C11RecordFixtures.date), mealType: nil)
        if includeReference { item.quantityDisplay = try JSONDecoder().decode(MealQuantityDisplay.self, from: Data(reference.utf8)) }
        return MealRecordResponse(data: MealRecordSnapshot(recordID: C11RecordFixtures.a, scope: .group,
            expectedVersion: version, itemIDs: [C11RecordFixtures.a], items: [item], editable: true, dayClosed: false,
            localDate: "2026-10-09", timezone: "America/Sao_Paulo", editBlockReason: nil), meta: C11RecordFixtures.meta)
    }

    private func makeModel(_ provider: any MealRecordProviding,
                           keys: C11FixtureKeys = C11FixtureKeys(),
                           center: FeatureInvalidationCenter = FeatureInvalidationCenter()) -> MealRecordModel {
        MealRecordModel(recordID: C11RecordFixtures.a, provider: provider,
            time: C11FixtureTime(), keys: keys, invalidation: center, isSessionActive: { true })
    }
}

private enum C11RecordFixtures {
    static let a = "11111111-1111-4111-8111-111111111111"
    static let b = "22222222-2222-4222-8222-222222222222"
    static let newID = "33333333-3333-4333-8333-333333333333"
    static let newSiblingID = "44444444-4444-4444-8444-444444444444"
    static let newThirdID = "55555555-5555-4555-8555-555555555555"
    static let date = Date(timeIntervalSince1970: 1_790_000_000)
    static let meta = MobileResponseMetadata(apiVersion: "v1", requestID: "c11-synthetic-unit")
    static let items = [
        MealRecordItemSnapshot(id: a, foodName: "Synthetic item A", quantityG: 50, kcal: 100,
            proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact", consumedAt: APITimestamp(value: date), mealType: nil),
        MealRecordItemSnapshot(id: b, foodName: "Synthetic item B", quantityG: 120, kcal: 70,
            proteinG: 4, carbsG: 5, fatG: 6, source: "user_kcal", consumedAt: APITimestamp(value: date), mealType: nil),
    ]
    static let open = MealRecordResponse(data: MealRecordSnapshot(recordID: a, scope: .group,
        expectedVersion: "opaque-fixture-version", itemIDs: [a, b], items: items,
        editable: true, dayClosed: false, localDate: "2026-10-09", timezone: "America/Sao_Paulo", editBlockReason: nil), meta: meta)
    static let closed = MealRecordResponse(data: MealRecordSnapshot(recordID: a, scope: .group,
        expectedVersion: "opaque-fixture-closed", itemIDs: [a, b], items: items,
        editable: false, dayClosed: true, localDate: "2026-10-08", timezone: "America/Sao_Paulo", editBlockReason: "MEAL_DAY_NOT_EDITABLE"), meta: meta)
    static let singleOpen = MealRecordResponse(data: MealRecordSnapshot(recordID: a, scope: .group,
        expectedVersion: "opaque-single-version", itemIDs: [a], items: [items[0]],
        editable: true, dayClosed: false, localDate: "2026-10-09", timezone: "America/Sao_Paulo",
        editBlockReason: nil), meta: meta)
    static let quantity85 = MealRecordResponse(data: MealRecordSnapshot(recordID: a, scope: .group,
        expectedVersion: "opaque-85g-version", itemIDs: [a, b], items: [
            MealRecordItemSnapshot(id: a, foodName: items[0].foodName, quantityG: 85, kcal: items[0].kcal,
                proteinG: items[0].proteinG, carbsG: items[0].carbsG, fatG: items[0].fatG,
                source: items[0].source, consumedAt: items[0].consumedAt, mealType: items[0].mealType),
            items[1],
        ], editable: true, dayClosed: false, localDate: "2026-10-09", timezone: "America/Sao_Paulo",
        editBlockReason: nil), meta: meta)
    static func receipt(_ operation: MealRecordMutationSnapshot.Operation,
                        removed: [String]? = nil) -> MealRecordMutationResponse {
        let selected = removed ?? (operation == .updated ? [a] : [a, b])
        let remaining = [a, b].filter { !selected.contains($0) }
        return MealRecordMutationResponse(data: MealRecordMutationSnapshot(recordID: a, operation: operation,
            newItemIDs: operation == .updated ? [newID, newSiblingID, newThirdID] : [],
            removedItemIDs: selected,
            nextRecordID: operation == .updated ? newSiblingID : remaining.first,
            snapshot: MealRecordPersistedSnapshot(id: "fixture-snapshot", date: "2026-10-09",
                caloriesConsumed: operation == .updated ? 123 : (remaining.isEmpty ? 0 : 70),
                proteinG: operation == .updated ? 3 : 0,
                carbsG: operation == .updated ? 4 : 0,
                fatG: operation == .updated ? 5 : 0, dailyBalance: 77)), meta: meta)
    }
}

private struct C11FixtureTime: TimeProviding { var now: Date { C11RecordFixtures.date } }
private final class C11FixtureKeys: IdempotencyKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0
    var count: Int { lock.withLock { issued } }
    func nextKey() throws -> IdempotencyKey {
        try lock.withLock { issued += 1; return try IdempotencyKey(validating: "c11-synthetic-key-\(issued)") }
    }
}

private actor MealRecordServiceStub: MealRecordProviding {
    enum Call: Equatable, Sendable {
        case get(String)
        case patch(MutationAttempt<MealRecordPatchCommand>)
        case delete(MutationAttempt<MealRecordDeleteCommand>)
    }
    private(set) var calls: [Call] = []
    private var detail: MealRecordResponse
    private let patchReceipt: MealRecordMutationResponse
    private var nextPatchFailure: MealRecordFailure?
    private var nextDeleteFailure: MealRecordFailure?
    private var readFails = false
    init(detail: MealRecordResponse = C11RecordFixtures.open,
         patchReceipt: MealRecordMutationResponse = C11RecordFixtures.receipt(.updated)) {
        self.detail = detail; self.patchReceipt = patchReceipt
    }
    func failNextPatch(_ value: MealRecordFailure) { nextPatchFailure = value }
    func failNextDelete(_ value: MealRecordFailure) { nextDeleteFailure = value }
    func failReads() { readFails = true }
    func replaceDetail(_ value: MealRecordResponse) { detail = value }
    func mealRecord(id: String) async throws -> MealRecordResponse {
        calls.append(.get(id))
        if readFails { throw MealRecordFailure.capability(.offline) }
        return detail
    }
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        calls.append(.patch(attempt))
        if let failure = nextPatchFailure { nextPatchFailure = nil; throw failure }
        return patchReceipt
    }
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        calls.append(.delete(attempt))
        if let failure = nextDeleteFailure { nextDeleteFailure = nil; throw failure }
        return C11RecordFixtures.receipt(.deleted, removed: attempt.payload.body.itemIDs)
    }
}

private actor C11DeferredProvider: MealRecordProviding {
    private var pending: CheckedContinuation<MealRecordMutationResponse, any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var patchCount = 0
    func mealRecord(id: String) async throws -> MealRecordResponse { C11RecordFixtures.open }
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        patchCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            let started = waiters; waiters.removeAll()
            for waiter in started { waiter.resume() }
        }
    }
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
    func waitUntilPatchStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func resolve() {
        let value = pending; pending = nil
        value?.resume(returning: C11RecordFixtures.receipt(.updated))
    }
}

private actor C11TransportStub: MobileAPIEnvelopeExecuting {
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }
    private(set) var requests: [Recorded] = []
    private var failure: MobileAPITransportError?
    func fail(_ value: MobileAPITransportError) { failure = value }
    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        requests.append(Recorded(method: request.method, path: request.path,
            body: request.body, idempotency: request.idempotency))
        if let failure { throw failure }
        let data: Data
        switch request.method {
        case .get: data = try JSONEncoder().encode(C11RecordFixtures.open)
        case .patch: data = try JSONEncoder().encode(C11RecordFixtures.receipt(.updated))
        case .delete:
            guard let body = request.body else { throw MobileAPITransportError.invalidResponse }
            let command = try JSONDecoder().decode(MealRecordDeleteBody.self, from: body)
            data = try JSONEncoder().encode(C11RecordFixtures.receipt(.deleted, removed: command.itemIDs))
        default: throw MobileAPITransportError.invalidResponse
        }
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: data)
    }
}

@MainActor
private final class C11PresentationReadEligibility {
    var active = true
}

/// Only the provider boundary is controlled; the actual Model owns admission,
/// publication, cancellation, drafts, read errors and command state.
private actor C11PresentationReadProvider: MealRecordProviding {
    enum Result: Sendable { case success, offline, cancelled }
    private var results: [Result]
    private let holdFirstRead: Bool
    private var heldRead: CheckedContinuation<Void, Never>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var reads: [String] = []

    init(results: [Result], holdFirstRead: Bool = false) {
        self.results = results
        self.holdFirstRead = holdFirstRead
    }

    func mealRecord(id: String) async throws -> MealRecordResponse {
        reads.append(id)
        let result = results.isEmpty ? .success : results.removeFirst()
        if holdFirstRead, reads.count == 1 {
            await withCheckedContinuation { continuation in
                heldRead = continuation
                let ready = startedWaiters
                startedWaiters.removeAll()
                for waiter in ready { waiter.resume() }
            }
        }
        switch result {
        case .success: return C11RecordFixtures.open
        case .offline: throw MealRecordFailure.capability(.offline)
        case .cancelled: throw CancellationError()
        }
    }

    func waitForHeldRead() async {
        if heldRead != nil { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func releaseHeldRead() {
        let held = heldRead
        heldRead = nil
        held?.resume()
    }

    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}
