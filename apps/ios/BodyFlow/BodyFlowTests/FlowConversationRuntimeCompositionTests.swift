import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
#endif

@Suite("Real Flow factory keeps the original authenticated lease")
struct FlowConversationRuntimeCompositionTests {
  @Test @MainActor func sourceCannotRecaptureTheNextAccountBetweenFactoryAndFeatureOpen()
    async throws
  {
    let f = try EditControllerFixture()
    let report = try OutboxDiskFixture()
    defer {
      f.disk.remove()
      report.remove()
    }
    let lifecycle = RuntimeSwappingLifecycle(base: f.http.lifecycle, counter: .init())
    let source = FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: lifecycle,
      media: nil, store: report.store, editing: .init(store: f.disk.store, keyVault: f.vault))
    await #expect(throws: SessionLifecycleError.sessionSuperseded) {
      try await source.open(expectedUserID: f.disk.lease.userID)
    }
    #expect(await f.http.stub.requests.isEmpty)
    #expect(await f.http.lifecycle.workCount == 0)
    #expect(!FileManager.default.fileExists(atPath: f.disk.store.root.path))
  }
  @Test func bundledProtocolSelectionIsClosedAndDefaultsOff() {
    #expect(FlowConversationRuntimeSelection.load(nil) == .legacy)
    #expect(FlowConversationRuntimeSelection.load("legacy") == .legacy)
    #expect(FlowConversationRuntimeSelection.load("meal_command_v1") == .mealCommandV1)
    for raw: Any in [
      "", "meal_command_v2", " meal_command_v1", "$(FLOW)", true, 1, ["mode": "meal_command_v1"],
    ] {
      #expect(FlowConversationRuntimeSelection.load(raw) == .unavailable)
    }
  }
  #if canImport(UIKit)
    @Test(arguments: [AppBuildFlavor.debug, .release])
    func realFourTabCandidateIsBuildSelectableWithoutChangingPersistedRoutes(
      _ flavor: AppBuildFlavor
    ) {
      let layout = AppNavigationLayout.resolve(
        arguments: [], buildFlavor: flavor,
        runtimeMode: .releaseUnavailable, presentsRealAccountIdentity: true,
        realConversationCandidate: true)
      #expect(layout.visibleTabs == [.today, .plan, .register, .progress])
      #expect(layout.title(for: .today, language: .portugueseBrazil) == "Flow")
      #expect(layout.title(for: .plan, language: .portugueseBrazil) == "Alimentação")
      #expect(layout.title(for: .register, language: .portugueseBrazil) == "Treino")
      #expect(layout.title(for: .progress, language: .portugueseBrazil) == "Jornada")
      #expect(
        AppNavigationLayout.resolve(
          arguments: [], buildFlavor: flavor,
          runtimeMode: .releaseUnavailable, presentsRealAccountIdentity: true) == .legacy)
      #expect(
        AppNavigationLayout.resolve(
          arguments: [], buildFlavor: flavor,
          runtimeMode: .demo, presentsRealAccountIdentity: false, realConversationCandidate: true)
          == .legacy)
      #expect(AppTab(rawValue: "today") == .today && AppTab(rawValue: "profile") == .profile)
    }
    @Test(arguments: [
      "qualified", "default-off", "stable19ef", "invalid-qa", "legacy-clinical", "unknown",
      "other-project", "other-origin", "demo",
    ])
    @MainActor func actualAppDependencyFactoryRequiresTheExplicitCompatibleFamily(_ variant: String)
      async throws
    {
      let lifecycle = RuntimeAssemblyLifecycle()
      let origin =
        variant == "stable19ef"
        ? "https://performe-ai-staging-bff.vercel.app"
        : "https://performe-command-candidate.vercel.app"
      let qa: CurrentClinicalQABinding
      if variant == "stable19ef" {
        qa = .absent
      } else if variant == "invalid-qa" {
        qa = .invalid
      } else {
        qa = .load(from: [
          "origin": variant == "other-origin" ? "https://other-candidate.vercel.app" : origin,
          "deployment_id": "dpl_SyntheticCandidate",
          "project_id": CurrentClinicalQABinding.projectID,
          "source_manifest_sha256": String(repeating: "a", count: 64),
          "receipt_sha256": String(repeating: "b", count: 64), "region": "gru1",
        ])
      }
      let configuration = AppLaunchConfiguration.resolve(
        arguments: [], buildFlavor: variant == "demo" ? .debug : .release)
      let dependencies = AppDependencies.make(
        configuration: configuration,
        mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
          configuration: try .init(originString: origin)),
        supabaseAuthConfiguration: try .init(
          originString:
            "https://\(variant == "other-project" ? "otherproject" : "xitugspwfxkcluxvrdeg").supabase.co",
          key: "sb_publishable_synthetic"),
        authenticationSessionStore: .init(secureStore: InMemorySecureStore()),
        sessionLifecycleOverride: lifecycle,
        currentClinicalRuntimeMode: variant == "legacy-clinical" ? .legacy : .currentV1,
        currentClinicalQABinding: qa,
        flowConversationRuntime: variant == "default-off"
          ? .legacy : (variant == "unknown" ? .unavailable : .mealCommandV1))
      #expect((dependencies.flowConversationSessions != nil) == (variant == "qualified"))
      if variant == "qualified" {
        #expect(
          dependencies.presentsRealAccountIdentity
            && dependencies.flowConversationSessions?.captureStaging != nil)
      }
      #expect(await lifecycle.leaseCalls == 0)
      if variant == "qualified" || variant == "default-off" {
        let userID = "90000000-0000-4000-8000-000000000001"
        let owner = Prompt14SessionOwner(userID: userID, dependencies: dependencies)
        let shell = AppShellView(userID: userID, dependencies: dependencies, sessionOwner: owner)
        #expect(
          shell.navigationLayout == (variant == "qualified" ? .conversationalPreview : .legacy))
        #expect((owner.flowConversation != nil) == (variant == "qualified"))
        owner.invalidateSynchronously()
        #expect(owner.flowConversation?.phase == (variant == "qualified" ? .closed : nil))
        await owner.endSession()
      }
    }
  #endif
  @Test @MainActor func actualSourceIsInertThenOpensRealCommandAndEditModelsWithDistinctPatient()
    async throws
  {
    let f = try EditControllerFixture()
    let report = try OutboxDiskFixture()
    defer {
      f.disk.remove()
      report.remove()
    }
    await f.seedKey()
    let keys = OutboxKeychainFake()
    await keys.seed(report.key.withUnsafeBytes { Data($0) }, owner: f.disk.owner.hash)
    let source = FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle,
      media: nil, store: report.store, keyVault: .init(service: "synthetic", security: keys),
      editing: .init(store: f.disk.store, keyVault: f.vault))
    #expect(await f.http.stub.requests.isEmpty)
    #expect(await f.http.lifecycle.workCount == 0)
    let wire = try ConversationControllerWireFixture()
    await f.http.stub.respond { _, _ in try wire.sessionReply(epoch: f.group.epoch) }
    let session = try await source.open(expectedUserID: f.disk.lease.userID)
    let identity = try #require(session.model.acceptedIdentity)
    #expect(
      identity.authUserID == UUID(uuidString: f.disk.lease.userID)
        && identity.ownerID == f.group.ownerID)
    #expect(identity.authUserID != identity.ownerID && identity.epoch == f.group.epoch)
    #expect(session.model.mealEditor != nil)
    #expect(await f.http.stub.requests.count == 1)
    var published = false
    try await session.publishIfCurrent { _ in published = true }
    #expect(published)
    session.model.composer = "private synthetic original draft"
    let editor = try #require(session.model.mealEditor)
    try editor.beginEditing(group: f.group, itemID: #require(f.group.current?.items.first?.id))
    #expect(!editor.foodName.isEmpty)
    session.invalidateSynchronously()
    #expect(
      session.model.isClosed && session.model.composer.isEmpty && editor.foodName.isEmpty
        && editor.presentation == nil)
    await #expect(throws: (any Error).self) {
      try await session.publishIfCurrent { _ in Issue.record("Closed owner cannot publish") }
    }
    await session.close()
    #expect(await f.http.lifecycle.workCount == 0)
  }
  @Test @MainActor func wrongOriginalAuthOwnerIsRefusedBeforeAnyRequestOrCiphertext() async throws {
    let f = try EditControllerFixture()
    defer { f.disk.remove() }
    let source = FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle,
      media: nil, editing: .init(store: f.disk.store, keyVault: f.vault))
    await #expect(throws: SessionLifecycleError.sessionSuperseded) {
      try await source.open(expectedUserID: UUID().uuidString.lowercased())
    }
    #expect(await f.http.stub.requests.isEmpty)
    #expect(await f.http.lifecycle.workCount == 0)
    #expect(!FileManager.default.fileExists(atPath: f.disk.store.root.path))
  }
  @Test(arguments: ["command", "edit", "feature"])
  func supersededOriginalLeaseCannotOpenUsingTheReplacementAccount(_ target: String) async throws {
    let f = try EditControllerFixture()
    let report = try OutboxDiskFixture()
    defer {
      f.disk.remove()
      report.remove()
    }
    let original = await f.http.lifecycle.leaseForRequest()
    await f.http.lifecycle.replace(
      .init(
        userID: UUID().uuidString.lowercased(), generation: original.generation + 1,
        bearer: "synthetic-replacement-factory-account"))
    let wire = try ConversationControllerWireFixture()
    await f.http.stub.respond { _, _ in try wire.sessionReply() }
    await #expect(throws: SessionLifecycleError.sessionSuperseded) {
      switch target {
      case "command":
        let controller = try await ConversationMealCommandController.open(
          transport: f.http.transport,
          lifecycle: f.http.lifecycle, store: report.store, expectedLease: original)
        await controller.close()
      case "edit":
        let controller = try await ConversationMealEditController.open(
          transport: f.http.transport,
          lifecycle: f.http.lifecycle, store: f.disk.store, keyVault: f.vault,
          expectedLease: original)
        await controller.close()
      default:
        let model = try await FlowConversationModel.open(
          transport: f.http.transport,
          lifecycle: f.http.lifecycle, store: report.store, expectedLease: original)
        await model.close()
      }
    }
    #expect(await f.http.stub.requests.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: report.store.fileURL(owner: f.disk.owner).path))
    #expect(!FileManager.default.fileExists(atPath: f.disk.store.fileURL(owner: f.disk.owner).path))
    #expect(await f.http.lifecycle.workCount == 0)
  }
}

private actor RuntimeLeaseCounter {
  private var count = 0
  func next(_ base: ConversationHTTPTestLifecycle) async -> SessionLease {
    count += 1
    if count == 2 {
      await base.replace(
        .init(
          userID: UUID().uuidString.lowercased(), generation: 8,
          bearer: "synthetic-factory-mid-open-swap"))
    }
    return await base.leaseForRequest()
  }
}
private struct RuntimeSwappingLifecycle: SessionLifecycleProviding {
  let base: ConversationHTTPTestLifecycle
  let counter: RuntimeLeaseCounter
  func currentBearerToken() async -> String? { await base.currentBearerToken() }
  func leaseForRequest() async throws -> SessionLease { await counter.next(base) }
  func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
  func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
    try await base.refreshAfterUnauthorized(lease: lease)
  }
  func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
  func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws
    -> UUID
  { try await base.beginPatientWork(lease: lease, cancel: cancel) }
  func finishPatientWork(_ id: UUID) async { await base.finishPatientWork(id) }
  func performPatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @Sendable () throws -> Value
  ) async throws -> Value {
    try await base.performPatientStateOperation(lease: lease, operation: operation)
  }
  func performVisiblePatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @MainActor @Sendable () throws -> Value
  ) async throws -> Value {
    try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
  }
}

#if canImport(UIKit)
  private actor RuntimeAssemblyLifecycle: SessionLifecycleProviding {
    private(set) var leaseCalls = 0
    func currentBearerToken() async -> String? { nil }
    func leaseForRequest() async throws -> SessionLease {
      leaseCalls += 1
      throw SessionLifecycleError.missingSession
    }
    func validate(_ lease: SessionLease) async throws { throw SessionLifecycleError.missingSession }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
      throw SessionLifecycleError.missingSession
    }
    func signOut() async -> RemoteRevocationOutcome { .confirmed }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws
      -> UUID
    { throw SessionLifecycleError.missingSession }
    func finishPatientWork(_ id: UUID) async {}
  }
#endif
