import Testing

@testable import BodyFlow

@Suite("7,700 Block Presentation")
@MainActor
struct Block7700PresentationTests {
    @Test("block detail uses only the Today block")
    func blockUsesTodayOnly() async {
        let provider = TodayQueueProvider([.success(BodyFlowTestFixtures.todayResponseWithBlock)])
        let model = Block7700ViewModel(today: provider)

        await model.load()

        #expect(model.descriptor?.targetKcal == 7_700)
        #expect(model.descriptor?.currentKcal == 2_500)
        #expect(model.descriptor?.percentage == 32)
        #expect(model.descriptor?.completedBlocks == 1)
        #expect(model.descriptor?.totalCreditedKcal == 10_200)
        #expect(model.descriptor?.source == "today-user-progress-snapshot")
        #expect(model.descriptor?.currentKcal != BodyFlowTestFixtures.progressSnapshot.deficitBlock)
    }

    @Test("block descriptor formats Today calories with the Portuguese locale")
    func formatsTodayValues() {
        let descriptor = Block7700Descriptor(block: BodyFlowTestFixtures.todayBlock)

        #expect(descriptor.targetText == "7.700 kcal")
        #expect(descriptor.currentText == "2.500 kcal")
        #expect(descriptor.creditedText == "10.200 kcal")
    }

    @Test("absent Today block is unavailable with no reconstructed zero descriptor")
    func unavailableBlock() async {
        let model = Block7700ViewModel(
            today: TodayQueueProvider([.success(BodyFlowTestFixtures.todayResponseWithoutBlock)])
        )

        await model.load()

        #expect(model.state == .unavailable)
        #expect(model.descriptor == nil)
    }

    @Test("offline retry retains the loaded block and marks its detail stale")
    func staleOfflineDetail() async {
        let provider = TodayQueueProvider([
            .success(BodyFlowTestFixtures.todayResponseWithBlock),
            .failure(.offline),
        ])
        let model = Block7700ViewModel(today: provider)

        await model.load()
        await model.retry()

        let presentation = Block7700DetailPresentation(state: model.state)
        #expect(model.state == .offline(previousValue: Block7700Descriptor(
            block: BodyFlowTestFixtures.todayBlock
        )))
        #expect(presentation.descriptor?.source == "today-user-progress-snapshot")
        #expect(presentation.showsStaleBanner)
        #expect(await provider.callCount == 2)
    }

    @Test("recoverable retry retains the loaded block and marks its detail stale")
    func staleRecoverableErrorDetail() async {
        let provider = TodayQueueProvider([
            .success(BodyFlowTestFixtures.todayResponseWithBlock),
            .failure(.serviceUnavailable),
        ])
        let model = Block7700ViewModel(today: provider)

        await model.load()
        await model.retry()

        let presentation = Block7700DetailPresentation(state: model.state)
        #expect(model.state == .failed(
            previousValue: Block7700Descriptor(block: BodyFlowTestFixtures.todayBlock),
            error: .serviceUnavailable
        ))
        #expect(presentation.descriptor?.currentText == "2.500 kcal")
        #expect(presentation.showsStaleBanner)
        #expect(await provider.callCount == 2)
    }

    @Test("only retained stale block details offer an inline retry")
    func staleDetailRetryPresentation() {
        let descriptor = Block7700Descriptor(block: BodyFlowTestFixtures.todayBlock)
        let staleOffline = Block7700DetailPresentation(
            state: .offline(previousValue: descriptor)
        )
        let staleError = Block7700DetailPresentation(
            state: .failed(
                previousValue: descriptor,
                error: .serviceUnavailable
            )
        )

        #expect(staleOffline.showsStaleBanner)
        #expect(staleOffline.showsRetry)
        #expect(staleError.showsStaleBanner)
        #expect(staleError.showsRetry)
        #expect(!Block7700DetailPresentation(state: .loaded(descriptor)).showsRetry)
        #expect(!Block7700DetailPresentation(
            state: .offline(previousValue: nil)
        ).showsRetry)
        #expect(!Block7700DetailPresentation(state: .unavailable).showsRetry)
    }

    @Test("cancelled or superseded block reads cannot publish a late block or error")
    func latePublicationIsSuppressed() async {
        let provider = TodayControlledProvider()
        let model = Block7700ViewModel(today: provider)

        let older = Task { await model.load() }
        await provider.waitUntilStarted(1)
        let newer = Task { await model.load() }
        await provider.waitUntilStarted(2)
        await provider.succeed(call: 2, with: BodyFlowTestFixtures.todayResponseWithBlock)
        await newer.value
        await provider.fail(call: 1, with: .serviceUnavailable)
        await older.value

        #expect(model.descriptor?.source == "today-user-progress-snapshot")
    }
}

private actor TodayQueueProvider: TodayProviding {
    enum Outcome: Sendable { case success(TodayResponse), failure(BodyFlowCapabilityError) }
    private var outcomes: [Outcome]
    private(set) var callCount = 0
    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }
    func today() async throws -> TodayResponse {
        callCount += 1
        guard !outcomes.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
        switch outcomes.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }
}

private actor TodayControlledProvider: TodayProviding {
    private var calls = 0
    private var continuations: [Int: CheckedContinuation<TodayResponse, Error>] = [:]
    func today() async throws -> TodayResponse {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { continuations[call] = $0 }
    }
    func waitUntilStarted(_ count: Int) async { while calls < count { await Task.yield() } }
    func succeed(call: Int, with response: TodayResponse) { continuations.removeValue(forKey: call)?.resume(returning: response) }
    func fail(call: Int, with error: BodyFlowCapabilityError) { continuations.removeValue(forKey: call)?.resume(throwing: error) }
}
