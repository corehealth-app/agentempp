enum TelemetryEventName: String, Sendable {
    case authScreenViewed = "auth_screen_viewed"
    case authOperationCompleted = "auth_operation_completed"
    case onboardingStepViewed = "onboarding_step_viewed"
    case onboardingStepCompleted = "onboarding_step_completed"
    case coachPersonaSelected = "coach_persona_selected"
    case onboardingCompleted = "onboarding_completed"
    case signOutCompleted = "sign_out_completed"
}

enum TelemetryAuthScreen: String, CaseIterable, Sendable {
    case signIn = "sign_in"
    case signUp = "sign_up"
    case passwordRecovery = "password_recovery"
    case emailConfirmation = "email_confirmation"
}

enum TelemetryOutcome: String, CaseIterable, Sendable {
    case success
    case failure
}

enum TelemetryErrorCategory: String, CaseIterable, Sendable {
    case invalidInput = "invalid_input"
    case invalidCredentials = "invalid_credentials"
    case confirmationRequired = "confirmation_required"
    case operationUnavailable = "operation_unavailable"
    case serviceUnavailable = "service_unavailable"
    case storageUnavailable = "storage_unavailable"
}

enum TelemetryOnboardingStep: String, CaseIterable, Sendable {
    case welcome
    case bodyData = "body_data"
    case objective
    case routine
    case persona
    case consent
    case completion
}

enum TelemetryPersona: String, CaseIterable, Sendable {
    case focus
    case impulse
    case zen
}

enum TelemetryValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case decimal(Double)
    case boolean(Bool)

    init?(_ value: any Sendable) {
        switch value {
        case let value as String:
            self = .string(value)
        case let value as Int:
            self = .integer(value)
        case let value as Double:
            self = .decimal(value)
        case let value as Bool:
            self = .boolean(value)
        default:
            return nil
        }
    }
}

struct TelemetryEvent: Equatable, Sendable {
    private static let allowedMetadataValues: [String: Set<String>] = [
        "screen": Set(TelemetryAuthScreen.allCases.map(\.rawValue)),
        "outcome": Set(TelemetryOutcome.allCases.map(\.rawValue)),
        "error_category": Set(TelemetryErrorCategory.allCases.map(\.rawValue)),
        "step": Set(TelemetryOnboardingStep.allCases.map(\.rawValue)),
        "persona": Set(TelemetryPersona.allCases.map(\.rawValue)),
    ]

    let name: TelemetryEventName
    let metadata: [String: TelemetryValue]

    init(
        name: TelemetryEventName,
        metadata: [String: any Sendable] = [:]
    ) {
        self.name = name
        self.metadata = metadata.reduce(into: [:]) { filtered, entry in
            if let allowedValues = Self.allowedMetadataValues[entry.key],
               let value = entry.value as? String,
               allowedValues.contains(value) {
                filtered[entry.key] = .string(value)
            }
        }
    }
}

extension TelemetryEvent {
    static func authScreenViewed(_ screen: TelemetryAuthScreen) -> TelemetryEvent {
        TelemetryEvent(
            name: .authScreenViewed,
            metadata: ["screen": screen.rawValue]
        )
    }

    static func authOperationCompleted(
        screen: TelemetryAuthScreen,
        outcome: TelemetryOutcome,
        errorCategory: TelemetryErrorCategory? = nil
    ) -> TelemetryEvent {
        var metadata: [String: any Sendable] = [
            "screen": screen.rawValue,
            "outcome": outcome.rawValue,
        ]
        if let errorCategory {
            metadata["error_category"] = errorCategory.rawValue
        }
        return TelemetryEvent(
            name: .authOperationCompleted,
            metadata: metadata
        )
    }

    static func onboardingStepViewed(
        _ step: TelemetryOnboardingStep
    ) -> TelemetryEvent {
        TelemetryEvent(
            name: .onboardingStepViewed,
            metadata: ["step": step.rawValue]
        )
    }

    static func onboardingStepCompleted(
        _ step: TelemetryOnboardingStep
    ) -> TelemetryEvent {
        TelemetryEvent(
            name: .onboardingStepCompleted,
            metadata: ["step": step.rawValue]
        )
    }

    static func coachPersonaSelected(
        _ persona: TelemetryPersona
    ) -> TelemetryEvent {
        TelemetryEvent(
            name: .coachPersonaSelected,
            metadata: ["persona": persona.rawValue]
        )
    }

    static var onboardingCompleted: TelemetryEvent {
        TelemetryEvent(name: .onboardingCompleted)
    }
}

protocol TelemetryClient: Sendable {
    func record(_ event: TelemetryEvent) async
}

actor InMemoryTelemetryClient: TelemetryClient {
    private var events: [TelemetryEvent] = []

    func record(_ event: TelemetryEvent) {
        events.append(event)
    }

    func snapshot() -> [TelemetryEvent] {
        events
    }
}

struct DisabledTelemetryClient: TelemetryClient {
    func record(_ event: TelemetryEvent) async {}
}

extension OnboardingStep {
    var telemetryValue: TelemetryOnboardingStep {
        switch self {
        case .welcome: .welcome
        case .bodyData: .bodyData
        case .objective: .objective
        case .routine: .routine
        case .persona: .persona
        case .consent: .consent
        case .completion: .completion
        }
    }
}

extension CoachPersona {
    var telemetryValue: TelemetryPersona {
        switch self {
        case .focus: .focus
        case .impulse: .impulse
        case .zen: .zen
        }
    }
}
