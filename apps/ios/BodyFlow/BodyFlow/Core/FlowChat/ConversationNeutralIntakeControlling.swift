import Foundation

struct ConversationNeutralIntakeSnapshot: Sendable {
  let context: ConversationCommandContext
  let entries: [ConversationNeutralIntakeOutboxEntry]
  let heldIDs: [UUID]
}
struct ConversationNeutralIntakeSavedPublication: Sendable {
  let input: FlowNeutralIntakeInput
  let acknowledgement: FlowNeutralIntakeFactualAcknowledgement
  let context: ConversationCommandContext
}
enum ConversationNeutralIntakeFailure: Sendable {
  case offline, storage, unavailable, changed, rateLimited, invalidInput, reconciliationRequired
}
enum ConversationNeutralIntakeEvent: Sendable {
  case scopeSuspended
  case scopeAccepted(ConversationCommandContext)
  case snapshot(ConversationNeutralIntakeSnapshot)
  case queued(UUID)
  case saved(ConversationNeutralIntakeSavedPublication)
  /// Delivery settled without registration, never a saved ACK or reward.
  case resolvedWithoutRegistration(
    input: FlowNeutralIntakeInput, response: FlowNeutralIntakeResponseSnapshot,
    context: ConversationCommandContext)
  case state(
    input: FlowNeutralIntakeInput, response: FlowNeutralIntakeResponseSnapshot, canContinue: Bool,
    context: ConversationCommandContext)
  case deferred(UUID, ConversationNeutralIntakeFailure)
}
protocol ConversationNeutralIntakeControlling: Sendable {
  func enqueue(
    input: FlowNeutralIntakeInput, expectedContext: ConversationCommandContext.Identity,
    publish: @escaping ConversationNeutralIntakeController.Publisher
  ) async throws -> UUID
  func refreshSession(_ publish: @escaping ConversationNeutralIntakeController.Publisher)
    async throws
  func publishSnapshot(_ publish: @escaping ConversationNeutralIntakeController.Publisher)
    async throws
  func send(intakeID: UUID, publish: @escaping ConversationNeutralIntakeController.Publisher)
    async throws
  func reconcile(intakeID: UUID, publish: @escaping ConversationNeutralIntakeController.Publisher)
    async throws
  func continueOriginal(
    intakeID: UUID, publish: @escaping ConversationNeutralIntakeController.Publisher) async throws
  func discardUnsent(
    intakeID: UUID, publish: @escaping ConversationNeutralIntakeController.Publisher) async throws
  func close() async
}

enum ConversationNeutralIntakeDeliveryState: Equatable, Sendable {
  case notRecorded, clarificationRequired, needsReply, pending, held, absent, unconfirmed
}
extension FlowNeutralIntakeResponseSnapshot {
  var deliveryState: ConversationNeutralIntakeDeliveryState {
    switch status {
    case .notRecorded: return .notRecorded
    case .clarificationRequired: return .clarificationRequired
    case .pending: return .pending
    case .held: return .held
    case .absent: return .absent
    case .selected:
      switch result {
      case .meal(.state(let value)):
        switch value.status {
        case .notRecorded: return .notRecorded
        case .pending: return .pending
        case .absent: return .absent
        }
      case .workout(.state(let value)):
        switch value.status {
        case .notRecorded: return .notRecorded
        case .needsReply: return .needsReply
        case .pending: return .pending
        case .absent: return .absent
        }
      default: return .unconfirmed
      }
    }
  }
}
