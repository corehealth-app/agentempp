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

    @Test("changed capture payload cancels the old task and starts its replacement")
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
        await work.waitUntilStarted(2)
        await work.waitUntilCancelled("first")
        #expect(await work.started == ["first", "replacement"])
        coordinator.discard()
        await work.resumeAll()
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

    private func recordCancellation(_ label: String) {
        cancelled.insert(label)
    }
}
