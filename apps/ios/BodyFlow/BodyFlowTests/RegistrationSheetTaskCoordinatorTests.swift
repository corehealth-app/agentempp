import Foundation
import Testing

@testable import BodyFlow

@Suite("Registration Sheet Task Coordinator")
@MainActor
struct RegistrationSheetTaskCoordinatorTests {
    @Test("identical capture intent retains the active task")
    func identicalCaptureRetainsActiveTask() async {
        let work = SuspendingSheetWork()
        let coordinator = RegistrationSheetTaskCoordinator()
        let intent = RegistrationSheetOperationIntent.capture(.text("Mesmo payload"))

        coordinator.perform(intent) {
            await work.run("first")
        }
        await work.waitUntilStarted(1)

        coordinator.perform(intent) {
            await work.run("duplicate")
        }
        #expect(await work.started == ["first"])
        #expect(!(await work.wasCancelled("first")))
        coordinator.discard()
        await work.resumeAll()
    }

    @Test("changed capture payload waits for the cancelled task before starting its replacement")
    func changedCapturePayloadReplacesActiveTask() async {
        let work = SuspendingSheetWork()
        let coordinator = RegistrationSheetTaskCoordinator()
        coordinator.perform(.capture(.text("Original"))) {
            await work.run("first")
        }
        await work.waitUntilStarted(1)

        coordinator.perform(.capture(.text("Alterado"))) {
            await work.run("replacement")
        }
        await work.waitUntilCancelled("first")
        #expect(await work.started == ["first"])
        await work.resume("first")
        await work.waitUntilStarted(2)
        #expect(await work.started == ["first", "replacement"])
        coordinator.discard()
        await work.resumeAll()
    }

    @Test("changed hydration intent runs after a cancelled non-cooperative recording unwinds")
    func changedHydrationIntentRunsAfterCancellationUnwinds() async {
        let recording = NonCooperativeHydrationRecording()
        let center = FeatureInvalidationCenter()
        let date = Date(timeIntervalSince1970: 1_784_589_300)
        let model = HydrationRegistrationModel(
            recording: recording,
            timeProvider: FixedTimeProvider(value: date),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "coordinator-hydration"),
            invalidationCenter: center
        )
        let coordinator = RegistrationSheetTaskCoordinator()
        var operationCalls = 0

        coordinator.perform(.hydration(amountML: 250, customAmount: "", occurredAt: date)) {
            operationCalls += 1
            await model.submitQuick(250, occurredAt: date)
        }
        await recording.waitUntilStarted(1)

        coordinator.perform(.hydration(amountML: 500, customAmount: "", occurredAt: date)) {
            operationCalls += 1
            await model.submitQuick(500, occurredAt: date)
        }
        await recording.waitUntilCancelled(1)

        guard operationCalls == 1 else {
            Issue.record("Replacement began while the first recording was still submitting")
            await recording.succeedNext()
            coordinator.discard()
            return
        }

        await recording.succeedNext()
        guard await recording.waitUntilStarted(2) else {
            Issue.record("Replacement was not started after the cancelled recording unwound")
            coordinator.discard()
            return
        }

        let attempts = await recording.attempts
        #expect(operationCalls == 2)
        #expect(attempts.map(\.payload.amountML) == [250, 500])
        #expect(attempts[0].key != attempts[1].key)

        await recording.succeedNext()
        guard await waitUntil({ model.receipt != nil }) else {
            Issue.record("Replacement receipt was not published")
            return
        }
        #expect(model.accessibilityFocusTarget == .operationSummary)
        #expect(center.revision(for: .today) == 1)
    }

    @Test("dismissal cancels the active task")
    func dismissalCancelsActiveTask() async {
        let work = SuspendingSheetWork()
        let coordinator = RegistrationSheetTaskCoordinator()
        coordinator.perform(.capture(.text("Ativa"))) {
            await work.run("active")
        }
        await work.waitUntilStarted(1)

        coordinator.discard()
        await work.waitUntilCancelled("active")
        await work.resumeAll()
    }
}

private actor SuspendingSheetWork {
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var started: [String] = []
    private var cancelled: Set<String> = []

    func run(_ label: String) async {
        started.append(label)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                continuations[label] = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation(label) }
        }
    }

    func waitUntilStarted(_ count: Int) async {
        while started.count < count {
            await Task.yield()
        }
    }

    func waitUntilCancelled(_ label: String) async {
        while !cancelled.contains(label) {
            await Task.yield()
        }
    }

    func wasCancelled(_ label: String) -> Bool {
        cancelled.contains(label)
    }

    func resumeAll() {
        let pending = continuations.values
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    func resume(_ label: String) {
        continuations.removeValue(forKey: label)?.resume()
    }

    private func recordCancellation(_ label: String) {
        cancelled.insert(label)
    }
}

private actor NonCooperativeHydrationRecording: HydrationRecording {
    private var continuations: [CheckedContinuation<HydrationReceipt, Never>] = []
    private(set) var attempts: [MutationAttempt<HydrationCommand>] = []
    private var cancellationCount = 0

    func record(_ attempt: MutationAttempt<HydrationCommand>) async throws -> HydrationReceipt {
        attempts.append(attempt)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func waitUntilStarted(_ count: Int) async -> Bool {
        for _ in 0..<1_000 {
            if attempts.count >= count { return true }
            await Task.yield()
        }
        return false
    }

    func waitUntilCancelled(_ count: Int) async {
        while cancellationCount < count {
            await Task.yield()
        }
    }

    func succeedNext() {
        continuations.removeFirst().resume(returning: DemoBodyFlowFixtures.hydrationReceipt)
    }

    private func recordCancellation() {
        cancellationCount += 1
    }
}

@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<1_000 {
        if condition() { return true }
        await Task.yield()
    }
    return false
}
