import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit

  @MainActor @Suite("Cold reopened actual historical content")
  struct FlowConversationJournalV3RenderingTests {
    @Test(arguments: [false, true])
    func reopenedWorkoutRendersLiteralSixSectionsWithoutSaveOrWriteActions(_ english: Bool)
      async throws
    {
      let f = try await journalV3HTTPFixture()
      defer { f.disk.remove() }
      let lease = await f.http.lifecycle.leaseForRequest()
      let source = FlowConversationSessionSource(
        transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true)
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
      guard case .v3Sections(_, let sections) = feedback.presentation.content else {
        Issue.record("Missing sections")
        return
      }
      for section in sections {
        let node = try #require(
          nodes.first { $0.identifier == "conversation.feedback.section." + section.key.rawValue })
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
        nodes.contains {
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
      #expect(
        questionNodes.contains {
          $0.label.contains(english ? "Which meal was it?" : "Qual foi a refeição?")
        })
      #expect(
        questionNodes.contains {
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
