import Foundation

/// Serializes explicit user actions around protected storage and the original
/// account lease. Reads never reconcile, retry or silently retire an intent.
actor JourneySocialPendingSession {
  nonisolated let binding: JourneySocialBinding
  nonisolated let origin: URL
  private let provider: any JourneySocialProviding
  private let store: JourneySocialPendingStore
  private var busy = false

  init(provider: any JourneySocialProviding, store: JourneySocialPendingStore) throws {
    binding = provider.binding
    origin = try journeySocialOrigin(provider.origin)
    self.provider = provider
    self.store = store
  }
  func pending() async throws -> JourneySocialPendingOperation? {
    try enter()
    defer { busy = false }
    try await validate()
    let value = try await store.load(authUserID: binding.authUserID)
    try await validate()
    if let value { try validateScope(value) }
    return value
  }
  func submit(_ operation: JourneySocialOperation) async throws -> JourneySocialMutationSnapshot {
    try enter()
    defer { busy = false }
    try await validate()
    guard operation.binding == binding else { throw SessionLifecycleError.sessionSuperseded }
    let pending = try JourneySocialPendingOperation(origin: origin, operation: operation)
    try await store.claim(pending)
    try await validate()
    let result = try await provider.submit(operation)
    try await validate()
    try await store.acknowledge(pending, result: result)
    try await validate()
    return result
  }
  func recover(_ pending: JourneySocialPendingOperation) async throws
    -> JourneySocialResolutionSnapshot
  {
    try enter()
    defer { busy = false }
    try await validate()
    try validateScope(pending)
    guard try await store.load(authUserID: binding.authUserID) == pending else {
      throw JourneySocialPendingError.pendingOperation
    }
    try await validate()
    let result = try await provider.recover(pending)
    try await validate()
    try await store.acknowledgeResolution(pending, result: result, current: binding)
    try await validate()
    return result
  }
  private func enter() throws {
    guard !busy else { throw JourneySocialPendingError.pendingOperation }
    busy = true
  }
  private func validateScope(_ pending: JourneySocialPendingOperation) throws {
    guard pending.origin == origin, pending.matches(binding) else {
      throw JourneySocialPendingError.scopeChanged
    }
  }
  private func validate() async throws {
    try Task.checkCancellation()
    try await provider.validate()
    try Task.checkCancellation()
  }
}
