import Foundation

/// An accepted authenticated read, not a payload signature or independent
/// clinical authority. The controller owns and revokes its internal grant.
struct ConversationCommandContext: Sendable {
  struct Identity: Equatable, Sendable {
    let authUserID: UUID
    let ownerID: UUID
    let sessionGeneration: UInt64
    let epoch: UUID
  }
  let observation: ConversationOutboxServerObservation
  let observedAt: String
  var authUserID: UUID { observation.authUserID }
  var ownerID: UUID { observation.ownerID }
  var sessionGeneration: UInt64 { observation.localSessionGeneration }
  var epoch: UUID { observation.epoch }
  var identity: Identity {
    .init(
      authUserID: authUserID, ownerID: ownerID, sessionGeneration: sessionGeneration, epoch: epoch)
  }
  func withCurrentAuthority<Value>(_ operation: () throws -> Value) throws -> Value {
    try observation.withCurrentAuthority(operation)
  }
}

/// The feature consumes the real controller. A test implementation may model
/// events, but no demo implementation is installed in product composition.
protocol ConversationMealCommandControlling: Sendable {
  func enqueue(
    command: ConversationMealCommand, expectedContext: ConversationCommandContext.Identity,
    publish: @escaping ConversationMealCommandController.Publisher
  ) async throws -> UUID
  func enqueue(
    source: ConversationMealCommand.Source, mealType: ConversationMealCommand.MealType?,
    publish: @escaping ConversationMealCommandController.Publisher
  ) async throws -> UUID
  func refreshSession(_ publish: @escaping ConversationMealCommandController.Publisher) async throws
  func publishSnapshot(_ publish: @escaping ConversationMealCommandController.Publisher)
    async throws
  func send(commandID: UUID, publish: @escaping ConversationMealCommandController.Publisher)
    async throws
  func reconcile(commandID: UUID, publish: @escaping ConversationMealCommandController.Publisher)
    async throws
  func resubmit(commandID: UUID, publish: @escaping ConversationMealCommandController.Publisher)
    async throws
  func discardUnsent(
    commandID: UUID, publish: @escaping ConversationMealCommandController.Publisher) async throws
  func holdForLocalReset(
    commandID: UUID, publish: @escaping ConversationMealCommandController.Publisher) async throws
  func closeTerminalDelivery(
    read: ConversationJournalRead, commandID: UUID,
    publish: @escaping ConversationMealCommandController.Publisher) async throws
  func close() async
}

extension ConversationMealCommandController: ConversationMealCommandControlling {}
