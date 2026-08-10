import Foundation
import Testing

@testable import BodyFlow

@Suite("Mascot experience view model")
@MainActor
struct MascotExperienceViewModelTests {
    @Test("initial revision publishes loading then the server-owned balanced snapshot")
    func loadingAndLoadedBalancedSnapshot() async throws {
        let response = Self.response(
            selected: nil,
            effective: .balanced,
            state: .inactive
        )
        let provider = MascotControlledProvider()
        let model = MascotExperienceViewModel(provider: provider)

        let task = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }

        #expect(model.state == .loading)

        await provider.succeed(call: 1, with: response)
        await task.value

        let presentation = try #require(model.state.presentation.value)
        #expect(model.state == .loaded(presentation))
        #expect(presentation.selected == nil)
        #expect(presentation.effective == .balanced)
        #expect(presentation.personality == MascotPersonalityDescriptor(
            geometry: .neutral,
            tone: .neutral
        ))
        #expect(presentation.mascotState.title == "Em repouso")
        #expect(presentation.changedAtText == "19/07/2026, 23:15")
        #expect(presentation.optionsByCode[.focus]?.name == "Foco do servidor")
        #expect(
            presentation.optionsByCode[.focus]?.description
                == "Direto do contrato remoto."
        )
        #expect(
            presentation.optionsByCode[.impulse]?.name
                == "Impulso do servidor"
        )
        #expect(presentation.optionsByCode[.zen]?.name == "Zen do servidor")
    }

    @Test("loaded options preserve noncanonical server order and code lookup")
    func optionOrderAndLookup() async throws {
        let options = [
            Self.serverOptions[2],
            Self.serverOptions[0],
            Self.serverOptions[1],
        ]
        let model = MascotExperienceViewModel(
            provider: MascotQueueProvider([
                .success(Self.response(options: options)),
            ])
        )

        await model.load(revision: 0)

        let presentation = try #require(model.state.presentation.value)
        #expect(presentation.options.map(\.code) == [.zen, .focus, .impulse])
        #expect(presentation.options.map(\.name) == [
            "Zen do servidor",
            "Foco do servidor",
            "Impulso do servidor",
        ])
        #expect(presentation.optionsByCode[.focus]?.name == "Foco do servidor")
        #expect(
            presentation.optionsByCode[.focus]?.description
                == "Direto do contrato remoto."
        )
    }

    @Test("initial offline remains offline without a fabricated value")
    func initialOffline() async {
        let model = MascotExperienceViewModel(
            provider: MascotQueueProvider([.failure(.offline)])
        )

        await model.load(revision: 0)

        #expect(model.state == .offline(previousValue: nil))
    }

    @Test("offline retry retains the complete prior server presentation")
    func staleOffline() async throws {
        let response = Self.response(selected: .focus, effective: .focus)
        let provider = MascotQueueProvider([
            .success(response),
            .failure(.offline),
        ])
        let model = MascotExperienceViewModel(provider: provider)

        await model.load(revision: 0)
        let loaded = try #require(model.state.presentation.value)
        await model.retry()

        #expect(model.state == .offline(previousValue: loaded))
    }

    @Test("service retry retains the complete prior server presentation")
    func staleError() async throws {
        let response = Self.response(selected: .impulse, effective: .impulse)
        let provider = MascotQueueProvider([
            .success(response),
            .failure(.serviceUnavailable),
        ])
        let model = MascotExperienceViewModel(provider: provider)

        await model.load(revision: 0)
        let loaded = try #require(model.state.presentation.value)
        await model.retry()

        #expect(model.state == .failed(
            previousValue: loaded,
            error: .serviceUnavailable
        ))
    }

    @Test("unavailable capability remains explicitly unavailable")
    func unavailable() async {
        let model = MascotExperienceViewModel(
            provider: MascotQueueProvider([.failure(.operationUnavailable)])
        )

        await model.load(revision: 0)

        #expect(model.state == .unavailable)
    }

    @Test("unsupported contract version fails closed")
    func unsupportedVersion() async {
        let response = Self.response(contractVersion: "bodyflow.coach-persona.v2")
        let model = MascotExperienceViewModel(
            provider: MascotQueueProvider([.success(response)])
        )

        await model.load(revision: 0)

        #expect(model.state == .failed(
            previousValue: nil,
            error: .unsupportedCoachContract
        ))
    }

    @Test("unsupported coach locale fails closed")
    func unsupportedLocale() async {
        let model = MascotExperienceViewModel(
            provider: MascotQueueProvider([.failure(.coachLocaleUnsupported)])
        )

        await model.load(revision: 0)

        #expect(model.state == .failed(
            previousValue: nil,
            error: .coachLocaleUnsupported
        ))
    }

    @Test("missing selectable option fails the v1 presentation contract closed")
    func incompleteOptionsFailClosed() async {
        let response = Self.response(
            options: Array(Self.serverOptions.dropLast())
        )
        let model = MascotExperienceViewModel(
            provider: MascotQueueProvider([.success(response)])
        )

        await model.load(revision: 0)

        #expect(model.state == .failed(
            previousValue: nil,
            error: .unsupportedCoachContract
        ))
    }

    @Test("selected and effective persona mismatch fails closed")
    func inconsistentEffectivePersonaFailsClosed() async {
        let response = Self.response(selected: .focus, effective: .zen)
        let model = MascotExperienceViewModel(
            provider: MascotQueueProvider([.success(response)])
        )

        await model.load(revision: 0)

        #expect(model.state == .failed(
            previousValue: nil,
            error: .unsupportedCoachContract
        ))
    }

    @Test("cancelled revision cannot publish its late snapshot")
    func cancellationSuppressesLateSnapshot() async {
        let provider = MascotControlledProvider()
        let model = MascotExperienceViewModel(provider: provider)

        let task = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }
        task.cancel()
        await provider.succeed(call: 1, with: Self.response())
        await task.value

        #expect(model.state == .loading)
    }

    @Test("newer coach revision wins over a late older snapshot")
    func supersessionSuppressesLateSnapshot() async throws {
        let older = Self.response(selected: .focus, effective: .focus)
        let newer = Self.response(
            selected: .zen,
            effective: .zen,
            state: .neglected,
            requestID: "coach-newer"
        )
        let provider = MascotControlledProvider()
        let model = MascotExperienceViewModel(provider: provider)

        let olderTask = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }
        let newerTask = Task { await model.load(revision: 1) }
        guard await provider.waitUntilStarted(2) else { return }

        await provider.succeed(call: 1, with: older)
        await olderTask.value
        #expect(model.state == .loading)

        await provider.succeed(call: 2, with: newer)
        await newerTask.value

        let presentation = try #require(model.state.presentation.value)
        #expect(presentation.selected == .zen)
        #expect(presentation.effective == .zen)
        #expect(presentation.mascotState.title == "Em pausa")
    }

    @Test("newer coach revision wins over a late older error")
    func supersessionSuppressesLateError() async throws {
        let newer = Self.response(selected: .zen, effective: .zen)
        let provider = MascotControlledProvider()
        let model = MascotExperienceViewModel(provider: provider)

        let olderTask = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }
        let newerTask = Task { await model.load(revision: 1) }
        guard await provider.waitUntilStarted(2) else { return }

        await provider.fail(call: 1, with: .serviceUnavailable)
        await olderTask.value
        #expect(model.state == .loading)

        await provider.succeed(call: 2, with: newer)
        await newerTask.value

        let presentation = try #require(model.state.presentation.value)
        #expect(presentation.selected == .zen)
        #expect(presentation.effective == .zen)
    }

    @Test("coach invalidation drives exactly one load per revision")
    func oneLoadPerCoachRevision() async {
        let provider = MascotQueueProvider([
            .success(Self.response()),
            .success(Self.response(
                selected: .focus,
                effective: .focus,
                requestID: "coach-refreshed"
            )),
        ])
        let model = MascotExperienceViewModel(provider: provider)
        let invalidationCenter = FeatureInvalidationCenter()

        let initialRevision = invalidationCenter.revision(for: .coachExperience)
        await model.load(revision: initialRevision)
        await model.load(revision: initialRevision)

        invalidationCenter.record(.hydrationRecorded)
        await model.load(
            revision: invalidationCenter.revision(for: .coachExperience)
        )

        invalidationCenter.record(.coachPersonaChanged)
        let changedRevision = invalidationCenter.revision(for: .coachExperience)
        #expect(changedRevision == initialRevision + 1)
        await model.load(revision: changedRevision)
        await model.load(revision: changedRevision)

        #expect(await provider.calls == 2)
    }

    private static let serverOptions = [
        CoachPersonaOption(
            code: .focus,
            name: "Foco do servidor",
            description: "Direto do contrato remoto."
        ),
        CoachPersonaOption(
            code: .impulse,
            name: "Impulso do servidor",
            description: "Energético do contrato remoto."
        ),
        CoachPersonaOption(
            code: .zen,
            name: "Zen do servidor",
            description: "Calmo do contrato remoto."
        ),
    ]

    private static func response(
        selected: SelectableCoachPersona? = nil,
        effective: EffectiveCoachPersona = .balanced,
        options: [CoachPersonaOption] = serverOptions,
        state: MascotWireState = .active,
        contractVersion: String = "bodyflow.coach-persona.v1",
        requestID: String = "coach-request"
    ) -> CoachExperienceResponse {
        CoachExperienceResponse(
            data: CoachExperienceSnapshot(
                selected: selected,
                effective: effective,
                options: options,
                mascot: MascotSnapshot(
                    state: state,
                    changedAt: APITimestamp(
                        value: Date(timeIntervalSince1970: 1_784_502_900)
                    )
                ),
                contractVersion: contractVersion
            ),
            meta: MobileResponseMetadata(apiVersion: "1", requestID: requestID)
        )
    }
}

private actor MascotQueueProvider: CoachExperienceProviding {
    enum Outcome: Sendable {
        case success(CoachExperienceResponse)
        case failure(BodyFlowCapabilityError)
    }

    private var outcomes: [Outcome]
    private(set) var calls = 0

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func coachExperience() async throws -> CoachExperienceResponse {
        calls += 1
        guard !outcomes.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }

        switch outcomes.removeFirst() {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }
}

private actor MascotControlledProvider: CoachExperienceProviding {
    private var continuations: [
        Int: CheckedContinuation<CoachExperienceResponse, any Error>
    ] = [:]
    private var calls = 0

    func coachExperience() async throws -> CoachExperienceResponse {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    @discardableResult
    func waitUntilStarted(
        _ count: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while calls < count {
            guard clock.now < deadline else {
                Issue.record(
                    "Timed out waiting for \(count) mascot loads; started: \(calls)"
                )
                return false
            }
            await Task.yield()
        }

        return true
    }

    func succeed(call: Int, with response: CoachExperienceResponse) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }

    func fail(call: Int, with error: BodyFlowCapabilityError) {
        continuations.removeValue(forKey: call)?.resume(throwing: error)
    }
}
