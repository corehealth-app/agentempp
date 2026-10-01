import Foundation
import Testing

@testable import BodyFlow

@Suite("Progress View Model")
@MainActor
struct ProgressViewModelTests {
    @Test("unsupported demo weight leaves legacy presentation intact; live null profile stays empty")
    func unsupportedAndEmptyProfile() async {
        let demo = ProgressViewModel(provider: ProgressQueueProvider([.success(BodyFlowTestFixtures.progressResponse)]))
        await demo.load()
        #expect(demo.profileWeight.state == nil)
        let provider = ControlledProfileWeightProvider()
        let model = ProfileWeightViewModel(provider: provider)
        let load = Task { await model.load() }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: ProfileWeightResponse(
            data: nil, meta: BodyFlowTestFixtures.progressResponse.meta
        ))
        await load.value
        #expect(model.state == .empty)
    }

    @Test("profile errors preserve official prior measurement; canceled and superseded loads cannot replace it")
    func profileLifetimeAndErrors() async {
        let provider = ControlledProfileWeightProvider()
        let model = ProfileWeightViewModel(provider: provider)
        let profile = ProfileWeightSnapshot(weightKG: 80, measuredAt: nil, instantSource: nil)
        let response = ProfileWeightResponse(data: profile, meta: BodyFlowTestFixtures.progressResponse.meta)
        let initial = Task { await model.load() }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: response)
        await initial.value
        let offline = Task { await model.load() }
        await provider.waitUntilStarted(2)
        await provider.fail(call: 2, with: .offline)
        await offline.value
        #expect(model.state == .offline(previousValue: profile))
        let cancelled = Task { await model.load() }
        await provider.waitUntilStarted(3)
        cancelled.cancel()
        await provider.succeed(call: 3, with: ProfileWeightResponse(
            data: ProfileWeightSnapshot(weightKG: 999, measuredAt: nil, instantSource: nil), meta: response.meta
        ))
        await cancelled.value
        #expect(model.state == .offline(previousValue: profile))
        let older = Task { await model.load() }
        await provider.waitUntilStarted(4)
        let newer = Task { await model.load() }
        await provider.waitUntilStarted(5)
        await provider.succeed(call: 5, with: response)
        await newer.value
        await provider.fail(call: 4, with: .serviceUnavailable)
        await older.value
        #expect(model.state == .loaded(profile))
    }

    @Test("physical QA A recorded 80 kg at 2026-10-01T16:15:33.319Z while progress weight is null")
    func physicalWeightReadsOfficialProfile() async throws {
        let profile = try JSONDecoder().decode(ProfileWeightSnapshot.self, from: Data(
            #"{"weight_kg":80,"weight_measured_at":"2026-10-01T16:15:33.319Z","weight_instant_source":"measured"}"#.utf8
        ))
        let progress = ProgressSnapshot(
            xpTotal: 0, level: 1, currentStreak: 0, longestStreak: 0,
            blocksCompleted: 0, deficitBlock: 0, currentWeight: nil,
            currentBodyFatPercent: nil, badgesEarned: [], lastActiveDate: nil,
            nextReevaluation: nil, updatedAt: BodyFlowTestFixtures.progressSnapshot.updatedAt
        )
        let provider = ProfileWeightProgressProvider(progress: progress, profile: profile)
        let model = ProgressViewModel(provider: provider)
        await model.load()

        #expect(model.profileWeight.state == .loaded(profile))
        #expect(await provider.profileCalls == 1)
        // Reading the official weight must not rewrite the old progress DTO.
        #expect(model.state == .loaded(progress))
        #expect(progress.currentWeight == nil)
    }

    @Test("complete progress response becomes loaded content")
    func loaded() async {
        let model = ProgressViewModel(
            provider: ProgressQueueProvider([.success(BodyFlowTestFixtures.progressResponse)])
        )

        await model.load()

        #expect(model.state == .loaded(BodyFlowTestFixtures.progressSnapshot))
    }

    @Test("only a null progress payload is the feature empty state")
    func empty() async {
        let model = ProgressViewModel(
            provider: ProgressQueueProvider([
                .success(BodyFlowTestFixtures.emptyProgressResponse),
            ])
        )

        await model.load()

        #expect(model.state == .empty)
    }

    @Test("minimum persisted progress remains loaded official data")
    func minimumProgressIsLoaded() async {
        let snapshot = ProgressSnapshot(
            xpTotal: 0, level: 1, currentStreak: 0, longestStreak: 0,
            blocksCompleted: 0, deficitBlock: 0, currentWeight: nil,
            currentBodyFatPercent: nil, badgesEarned: [], lastActiveDate: nil,
            nextReevaluation: nil,
            updatedAt: BodyFlowTestFixtures.progressSnapshot.updatedAt
        )
        let response = ProgressResponse(
            data: snapshot,
            meta: BodyFlowTestFixtures.progressResponse.meta
        )
        let model = ProgressViewModel(
            provider: ProgressQueueProvider([.success(response)])
        )

        await model.load()

        #expect(model.state == .loaded(snapshot))
    }

    @Test("offline and recoverable failures retain exactly the received snapshot")
    func staleStates() async {
        let provider = ProgressQueueProvider([
            .success(BodyFlowTestFixtures.progressResponse), .failure(.offline),
            .failure(.serviceUnavailable),
        ])
        let model = ProgressViewModel(provider: provider)

        await model.load()
        await model.retry()
        #expect(model.state == .offline(previousValue: BodyFlowTestFixtures.progressSnapshot))

        await model.retry()
        #expect(model.state == .failed(
            previousValue: BodyFlowTestFixtures.progressSnapshot,
            error: .serviceUnavailable
        ))
    }

    @Test("initial capability outcomes map to every non-content read state")
    func initialStates() async {
        let offline = ProgressViewModel(provider: ProgressQueueProvider([.failure(.offline)]))
        await offline.load()
        #expect(offline.state == .offline(previousValue: nil))

        let failed = ProgressViewModel(provider: ProgressQueueProvider([.failure(.serviceUnavailable)]))
        await failed.load()
        #expect(failed.state == .failed(previousValue: nil, error: .serviceUnavailable))

        let unavailable = ProgressViewModel(provider: ProgressQueueProvider([.failure(.operationUnavailable)]))
        await unavailable.load()
        #expect(unavailable.state == .unavailable)
    }

    @Test("cancelled progress load cannot publish its late response or error")
    func cancellation() async {
        let provider = ProgressControlledProvider()
        let model = ProgressViewModel(provider: provider)

        let load = Task { await model.load() }
        await provider.waitUntilStarted(1)
        load.cancel()
        await provider.succeed(call: 1, with: BodyFlowTestFixtures.progressResponse)
        await load.value
        #expect(model.state == .idle)
    }

    @Test("newer progress load suppresses late results and errors")
    func supersession() async {
        let provider = ProgressControlledProvider()
        let model = ProgressViewModel(provider: provider)

        let older = Task { await model.load() }
        await provider.waitUntilStarted(1)
        let newer = Task { await model.load() }
        await provider.waitUntilStarted(2)
        await provider.succeed(call: 2, with: BodyFlowTestFixtures.progressResponse)
        await newer.value
        await provider.fail(call: 1, with: .serviceUnavailable)
        await older.value

        #expect(model.state == .loaded(BodyFlowTestFixtures.progressSnapshot))
    }
}

private actor ProfileWeightProgressProvider: ProgressProviding {
    let progressSnapshot: ProgressSnapshot
    let profile: ProfileWeightSnapshot
    private(set) var profileCalls = 0
    init(progress: ProgressSnapshot, profile: ProfileWeightSnapshot) {
        progressSnapshot = progress
        self.profile = profile
    }
    func progress() async throws -> ProgressResponse {
        ProgressResponse(data: progressSnapshot, meta: BodyFlowTestFixtures.progressResponse.meta)
    }
    func profileWeight() async throws -> ProfileWeightResponse? {
        profileCalls += 1
        return ProfileWeightResponse(data: profile, meta: BodyFlowTestFixtures.progressResponse.meta)
    }
}

private actor ProgressQueueProvider: ProgressProviding {
    enum Outcome: Sendable { case success(ProgressResponse), failure(BodyFlowCapabilityError) }
    private var outcomes: [Outcome]
    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }
    func progress() async throws -> ProgressResponse {
        guard !outcomes.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
        switch outcomes.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }
}

private actor ProgressControlledProvider: ProgressProviding {
    private var calls = 0
    private var continuations: [Int: CheckedContinuation<ProgressResponse, Error>] = [:]
    func progress() async throws -> ProgressResponse {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { continuations[call] = $0 }
    }
    func waitUntilStarted(_ count: Int) async { while calls < count { await Task.yield() } }
    func succeed(call: Int, with response: ProgressResponse) { continuations.removeValue(forKey: call)?.resume(returning: response) }
    func fail(call: Int, with error: BodyFlowCapabilityError) { continuations.removeValue(forKey: call)?.resume(throwing: error) }
}


private actor ControlledProfileWeightProvider: ProgressProviding {
    private var calls = 0
    private var continuations: [Int: CheckedContinuation<ProfileWeightResponse?, Error>] = [:]
    func progress() async throws -> ProgressResponse { BodyFlowTestFixtures.progressResponse }
    func profileWeight() async throws -> ProfileWeightResponse? {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { continuations[call] = $0 }
    }
    func waitUntilStarted(_ count: Int) async { while calls < count { await Task.yield() } }
    func succeed(call: Int, with response: ProfileWeightResponse) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }
    func fail(call: Int, with error: BodyFlowCapabilityError) {
        continuations.removeValue(forKey: call)?.resume(throwing: error)
    }
}
