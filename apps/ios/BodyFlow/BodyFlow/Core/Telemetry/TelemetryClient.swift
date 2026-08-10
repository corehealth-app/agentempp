enum TelemetryEventName: String, Sendable {
    case authScreenViewed = "auth_screen_viewed"
    case authOperationCompleted = "auth_operation_completed"
    case onboardingStepViewed = "onboarding_step_viewed"
    case onboardingStepCompleted = "onboarding_step_completed"
    case coachPersonaSelected = "coach_persona_selected"
    case onboardingCompleted = "onboarding_completed"
    case signOutCompleted = "sign_out_completed"
    case featureScreenViewed = "feature_screen_viewed"
    case registrationOperationCompleted = "registration_operation_completed"
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
    case offline
    case serviceUnavailable = "service_unavailable"
    case storageUnavailable = "storage_unavailable"
    case idempotencyConflict = "idempotency_conflict"
    case registrationNotPending = "registration_not_pending"
    case registrationExpired = "registration_expired"
    case routineTransitionInvalid = "routine_transition_invalid"
    case routineSnoozeInvalid = "routine_snooze_invalid"
}

enum TelemetryFeatureScreen: String, CaseIterable, Sendable {
    case today
    case todayRecommendations = "today_recommendations"
    case register
    case mealCapture = "meal_capture"
    case mealProposal = "meal_proposal"
    case workoutProposal = "workout_proposal"
    case hydration
    case weight
    case routineList = "routine_list"
    case routineDetail = "routine_detail"
    case routineHistory = "routine_history"
    case plan
    case planDetail = "plan_detail"
    case progress
    case block7700 = "block_7700"
    case history
    case historyMealLog = "history_meal_log"
    case historyWorkout = "history_workout"
    case library
    case contentDetail = "content_detail"
    case mascot
}

enum TelemetryMascotStateClassification: String, CaseIterable, Sendable {
    case evolving
    case unknown
}

enum TelemetryRegistrationKind: String, CaseIterable, Sendable {
    case meal
    case workout
    case weight
    case hydration
}

enum TelemetryMealCaptureSource: String, CaseIterable, Sendable {
    case text
    case photo
    case audio
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
    private static let contextExclusivePrompt14Screens: Set<String> = [
        TelemetryFeatureScreen.library.rawValue,
        TelemetryFeatureScreen.contentDetail.rawValue,
        TelemetryFeatureScreen.todayRecommendations.rawValue,
        TelemetryFeatureScreen.mascot.rawValue,
    ]

    private static let allowedMetadataValues: [String: Set<String>] = [
        "screen": Set(TelemetryAuthScreen.allCases.map(\.rawValue))
            .union(TelemetryFeatureScreen.allCases.map(\.rawValue)),
        "outcome": Set(TelemetryOutcome.allCases.map(\.rawValue)),
        "error_category": Set(TelemetryErrorCategory.allCases.map(\.rawValue)),
        "step": Set(TelemetryOnboardingStep.allCases.map(\.rawValue)),
        "persona": Set(TelemetryPersona.allCases.map(\.rawValue)),
        "registration_kind": Set(
            TelemetryRegistrationKind.allCases.map(\.rawValue)
        ),
        "capture_source": Set(
            TelemetryMealCaptureSource.allCases.map(\.rawValue)
        ),
        "mascot_state_classification": Set(
            TelemetryMascotStateClassification.allCases.map(\.rawValue)
        ),
    ]

    let name: TelemetryEventName
    let metadata: [String: TelemetryValue]

    init(
        name: TelemetryEventName,
        metadata: [String: any Sendable] = [:]
    ) {
        self.name = name
        let allowlisted = metadata.reduce(into: [String: TelemetryValue]()) {
            filtered,
            entry in
            if entry.key == "calculation_version",
               let value = entry.value as? String,
               Self.isValidCalculationVersion(value) {
                filtered[entry.key] = .string(value)
                return
            }
            if let allowedValues = Self.allowedMetadataValues[entry.key],
               let value = entry.value as? String,
               allowedValues.contains(value) {
                filtered[entry.key] = .string(value)
            }
        }
        self.metadata = Self.contextualMetadata(
            for: name,
            from: allowlisted
        )
    }

    private static func contextualMetadata(
        for name: TelemetryEventName,
        from metadata: [String: TelemetryValue]
    ) -> [String: TelemetryValue] {
        var contextual = metadata
        let screen = contextual["screen"].flatMap { value -> String? in
            guard case let .string(rawValue) = value else { return nil }
            return rawValue
        }

        guard name == .featureScreenViewed else {
            contextual.removeValue(forKey: "mascot_state_classification")
            if let screen,
               contextExclusivePrompt14Screens.contains(screen) {
                contextual.removeValue(forKey: "screen")
            }
            return contextual
        }

        guard let screen else {
            contextual.removeValue(forKey: "mascot_state_classification")
            return contextual
        }

        guard contextExclusivePrompt14Screens.contains(screen) else {
            contextual.removeValue(forKey: "mascot_state_classification")
            return contextual
        }

        let allowedKeys: Set<String> = screen
            == TelemetryFeatureScreen.mascot.rawValue
            ? ["screen", "outcome", "mascot_state_classification"]
            : ["screen", "outcome"]
        return contextual.filter { allowedKeys.contains($0.key) }
    }

    private static func isValidCalculationVersion(_ value: String) -> Bool {
        let bytes = value.utf8
        guard (1...64).contains(bytes.count) else { return false }

        return bytes.allSatisfy { byte in
            switch byte {
            case 48...57, 65...90, 97...122, 45, 46, 58, 95:
                true
            default:
                false
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

    static func featureScreenViewed(
        _ screen: TelemetryFeatureScreen,
        calculationVersion: String? = nil
    ) -> TelemetryEvent {
        var metadata: [String: any Sendable] = [
            "screen": screen.rawValue,
        ]
        if let calculationVersion {
            metadata["calculation_version"] = calculationVersion
        }
        return TelemetryEvent(
            name: .featureScreenViewed,
            metadata: metadata
        )
    }

    static func registrationOperationCompleted(
        kind: TelemetryRegistrationKind,
        captureSource: TelemetryMealCaptureSource? = nil,
        outcome: TelemetryOutcome,
        errorCategory: TelemetryErrorCategory? = nil,
        calculationVersion: String? = nil
    ) -> TelemetryEvent {
        var metadata: [String: any Sendable] = [
            "registration_kind": kind.rawValue,
            "outcome": outcome.rawValue,
        ]
        if kind == .meal, let captureSource {
            metadata["capture_source"] = captureSource.rawValue
        }
        if let errorCategory {
            metadata["error_category"] = errorCategory.rawValue
        }
        if let calculationVersion {
            metadata["calculation_version"] = calculationVersion
        }
        return TelemetryEvent(
            name: .registrationOperationCompleted,
            metadata: metadata
        )
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

extension RegistrationKind {
    var telemetryValue: TelemetryRegistrationKind {
        switch self {
        case .meal: .meal
        case .training: .workout
        case .weight: .weight
        case .hydration: .hydration
        }
    }
}

extension MealCaptureSource {
    var telemetryValue: TelemetryMealCaptureSource {
        switch self {
        case .text: .text
        case .photoDemonstration: .photo
        case .audioDemonstration: .audio
        }
    }
}

extension BodyFlowCapabilityError {
    var telemetryValue: TelemetryErrorCategory {
        switch self {
        case .operationUnavailable:
            .operationUnavailable
        case .offline:
            .offline
        case .serviceUnavailable:
            .serviceUnavailable
        case .invalidInput,
             .invalidIdempotencyKey,
             .invalidContentContract,
             .invalidContentCursor,
             .unsupportedMarkdown,
             .unsupportedCoachContract,
             .invalidContentCover,
             .contentCoverTooLarge,
             .coachLocaleUnsupported:
            .invalidInput
        case .contentNotFound,
             .contentCoverNotFound,
             .subscriptionRequired:
            .operationUnavailable
        case .idempotencyConflict,
             .contentVersionChanged,
             .idempotencyRequestInProgress:
            .idempotencyConflict
        case .registrationNotPending:
            .registrationNotPending
        case .registrationExpired:
            .registrationExpired
        case .routineTransitionInvalid:
            .routineTransitionInvalid
        case .routineSnoozeInvalid:
            .routineSnoozeInvalid
        }
    }
}

extension MascotWireState {
    var telemetryClassification: TelemetryMascotStateClassification? {
        switch self {
        case .evolving:
            .evolving
        case .unknown:
            .unknown
        case .inactive, .reactivating, .active, .neglected:
            nil
        }
    }
}
