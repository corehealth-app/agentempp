#if DEBUG
import Testing

@testable import BodyFlow

@Suite("C11 Real Loading Context Terminal Reentry")
@MainActor
struct C11RootNavigationDeliveryReentryTests {
    @Test("real didFinish reentry is post-admission and completed401 only follows callback return")
    func didFinishReentryPreservesRealCompleted401() async throws {
        let result = try await C11RootNavigationReentryControl.run(.success401)
        assertBeforeAndInside(result)
        #expect(result.afterOwnedTask.completed401 == 1)
        #expect(result.afterOwnedTask.success == 1)
        #expect(result.afterOwnedTask.error == 0)
        #expect(result.afterOwnedTask.callbackCancel == 0)
        #expect(result.afterOwnedTask.stopBefore == 0)
        #expect(result.afterOwnedTask.stopAfter == 1)
        #expect(result.receivedCallbacks == 1)
        #expect(result.dataCallbacks == 1)
        #expect(result.finishedCallbacks == 1)
        #expect(result.failedCallbacks == 0)
        #expect(result.unexpectedCallbacks == 0)
        #expect(result.contextFinished)
        #expect(result.protocolReleasedContext)
    }

    @Test("real didFail reentry is post-admission and error only follows callback return")
    func didFailReentryPreservesRealFailure() async throws {
        let result = try await C11RootNavigationReentryControl.run(.failure)
        assertBeforeAndInside(result)
        #expect(result.afterOwnedTask.completed401 == 0)
        #expect(result.afterOwnedTask.success == 0)
        #expect(result.afterOwnedTask.error == 1)
        #expect(result.afterOwnedTask.callbackCancel == 0)
        #expect(result.afterOwnedTask.stopBefore == 0)
        #expect(result.afterOwnedTask.stopAfter == 1)
        #expect(result.receivedCallbacks == 0)
        #expect(result.dataCallbacks == 0)
        #expect(result.finishedCallbacks == 0)
        #expect(result.failedCallbacks == 1)
        #expect(result.unexpectedCallbacks == 0)
        #expect(result.contextFinished)
        #expect(result.protocolReleasedContext)
    }

    private func assertBeforeAndInside(_ result: C11RootNavigationReentryResult) {
        // Literal expectations, sampled from inside the actual client callback.
        // The observer has not yet returned from that callback in either sample.
        #expect(result.beforeStop.completed401 == 0)
        #expect(result.beforeStop.success == 0)
        #expect(result.beforeStop.error == 0)
        #expect(result.beforeStop.callbackCancel == 0)
        #expect(result.beforeStop.stopBefore == 0)
        #expect(result.beforeStop.stopAfter == 0)
        #expect(result.insideCallbackAfterStop.completed401 == 0)
        #expect(result.insideCallbackAfterStop.success == 0)
        #expect(result.insideCallbackAfterStop.error == 0)
        #expect(result.insideCallbackAfterStop.callbackCancel == 0)
        #expect(result.insideCallbackAfterStop.stopBefore == 0)
        #expect(result.insideCallbackAfterStop.stopAfter == 1)
    }
}
#endif
