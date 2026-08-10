import Foundation
import Observation

enum CoachPersonaEditorOperationState: Equatable, Sendable {
    case loading
    case idle
    case saving
    case failed(AppPresentationError)
}

struct CoachPersonaPickerOption: Identifiable, Equatable, Sendable {
    let persona: CoachPersona
    let name: String
    let description: String

    var id: String { persona.id }
}

@MainActor
@Observable
final class CoachPersonaEditorModel: Identifiable {
    let id = UUID()
    let userID: String

    private let repository: any CoachPersonaRepository
    private let telemetry: any TelemetryClient
    private let cancellationCheck: @MainActor () -> Bool
    private let onPersistedPersonaChanged: @MainActor () -> Void
    private var activeOperationID: UUID?

    private(set) var pickerOptions: [CoachPersonaPickerOption]?
    private(set) var selected: CoachPersona?
    private(set) var persisted: CoachPersona?
    private(set) var operationState: CoachPersonaEditorOperationState

    init(
        userID: String,
        repository: any CoachPersonaRepository,
        telemetry: any TelemetryClient = DisabledTelemetryClient(),
        serverOptions: [CoachPersonaOption] = [],
        initialSelected: CoachPersona? = nil,
        initialPersisted: CoachPersona? = nil,
        initialOperationState: CoachPersonaEditorOperationState = .loading,
        cancellationCheck: @escaping @MainActor () -> Bool = { false },
        onPersistedPersonaChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.userID = userID
        self.repository = repository
        self.telemetry = telemetry
        pickerOptions = Self.validatedPickerOptions(serverOptions)
        selected = initialSelected
        persisted = initialPersisted
        operationState = initialOperationState
        self.cancellationCheck = cancellationCheck
        self.onPersistedPersonaChanged = onPersistedPersonaChanged
    }

    func load() async {
        guard operationState != .saving else { return }
        let operationID = UUID()
        activeOperationID = operationID
        operationState = .loading

        do {
            let loaded = try await repository.selectedPersona(for: userID)
            guard canPublish(operationID) else {
                finishCancelledOperation(operationID)
                return
            }
            persisted = loaded
            selected = loaded
            activeOperationID = nil
            operationState = .idle
        } catch is CancellationError {
            finishCancelledOperation(operationID)
        } catch {
            guard canPublish(operationID) else {
                finishCancelledOperation(operationID)
                return
            }
            activeOperationID = nil
            operationState = .failed(presentationError(for: error))
        }
    }

    func select(_ persona: CoachPersona) {
        guard operationState != .loading, operationState != .saving else { return }
        selected = persona
        if case .failed = operationState {
            operationState = .idle
        }
    }

    func updateServerOptions(_ serverOptions: [CoachPersonaOption]) {
        pickerOptions = Self.validatedPickerOptions(serverOptions)
    }

    func save() async -> Bool {
        guard operationState != .loading,
              operationState != .saving,
              let selectedPersona = selected else {
            return false
        }

        if selectedPersona == persisted {
            operationState = .idle
            return true
        }

        let operationID = UUID()
        activeOperationID = operationID
        operationState = .saving

        do {
            try await repository.setPersona(selectedPersona, for: userID)
            guard canPublish(operationID) else {
                finishCancelledOperation(operationID)
                return false
            }
            persisted = selectedPersona
            activeOperationID = nil
            operationState = .idle
            onPersistedPersonaChanged()
            await telemetry.record(.coachPersonaSelected(selectedPersona.telemetryValue))
            return true
        } catch is CancellationError {
            finishCancelledOperation(operationID)
            return false
        } catch {
            guard canPublish(operationID) else {
                finishCancelledOperation(operationID)
                return false
            }
            self.selected = persisted
            activeOperationID = nil
            operationState = .failed(presentationError(for: error))
            return false
        }
    }

    static func validatedPickerOptions(
        _ serverOptions: [CoachPersonaOption]
    ) -> [CoachPersonaPickerOption]? {
        guard serverOptions.count == 3 else { return nil }

        let codes = serverOptions.map(\.code)
        guard Set(codes) == Set(SelectableCoachPersona.allCases),
              Set(codes).count == serverOptions.count
        else {
            return nil
        }

        return serverOptions.map { option in
            CoachPersonaPickerOption(
                persona: persona(for: option.code),
                name: option.name,
                description: option.description
            )
        }
    }

    private static func persona(
        for selectable: SelectableCoachPersona
    ) -> CoachPersona {
        switch selectable {
        case .focus: .focus
        case .impulse: .impulse
        case .zen: .zen
        }
    }

    func cancelActiveOperation() {
        guard activeOperationID != nil else { return }
        activeOperationID = nil
        operationState = .idle
    }

    private var isCancellationRequested: Bool {
        Task.isCancelled || cancellationCheck()
    }

    private func canPublish(_ operationID: UUID) -> Bool {
        activeOperationID == operationID && !isCancellationRequested
    }

    private func finishCancelledOperation(_ operationID: UUID) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        operationState = .idle
    }

    private func presentationError(for error: Error) -> AppPresentationError {
        switch error {
        case CoachPersonaRepositoryError.serviceUnavailable:
            .serviceUnavailable
        case CoachPersonaRepositoryError.storageUnavailable:
            .storageUnavailable
        default:
            .operationUnavailable
        }
    }
}
