#if DEBUG
import Foundation
import Testing

@testable import BodyFlow

@Suite("Flow Debug preview support")
struct FlowChatPreviewSupportTests {
    @Test
    func exactArgumentsRequireExistingDemoBoundaryAndSingleValidScene() {
        for scenario in FlowPreviewScenario.allCases {
            let flag = "--ui-testing-flow-\(scenario.rawValue)"
            #expect(FlowPreviewScenario.resolve(arguments: ["--ui-testing", flag]) == scenario)
            #expect(FlowPreviewScenario.resolve(arguments: [flag]) == nil)
        }
        #expect(FlowPreviewScenario.resolve(arguments: ["--ui-testing", "--ui-testing-flow-unknown"]) == nil)
        #expect(FlowPreviewScenario.resolve(arguments: ["--ui-testing", "--ui-testing-flow-empty", "--ui-testing-flow-response"]) == nil)
        #expect(FlowPreviewScenario.resolve(arguments: ["--ui-testing", "--ui-testing-flow-empty", "--ui-testing-flow-empty"]) == nil)
        #expect(AppLaunchConfiguration.resolve(arguments: ["--ui-testing", "--ui-testing-flow-response"], buildFlavor: .release).mode == .releaseUnavailable)
        let reduceMotionArguments = ["--ui-testing", "--ui-testing-flow-longHistory", "--ui-testing-prompt13-reduce-motion"]
        #expect(FlowPreviewScenario.resolve(arguments: reduceMotionArguments) == .longHistory)
        #expect(AppLaunchConfiguration.resolve(arguments: reduceMotionArguments, buildFlavor: .debug).accessibilityReduceMotionOverride == true)
        #expect(AppLaunchConfiguration.resolve(arguments: reduceMotionArguments, buildFlavor: .release).accessibilityReduceMotionOverride == nil)
    }

    @Test
    func mockReplyIsLocalDeterministicAndExactKeyReplayDoesNotDuplicateHistory() async throws {
        let repository = FlowPreviewRepository(scenario: .empty)
        let key = try IdempotencyKey(validating: "flow-preview-test-key")
        let response = try await repository.send(text: "QA message", idempotencyKey: key)
        let replay = try await repository.send(text: "QA message", idempotencyKey: key)
        #expect(replay == response)
        let history = try await repository.history(limit: 50)
        #expect(history.messages.count == 2)
        #expect(history.messages.last == response.message)
        #expect(response.message.content.contains("QA"))
        #expect(response.message.content.contains("local"))
        #expect(await repository.sendCallCount == 2)
    }

    @Test
    func retryOnceRequiresExplicitRetryWithSameKey() async throws {
        let repository = FlowPreviewRepository(scenario: .retryOnce)
        let key = try IdempotencyKey(validating: "flow-preview-retry-key")
        await #expect(throws: URLError.self) {
            try await repository.send(text: "QA retry", idempotencyKey: key)
        }
        #expect(try await repository.history(limit: 50).messages.isEmpty)
        let response = try await repository.send(text: "QA retry", idempotencyKey: key)
        #expect(response.message.state == .completed)
        #expect(await repository.sentKeys == [key.value, key.value])
    }

    @Test
    func suppliedProcessingLongRawHistoryAndOfflineStayDistinct() async throws {
        let processing = try await FlowPreviewRepository(scenario: .processing).history(limit: 50)
        #expect(processing.messages.last?.state == .processing)
        let long = try await FlowPreviewRepository(scenario: .longHistory).history(limit: 50)
        #expect(long.messages.count == 40)
        #expect(Set(long.messages.map(\.role)) == [.user, .assistant])
        let response = try await FlowPreviewRepository(scenario: .response).history(limit: 50)
        #expect(response.messages.last?.content.contains("**QA literal**") == true)
        #expect((response.messages.last?.content.count ?? 0) > 2_000)
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await FlowPreviewRepository(scenario: .offline).history(limit: 50)
        }
    }
}
#endif
