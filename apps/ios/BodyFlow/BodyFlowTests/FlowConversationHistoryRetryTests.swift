import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI

  @MainActor @Suite("Explicit recovery of unavailable conversation history", .serialized)
  struct FlowConversationHistoryRetryTests {
    @Test(arguments: [false, true])
    func failedHistoryOffersAnEnabledReadRetryInTheActualRecoveryContent(_ english: Bool) async throws {
      let f = try await journalV3HTTPFixture()
      defer { f.disk.remove() }
      await f.http.stub.respond { request, _ in
        if request.url?.path == "/api/mobile/v1/conversation/journal" {
          return .failure(503, "conversation_journal_unavailable")
        }
        if request.url?.path == "/api/mobile/v1/conversation/intakes/session" {
          return f.intakeSession
        }
        return f.mealSession
      }
      let lease = await f.http.lifecycle.leaseForRequest()
      let session = try await FlowConversationSessionSource(
        transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true
      ).open(expectedUserID: lease.userID)
      defer { session.invalidateSynchronously() }
      await session.model.loadHistory()
      #expect(session.model.unifiedHistoryUnavailable && session.model.unifiedRows.isEmpty)
      let host = SignUpRenderingProbe.host(
        FlowConversationHistoryRecoveryContent(model: session.model, english: english),
        width: 390, height: 800)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(nodes.contains { $0.label.contains(english
        ? "History is unavailable right now." : "O histórico está indisponível no momento.") })
      let node = try #require(nodes.first { $0.identifier == "conversation.history.retry" })
      #expect(node.label == (english ? "Retry history" : "Tentar carregar histórico novamente"))
      #expect(node.isEnabled && node.frame.width > 0 && node.frame.height > 0)
      #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
      #expect(session.model.savedEffectRevision == 0)
      await session.close()
    }

    @Test func retryRestoresHistoryWithoutWritingAndClosedSessionCannotRetry() async throws {
      let f = try await journalV3HTTPFixture()
      defer { f.disk.remove() }
      await f.http.stub.respond { request, _ in
        if request.url?.path == "/api/mobile/v1/conversation/journal" {
          return .failure(503, "conversation_journal_unavailable")
        }
        if request.url?.path == "/api/mobile/v1/conversation/intakes/session" {
          return f.intakeSession
        }
        return f.mealSession
      }
      let lease = await f.http.lifecycle.leaseForRequest()
      let session = try await FlowConversationSessionSource(
        transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true
      ).open(expectedUserID: lease.userID)
      await session.model.loadHistory()
      #expect(session.model.unifiedHistoryUnavailable && session.model.unifiedRows.isEmpty)
      let page = try neutralHTTP(JSONSerialization.jsonObject(with: f.page))
      await f.http.stub.respond { _, _ in page }
      await session.model.loadHistory()
      #expect(!session.model.unifiedHistoryUnavailable && session.model.unifiedRows.count == 1)
      let original = try #require(session.model.unifiedRows.first)
      #expect(session.model.unifiedHistory.feedback(for: original) != nil)
      await session.model.loadHistory()
      #expect(session.model.unifiedRows.map(\.eventID) == [original.eventID])
      #expect(session.model.savedEffectRevision == 0)
      let reads = await f.http.stub.requests
      #expect(reads.filter { $0.url?.path == "/api/mobile/v1/conversation/journal" }.count == 3)
      #expect(reads.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
      await session.close()
      await session.model.loadHistory()
      #expect(session.model.unifiedRows.isEmpty)
      #expect(await f.http.stub.requests.count == reads.count)
    }
  }
#endif
