import Foundation
import Testing
@testable import BodyFlow

// Exact missing-record presentation and unknown-command retry regressions.
// Review-action eligibility is covered separately from this presentation.
@MainActor
@Suite("C11 record availability and review eligibility")
struct MealRecordAvailabilityTests {
    enum MissingPath: String, Sendable { case deletedElsewhere, correctedElsewhere, conflictThenMissing }

    @Test("L2: an official missing-record read removes editable presentation, preserving the declined command",
          arguments: [MissingPath.deletedElsewhere, .correctedElsewhere, .conflictThenMissing])
    func missingReadAfterDefinitiveRefusalIsReadOnly(_ path: MissingPath) async throws {
        let server = C11L24Fixtures.server()
        let repository = MobileMealRecordRepository(transport: server)
        let keys = C11L24Keys()
        let center = FeatureInvalidationCenter()
        let model = C11L24Fixtures.model(C11L24Fixtures.a, provider: repository, keys: keys, center: center)
        await model.load()
        model.draft?.items[0].quantityText = "25"
        let typed = try #require(model.draft)
        let official = try #require(model.detail)

        if path == .conflictThenMissing {
            // B changes on the second synthetic device. A's old version then
            // refuses this Save with the real repository's typed HTTP409.
            let sibling = C11L24Fixtures.model(C11L24Fixtures.b, provider: repository, keys: C11L24Keys(prefix: "external-b"))
            await sibling.load()
            sibling.draft?.items[1].quantityText = "55"
            await sibling.save(language: .englishUnitedStates)
            try #require(sibling.confirmedReceipt != nil)
            await model.save(language: .englishUnitedStates)
            try #require(model.failure == .versionChanged)
            let external = C11L24Fixtures.model(C11L24Fixtures.a, provider: repository)
            await external.load()
            await external.delete()
            try #require(external.confirmedReceipt?.data.removedItemIDs == [C11L24Fixtures.a])
        } else {
            // The second model runs a genuine DELETE or PATCH against the
            // unchanged existing synthetic C11FakeMealServer/repository.
            let external = C11L24Fixtures.model(C11L24Fixtures.a, provider: repository)
            await external.load()
            if path == .correctedElsewhere {
                external.draft?.items[0].quantityText = "40"
                await external.save(language: .englishUnitedStates)
            } else {
                await external.delete()
            }
            try #require(external.confirmedReceipt?.data.removedItemIDs == [C11L24Fixtures.a])
            await model.save(language: .englishUnitedStates)
            try #require(model.failure == .notFound)
        }
        let attempt = try #require(model.retainedAttempt)
        let failure = try #require(model.failure)
        try #require(!failure.mayRetrySameAttempt)
        try #require(keys.count == 1)
        await model.load()
        try #require(model.readFailure == .notFound)
        let beforeDrawReads = await server.reads
        let beforeDrawMutations = await server.mutationCount
        let presentation = MealRecordDetailPresentation.make(model: model, localRow: C11L24Fixtures.localRow)
        if case let .readOnly(items) = presentation.content {
            #expect(items == official.data.items,
                    "Previously read official values remain historical/read-only; no fresh values are invented")
        } else {
            Issue.record("GET MEAL_RECORD_NOT_FOUND must not continue presenting the stale mutable form")
        }
        #expect(model.detail == official)
        #expect(model.draft == typed)
        #expect(model.retainedAttempt == attempt)
        #expect(model.failure == failure)
        #expect(model.attemptHistory == [attempt])
        #expect(model.confirmedReceipt == nil)
        #expect(!model.canStartMutation)
        #expect(!model.canEditDraft)
        model.reviewLatest()
        await model.save(language: .englishUnitedStates)
        await model.delete()
        await model.retry()
        #expect(model.draft == typed)
        #expect(model.retainedAttempt == attempt)
        #expect(keys.count == 1)
        #expect(await server.reads == beforeDrawReads)
        #expect(await server.mutationCount == beforeDrawMutations)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
    }

    @Test("L2 control: GET404 cannot discard an unknown committed command or its same-key retry")
    func missingReadDoesNotResolveAnUnknownCommand() async throws {
        let server = C11L24Fixtures.server()
        let repository = MobileMealRecordRepository(transport: server)
        let loss = C11L24LostReply(base: repository)
        let keys = C11L24Keys()
        let center = FeatureInvalidationCenter()
        let model = C11L24Fixtures.model(C11L24Fixtures.a, provider: loss, keys: keys, center: center)
        await model.load()
        model.draft?.items[0].quantityText = "25"
        let typed = try #require(model.draft)
        await model.save(language: .englishUnitedStates)
        try #require(model.failure == .interruptedUnknown)
        let attempt = try #require(model.retainedAttempt)
        try #require(await server.itemIDs.contains(C11L24Fixtures.new1))
        // The command committed to a replacement ID, but its response was lost.
        // The original record now answers the official missing-record code.
        await model.load()
        try #require(model.readFailure == .notFound)
        let presentation = MealRecordDetailPresentation.make(model: model, localRow: C11L24Fixtures.localRow)
        if case .form = presentation.content {} else {
            Issue.record("An unknown command must retain its explicit retry UI, not become terminal missing-record presentation")
        }
        #expect(model.retainedAttempt == attempt)
        #expect(model.draft == typed)
        #expect(model.failure == .interruptedUnknown)
        #expect(model.confirmedReceipt == nil)
        #expect(keys.count == 1)
        await model.retry()
        #expect(keys.count == 1)
        #expect(await server.mutationCount == 2)
        #expect(model.attemptHistory == [attempt])
        #expect(model.confirmedReceipt?.data.nextRecordID == C11L24Fixtures.new1)
        #expect(model.retainedAttempt == nil)
        #expect(center.revision(for: .today) == 1)
        #expect(center.revision(for: .history) == 1)
    }

}
