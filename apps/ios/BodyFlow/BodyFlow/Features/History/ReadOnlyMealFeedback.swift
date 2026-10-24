import SwiftUI
import Observation

/// An optional reader only: it never starts an editing capability or mutation.
@MainActor
@Observable
final class ReadOnlyMealFeedbackModel {
    let recordID: String
    private(set) var feedback: RegistrationFeedbackSnapshot?
    private(set) var isLoading = false
    private var settled = false
    private var ownership: FeatureLoadOwnership?
    private let provider: any MealRecordProviding
    private let isSessionActive: @MainActor @Sendable () -> Bool

    init(recordID: String, provider: any MealRecordProviding,
         isSessionActive: @escaping @MainActor @Sendable () -> Bool) throws {
        guard let id = WorkoutStrengthWire.uuid(recordID) else { throw BodyFlowCapabilityError.invalidInput }
        self.recordID = id
        self.provider = provider
        self.isSessionActive = isSessionActive
    }

    func load() async {
        guard isSessionActive(), !Task.isCancelled, !isLoading, !settled else { return }
        let operation = FeatureLoadOwnership()
        ownership = operation
        isLoading = true
        await withTaskCancellationHandler {
            do {
                let response = try await provider.mealRecord(id: recordID)
                guard response.data.recordID == recordID else { throw BodyFlowCapabilityError.serviceUnavailable }
                guard publish(operation) else { return }
                feedback = response.data.feedback
                settled = true
            } catch is CancellationError {
                operation.invalidate()
            } catch {
                // The ordinary History row remains visible on optional failure.
                guard publish(operation) else { return }
                feedback = nil
                settled = true
            }
        } onCancel: { operation.invalidate() }
        guard ownership === operation else { return }
        ownership = nil
        isLoading = false
    }

    func cancel() {
        ownership?.invalidate()
        ownership = nil
        feedback = nil
        isLoading = false
        settled = false
    }

    private func publish(_ operation: FeatureLoadOwnership) -> Bool {
        ownership === operation && isSessionActive() && !Task.isCancelled && operation.claimPublication()
    }
}

@MainActor
struct MealHistoryFeedbackConfiguration {
    struct Identity: Hashable {
        let context: ObjectIdentifier
        let activation: MealRecordAuthenticatedActivation
        let recordID: String
    }
    let identity: Identity
    private let context: WorkoutRegistrationReadyContext
    private let provider: MobileMealRecordRepository

    init?(recordID: String, context: WorkoutRegistrationReadyContext?) {
        guard let id = WorkoutStrengthWire.uuid(recordID), let context, context.isActive else { return nil }
        self.context = context
        identity = Identity(context: ObjectIdentifier(context), activation: context.activation, recordID: id)
        // This is the original captured envelope/lease, never the current global client.
        provider = MobileMealRecordRepository(transport: context.provider.transport)
    }
    var isActive: Bool { context.isActive }
    func makeModel() throws -> ReadOnlyMealFeedbackModel {
        try ReadOnlyMealFeedbackModel(recordID: identity.recordID, provider: provider,
            isSessionActive: { [weak context] in context?.isActive == true })
    }
}

@MainActor
struct ReadOnlyMealFeedbackHost: View {
    let configuration: MealHistoryFeedbackConfiguration
    var body: some View {
        ReadOnlyMealFeedbackActive(configuration: configuration).id(configuration.identity)
    }
}

@MainActor
private struct ReadOnlyMealFeedbackActive: View {
    let configuration: MealHistoryFeedbackConfiguration
    @State private var model: ReadOnlyMealFeedbackModel?
    init(configuration: MealHistoryFeedbackConfiguration) {
        self.configuration = configuration
        _model = State(initialValue: try? configuration.makeModel())
    }
    var body: some View {
        // A concrete host must exist before the optional read completes.
        // An empty conditional Group has no appearance to start its task.
        VStack(alignment: .leading, spacing: 0) {
            if configuration.isActive, let feedback = model?.feedback {
                BodyFlowCard { OriginalRegistrationFeedbackView(feedback: feedback) }
            }
        }
        .task { await model?.load() }
        .onDisappear { model?.cancel() }
    }
}
