import Foundation

/// Inert source; never installed by default or by a launch-argument grant.
struct JourneySocialSessionSource: Sendable {
  let transport: MobileAPITransport
  let lifecycle: any SessionLifecycleProviding
  let pendingStore: JourneySocialPendingStore?
  init(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    pendingStore: JourneySocialPendingStore? = nil
  ) {
    self.transport = transport
    self.lifecycle = lifecycle
    self.pendingStore = pendingStore
  }
  @MainActor func open(expectedUserID: String) async throws -> JourneySocialModel {
    try Task.checkCancellation()
    guard let expected = UUID(uuidString: expectedUserID),
      transport.supportsCurrentClinicalSessionBinding
    else {
      throw SessionLifecycleError.sessionSuperseded
    }
    let lease = try await lifecycle.leaseForRequest()
    guard UUID(uuidString: lease.userID) == expected else {
      throw SessionLifecycleError.sessionSuperseded
    }
    try await lifecycle.validate(lease)
    let repository = try await MobileJourneySocialRepository.scoped(
      transport: transport, lifecycle: lifecycle, lease: lease)
    let store: JourneySocialPendingStore
    if let pendingStore {
      store = pendingStore
    } else {
      store = try await .live(origin: repository.origin)
    }
    let model = try JourneySocialModel(provider: repository, store: store)
    do {
      try await model.publishIfCurrent {}
      return model
    } catch {
      await model.close()
      throw error
    }
  }
}
