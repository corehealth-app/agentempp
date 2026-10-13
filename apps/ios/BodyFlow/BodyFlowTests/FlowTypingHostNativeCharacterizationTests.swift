#if DEBUG
import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

@MainActor
@Suite("Flow typing host native boundary", .serialized)
struct FlowTypingHostNativeCharacterizationTests {
    @Test("longHistory40 and five local exchanges remove native typing animations after each reply")
    func fiveRepliesRemoveTypingHostsAndNativeLoops() async throws {
        let repository = FlowPreviewRepository(scenario: .longHistory)
        let model = FlowChatModel(userID: "native-flow-typing-fixture", provider: repository,
                                  keyProvider: RandomIdempotencyKeyProvider())
        await model.load()
        try #require(model.messages.count == 40)
        let host = PremiumRenderingTestSupport.liveAccessibilityHost(
            NavigationStack {
                FlowChatView(model: model)
                    .environment(\.bodyFlowReduceMotion, false)
                    .environment(\.bodyFlowVisualPolicy, BodyFlowVisualPolicy())
            }, width: 402, size: .large
        )
        defer { model.cancel(); host.detach() }
        let initialTypingCount = host.nativeViews(BodyFlowTypingDotsView.self).count
        #expect(initialTypingCount == 0)

        for index in 0..<5 {
            model.composer = "QA local \(index)"
            let send = Task { await model.send() }
            do {
                // The real DEBUG repository holds its reply for two seconds.
                // This yields to the actual model/SwiftUI task; no mock provider.
                try await Task.sleep(for: .milliseconds(100))
                let awaitingReply = model.isSending
                try #require(awaitingReply)
                var pendingHosts = host.nativeViews(BodyFlowTypingDotsView.self)
                let pendingHostCount = pendingHosts.count
                try #require(pendingHostCount == 1)
                let pendingHostsAreAttached = pendingHosts.allSatisfy { $0.window != nil }
                #expect(pendingHostsAreAttached)
                let pendingLoopCount = pendingHosts.flatMap(\.dots).filter { dot in
                    let animation = dot.layer.animation(forKey: "bodyflow.typing")
                    return animation?.repeatCount.isInfinite == true
                }.count
                try #require(pendingLoopCount == 3)
                let priorHosts = pendingHosts.map(FlowTypingWeakNativeHost.init)
                pendingHosts.removeAll() // Observe old hosts weakly across the reply.

                await send.value
                let requestFinished = !model.isSending && !model.isReconcilingHistory && !model.isLoading
                try #require(requestFinished)
                let messageCount = model.messages.count
                #expect(messageCount == 40 + 2 * (index + 1))

                // nativeViews calls the existing settle() recipe: 0.1 seconds,
                // layout, public UIView walk, no AX tree/text/image collection.
                // Require at least 0.3s for the finite removal transition; cap
                // this check at twelve settle passes (nominally 1.2s).
                var cleared = false
                var remainingHostCount = 0
                var oldHostHasRegisteredTyping = false
                for pass in 0..<12 {
                    remainingHostCount = host.nativeViews(BodyFlowTypingDotsView.self).count
                    oldHostHasRegisteredTyping = priorHosts.contains { reference in
                        reference.view?.dots.contains { dot in
                            dot.layer.animation(forKey: "bodyflow.typing") != nil
                        } == true
                    }
                    if pass >= 2 && remainingHostCount == 0 && !oldHostHasRegisteredTyping {
                        cleared = true
                        break
                    }
                }
                #expect(cleared)
                #expect(remainingHostCount == 0)
                #expect(!oldHostHasRegisteredTyping)
            } catch {
                send.cancel()
                model.cancel()
                await send.value
                throw error
            }
        }
        let finalMessageCount = model.messages.count
        let uniqueMessageCount = Set(model.messages.map(\.id)).count
        let sendCallCount = await repository.sendCallCount
        #expect(finalMessageCount == 50)
        #expect(uniqueMessageCount == 50)
        #expect(sendCallCount == 5)
    }
}

@MainActor
private final class FlowTypingWeakNativeHost {
    weak var view: BodyFlowTypingDotsView?
    init(_ view: BodyFlowTypingDotsView) { self.view = view }
}
#endif
