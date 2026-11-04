import Foundation

/// Bundled build selection, never a launch argument, user setting or server
/// grant. Actual protocol/session authority still comes from authenticated GET.
enum FlowConversationRuntimeSelection: Equatable, Sendable {
  case legacy, mealCommandV1, unavailable
  static let infoKey = "PERFORME_FLOW_COMMAND_RUNTIME"
  static func load(_ raw: Any?) -> Self {
    guard let raw else { return .legacy }
    guard let value = raw as? String else { return .unavailable }
    switch value {
    case "legacy": return .legacy
    case "meal_command_v1": return .mealCommandV1
    default: return .unavailable
    }
  }
  var requestsRealAccount: Bool { self != .legacy }
}

/// Inert concrete factory. Production composition supplies real owned media;
/// construction starts no request, key access, permission or Storage upload.
struct FlowConversationSessionSource: Sendable {
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private let media: FlowConversationMediaDependencies?
  private let store: EncryptedConversationOutboxStore
  private let keyVault: ConversationOutboxKeyVault
  private let editing: FlowConversationMealEditingDependencies
  var captureStaging: MediaStagingStore? { media?.staging }
  init(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    media: FlowConversationMediaDependencies?,
    store: EncryptedConversationOutboxStore = .device,
    keyVault: ConversationOutboxKeyVault = .init(),
    editing: FlowConversationMealEditingDependencies = .init()
  ) {
    self.transport = transport
    self.lifecycle = lifecycle
    self.media = media
    self.store = store
    self.keyVault = keyVault
    self.editing = editing
  }
  @MainActor func open(expectedUserID: String) async throws -> FlowConversationBoundSession {
    try Task.checkCancellation()
    let lease = try await lifecycle.leaseForRequest()
    guard let expected = UUID(uuidString: expectedUserID),
      UUID(uuidString: lease.userID) == expected
    else { throw SessionLifecycleError.sessionSuperseded }
    try await lifecycle.validate(lease)
    let model = try await FlowConversationModel.open(
      transport: transport, lifecycle: lifecycle, store: store, keyVault: keyVault,
      media: media, editing: editing, linkedReplies: true, historyVersion: .v2, expectedLease: lease
    )
    let session = FlowConversationBoundSession(model: model, lifecycle: lifecycle, lease: lease)
    do {
      try await lifecycle.validate(lease)
      try Task.checkCancellation()
      try await session.publishIfCurrent { _ in }
      return session
    } catch {
      await session.close()
      throw error
    }
  }
}

/// Created only by the concrete source. The original Auth lease and actual
/// command grant fence publication together; no patient/epoch is fabricated.
@MainActor
final class FlowConversationBoundSession: CustomStringConvertible, CustomReflectable {
  let model: FlowConversationModel
  private let lifecycle: any SessionLifecycleProviding
  private var lease: SessionLease?
  fileprivate init(
    model: FlowConversationModel, lifecycle: any SessionLifecycleProviding, lease: SessionLease
  ) {
    self.model = model
    self.lifecycle = lifecycle
    self.lease = lease
  }
  func publishIfCurrent(
    _ publish: @escaping @MainActor @Sendable (FlowConversationBoundSession) -> Void
  ) async throws {
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    try await lifecycle.validate(lease)
    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
      guard self.lease != nil, !self.model.isClosed else {
        throw ConversationOutboxError.sessionClosed
      }
      try Task.checkCancellation()
      try self.model.withCurrentAuthority {
        guard let identity = self.model.acceptedIdentity,
          identity.authUserID == UUID(uuidString: lease.userID),
          identity.sessionGeneration == lease.generation
        else { throw SessionLifecycleError.sessionSuperseded }
        publish(self)
      }
    }
  }
  func invalidateSynchronously() {
    lease = nil
    model.invalidateSynchronously()
  }
  func close() async {
    invalidateSynchronously()
    await model.close()
  }
  nonisolated var description: String { "FlowConversationBoundSession(redacted)" }
  nonisolated var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .class) }
}
