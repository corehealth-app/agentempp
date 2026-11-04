import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
#endif

@Suite("Flow renders genuine linked history without invented meal facts")
struct FlowConversationThreadEventViewTests {
  @Test func actualFiveKindsKeepNegativeReportAndSavedChildSeparate() throws {
    let page = try fixture()
    let parent = try #require(page.threads.first)
    let rows = page.items.map {
      FlowConversationThreadEventPresentation(
        entry: $0, parent: parent, observedQuestion: nil, english: false)
    }
    #expect(rows[4].title == "Relato original não registrado")
    #expect(rows[4].sourceText == "Comi leite")
    #expect(rows[1].title == "Refeição registrada após resposta vinculada")
    #expect(rows[1].linkedActionGate != nil)
    #expect(rows[3].lines.contains("200 mL"))
    #expect(
      rows[3].lines.contains("Pergunta daquela resposta: Qual quantidade de leite você consumiu?"))
    #expect(rows[2].title == "Preparação histórica concluída")
    #expect(rows[0].title == "Edição salva")
    #expect(rows.allSatisfy { $0.observedQuestionLines.isEmpty })
    #expect(rows.flatMap(\.lines).allSatisfy { !$0.contains("kcal") && !$0.contains("cmeal1:") })
  }

  @Test func observedQuestionIsClearlyReadOnlyAndNeverRelabelsHistoricalAnswer() throws {
    let page = try fixture()
    let parent = try #require(page.threads.first)
    guard case .reply(let reply) = page.items[3].detail else {
      Issue.record("Actual reply required")
      return
    }
    let value = FlowConversationThreadEventPresentation(
      entry: page.items[4], parent: parent, observedQuestion: reply.question, english: false)
    #expect(value.observedQuestionLines.contains("Pergunta observada no histórico"))
    #expect(value.observedQuestionLines.contains("Qual quantidade de leite você consumiu?"))
    #expect(
      value.observedQuestionLines.contains(
        "A resposta vinculada ainda não está disponível. Seu relato original está preservado."))
  }

  #if canImport(UIKit)
    @Test @MainActor func actualSDKChildUsesItsRealRegistrationIDAndSixLiteralMaskedSections()
      throws
    {
      // Actual coherent SDK pieces; not a fabricated journal/command envelope.
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/ConversationLinkedFeedbackSDKFixtures.json")
      let raw = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
      func decode<T: Decodable>(_ type: T.Type, _ key: String) throws -> T {
        let value = try #require(raw[key])
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
      }
      let child = try decode(ConversationThreadPageSnapshot.Binding.self, "childBinding")
      let parent = try decode(ConversationThreadPageSnapshot.Binding.self, "parentBinding")
      let receipt = try decode(ConversationThreadPageSnapshot.LinkedReceipt.self, "receipt")
      let presentation = try decode(ConversationFeedbackPresentationSnapshot.self, "presentation")
      let decision = try #require(raw["parentDecisionHash"] as? String)
      try #require(receipt.matches(child: child, parent: parent, decisionHash: decision))
      let scope = ConversationFeedbackPresentationSnapshot.Scope(
        ownerID: child.ownerID.uuidString.lowercased(), sessionGeneration: 7,
        epoch: child.epoch.uuidString.lowercased())
      let feedback = try #require(receipt.boundFeedback(presentation, binding: child, scope: scope))
      #expect(receipt.registrationID != child.commandID)
      let host = SignUpRenderingProbe.host(
        ConversationFeedbackPresentationView(feedback: feedback), width: 390, height: 1800)
      defer { host.detach() }
      let nodes = host.nodes()
      guard case .sections(_, let sections) = presentation.content else {
        Issue.record("Six sections required")
        return
      }
      #expect(sections.count == 6)
      for section in sections {
        let node = try #require(
          nodes.first {
            $0.identifier == "conversation.feedback.section.\(section.key.rawValue)" && $0.isElement
          })
        #expect(node.label.utf16.elementsEqual(section.text.utf16))
        #expect(node.frame.width > 0 && node.frame.height > 0)
      }
      #expect(
        nodes.contains {
          $0.identifier == "conversation.feedback.historical"
            && $0.label.contains(receipt.localDate)
        })
    }

    @Test @MainActor func actualNativeComponentShowsEachRealVariantAndNoChildEditor() throws {
      let page = try fixture()
      let parent = try #require(page.threads.first)
      for entry in page.items {
        let expected = FlowConversationThreadEventPresentation(
          entry: entry, parent: parent, observedQuestion: nil, english: false)
        let host = SignUpRenderingProbe.host(
          FlowConversationThreadEventView(
            entry: entry, parent: parent, observedQuestion: nil, feedback: nil, english: false),
          width: 390, height: 1600)
        defer { host.detach() }
        let nodes = host.nodes()
        let title = try #require(nodes.first { $0.label == expected.title && $0.isElement })
        #expect(title.frame.width > 0 && title.frame.height > 0)
        if let source = expected.sourceText {
          #expect(nodes.contains { $0.label.utf16.elementsEqual(source.utf16) && $0.isElement })
        }
        for line in expected.lines {
          #expect(nodes.contains { $0.label.utf16.elementsEqual(line.utf16) && $0.isElement })
        }
        #expect(
          !nodes.contains {
            $0.identifier.contains("meal.edit")
              || $0.identifier.contains("conversation.feedback.section")
          })
      }
    }
  #endif

  private func fixture() throws -> ConversationThreadPageSnapshot {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(
          forResource: "ConversationThreadPagePublicFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationThreadPagePublicFixtures.json")
    #endif
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let data = try #require(object["data"])
    return try .init(data: JSONSerialization.data(withJSONObject: data))
  }
}
