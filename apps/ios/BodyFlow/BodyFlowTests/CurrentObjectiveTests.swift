import Foundation
import Testing

@testable import BodyFlow

@Suite("Current objective — read only")
struct CurrentObjectiveTests {
    @Test("A pending first-phase choice is visible even without targets")
    func pendingPhaseIsNotAnEmptyScreen() throws {
        let policy = try JSONDecoder().decode(CurrentClinicalPolicy.self,
            from: Data(CurrentClinicalPolicyTests.policy.utf8))
        let snapshot = CurrentObjectiveSnapshot(currentProtocol: nil, targets: nil, welcome: nil, clinicalPolicy: policy)
        #expect(!snapshot.isEmpty)
    }
    @Test(arguments: SupportedAppLanguage.allCases)
    func frameIsLocalizedAndClosingIsDifferentFromOnboarding(_ language: SupportedAppLanguage) throws {
        #expect(try AppLocalization.string("current-objective.title", for: language) ==
            (language == .portugueseBrazil ? "Seu objetivo" : "Your objective"))
        #expect(try AppLocalization.string("current-objective.welcome.close", for: language) ==
            (language == .portugueseBrazil ? "Fechar" : "Close"))
        #expect(try AppLocalization.string("current-objective.refreshing", for: language) ==
            (language == .portugueseBrazil ? "Atualizando…" : "Refreshing…"))
    }
    @Test("GET keeps server numbers and paragraphs without submitting patient data")
    func readsExactContract() async throws {
        let transport = ObjectiveTransport(payload: Data(#"{"current_protocol":"manutencao","targets":{"calories":2123.45,"protein_g":123.45},"welcome":{"protocol":"manutencao","paragraphs":["First\nsecond line","Repeated","Repeated"]}}"#.utf8))
        let snapshot = try await MobileCurrentObjectiveRepository(transport: transport).currentObjective()
        #expect(snapshot.currentProtocol == .maintenance)
        #expect(snapshot.targets?.calories == Decimal(string: "2123.45"))
        #expect(snapshot.targets?.proteinG == Decimal(string: "123.45"))
        #expect(snapshot.welcome?.paragraphs == ["First\nsecond line", "Repeated", "Repeated"])
        let request = try #require(await transport.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/protocol")
        #expect(request.body == nil)
        #expect(request.queryItems.isEmpty)
        #expect(request.idempotency == .notRequired)
    }

    @Test(arguments: [
        #"{"current_protocol":null,"targets":null,"welcome":null}"#,
        #"{"current_protocol":null,"targets":{"calories":null,"protein_g":null},"welcome":null}"#,
    ])
    func missingNumbersAreNotFabricated(_ json: String) async throws {
        let result = try await MobileCurrentObjectiveRepository(transport: ObjectiveTransport(payload: Data(json.utf8))).currentObjective()
        #expect(result.currentProtocol == nil)
        #expect(result.targets?.calories == nil)
        #expect(result.targets?.proteinG == nil)
        #expect(result.welcome == nil)
    }

    @Test(arguments: [
        #"{"current_protocol":"unexpected","targets":null,"welcome":null}"#,
        #"{"current_protocol":"manutencao","targets":null,"welcome":{"protocol":"ganho_massa","paragraphs":["Wrong owner objective"]}}"#,
        #"{"current_protocol":null,"targets":null,"welcome":{"protocol":"manutencao","paragraphs":["Orphan welcome"]}}"#,
    ])
    func malformedProtocolFailsClosed(_ json: String) async {
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await MobileCurrentObjectiveRepository(transport: ObjectiveTransport(payload: Data(json.utf8))).currentObjective()
        }
    }

    @Test(arguments: [
        ObjectiveFailureCase(transport: .network, expected: .offline),
        ObjectiveFailureCase(transport: .http(status: 402, code: "subscription_required", requestID: nil), expected: .subscriptionRequired),
        ObjectiveFailureCase(transport: .server(status: 500, code: "data_access_failed", requestID: nil), expected: .serviceUnavailable),
    ])
    func mapsReadFailures(_ item: ObjectiveFailureCase) async {
        await #expect(throws: item.expected) {
            try await MobileCurrentObjectiveRepository(transport: ObjectiveTransport(error: item.transport)).currentObjective()
        }
    }

    @Test func cancellationIsNotPresentedAsServerFailure() async {
        await #expect(throws: CancellationError.self) {
            try await MobileCurrentObjectiveRepository(transport: ObjectiveTransport(cancel: true)).currentObjective()
        }
    }

    @MainActor @Test("refresh preserves snapshot; duplicate call does not start another read")
    func refreshPreservesDataAndCoalesces() async {
        let source = ObjectiveReadGate()
        let model = CurrentObjectiveModel(userID: "synthetic-A", provider: source)
        let first = Task { await model.load() }
        await source.waitForCalls(1)
        await source.finish(.success(Self.snapshot))
        await first.value
        #expect(model.state.presentation.value?.currentProtocol == .maintenance)
        let refresh = Task { await model.load() }
        await source.waitForCalls(2)
        #expect(model.isLoading)
        #expect(model.state.presentation.value?.targets?.calories == Decimal(string: "2123.45"))
        await model.load()
        #expect(await source.calls == 2)
        await source.finish(.failure(.offline))
        await refresh.value
        #expect(!model.isLoading)
        #expect(model.state.presentation.showsStaleBanner)
        #expect(model.state.presentation.value?.welcome?.paragraphs == ["Server message"])
        let retry = Task { await model.load() }
        await source.waitForCalls(3)
        await source.finish(.success(Self.snapshot))
        await retry.value
        #expect(!model.state.presentation.showsStaleBanner)
    }

    @MainActor @Test("late A never fills B or a new A, and invalidated model cannot read again")
    func lateResponseDoesNotSurviveSession() async {
        let oldSource = ObjectiveReadGate()
        let oldA = CurrentObjectiveModel(userID: "synthetic-A", provider: oldSource)
        let pending = Task { await oldA.load() }
        await oldSource.waitForCalls(1)
        oldA.invalidate()
        let b = CurrentObjectiveModel(userID: "synthetic-B", provider: FixedObjectiveProvider(snapshot: .init(currentProtocol: .muscleGain, targets: nil, welcome: nil)))
        await b.load()
        b.invalidate()
        let newA = CurrentObjectiveModel(userID: "synthetic-A", provider: FixedObjectiveProvider(snapshot: .init(currentProtocol: .bodyRecomposition, targets: nil, welcome: nil)))
        await newA.load()
        await oldSource.finish(.success(Self.snapshot))
        await pending.value
        await oldA.load()
        #expect(await oldSource.calls == 1)
        #expect(oldA.state == .idle)
        #expect(b.state == .idle)
        #expect(newA.state.presentation.value?.currentProtocol == .bodyRecomposition)
    }

    @MainActor @Test("a cancelled caller cannot publish its late success or overwrite a newer read")
    func cancellationPreservesNextRead() async {
        let source = ObjectiveReadGate()
        let model = CurrentObjectiveModel(userID: "synthetic-A", provider: source)
        let old = Task { await model.load() }
        await source.waitForCalls(1)
        old.cancel()
        model.cancelRead()
        let next = Task { await model.load() }
        await source.waitForCalls(2)
        await source.finish(.success(Self.snapshot), at: 1)
        await next.value
        await source.finish(.failure(.serviceUnavailable), at: 0)
        await old.value
        #expect(model.state.presentation.value?.currentProtocol == .maintenance)
        #expect(!model.state.presentation.showsStaleBanner)
        #expect(!model.isLoading)
    }

    @MainActor @Test func absentObjectiveWithOfficialTargetsKeepsTargets() async {
        let model = CurrentObjectiveModel(userID: "synthetic-A", provider: FixedObjectiveProvider(snapshot: .init(currentProtocol: nil, targets: .init(calories: 1800, proteinG: nil), welcome: nil)))
        await model.load()
        #expect(model.state.presentation.value?.currentProtocol == nil)
        #expect(model.state.presentation.value?.targets?.calories == 1800)
    }

    @MainActor @Test func providerCannotReplaceAnObjectiveWithAnotherWelcome() async {
        let model = CurrentObjectiveModel(userID: "synthetic-A", provider: FixedObjectiveProvider(snapshot:
            .init(currentProtocol: .maintenance, targets: nil,
                welcome: .init(protocol: .muscleGain, paragraphs: ["Not this objective"]))
        ))
        await model.load()
        #expect(model.state == .failed(previousValue: nil, error: .serviceUnavailable))
    }

    @MainActor @Test func emptyReadAndFirstErrorCanRetry() async {
        let source = ObjectiveReadGate()
        let model = CurrentObjectiveModel(userID: "synthetic-A", provider: source)
        let first = Task { await model.load() }
        await source.waitForCalls(1)
        await source.finish(.failure(.offline))
        await first.value
        #expect(model.state == .offline(previousValue: nil))
        let retry = Task { await model.load() }
        await source.waitForCalls(2)
        await source.finish(.success(.init(currentProtocol: nil, targets: nil, welcome: nil)))
        await retry.value
        #expect(model.state == .empty)
    }

    @Test("Release ignores all synthetic objective scenarios")
    func releaseNeverInstallsSyntheticProvider() throws {
        let args = ["--ui-testing", "--ui-testing-current-objective", "--ui-testing-current-objective-empty", "--ui-testing-current-objective-offline", "--ui-testing-current-objective-long"]
        let config = AppLaunchConfiguration.resolve(arguments: args, buildFlavor: .release)
        let unavailable = AppDependencies.make(configuration: config)
        #expect(unavailable.currentObjective == nil)
        let real = AppDependencies.make(configuration: config,
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(configuration: try MobileAPIConfiguration(originString: "https://staging.example.test")),
            sessionTokenProvider: ObjectiveSessionToken())
        #expect(real.currentObjective is MobileCurrentObjectiveRepository)
        #expect(!(real.currentObjective is DemoCurrentObjectiveProvider))
        #expect(AppRoute.currentObjective.tab == .profile)
    }

    private static let snapshot = CurrentObjectiveSnapshot(currentProtocol: .maintenance,
        targets: .init(calories: Decimal(string: "2123.45"), proteinG: Decimal(string: "123.45")),
        welcome: .init(protocol: .maintenance, paragraphs: ["Server message"]))
}

struct ObjectiveFailureCase: Sendable {
    let transport: MobileAPITransportError
    let expected: BodyFlowCapabilityError
}
private struct ObjectiveSessionToken: SessionTokenProviding {
    func currentBearerToken() async -> String? { "synthetic-local-token" }
}
private struct ObjectiveRecordedRequest: Sendable {
    let method: HTTPMethod
    let path: String
    let body: Data?
    let queryItems: [URLQueryItem]
    let idempotency: MobileAPIIdempotency
}
private actor ObjectiveTransport: MobileAPIExecuting {
    let payload: Data
    let error: MobileAPITransportError?
    let cancel: Bool
    private(set) var requests: [ObjectiveRecordedRequest] = []
    init(payload: Data = Data(), error: MobileAPITransportError? = nil, cancel: Bool = false) {
        self.payload = payload; self.error = error; self.cancel = cancel
    }
    func execute<Response: Decodable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> Response {
        requests.append(.init(method: request.method, path: request.path, body: request.body, queryItems: request.queryItems, idempotency: request.idempotency))
        if cancel { throw CancellationError() }
        if let error { throw error }
        return try JSONDecoder().decode(Response.self, from: payload)
    }
}
private struct FixedObjectiveProvider: CurrentObjectiveProviding {
    let snapshot: CurrentObjectiveSnapshot
    func currentObjective() async throws -> CurrentObjectiveSnapshot { snapshot }
}
private actor ObjectiveReadGate: CurrentObjectiveProviding {
    private(set) var calls = 0
    private var pending: [CheckedContinuation<CurrentObjectiveSnapshot, any Error>?] = []
    private var started: [(Int, CheckedContinuation<Void, Never>)] = []
    func currentObjective() async throws -> CurrentObjectiveSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            calls += 1
            let ready = started.filter { calls >= $0.0 }
            started.removeAll { calls >= $0.0 }
            for (_, waiter) in ready { waiter.resume() }
        }
    }
    func waitForCalls(_ count: Int) async {
        if calls >= count { return }
        await withCheckedContinuation { started.append((count, $0)) }
    }
    func finish(_ result: Result<CurrentObjectiveSnapshot, BodyFlowCapabilityError>, at index: Int? = nil) {
        guard let i = index ?? pending.firstIndex(where: { $0 != nil }), let continuation = pending[i] else { preconditionFailure("Missing pending test read") }
        pending[i] = nil
        continuation.resume(with: result.mapError { $0 as any Error })
    }
}
