import Foundation
import Testing

@testable import BodyFlow

@Suite("Today Contract")
struct TodayContractTests {
    @Test("official daily values remain exactly as received")
    func preservesOfficialDailyValues() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.data.targets.caloriesKcal == 1_935)
        #expect(response.data.consumed.caloriesKcal == 1_200)
        #expect(response.data.remainingFoodKcal == 731)
        #expect(response.data.foodExcessKcal == 17)
        #expect(response.data.exerciseKcal == 419)
        #expect(response.data.dailyBalanceKcal == -83)
        #expect(response.data.dailyBalanceStatus == "provisional")
    }

    @Test("envelope and extensible source decode their exact server keys")
    func decodesEnvelopeAndExtensibleSource() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.meta.apiVersion == "v1")
        #expect(response.meta.requestID == "request-today-contract-0001")
        #expect(response.data.localDate == "2026-07-20")
        #expect(response.data.calculationVersion == "bodyflow.daily-state.v2")
        #expect(response.data.meals[0].nutritionSource == "future_catalog_v99")
    }

    @Test("nullable targets and hydration without target remain absent")
    func preservesNullableTargetsAndHydration() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.data.targets.proteinG == nil)
        #expect(response.data.targets.proteinSource == nil)
        #expect(response.data.proteinStatus.targetG == nil)
        #expect(response.data.proteinStatus.remainingG == nil)
        #expect(response.data.proteinStatus.percentage == nil)
        #expect(response.data.hydration.consumedML == 1_250)
        #expect(response.data.hydration.targetML == nil)
        #expect(response.data.hydration.remainingML == nil)
        #expect(response.data.hydration.percentage == nil)
        #expect(response.data.hydration.status == "tracked_without_target")
    }

    @Test("nullable calorie target and source remain absent")
    func preservesNullableCalorieTargetAndSource() throws {
        let response = try BodyFlowTestFixtures
            .decodeTodayWithoutCalorieTarget()

        #expect(response.data.targets.caloriesKcal == nil)
        #expect(response.data.targets.caloriesSource == nil)
    }

    @Test("server row and occurrence order is preserved")
    func preservesResponseOrder() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.data.meals.map(\.id) == ["meal-z", "meal-a"])
        #expect(response.data.workouts.map(\.id) == ["workout-z", "workout-a"])
        #expect(
            response.data.supplements.items[0].schedules.map(\.id)
                == ["rule-20", "rule-08"]
        )
        #expect(
            response.data.supplements.items[0].occurrences
                .map(\.reminderRuleID) == ["rule-20", "rule-08"]
        )
        #expect(
            response.data.pendingActions.registrations.map(\.id)
                == ["pending-z", "pending-a"]
        )
    }

    @Test("completion pending actions and source metadata remain server-authored")
    func decodesCompletionPendingActionsAndSources() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.data.completionStatus.status == "pending_information")
        #expect(!response.data.completionStatus.dayClosed)
        #expect(response.data.completionStatus.hasSufficientData == nil)
        #expect(response.data.pendingActions.registrations[1].mealType == nil)
        #expect(response.data.pendingActions.mealGaps.open == ["jantar"])
        #expect(response.data.pendingActions.mealGaps.activeDays == 10)
        #expect(response.data.sources.targets == "daily_snapshot")
        #expect(response.data.sources.hydrationTarget == "unavailable")
        #expect(response.data.sources.block7700 == "user_progress")
    }

    @Test("optional server block decodes without a local replacement")
    func preservesOptionalBlock() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()
        let responseWithoutBlock = try BodyFlowTestFixtures
            .decodeTodayWithoutOptionalBlock()

        #expect(response.data.block7700?.currentKcal == 2_500)
        #expect(response.data.block7700?.totalCreditedKcal == 10_200)
        #expect(responseWithoutBlock.data.block7700 == nil)
    }

    @Test("provider exposes the shared Today response")
    func providerReturnsTodayResponse() async throws {
        let expected = try BodyFlowTestFixtures.decodeInconsistentToday()
        let provider: any TodayProviding = TodayProviderStub(response: expected)

        #expect(try await provider.today() == expected)
    }
}

private struct TodayProviderStub: TodayProviding {
    let response: TodayResponse

    func today() async throws -> TodayResponse {
        response
    }
}
