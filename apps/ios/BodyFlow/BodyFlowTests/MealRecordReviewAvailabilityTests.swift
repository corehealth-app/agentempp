import Foundation
import Testing
@testable import BodyFlow

// Characterizes the existing command guard and its effect on the real model.
// Button availability requires separate verification of the actual view.
@MainActor
@Suite("C11 review eligibility characterization")
struct MealRecordReviewAvailabilityTests {
    @Test("L4 characterization: review eligibility matches the actual guarded action across failed and successful GET")
    func reviewEligibilityRequiresAnOfficialReadAfterTheDefinitiveAttempt() async throws {
        let server = C11L24Fixtures.server()
        let repository = MobileMealRecordRepository(transport: server)
        let reads = C11L24ReadControl(base: repository)
        let keys = C11L24Keys()
        let model = C11L24Fixtures.model(C11L24Fixtures.a, provider: reads, keys: keys)
        await model.load()
        model.draft?.items[0].quantityText = "25"
        let typed = try #require(model.draft)
        let sibling = C11L24Fixtures.model(C11L24Fixtures.b, provider: repository, keys: C11L24Keys(prefix: "external-b"))
        await sibling.load()
        sibling.draft?.items[1].quantityText = "55"
        await sibling.save(language: .englishUnitedStates)
        try #require(sibling.confirmedReceipt != nil)
        await model.save(language: .englishUnitedStates)
        try #require(model.failure == .versionChanged)
        let attempt = try #require(model.retainedAttempt)
        #expect(!model.canReviewLatest)
        model.reviewLatest()
        #expect(model.draft == typed)
        #expect(model.retainedAttempt == attempt)
        await reads.failNextRead(.capability(.offline))
        await model.load()
        try #require(model.readFailure == .capability(.offline))
        #expect(!model.canReviewLatest)
        model.reviewLatest()
        #expect(model.draft == typed)
        #expect(model.retainedAttempt == attempt)
        await model.load()
        try #require(model.readFailure == nil)
        try #require(model.detail?.data.expectedVersion != typed.expectedVersion)
        #expect(model.canReviewLatest)
        // Preserve the existing guard's semantics: a later failed GET does not
        // invalidate the successful post-attempt official read already held.
        await reads.failNextRead(.capability(.offline))
        await model.load()
        try #require(model.readFailure == .capability(.offline))
        #expect(model.canReviewLatest)
        let current = try #require(model.detail)
        let mutations = await server.mutationCount
        model.reviewLatest()
        #expect(model.draft?.expectedVersion == current.data.expectedVersion)
        #expect(model.archivedDraft == typed)
        #expect(model.retainedAttempt == nil)
        #expect(model.failure == nil)
        #expect(keys.count == 1)
        #expect(await server.mutationCount == mutations)
    }
}
