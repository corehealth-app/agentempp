import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  @MainActor @Suite("Training protocol is selected by the real dependency factory")
  struct TrainingExecutionRuntimeSelectionTests {
    @Test(arguments: [false, true])
    func actualFactoryUsesOnlyTheSelectedProtocolAndRetainsTheOriginalLogin(_ completion: Bool)
      async throws
    {
      let h = try await TrainingRuntimeFactoryHarness.make(completion: completion)
      let source = try #require(h.dependencies.trainingExecutionSessions)
      #expect(await h.stub.requests.isEmpty)
      let model = try await source.open(expectedUserID: h.authID)
      #expect(model.supportsCompletion == completion)
      await model.load()
      #expect(model.home != nil && model.failure == nil)
      let requests = await h.stub.requests
      #expect(
        requests.map { $0.url!.path } == [
          "/api/mobile/v1/me",
          "/api/mobile/v1/training/" + (completion ? "execution-v2" : "execution"),
        ])
      #expect(requests.allSatisfy { $0.httpMethod == "GET" })
      let count = requests.count
      await h.lifecycle.replace(
        .init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-next"))
      await model.load()
      #expect(await h.stub.requests.count == count)
      await model.close()
    }

    @Test func unavailableCompletionNeverFallsBackToProgressOrDisablesFlow() async throws {
      let h = try await TrainingRuntimeFactoryHarness.make(
        completion: true, selection: .unavailable)
      #expect(h.dependencies.trainingExecutionSessions == nil)
      #expect(h.dependencies.flowConversationSessions != nil)
      #expect(h.dependencies.currentClinicalReadSessions != nil)
      #expect(await h.stub.requests.isEmpty)
    }

    @Test func failedCompletionHomeNeverFallsBackToTheOldEndpoint() async throws {
      let h = try await TrainingRuntimeFactoryHarness.make(completion: true)
      let source = try #require(h.dependencies.trainingExecutionSessions)
      let model = try await source.open(expectedUserID: h.authID)
      await h.stub.respond { _, _ in .failure(503, "training_completion_unavailable") }
      await model.load()
      #expect(model.supportsCompletion && model.home == nil && model.failure != nil)
      #expect(
        await h.stub.requests.map { $0.url!.path } == [
          "/api/mobile/v1/me", "/api/mobile/v1/training/execution-v2",
        ])
      await model.close()
    }
  }

  @MainActor private struct TrainingRuntimeFactoryHarness {
    let dependencies: AppDependencies
    let stub: ConversationHTTPStub
    let lifecycle: ConversationHTTPTestLifecycle
    let authID: String

    static func make(completion: Bool, selection: TrainingExecutionRuntimeSelection? = nil)
      async throws -> Self
    {
      let fixture = try TrainingCompletionFixture()
      let progressFixture = try TrainingExecutionFixture()
      let progressHome = try TrainingExecutionHomeSnapshot(data: progressFixture.data("home"))
      let authID =
        try completion
        ? fixture.finish().binding.authUserID.uuidString.lowercased()
        : progressHome.scope.authUserID.uuidString.lowercased()
      let lifecycle = ConversationHTTPTestLifecycle()
      await lifecycle.replace(
        .init(userID: authID, generation: 7, bearer: "synthetic-factory-training"))
      let stub = ConversationHTTPStub()
      let host = UUID().uuidString.lowercased() + ".vercel.app"
      let origin = "https://" + host
      let completionServer = CompletionTransportServer(fixture: fixture)
      let progressServer = try TrainingNativeServer(fixture: progressFixture)
      await stub.respond { request, _ in
        if completion { return try await completionServer.reply(request) }
        return try await progressServer.reply(request)
      }
      let dependencies = AppDependencies.make(
        configuration: .resolve(arguments: [], buildFlavor: .release),
        mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
          configuration: try .init(originString: origin)),
        mobileAPISession: ConversationHTTPFixture.makeSession(host: host, stub: stub),
        supabaseAuthConfiguration: try .init(
          originString: "https://xitugspwfxkcluxvrdeg.supabase.co", key: "sb_publishable_synthetic"),
        authenticationSessionStore: .init(secureStore: InMemorySecureStore()),
        sessionLifecycleOverride: lifecycle,
        currentClinicalRuntimeMode: .currentV1,
        currentClinicalQABinding: .load(from: [
          "origin": origin, "deployment_id": "dpl_SyntheticTrainingFactory",
          "project_id": CurrentClinicalQABinding.projectID,
          "source_manifest_sha256": String(repeating: "a", count: 64),
          "receipt_sha256": String(repeating: "b", count: 64), "region": "gru1",
        ]),
        flowConversationRuntime: .neutralIntakeV1,
        trainingExecutionRuntime: selection ?? (completion ? .completionV1 : .progressV1))
      return .init(dependencies: dependencies, stub: stub, lifecycle: lifecycle, authID: authID)
    }
  }
#endif
