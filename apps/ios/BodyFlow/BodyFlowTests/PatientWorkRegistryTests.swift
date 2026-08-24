import Foundation
import Testing
@testable import BodyFlow

@Suite("Patient Work Registry")
struct PatientWorkRegistryTests {
    @Test("finished work is removed without cancellation")
    func finishRemovesWork() async throws {
        let registry = PatientWorkRegistry()
        let signal = CancellationSignal()
        let id = try #require(await registry.begin(
            userID: "user-a",
            generation: 3,
            cancel: signal.cancel
        ))

        await registry.finish(id)
        await registry.cancelAll(userID: "user-a", generation: 3)

        #expect(signal.count == 0)
        #expect(await registry.activeCount == 0)
    }

    @Test("cancellation is scoped to the exact user generation")
    func cancellationIsPatientScoped() async {
        let registry = PatientWorkRegistry()
        let old = CancellationSignal()
        let current = CancellationSignal()
        _ = await registry.begin(
            userID: "user-a", generation: 4, cancel: old.cancel
        )
        _ = await registry.begin(
            userID: "user-a", generation: 5, cancel: current.cancel
        )

        await registry.cancelAll(userID: "user-a", generation: 4)

        #expect(old.count == 1)
        #expect(current.count == 0)
        #expect(await registry.activeCount == 1)
    }

    @Test("a retired patient generation rejects late registration")
    func retiredGenerationRejectsLateRegistration() async {
        let registry = PatientWorkRegistry()
        let signal = CancellationSignal()

        await registry.cancelAll(userID: "user-a", generation: 8)
        let id = await registry.begin(
            userID: "user-a",
            generation: 8,
            cancel: signal.cancel
        )

        #expect(id == nil)
        #expect(signal.count == 1)
        #expect(await registry.activeCount == 0)
    }

    @Test("finish reports whether it still owned the registered work")
    func finishReportsRegistrationOwnership() async throws {
        let registry = PatientWorkRegistry()
        let id = try #require(await registry.begin(
            userID: "user-a",
            generation: 9,
            cancel: {}
        ))

        #expect(await registry.finish(id))
        #expect(await registry.finish(id) == false)
    }
}

private final class CancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func cancel() { lock.withLock { value += 1 } }
}
