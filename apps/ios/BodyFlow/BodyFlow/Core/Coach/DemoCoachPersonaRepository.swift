import Foundation

actor DemoCoachPersonaRepository: CoachPersonaRepository {
    private let stateStore: DemoStateStore
    private let behavior: DemoOperationBehavior<CoachPersonaRepositoryError>

    init(
        stateStore: DemoStateStore,
        behavior: DemoOperationBehavior<CoachPersonaRepositoryError> = .succeed(after: nil)
    ) {
        self.stateStore = stateStore
        self.behavior = behavior
    }

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        guard userID == DemoUser.id else {
            throw CoachPersonaRepositoryError.serviceUnavailable
        }
        try await apply(behavior)
        do {
            return try await stateStore.loadCoachPersona(for: userID)
        } catch {
            throw CoachPersonaRepositoryError.storageUnavailable
        }
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        guard userID == DemoUser.id else {
            throw CoachPersonaRepositoryError.serviceUnavailable
        }
        try await apply(behavior)
        try Task.checkCancellation()
        do {
            try await stateStore.saveCoachPersona(persona, for: userID)
        } catch {
            throw CoachPersonaRepositoryError.storageUnavailable
        }
    }

    private func apply(
        _ behavior: DemoOperationBehavior<CoachPersonaRepositoryError>
    ) async throws {
        switch behavior {
        case .succeed(let delay):
            if let delay { try await Task.sleep(for: delay) }
        case .fail(let error, let delay):
            if let delay { try await Task.sleep(for: delay) }
            try Task.checkCancellation()
            throw error
        }
    }
}
