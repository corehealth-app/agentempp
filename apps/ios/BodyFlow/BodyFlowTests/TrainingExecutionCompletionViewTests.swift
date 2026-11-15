import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  @MainActor @Suite("Actual completed training has a distinct visible outcome")
  struct TrainingExecutionCompletionViewTests {
    @Test func genuineCompletedSessionIsNotLabelledInProgress() async throws {
      let h = try await CompletionModelHarness.make()
      let model = h.model()
      await model.load()
      await model.select(h.operation.sessionID)
      #expect(await model.finish(report: h.report))
      // This OS does not expose the root ScrollView through the in-process AX
      // probe. Host the exact phase component used by that root, from its actual
      // validated model state; this is component proof, not full native UI QA.
      let host = SignUpRenderingProbe.host(
        TrainingExecutionPhaseView(phase: try #require(model.session?.phase), english: false),
        width: 390, height: 180)
      defer { host.detach() }
      let nodes = host.nodes()
      let phase = try #require(nodes.first { $0.identifier == "training.execution.phase" })
      #expect(phase.label == "Execução concluída")
    }
  }
#endif

#if canImport(UIKit)
  extension TrainingExecutionCompletionViewTests {
    @Test func completionSummaryShowsActualDurationAndAllSixHistoricalFeedbackSections() throws {
      let f = try TrainingCompletionFixture()
      let value = try TrainingExecutionCompletionSnapshot(data: f.data("completed_completion"))
      let host = SignUpRenderingProbe.host(
        TrainingExecutionCompletionFactsView(completion: value, english: false), width: 390,
        height: 1800)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(nodes.contains { $0.label == "Treino registrado" })
      #expect(nodes.contains { $0.label == "30 min" })
      for key in ["saved", "items", "summary", "day", "block", "education"] {
        #expect(nodes.contains { $0.identifier == "training.completion.feedback." + key })
      }
    }
    @Test func userShareContainsOnlyPerformedFactsAndRefusesReservedOrRemovedRecords() throws {
      let f = try TrainingCompletionFixture()
      let value = try TrainingExecutionCompletionSnapshot(data: f.data("completed_completion"))
      let content = try #require(TrainingExecutionShareContent(completion: value, english: false))
      #expect(
        content.text.contains("30 min") && content.text.contains("15,5 kg")
          && content.text.contains("8 repetições"))
      #expect(!content.text.contains(value.ownerID.uuidString.lowercased()))
      #expect(
        !content.text.contains("7.700") && !content.text.contains("proteína")
          && !content.text.contains("Recomendado"))
      #expect(
        TrainingExecutionShareContent(
          completion: try TrainingExecutionCompletionSnapshot(data: f.data("reserved_completion")),
          english: false) == nil)
      var raw = try f.object("completed_completion")
      raw["workout_state"] = "removed"
      #expect(
        TrainingExecutionShareContent(
          completion: try TrainingExecutionCompletionSnapshot(
            data: JSONSerialization.data(withJSONObject: raw)), english: true) == nil)
    }
  }
#endif
