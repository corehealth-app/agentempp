import Foundation
import Testing

@testable import BodyFlow

@Suite("Plan View Model")
@MainActor
struct PlanViewModelTests {
    @Test("complete plan response becomes loaded content")
    func loaded() async throws {
        let response = try fixtureResponse()
        let model = PlanViewModel(provider: PlanQueueProvider([.success(response)]))

        await model.load()

        #expect(model.state == .loaded(response.data))
    }

    @Test("absence of both plan collections is a feature empty state")
    func empty() async throws {
        let response = try fixtureResponse(training: nil, nutrition: [])
        let model = PlanViewModel(provider: PlanQueueProvider([.success(response)]))

        await model.load()

        #expect(model.state == .empty)
    }

    @Test("offline refresh retains the complete prior plan")
    func staleOffline() async throws {
        let response = try fixtureResponse()
        let model = PlanViewModel(provider: PlanQueueProvider([
            .success(response),
            .failure(.offline),
        ]))

        await model.load()
        await model.retry()

        #expect(model.state == .offline(previousValue: response.data))
    }

    @Test("recoverable refresh retains the complete prior plan")
    func staleError() async throws {
        let response = try fixtureResponse()
        let model = PlanViewModel(provider: PlanQueueProvider([
            .success(response),
            .failure(.serviceUnavailable),
        ]))

        await model.load()
        await model.retry()

        #expect(model.state == .failed(
            previousValue: response.data,
            error: .serviceUnavailable
        ))
    }

    @Test("retry starts a new plan read after an initial failure")
    func retry() async throws {
        let response = try fixtureResponse()
        let provider = PlanQueueProvider([
            .failure(.serviceUnavailable),
            .success(response),
        ])
        let model = PlanViewModel(provider: provider)

        await model.load()
        await model.retry()

        #expect(model.state == .loaded(response.data))
        #expect(await provider.callCount == 2)
    }

    @Test("cancelled plan load does not publish its late snapshot")
    func cancellation() async throws {
        let response = try fixtureResponse()
        let provider = PlanControlledProvider()
        let model = PlanViewModel(provider: provider)

        let task = Task { await model.load() }
        await provider.waitUntilStarted(1)
        task.cancel()
        await provider.succeed(call: 1, with: response)
        await task.value

        #expect(model.state == .idle)
    }

    @Test("unavailable plan capability maps to the release unavailable state")
    func unavailable() async {
        let model = PlanViewModel(
            provider: PlanQueueProvider([.failure(.operationUnavailable)])
        )

        await model.load()

        #expect(model.state == .unavailable)
    }

    private func fixtureResponse(
        training: TrainingPlanSnapshot? = TrainingPlanSnapshot(
            id: "training-1",
            planType: "strength",
            daysPerWeek: 4,
            equipmentSummary: "Halteres e banco",
            generatedAt: APITimestamp(value: Date(timeIntervalSince1970: 1_784_589_300)),
            validUntil: APITimestamp(value: Date(timeIntervalSince1970: 1_787_151_600)),
            version: 3,
            notes: "Progressão semanal"
        ),
        nutrition: [NutritionPrescriptionSnapshot] = [
            NutritionPrescriptionSnapshot(
                id: "nutrition-1",
                type: "macro_targets",
                payload: .object(["misleading": .string("never render")]),
                generatedAt: APITimestamp(value: Date(timeIntervalSince1970: 1_784_589_300)),
                validUntil: nil,
                version: 2,
                notes: "Prescrição revisada"
            ),
        ]
    ) throws -> PlanResponse {
        PlanResponse(
            data: PlanSnapshot(training: training, nutrition: nutrition),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "plan-test")
        )
    }
}

private actor PlanQueueProvider: PlanProviding {
    enum Outcome: Sendable {
        case success(PlanResponse)
        case failure(BodyFlowCapabilityError)
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func plan() async throws -> PlanResponse {
        callCount += 1
        guard !outcomes.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        switch outcomes.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }
}

private actor PlanControlledProvider: PlanProviding {
    private var continuations: [Int: CheckedContinuation<PlanResponse, Error>] = [:]
    private var calls = 0

    func plan() async throws -> PlanResponse {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitUntilStarted(_ count: Int) async {
        while calls < count { await Task.yield() }
    }

    func succeed(call: Int, with response: PlanResponse) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }
}
