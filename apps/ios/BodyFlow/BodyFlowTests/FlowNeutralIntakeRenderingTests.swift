import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
  @MainActor @Suite("Real neutral composer and factual transcript content")
  struct FlowNeutralIntakeRenderingTests {
    @Test func actualFlowComposerMountsNeutralInputAndSendInsteadOfMealOnlyComposer() async throws {
      let f = try await neutralVisibleFixture()
      defer { f.disk.remove() }
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      let host = SignUpRenderingProbe.host(
        FlowConversationComposerContent(
          model: model, capture: nil, captureAction: { _ in }, discardAction: { _, _ in }
        ).environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 500)
      defer { host.detach() }
      let initial = host.nodes()
      // Vertical SwiftUI TextField embeds a UITextView/ScrollView. The shared
      // probe cannot read that scroll's AX descendants. Exercise the actual
      // mounted native input and its binding instead; no synthetic AX nodes.
      let fields = host.scrollViews().compactMap { $0 as? UITextView }
      #expect(fields.count == 1)
      let field = try #require(fields.first)
      #expect(
        field.window != nil && field.isEditable && field.isUserInteractionEnabled
          && !field.isHidden && field.bounds.width > 0 && field.bounds.height > 0)
      #expect(initial.contains { $0.identifier == "conversation.neutral.send" && !$0.isEnabled })
      #expect(field.becomeFirstResponder())
      field.insertText("leite integral 206 g")
      host.settle()
      #expect(neutral.composer == "leite integral 206 g" && field.text == "leite integral 206 g")
      neutral.mealTypeHint = .cafe
      let typed = host.nodes()
      #expect(
        typed.contains {
          $0.identifier == "conversation.neutral.send" && $0.isEnabled
            && $0.frame.width > 0 && $0.frame.height > 0
        }, Comment(rawValue: String(describing: typed)))
      field.resignFirstResponder()
      await neutral.submit()
      #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
      await model.close()
    }
    @Test(arguments: ["workout_known_unit", "workout_unknown_unit"])
    func confirmedWorkoutRendersFactualDurationAndUnknownEnergyDistinctly(_ variant: String)
      async throws
    {
      let f = try await neutralVisibleFixture(variant: variant)
      defer { f.disk.remove() }
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      neutral.composer = "Fiz 30 minutos de caminhada."
      await neutral.submit()
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeTranscriptContent(model: neutral).environment(
          \.locale, Locale(identifier: "pt_BR")), width: 390, height: 1000)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(nodes.contains { $0.label.contains("Atividade registrada") })
      #expect(nodes.contains { $0.label.contains("30 min") })
      #expect(!nodes.contains { $0.label.contains("154 kcal") || $0.label.contains("0 kcal") })
      if variant == "workout_unknown_unit" {
        #expect(nodes.contains { $0.label.contains("Gasto estimado indisponível") })
      } else {
        #expect(nodes.contains { $0.label.contains("O comentário atual está indisponível") })
      }
      await model.close()
    }
    @Test(arguments: ["pt", "en"])
    func workoutSixSectionsRenderVerbatimFromLegitimateCurrentPolicyWrapper(_ language: String)
      throws
    {
      let (saved, scope) = try neutralWorkoutPresentationUnit(language: language)
      let input = try FlowNeutralIntakeInput(intakeID: UUID(), source: .text("Fiz caminhada"))
      let bound = try #require(
        ConversationFeedbackPresentationSnapshot.boundWorkout(saved, scope: scope))
      let row = FlowNeutralIntakeSavedRow(
        input: input, acknowledgement: .workout(saved),
        identity: .init(
          authUserID: UUID(), ownerID: saved.ownerID, sessionGeneration: 7, epoch: saved.epoch),
        feedback: bound)
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeSavedContent(row: row, english: language == "en").environment(
          \.locale, Locale(identifier: language == "en" ? "en_US" : "pt_BR")), width: 390,
        height: 2400)
      defer { host.detach() }
      let nodes = host.nodes()
      guard case .v3Sections(_, let sections) = bound.presentation.content else {
        Issue.record("Missing six sections")
        return
      }
      for section in sections {
        let node = try #require(
          nodes.first { $0.identifier == "conversation.feedback.section." + section.key.rawValue })
        #expect(node.label == section.text && node.frame.width > 0 && node.frame.height > 0)
      }
    }
    @Test(arguments: [
      "meal_not_recorded_unit:pt", "meal_not_recorded_unit:en", "workout_not_recorded_unit:pt",
      "workout_not_recorded_unit:en",
    ])
    func selectedTypedNotRecordedRendersClosedWithoutWaitingOrContinuation(_ example: String)
      async throws
    {
      let parts = example.split(separator: ":").map(String.init)
      let english = parts[1] == "en"
      let f = try await neutralVisibleFixture(variant: parts[0])
      defer { f.disk.remove() }
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      neutral.composer = "Relato sem registro"
      await neutral.submit()
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeTranscriptContent(model: neutral).environment(
          \.locale, Locale(identifier: english ? "en_US" : "pt_BR")), width: 390, height: 1000)
      defer { host.detach() }
      let nodes = host.nodes()
      let text =
        english
        ? "This message did not record a meal or activity."
        : "Esta mensagem não registrou refeição nem atividade."
      #expect(nodes.contains { $0.label.contains(text) })
      #expect(
        !nodes.contains {
          $0.label.contains("Waiting for the original factual confirmation")
            || $0.label.contains("Aguardando a confirmação factual")
            || $0.identifier == "conversation.neutral.continue"
        })
      #expect(model.savedEffectRevision == 0 && neutral.savedRows.isEmpty)
      await model.close()
    }
    @Test func confirmedMealRendersFromTheRealControllerPublication() async throws {
      let f = try await neutralVisibleFixture()
      defer { f.disk.remove() }
      let model = try await FlowConversationModel.open(
        transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
        keyVault: f.vault, neutralIntakeEnabled: true)
      let neutral = try #require(model.neutralIntake)
      neutral.composer = "leite integral 206 g"
      neutral.mealTypeHint = .cafe
      await neutral.submit()
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeTranscriptContent(model: neutral).environment(
          \.locale, Locale(identifier: "pt_BR")), width: 390, height: 900)
      defer { host.detach() }
      #expect(host.nodes().contains { $0.label.contains("Refeição registrada") })
      #expect(host.nodes().contains { $0.label.contains("leite integral 206 g") })
      #expect(!host.nodes().contains { $0.label.contains("Atividade registrada") })
      await model.close()
    }
  }
#endif
