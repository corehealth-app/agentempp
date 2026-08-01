import Foundation
import Testing

@testable import BodyFlow

@Suite("Hydration registration model")
@MainActor
struct HydrationRegistrationModelTests {
    @Test("quick and custom commands use the injected occurrence time")
    func fixedOccurrenceTime() async throws {
        let harness = Self.makeHarness()

        #expect(harness.model.initialOccurredAt == Self.fixedDate)
        await harness.model.submitQuick(250)
        await harness.model.submitCustom("5000")

        let attempts = await harness.recording.attempts
        #expect(attempts.map(\.payload.amountML) == [250, 5_000])
        #expect(attempts.allSatisfy { $0.payload.occurredAt.value == Self.fixedDate })
        #expect(attempts.allSatisfy { $0.createdAt == Self.fixedDate })
    }

    @Test("hydration rejects out-of-range and non-integer custom values without an operation")
    func validationBounds() async {
        let harness = Self.makeHarness()

        await harness.model.submitCustom("0")
        await harness.model.submitCustom("5001")
        await harness.model.submitCustom("250.5")

        #expect(await harness.recording.attempts.isEmpty)
        #expect(harness.center.revision(for: .today) == 0)
        #expect(harness.model.captureError == .invalidInput)

        await harness.model.submitCustom("1")
        await harness.model.submitCustom("5000")
        #expect(await harness.recording.attempts.map(\.payload.amountML) == [1, 5_000])
    }

    @Test("each new hydration intention gets one key and retry replays the retained attempt")
    func keysAndRetry() async throws {
        let harness = Self.makeHarness(outcomes: [
            .failure(.serviceUnavailable),
            .success(Self.receipt),
            .success(Self.receipt)
        ])

        await harness.model.submitQuick(250)
        guard case let .failed(retained, .serviceUnavailable) = harness.model.mutationState else {
            Issue.record("Expected the failed hydration attempt to be retained")
            return
        }
        await harness.model.retry()
        await harness.model.submitQuick(500)

        let attempts = await harness.recording.attempts
        #expect(attempts[0] == retained)
        #expect(attempts[1] == retained)
        #expect(attempts[2].key != retained.key)
    }

    @Test("a double hydration submit invokes the recorder only once")
    func doubleSubmit() async {
        let recording = ControlledHydrationRecording()
        let model = HydrationRegistrationModel(
            recording: recording,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "hydration-double"),
            invalidationCenter: FeatureInvalidationCenter()
        )

        let first = Task { await model.submitQuick(250) }
        await recording.waitUntilStarted()
        let second = Task { await model.submitQuick(250) }
        await recording.succeed(with: Self.receipt)
        await first.value
        await second.value

        #expect(await recording.callCount == 1)
    }

    @Test("successful hydration invalidates Today once and focuses the operation summary")
    func successInvalidatesTodayOnce() async {
        let harness = Self.makeHarness()

        await harness.model.submitQuick(750)

        #expect(harness.center.revision(for: .today) == 1)
        #expect(harness.center.revision(for: .history) == 0)
        #expect(harness.model.accessibilityFocusTarget == .operationSummary)
        harness.model.consumeAccessibilityFocus()
        #expect(harness.model.accessibilityFocusTarget == nil)
    }

    @Test("cancelled and superseded hydration tasks cannot publish a late receipt error or revision")
    func cancellationAndSupersessionPreventLatePublication() async {
        let recording = ControlledHydrationRecording()
        let center = FeatureInvalidationCenter()
        let model = HydrationRegistrationModel(
            recording: recording,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "hydration-late"),
            invalidationCenter: center
        )

        let cancelled = Task { await model.submitQuick(250) }
        await recording.waitUntilStarted()
        model.discardSheet()
        await recording.succeed(with: Self.receipt)
        await cancelled.value
        #expect(model.mutationState == .idle)
        #expect(model.accessibilityFocusTarget == nil)
        #expect(center.revision(for: .today) == 0)

        let superseded = Task { await model.submitQuick(500) }
        await recording.waitUntilStarted()
        model.startNewEntry()
        await recording.fail(with: .serviceUnavailable)
        await superseded.value
        #expect(model.mutationState == .idle)
        #expect(model.captureError == nil)
        #expect(model.accessibilityFocusTarget == nil)
        #expect(center.revision(for: .today) == 0)
    }

    @Test("hydration emits only a Today revision and Today adopts one complete refreshed snapshot")
    func hydrationRefreshesTodayThroughRevisionOwner() async throws {
        let center = FeatureInvalidationCenter()
        let initial = DemoBodyFlowFixtures.loadedToday
        let replacement = DemoBodyFlowFixtures.postHydrationToday
        let provider = TodaySequenceProvider([initial, replacement])
        let today = TodayViewModel(provider: provider)
        let model = HydrationRegistrationModel(
            recording: HydrationRecordingSpy(outcomes: [.success(Self.receipt)]),
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "hydration-today"),
            invalidationCenter: center
        )

        await today.load(revision: center.revision(for: .today))
        await model.submitQuick(250)
        let revision = center.revision(for: .today)
        await today.load(revision: revision)
        await today.load(revision: revision)

        #expect(await provider.callCount == 2)
        #expect(today.state == .loaded(replacement.data))
        #expect(replacement.data.hydration.consumedML != initial.data.hydration.consumedML + 250)
    }

    private static func makeHarness(
        outcomes: [HydrationOutcome] = [.success(receipt), .success(receipt)]
    ) -> HydrationHarness {
        let center = FeatureInvalidationCenter()
        let recording = HydrationRecordingSpy(outcomes: outcomes)
        return HydrationHarness(
            model: HydrationRegistrationModel(
                recording: recording,
                timeProvider: FixedTimeProvider(value: fixedDate),
                keyProvider: DeterministicIdempotencyKeyProvider(prefix: "hydration"),
                invalidationCenter: center
            ),
            recording: recording,
            center: center
        )
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_784_589_300)
private static let receipt = DemoBodyFlowFixtures.hydrationReceipt
}

@Suite("Weight registration model")
@MainActor
struct WeightRegistrationModelTests {
    @Test("weight uses the injected recorded time")
    func fixedRecordedTime() async throws {
        let harness = Self.makeHarness()

        #expect(harness.model.initialRecordedAt == Self.fixedDate)
        await harness.model.submit(weightKG: 78.4)

        let attempt = try #require(await harness.recording.attempts.first)
        #expect(attempt.payload.recordedAt == Self.fixedDate)
        #expect(attempt.createdAt == Self.fixedDate)
    }

    @Test("weight accepts only the inclusive local app-domain bounds")
    func validationBounds() async {
        let harness = Self.makeHarness()

        await harness.model.submit(weightKG: 29.99)
        await harness.model.submit(weightKG: 300.01)
        #expect(await harness.recording.attempts.isEmpty)
        #expect(harness.model.captureError == .invalidInput)

        await harness.model.submit(weightKG: 30)
        await harness.model.submit(weightKG: 300)
        #expect(await harness.recording.attempts.map(\.payload.weightKG) == [30, 300])
    }

    @Test("weight returns the literal local-only receipt without invalidating reads")
    func localReceiptDoesNotInvalidate() async {
        let harness = Self.makeHarness()

        await harness.model.submit(weightKG: 78.4)

        #expect(harness.model.receipt?.label == "Demonstração local; não sincronizado")
        #expect(harness.center.revision(for: .today) == 0)
        #expect(harness.center.revision(for: .history) == 0)
        #expect(harness.model.accessibilityFocusTarget == .operationSummary)
    }

    @Test("an invalid weight clears a previous local receipt and focuses validation")
    func invalidWeightClearsPreviousReceipt() async {
        let harness = Self.makeHarness()

        await harness.model.submit(weightKG: 78.4)
        #expect(harness.model.receipt?.label == "Demonstração local; não sincronizado")

        await harness.model.submit(weightKG: 29.99)

        #expect(harness.model.mutationState == .idle)
        #expect(harness.model.receipt == nil)
        #expect(harness.model.captureError == .invalidInput)
        #expect(harness.model.accessibilityFocusTarget == .operationSummary)
    }

    @Test("weight retry replays an identical attempt and a conflict remains visible")
    func replayAndConflict() async {
        let replay = Self.makeHarness(outcomes: [.failure(.serviceUnavailable), .success(Self.receipt)])
        await replay.model.submit(weightKG: 78.4)
        guard case let .failed(retained, .serviceUnavailable) = replay.model.mutationState else {
            Issue.record("Expected the failed weight attempt to be retained")
            return
        }
        await replay.model.retry()
        #expect(await replay.recording.attempts == [retained, retained])

        let conflict = Self.makeHarness(outcomes: [.failure(.idempotencyConflict)])
        await conflict.model.submit(weightKG: 78.4)
        #expect(conflict.model.captureError == .idempotencyConflict)
        #expect(conflict.model.accessibilityFocusTarget == .operationSummary)
    }

    @Test("unavailable weight never produces a receipt")
    func unavailable() async {
        let harness = Self.makeHarness(outcomes: [.failure(.operationUnavailable)])

        await harness.model.submit(weightKG: 78.4)

        #expect(harness.model.mutationState == .unavailable)
        #expect(harness.model.receipt == nil)
        #expect(harness.model.accessibilityFocusTarget == .operationSummary)
    }

    @Test("cancelled and superseded weight tasks cannot publish a late receipt or error")
    func cancellationAndSupersessionPreventLatePublication() async {
        let recording = ControlledWeightRecording()
        let model = WeightRegistrationModel(
            recording: recording,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "weight-late"),
            invalidationCenter: FeatureInvalidationCenter()
        )

        let cancelled = Task { await model.submit(weightKG: 78.4) }
        await recording.waitUntilStarted()
        model.discardSheet()
        await recording.succeed(with: Self.receipt)
        await cancelled.value
        #expect(model.receipt == nil)
        #expect(model.captureError == nil)

        let superseded = Task { await model.submit(weightKG: 80) }
        await recording.waitUntilStarted()
        model.startNewEntry()
        await recording.fail(with: .serviceUnavailable)
        await superseded.value
        #expect(model.receipt == nil)
        #expect(model.captureError == nil)
    }

    private static func makeHarness(
        outcomes: [WeightOutcome] = [.success(receipt), .success(receipt)]
    ) -> WeightHarness {
        let center = FeatureInvalidationCenter()
        let recording = WeightRecordingSpy(outcomes: outcomes)
        return WeightHarness(
            model: WeightRegistrationModel(
                recording: recording,
                timeProvider: FixedTimeProvider(value: fixedDate),
                keyProvider: DeterministicIdempotencyKeyProvider(prefix: "weight"),
                invalidationCenter: center
            ),
            recording: recording,
            center: center
        )
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_784_589_300)
    private static let receipt = WeightDemoReceipt(
        weightKG: 78.4,
        recordedAt: fixedDate,
        label: "Demonstração local; não sincronizado"
    )
}

@MainActor
private struct HydrationHarness {
    let model: HydrationRegistrationModel
    let recording: HydrationRecordingSpy
    let center: FeatureInvalidationCenter
}

@MainActor
private struct WeightHarness {
    let model: WeightRegistrationModel
    let recording: WeightRecordingSpy
    let center: FeatureInvalidationCenter
}

private enum HydrationOutcome: Sendable {
    case success(HydrationReceipt)
    case failure(BodyFlowCapabilityError)

    func get() throws -> HydrationReceipt {
        switch self {
        case let .success(receipt): receipt
        case let .failure(error): throw error
        }
    }
}

private enum WeightOutcome: Sendable {
    case success(WeightDemoReceipt)
    case failure(BodyFlowCapabilityError)

    func get() throws -> WeightDemoReceipt {
        switch self {
        case let .success(receipt): receipt
        case let .failure(error): throw error
        }
    }
}

private actor HydrationRecordingSpy: HydrationRecording {
    private var outcomes: [HydrationOutcome]
    private(set) var attempts: [MutationAttempt<HydrationCommand>] = []

    init(outcomes: [HydrationOutcome]) { self.outcomes = outcomes }

    func record(_ attempt: MutationAttempt<HydrationCommand>) async throws -> HydrationReceipt {
        attempts.append(attempt)
        return try outcomes.removeFirst().get()
    }
}

private actor WeightRecordingSpy: WeightRecording {
    private var outcomes: [WeightOutcome]
    private(set) var attempts: [MutationAttempt<WeightCommand>] = []

    init(outcomes: [WeightOutcome]) { self.outcomes = outcomes }

    func record(_ attempt: MutationAttempt<WeightCommand>) async throws -> WeightDemoReceipt {
        attempts.append(attempt)
        return try outcomes.removeFirst().get()
    }
}

private actor ControlledHydrationRecording: HydrationRecording {
    private var continuation: CheckedContinuation<Result<HydrationReceipt, BodyFlowCapabilityError>, Never>?
    private var started = false
    private(set) var callCount = 0

    func record(_ attempt: MutationAttempt<HydrationCommand>) async throws -> HydrationReceipt {
        callCount += 1
        started = true
        return try await withCheckedContinuation { continuation = $0 }.get()
    }

    func waitUntilStarted() async { while !started { await Task.yield() } }
    func succeed(with receipt: HydrationReceipt) { continuation?.resume(returning: .success(receipt)) }
    func fail(with error: BodyFlowCapabilityError) { continuation?.resume(returning: .failure(error)) }
}

private actor ControlledWeightRecording: WeightRecording {
    private var continuation: CheckedContinuation<Result<WeightDemoReceipt, BodyFlowCapabilityError>, Never>?
    private var started = false

    func record(_ attempt: MutationAttempt<WeightCommand>) async throws -> WeightDemoReceipt {
        started = true
        return try await withCheckedContinuation { continuation = $0 }.get()
    }

    func waitUntilStarted() async { while !started { await Task.yield() } }
    func succeed(with receipt: WeightDemoReceipt) { continuation?.resume(returning: .success(receipt)) }
    func fail(with error: BodyFlowCapabilityError) { continuation?.resume(returning: .failure(error)) }
}

private actor TodaySequenceProvider: TodayProviding {
    private var values: [TodayResponse]
    private(set) var callCount = 0

    init(_ values: [TodayResponse]) { self.values = values }

    func today() async throws -> TodayResponse {
        callCount += 1
        return values.removeFirst()
    }
}
