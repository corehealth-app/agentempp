import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit

  @MainActor @Suite("Cold reopened actual historical content")
  struct FlowConversationJournalV3RenderingTests {
    @Test
    func reopenedConversationReplyRendersEmphasisWithoutMarkupOrLinks() throws {
      var page = try journalV3PendingUnit(publicJournalV3Pages()[0], child: nil, reason: "question")
      var rows = try #require(page["items"] as? [[String: Any]])
      rows[0]["outcome"] = [
        "status": "not_recorded", "feedback": NSNull(), "reason": "question",
        "turn_reply": [
          "schema": "conversation.turn-reply.v1",
          "text": "Caminhada **leve**, com **43 kcal** estimadas.\n\nVeja [o resumo](https://example.invalid).",
        ],
      ]
      page["items"] = rows
      let decoder = JSONDecoder()
      ConversationTurnReplySelection.configure(decoder, requested: true, echo: "1")
      let decoded = try decoder.decode(
        ConversationJournalV3PageSnapshot.self, from: JSONSerialization.data(withJSONObject: page))
      let entry = try #require(decoded.items.first)
      let host = SignUpRenderingProbe.host(
        FlowConversationJournalV3Content(entry: entry, feedback: nil, english: false),
        width: 390, height: 800)
      defer { host.detach() }
      let nodes = host.nodes()
      let reply = try #require(nodes.first { $0.identifier == "conversation.turn.reply" })
      #expect(reply.label == "Caminhada leve, com 43 kcal estimadas.\n\nVeja o resumo.")
      let formatted = FlowChatPresentation.turnReplyText(try #require(entry.turnReply))
      #expect(formatted.runs.allSatisfy { $0.link == nil })
      #expect(formatted.runs.contains {
        $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
      })
    }

    @Test(arguments: [false, true])
    func reopenedWorkoutRendersCompactReplyWithSixDetailsAndNoWriteActions(_ english: Bool)
      async throws
    {
      let f = try await journalV3HTTPFixture()
      defer { f.disk.remove() }
      let lease = await f.http.lifecycle.leaseForRequest()
      let source = FlowConversationSessionSource(
        transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
        keyVault: f.vault,
        editing: .init(
          store: .init(directory: f.disk.directory),
          keyVault: .init(
            service: ConversationMealEditOutboxSession.keychainService,
            security: OutboxKeychainFake())),
        neutralIntakeEnabled: true)
      let first = try await source.open(expectedUserID: lease.userID)
      await first.model.loadHistory()
      #expect(first.model.unifiedRows.count == 1)
      await first.close()
      let reopened = try await source.open(expectedUserID: lease.userID)
      await reopened.model.loadHistory()
      defer { reopened.invalidateSynchronously() }
      let entry = try #require(reopened.model.unifiedRows.first)
      let feedback = try #require(reopened.model.unifiedHistory.feedback(for: entry))
      let host = SignUpRenderingProbe.host(
        FlowConversationJournalV3Content(entry: entry, feedback: feedback, english: english)
          .environment(\.locale, Locale(identifier: english ? "en_US" : "pt_BR")), width: 390,
        height: 2400)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(
        nodes.contains {
          $0.label.contains(english ? "Activity registered" : "Atividade registrada")
        })
      #expect(nodes.contains { $0.label.contains("30 min") })
      #expect(nodes.contains { $0.identifier == "conversation.feedback.details" })
      #expect(!nodes.contains { $0.identifier.hasPrefix("conversation.feedback.section.") })
      guard case .v3Sections(_, let sections) = feedback.presentation.content else {
        Issue.record("Missing sections")
        return
      }
      #expect(sections.map(\.key) == [.saved, .items, .summary, .day, .block, .education])
      let details = SignUpRenderingProbe.host(
        ConversationFeedbackPresentationView(feedback: feedback)
          .environment(\.locale, Locale(identifier: english ? "en_US" : "pt_BR")),
        width: 390, height: 2400)
      defer { details.detach() }
      for section in sections {
        let node = try #require(
          details.nodes().first {
            $0.identifier == "conversation.feedback.section." + section.key.rawValue })
        #expect(node.label == section.text && node.frame.width > 0 && node.frame.height > 0)
      }
      #expect(
        !nodes.contains {
          $0.identifier.contains("undo") || $0.identifier.contains("continue")
            || $0.identifier.contains("reply.answer")
        })
      #expect(reopened.model.savedEffectRevision == 0)
      #expect(
        await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
      await reopened.close()
    }
    @Test(arguments: [false, true])
    func nullableEnergyAndObservedQuestionsRenderWithoutInventingZeroOrLease(_ english: Bool) throws
    {
      let entry = try decodePublicJournalV3(publicJournalV3Pages()[0]).items[0]
      let host = SignUpRenderingProbe.host(
        FlowConversationJournalV3Content(entry: entry, feedback: nil, english: english), width: 390,
        height: 800)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(
        nodes.contains {
          $0.label.contains(
            english ? "Energy expenditure unavailable" : "Gasto energético indisponível")
        })
      #expect(!nodes.contains { $0.label.contains("0 kcal") })
      #expect(
        !nodes.contains {
          $0.label.contains(
            english ? "original attachment is unavailable" : "anexo original está indisponível")
        })
      let question = try decodePublicJournalV3(publicJournalV3Pages()[2]).items.first {
        $0.kind == .reply
      }!
      let questionHost = SignUpRenderingProbe.host(
        FlowConversationJournalV3Content(entry: question, feedback: nil, english: english),
        width: 390, height: 900)
      defer { questionHost.detach() }
      let questionNodes = questionHost.nodes()
      let questionBubble = try #require(questionNodes.first {
        $0.label.contains(english ? "Which meal was it?" : "Qual foi a refeição?")
      })
      let answerBubble = try #require(questionNodes.first {
        $0.identifier == "conversation.journal3.source"
      })
      #expect(questionBubble.frame.minY < answerBubble.frame.minY)
      #expect(
        !questionNodes.contains {
          $0.label.contains(
            english
              ? "Observed question, for reference only."
              : "Pergunta observada, apenas para consulta.")
        })
      #expect(
        !questionNodes.contains {
          $0.identifier.contains("reply.answer") || $0.identifier.contains("continue")
        })

    }
    @Test func completedMealKeepsOriginalSourceWithoutStaleFailure() throws {
      let pages = try publicJournalV3Pages()
      let entries = try decodePublicJournalV3(pages[5]).items
      let report = try #require(entries.first { $0.kind == .report })
      let original = try #require(try decodePublicJournalV3(pages[7]).items.first)
      let completedMeals = FlowConversationJournalV3Presentation.CompletedMeals(entries: entries)
      #expect(!completedMeals.showsOutcome(for: original))
      #expect(!completedMeals.showsOutcome(for: report))
      let incomplete = FlowConversationJournalV3Presentation.CompletedMeals(entries: [original])
      #expect(incomplete.showsOutcome(for: original))
      let host = SignUpRenderingProbe.host(
        FlowConversationJournalV3Content(
          entry: original, feedback: nil, english: false,
          showsOutcome: completedMeals.showsOutcome(for: original)),
        width: 390, height: 700)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(nodes.contains { $0.identifier == "conversation.journal3.source" })
      #expect(!nodes.contains { $0.identifier == "conversation.journal3.status" })
    }

    @Test(arguments: ["saved", "save_undone", "registration_undone"])
    func actualHistoricalEditVariantsRemainReadonlyInPTEN(_ change: String) throws {
      let entry = try decodePublicJournalV3(journalV3EditPageUnit(change: change)).items[0]
      for english in [false, true] {
        let host = SignUpRenderingProbe.host(
          FlowConversationJournalV3Content(entry: entry, feedback: nil, english: english),
          width: 390, height: 700)
        let nodes = host.nodes()
        let expected =
          english
          ? (change == "saved"
            ? "Meal updated"
            : change == "save_undone" ? "Meal change undone" : "Meal registration undone")
          : (change == "saved"
            ? "Refeição atualizada"
            : change == "save_undone"
              ? "Alteração de refeição desfeita" : "Registro de refeição desfeito")
        #expect(nodes.contains { $0.label.contains(expected) })
        #expect(
          !nodes.contains {
            $0.identifier.contains("meal.undo") || $0.identifier.contains("meal.edit")
              || $0.identifier.contains("continue")
          })
        host.detach()
      }
    }
  }
#endif
