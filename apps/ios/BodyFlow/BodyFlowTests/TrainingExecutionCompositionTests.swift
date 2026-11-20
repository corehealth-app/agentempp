import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI

  @MainActor @Suite("Training editor preserves actual values and shell ownership")
  struct TrainingExecutionCompositionTests {
    @Test func sourceIsInertAndRootWithdrawsItsActualModelSynchronously() async throws {
      let h = try await TrainingNativeHarness.make()
      let count = await h.http.stub.requests.count
      let source = TrainingExecutionSessionSource(
        transport: h.http.transport, lifecycle: h.http.lifecycle, pendingStore: h.store)
      var deps = AppDependencies.scaffold()
      deps.trainingExecutionSessions = source
      let owner = Prompt14SessionOwner(
        userID: h.repository.authUserID.uuidString.lowercased(), dependencies: deps)
      let coordinator = try #require(owner.trainingExecution)
      #expect(coordinator.model == nil)
      #expect(await h.http.stub.requests.count == count)
      await coordinator.load()
      let model = try #require(coordinator.model)
      await model.load()
      #expect(model.home?.scope.ownerID == h.repository.ownerID)
      owner.invalidateSynchronously()
      #expect(model.isClosed && coordinator.model == nil)
      await owner.endSession()
      #expect(!owner.hasRetainedCapabilities)
      let closedCount = await h.http.stub.requests.count
      await coordinator.load()
      #expect(await h.http.stub.requests.count == closedCount)
    }
    @Test func sourceCannotBindTheNextLoginOrPublishALateOpen() async throws {
      let h = try await TrainingNativeHarness.make()
      let source = TrainingExecutionSessionSource(
        transport: h.http.transport, lifecycle: h.http.lifecycle, pendingStore: h.store)
      let count = await h.http.stub.requests.count
      await #expect(throws: SessionLifecycleError.sessionSuperseded) {
        try await source.open(expectedUserID: UUID().uuidString)
      }
      #expect(await h.http.stub.requests.count == count)
      let barrier = ConversationControllerBarrier()
      await h.http.stub.respond { request, _ in
        await barrier.enter()
        await barrier.finish()
        return try await h.server.reply(request)
      }
      let coordinator = TrainingExecutionShellCoordinator(
        userID: h.repository.authUserID.uuidString.lowercased(), source: source)
      let load = Task { await coordinator.load() }
      #expect(await barrier.waitEnteredOrFinished())
      coordinator.invalidateSynchronously()
      await barrier.release()
      await load.value
      await coordinator.close()
      #expect(coordinator.model == nil && coordinator.phase == .closed)
    }
    @Test(arguments: [false, true]) func prescriptionDoesNotShowUnperformedSetsAsDone(
      _ english: Bool
    ) throws {
      let fixture = try TrainingExecutionFixture()
      let snapshot = try TrainingExecutionMutationSnapshot(data: fixture.data("created"))
      let view = TrainingExecutionPrescriptionFactsView(
        prescription: snapshot.session.definition.exercises[0],
        actual: snapshot.session.exercises[0], english: english)
      let host = SignUpRenderingProbe.host(view, width: 390, height: 400)
      defer { host.detach() }
      let node = try #require(
        host.nodes().first { $0.identifier == "training.execution.exercise.0" })
      #expect(node.label.contains(english ? "Recommended" : "Recomendado"))
      #expect(node.label.contains("3"))
      #expect(node.label.contains(english ? "No sets recorded" : "Nenhuma série anotada"))
      #expect(!node.label.contains(english ? "3 completed" : "3 concluídas"))
    }
    @Test func actualZeroLoadAndUnknownRepetitionsAreVisibleAsDifferentFacts() throws {
      let set = try TrainingExecutionSet(
        id: UUID(), index: 0, repetitions: nil, loadKg: 0, durationSeconds: nil, completed: true)
      let host = SignUpRenderingProbe.host(
        TrainingExecutionActualSetView(set: set, english: false), width: 390, height: 250)
      defer { host.detach() }
      let node = try #require(
        host.nodes().first { $0.identifier.hasPrefix("training.execution.actual.") })
      #expect(node.label.contains("0 kg") && node.label.contains("Repetições não informadas"))
      #expect(!node.label.contains("0 repetições"))
    }
    @Test func editorPreservesAnExistingSetIdentityAndAcceptsCommaWithoutInventingUnknownNumbers()
      throws
    {
      let original = try TrainingExecutionSet(
        id: UUID(), index: 2, repetitions: nil, loadKg: nil, durationSeconds: nil, completed: false)
      var draft = TrainingExecutionSetDraft(set: original)
      draft.load = "15,5"
      draft.completed = true
      let result = try draft.actual()
      #expect(result.id == original.id && result.index == 2)
      #expect(result.loadKg == 15.5 && result.repetitions == nil && result.durationSeconds == nil)
      draft.repetitions = "0"
      draft.load = "0"
      #expect(try draft.actual().repetitions == 0 && draft.actual().loadKg == 0)
    }
    @Test(arguments: ["-1", "NaN", "1e3", "1.000,5", "10000.01", "Infinity"])
    func editorRejectsInvalidLoadWithoutClampingItToZero(_ input: String) throws {
      var draft = TrainingExecutionSetDraft(index: 0)
      draft.load = input
      #expect(throws: (any Error).self) { try draft.actual() }
    }
  }
#endif

#if canImport(UIKit)
  extension TrainingExecutionCompositionTests {
    @Test func editingAnUntouchedTinyKnownLoadPreservesTheExactStoredValue() throws {
      let original = try TrainingExecutionSet(
        id: UUID(), index: 0, repetitions: nil, loadKg: 0.0000001, durationSeconds: nil,
        completed: true)
      let draft = TrainingExecutionSetDraft(set: original)
      #expect(try draft.actual().loadKg == original.loadKg)
    }
  }
#endif

#if canImport(UIKit)
  extension TrainingExecutionCompositionTests {
    @Test func editorExplainsAndDisablesSaveAfterTheSessionBecomesTerminal() async throws {
      let h = try await TrainingNativeHarness.make()
      let model = h.model()
      await model.load()
      #expect(await model.start(dayIndex: 0))
      let id = try #require(model.session?.id)
      try await h.server.abandonFromAnotherClient()
      await model.select(id)
      #expect(model.session?.phase == .abandoned && !model.canEdit)
      let host = SignUpRenderingProbe.host(
        TrainingExecutionSetEditor(model: model, exercise: 0, draft: .init(index: 0)), width: 390,
        height: 900)
      defer { host.detach() }
      let nodes = host.nodes()
      // The toolbar also exposes a non-button layout wrapper with this identifier.
      // Inspect the actionable button's disabled trait, not that wrapper.
      let save = try #require(nodes.first {
        $0.identifier == "training.execution.editor.save" && $0.isButton
      })
      #expect(!save.isEnabled)
      #expect(nodes.contains { $0.identifier == "training.execution.editor.readonly" })
    }
  }
#endif

#if canImport(UIKit)
  extension TrainingExecutionCompositionTests {
    @Test func completePlanReadRemainsReachableWithoutCreatingAnExecution() async throws {
      let h = try await TrainingNativeHarness.make()
      let coordinator = TrainingExecutionShellCoordinator(
        userID: h.repository.authUserID.uuidString.lowercased(),
        source: .init(
          transport: h.http.transport, lifecycle: h.http.lifecycle, pendingStore: h.store))
      await coordinator.load()
      let model = try #require(coordinator.model)
      await model.load()
      let plan = PlanViewModel(provider: AppDependencies.scaffold().plan)
      let host = SignUpRenderingProbe.host(
        NavigationStack { TrainingExecutionRootView(coordinator: coordinator, plan: plan) },
        width: 390, height: 900)
      defer { host.detach() }
      let node = host.nodes().first { $0.identifier == "training.execution.full-plan" }
      #expect(node?.isButton == true && node?.isEnabled == true)
      #expect(await h.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
      await coordinator.close()
    }
  }
#endif
