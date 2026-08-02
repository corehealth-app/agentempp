import Testing

@testable import BodyFlow

@Suite("Prompt 13 Telemetry")
struct Prompt13TelemetryTests {
    @Test("screen view keeps only the bounded screen and one-character calculation version")
    func screenViewAllowsOneCharacterCalculationVersion() {
        let event = TelemetryEvent.featureScreenViewed(
            .today,
            calculationVersion: "A"
        )

        #expect(event.name == .featureScreenViewed)
        #expect(event.metadata == [
            "screen": .string("today"),
            "calculation_version": .string("A"),
        ])
    }

    @Test("calculation version accepts exactly 64 allowed ASCII characters")
    func calculationVersionAllowsExactly64Characters() {
        let event = TelemetryEvent.featureScreenViewed(
            .progress,
            calculationVersion: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        )

        #expect(event.metadata == [
            "screen": .string("progress"),
            "calculation_version": .string(
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
            ),
        ])
    }

    @Test(
        "invalid calculation versions are omitted without truncation or normalization",
        arguments: [
            ("", "substitute"),
            (
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
            ),
            (" demo.prompt13.v1 ", "demo.prompt13.v1"),
            ("demo/prompt13/v1", "demo.prompt13.v1"),
            ("versão.1", "versao.1"),
        ]
    )
    func calculationVersionRejectsWholeInvalidValue(
        invalid: String,
        forbiddenReplacement: String
    ) {
        let event = TelemetryEvent.featureScreenViewed(
            .today,
            calculationVersion: invalid
        )

        #expect(event.metadata == ["screen": .string("today")])
        #expect(
            event.metadata["calculation_version"]
                != .string(forbiddenReplacement)
        )
    }

    @Test("registration event exposes only bounded enums")
    func registrationEventUsesControlledVocabulary() {
        let event = TelemetryEvent.registrationOperationCompleted(
            kind: .meal,
            captureSource: .photo,
            outcome: .failure,
            errorCategory: .serviceUnavailable,
            calculationVersion: "demo.prompt13:v1"
        )

        #expect(event.name == .registrationOperationCompleted)
        #expect(event.metadata == [
            "registration_kind": .string("meal"),
            "capture_source": .string("photo"),
            "outcome": .string("failure"),
            "error_category": .string("service_unavailable"),
            "calculation_version": .string("demo.prompt13:v1"),
        ])
    }

    @Test(
        "capture source is omitted outside meal registration",
        arguments: [
            TelemetryRegistrationKind.workout,
            TelemetryRegistrationKind.weight,
            TelemetryRegistrationKind.hydration,
        ]
    )
    func captureSourceIsMealOnly(kind: TelemetryRegistrationKind) {
        let event = TelemetryEvent.registrationOperationCompleted(
            kind: kind,
            captureSource: .photo,
            outcome: .success
        )

        #expect(event.metadata == [
            "registration_kind": .string(kind.rawValue),
            "outcome": .string("success"),
        ])
    }

    @Test("constructing telemetry leaves the complete Today snapshot unchanged")
    func eventConstructionDoesNotMutateTodaySnapshot() {
        let snapshot = DemoBodyFlowFixtures.loadedToday.data

        let event = TelemetryEvent.featureScreenViewed(
            .today,
            calculationVersion: snapshot.calculationVersion
        )

        #expect(DemoBodyFlowFixtures.loadedToday.data == snapshot)
        #expect(
            event.metadata["calculation_version"]
                == .string(snapshot.calculationVersion)
        )
    }

    @Test("meal source mapping strips text and demonstration labels")
    func mealCaptureMappingCannotExposePayload() {
        #expect(
            MealCaptureSource.text("segredo do paciente").telemetryValue
                == .text
        )
        #expect(
            MealCaptureSource.photoDemonstration(
                label: "imagem-com-identificador"
            ).telemetryValue == .photo
        )
        #expect(
            MealCaptureSource.audioDemonstration(
                label: "audio-com-identificador"
            ).telemetryValue == .audio
        )
    }

    @Test("registration and capability mappings stay bounded")
    func domainMappingsStayBounded() {
        #expect(RegistrationKind.meal.telemetryValue == .meal)
        #expect(RegistrationKind.training.telemetryValue == .workout)
        #expect(RegistrationKind.weight.telemetryValue == .weight)
        #expect(RegistrationKind.hydration.telemetryValue == .hydration)

        #expect(BodyFlowCapabilityError.invalidInput.telemetryValue == .invalidInput)
        #expect(BodyFlowCapabilityError.offline.telemetryValue == .offline)
        #expect(
            BodyFlowCapabilityError.idempotencyConflict.telemetryValue
                == .idempotencyConflict
        )
        #expect(
            BodyFlowCapabilityError.registrationNotPending.telemetryValue
                == .registrationNotPending
        )
        #expect(
            BodyFlowCapabilityError.registrationExpired.telemetryValue
                == .registrationExpired
        )
        #expect(
            BodyFlowCapabilityError.routineTransitionInvalid.telemetryValue
                == .routineTransitionInvalid
        )
        #expect(
            BodyFlowCapabilityError.routineSnoozeInvalid.telemetryValue
                == .routineSnoozeInvalid
        )
        #expect(
            BodyFlowCapabilityError.invalidIdempotencyKey.telemetryValue
                == .invalidInput
        )
    }

    @Test("free-form and sensitive Prompt 13 metadata never survives filtering")
    func sensitiveMetadataIsRejected() {
        let event = TelemetryEvent(
            name: .registrationOperationCompleted,
            metadata: [
                "screen": "today",
                "registration_kind": "meal",
                "capture_source": "audio",
                "outcome": "success",
                "error_category": "offline",
                "calculation_version": "bodyflow.daily-state:v2",
                "meal_text": "arroz e feijão",
                "food_name": "alimento",
                "image_data": "base64",
                "audio_data": "base64",
                "weight_kg": 78.4,
                "body_fat_percent": 19.5,
                "routine_name": "medicamento",
                "dose": "10 mg",
                "raw_response": "{ secret: true }",
                "raw_error": "provider body",
                "signed_url": "https://fixture.invalid/signed",
                "provider_id": "provider-123",
                "user_id": "user-123",
                "idempotency_key": "secret-key",
            ]
        )

        #expect(event.metadata == [
            "screen": .string("today"),
            "registration_kind": .string("meal"),
            "capture_source": .string("audio"),
            "outcome": .string("success"),
            "error_category": .string("offline"),
            "calculation_version": .string("bodyflow.daily-state:v2"),
        ])
    }

    @Test("free-form values cannot enter bounded Prompt 13 keys")
    func freeFormValuesAreRejected() {
        let event = TelemetryEvent(
            name: .registrationOperationCompleted,
            metadata: [
                "screen": "patient-home",
                "registration_kind": "custom-registration",
                "capture_source": "camera-roll-filename",
                "outcome": "mostly-success",
                "error_category": "raw server explanation",
            ]
        )

        #expect(event.metadata.isEmpty)
    }
}
