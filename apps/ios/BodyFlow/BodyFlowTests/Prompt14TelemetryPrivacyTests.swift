import Testing

@testable import BodyFlow

@Suite("Prompt 14 Telemetry Privacy")
struct Prompt14TelemetryPrivacyTests {
    @Test("Prompt 14 telemetry drops content and patient text")
    func stripsSensitiveMetadata() {
        let event = TelemetryEvent(
            name: .featureScreenViewed,
            metadata: [
                "screen": "content_detail",
                "outcome": "success",
                "mascot_state_classification": "evolving",
                "title": "private title",
                "excerpt": "private excerpt",
                "body_markdown": "private body",
                "cover_url": "/api/mobile/v1/content/covers/secret",
                "cover_capability": "secret-capability",
                "badge_text": "private badge",
                "name": "Private Person",
                "email": "private@example.invalid",
                "bearer": "secret-bearer",
                "authorization": "Bearer secret-bearer",
                "weight_kg": 78.4,
                "body_fat_percent": 19.5,
                "xp_total": 250,
                "current_streak": 8,
            ]
        )

        #expect(event.metadata == [
            "screen": .string("content_detail"),
            "outcome": .string("success"),
        ])
    }

    @Test("Prompt 14 screen vocabulary is bounded to approved surfaces")
    func acceptsApprovedPrompt14ScreensOnly() {
        let approved: [TelemetryFeatureScreen] = [
            .library,
            .contentDetail,
            .todayRecommendations,
            .mascot,
            .progress,
        ]

        #expect(approved.map(\.rawValue) == [
            "library",
            "content_detail",
            "today_recommendations",
            "mascot",
            "progress",
        ])

        for screen in approved {
            let event = TelemetryEvent(
                name: .featureScreenViewed,
                metadata: ["screen": screen.rawValue]
            )
            #expect(event.metadata == ["screen": .string(screen.rawValue)])
        }

        let rejected = TelemetryEvent(
            name: .featureScreenViewed,
            metadata: ["screen": "private-publication-title"]
        )
        #expect(rejected.metadata.isEmpty)
    }

    @Test("Mascot telemetry emits only evolving or bounded unknown classification")
    func mascotStateClassificationDoesNotExposeRawUnknownValue() {
        #expect(
            MascotWireState.evolving.telemetryClassification == .evolving
        )
        #expect(
            MascotWireState.unknown(
                "future-state-with-private-or-unbounded-text"
            ).telemetryClassification == .unknown
        )
        #expect(MascotWireState.active.telemetryClassification == nil)

        for classification in TelemetryMascotStateClassification.allCases {
            let event = TelemetryEvent(
                name: .featureScreenViewed,
                metadata: [
                    "screen": "mascot",
                    "mascot_state_classification": classification.rawValue,
                ]
            )
            #expect(event.metadata == [
                "screen": .string("mascot"),
                "mascot_state_classification": .string(
                    classification.rawValue
                ),
            ])
        }

        let rawUnknown = TelemetryEvent(
            name: .featureScreenViewed,
            metadata: [
                "screen": "mascot",
                "mascot_state_classification":
                    "future-state-with-private-or-unbounded-text",
            ]
        )
        #expect(rawUnknown.metadata == ["screen": .string("mascot")])
    }

    @Test("Telemetry failure boundary remains side-effect free")
    func disabledTelemetryDoesNotAffectFunctionalFlow() async {
        let event = TelemetryEvent(
            name: .featureScreenViewed,
            metadata: [
                "screen": "library",
                "outcome": "failure",
            ]
        )
        let telemetry: any TelemetryClient = DisabledTelemetryClient()

        await telemetry.record(event)

        #expect(event.metadata == [
            "screen": .string("library"),
            "outcome": .string("failure"),
        ])
    }

    @Test("Prompt 14 metadata is discarded from unrelated events")
    func prompt14MetadataIsEventScoped() {
        let event = TelemetryEvent(
            name: .authOperationCompleted,
            metadata: [
                "screen": "library",
                "outcome": "failure",
                "error_category": "service_unavailable",
                "mascot_state_classification": "unknown",
            ]
        )

        #expect(event.metadata == [
            "outcome": .string("failure"),
            "error_category": .string("service_unavailable"),
        ])
    }

    @Test("New Prompt 14 screens keep only their contextual vocabulary")
    func prompt14ScreensDropLegacyMetadata() {
        let screens: [(String, Bool)] = [
            ("library", false),
            ("content_detail", false),
            ("today_recommendations", false),
            ("mascot", true),
        ]

        for (screen, allowsMascotClassification) in screens {
            let event = TelemetryEvent(
                name: .featureScreenViewed,
                metadata: [
                    "screen": screen,
                    "outcome": "success",
                    "mascot_state_classification": "evolving",
                    "error_category": "offline",
                    "step": "welcome",
                    "persona": "focus",
                    "calculation_version": "legacy.prompt13:v1",
                    "registration_kind": "meal",
                    "capture_source": "text",
                ]
            )
            var expected: [String: TelemetryValue] = [
                "screen": .string(screen),
                "outcome": .string("success"),
            ]
            if allowsMascotClassification {
                expected["mascot_state_classification"] = .string("evolving")
            }

            #expect(event.metadata == expected)
        }
    }

    @Test("Mascot classification requires feature screen viewed on mascot")
    func mascotClassificationIsScreenScoped() {
        let wrongFeatureScreen = TelemetryEvent(
            name: .featureScreenViewed,
            metadata: [
                "screen": "today",
                "mascot_state_classification": "evolving",
            ]
        )
        let wrongEvent = TelemetryEvent(
            name: .registrationOperationCompleted,
            metadata: [
                "screen": "mascot",
                "outcome": "success",
                "mascot_state_classification": "unknown",
            ]
        )

        #expect(wrongFeatureScreen.metadata == [
            "screen": .string("today"),
        ])
        #expect(wrongEvent.metadata == [
            "outcome": .string("success"),
        ])
    }

    @Test("Inherited telemetry remains unchanged outside new Prompt 14 screens")
    func inheritedTelemetryPoliciesRemainIntact() {
        let auth = TelemetryEvent.authOperationCompleted(
            screen: .signIn,
            outcome: .failure,
            errorCategory: .serviceUnavailable
        )
        let today = TelemetryEvent.featureScreenViewed(
            .today,
            calculationVersion: "legacy.prompt13:v1"
        )
        let progress = TelemetryEvent.featureScreenViewed(
            .progress,
            calculationVersion: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        )

        #expect(auth.metadata == [
            "screen": .string("sign_in"),
            "outcome": .string("failure"),
            "error_category": .string("service_unavailable"),
        ])
        #expect(today.metadata == [
            "screen": .string("today"),
            "calculation_version": .string("legacy.prompt13:v1"),
        ])
        #expect(progress.metadata == [
            "screen": .string("progress"),
            "calculation_version": .string(
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
            ),
        ])
    }
}
