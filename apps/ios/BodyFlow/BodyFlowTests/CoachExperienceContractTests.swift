import Foundation
import Testing

@testable import BodyFlow

@Suite("Coach Experience Contract")
struct CoachExperienceContractTests {
    @Test("coach experience preserves server personas and contract version")
    func decodesCoachExperience() throws {
        let response = try JSONDecoder().decode(
            CoachExperienceResponse.self,
            from: Self.coachExperienceJSON
        )

        #expect(response.meta.requestID == "request-coach-experience-0001")
        #expect(response.data.selected == nil)
        #expect(response.data.effective == .balanced)
        #expect(response.data.options.map(\.code) == [.focus, .impulse, .zen])
        #expect(response.data.options.map(\.id) == [.focus, .impulse, .zen])
        #expect(response.data.options.map(\.name) == ["Foco", "Impulso", "Zen"])
        #expect(response.data.options.map(\.description) == [
            "Direto e objetivo.",
            "Positivo e energético.",
            "Calmo e acolhedor.",
        ])
        #expect(response.data.mascot.state == .evolving)
        #expect(
            response.data.mascot.changedAt
                == timestamp("2026-07-29T22:15:16.123Z")
        )
        #expect(response.data.contractVersion == "bodyflow.coach-persona.v1")
        #expect(
            CoachExperienceV1PresentationContract.validatedSnapshot(
                from: response
            ) == response.data
        )

        assertContract(response)
    }

    @Test("v1 presentation boundary rejects an unsupported contract after decoding")
    func rejectsUnsupportedCoachContract() throws {
        let json = try #require(
            String(data: Self.coachExperienceJSON, encoding: .utf8)
        )
        let response = try JSONDecoder().decode(
            CoachExperienceResponse.self,
            from: Data(
                json.replacingOccurrences(
                    of: "bodyflow.coach-persona.v1",
                    with: "bodyflow.coach-persona.v2"
                ).utf8
            )
        )

        #expect(response.data.contractVersion == "bodyflow.coach-persona.v2")
        #expect(
            CoachExperienceV1PresentationContract.validatedSnapshot(
                from: response
            ) == nil
        )
    }

    @Test("selectable and effective personas decode only their wire domains")
    func decodesPersonaDomains() throws {
        let selectable = try JSONDecoder().decode(
            [SelectableCoachPersona].self,
            from: Data(#"["focus","impulse","zen"]"#.utf8)
        )
        let effective = try JSONDecoder().decode(
            [EffectiveCoachPersona].self,
            from: Data(#"["focus","impulse","zen","balanced"]"#.utf8)
        )

        #expect(selectable == [.focus, .impulse, .zen])
        #expect(effective == [.focus, .impulse, .zen, .balanced])
    }

    @Test("all documented mascot wire states round trip without normalization")
    func roundTripsDocumentedMascotStates() throws {
        let expected: [(String, MascotWireState)] = [
            ("inactive", .inactive),
            ("reactivating", .reactivating),
            ("active", .active),
            ("evolving", .evolving),
            ("neglected", .neglected),
        ]

        for (rawValue, state) in expected {
            let decoded = try JSONDecoder().decode(
                MascotWireState.self,
                from: Data("\"\(rawValue)\"".utf8)
            )
            #expect(decoded == state)
            #expect(try JSONEncoder().encode(decoded) == Data("\"\(rawValue)\"".utf8))
        }
    }

    @Test("unknown mascot value is preserved without mapping to active")
    func preservesUnknownMascot() throws {
        let state = try JSONDecoder().decode(
            MascotWireState.self,
            from: Data("\"future_state\"".utf8)
        )

        #expect(state == .unknown("future_state"))
        #expect(state != .active)
        #expect(try JSONEncoder().encode(state) == Data("\"future_state\"".utf8))
    }

    @Test("provider returns the shared coach experience envelope")
    func providerReturnsCoachExperience() async throws {
        let expected = try JSONDecoder().decode(
            CoachExperienceResponse.self,
            from: Self.coachExperienceJSON
        )
        let provider: any CoachExperienceProviding = CoachExperienceProviderStub(
            response: expected
        )

        #expect(try await provider.coachExperience() == expected)
    }

    private func timestamp(_ value: String) -> APITimestamp {
        try! JSONDecoder().decode(
            APITimestamp.self,
            from: Data("\"\(value)\"".utf8)
        )
    }

    private func assertContract<T: Codable & Equatable & Sendable>(_: T) {}

    private static let coachExperienceJSON = Data(
        """
        {
          "data": {
            "selected": null,
            "effective": "balanced",
            "options": [
              {
                "code": "focus",
                "name": "Foco",
                "description": "Direto e objetivo."
              },
              {
                "code": "impulse",
                "name": "Impulso",
                "description": "Positivo e energético."
              },
              {
                "code": "zen",
                "name": "Zen",
                "description": "Calmo e acolhedor."
              }
            ],
            "mascot": {
              "state": "evolving",
              "changed_at": "2026-07-29T22:15:16.123Z"
            },
            "contract_version": "bodyflow.coach-persona.v1",
            "future_coach_field": {"ignored": true}
          },
          "meta": {
            "api_version": "v1",
            "request_id": "request-coach-experience-0001"
          }
        }
        """.utf8
    )
}

private struct CoachExperienceProviderStub: CoachExperienceProviding {
    let response: CoachExperienceResponse

    func coachExperience() async throws -> CoachExperienceResponse {
        response
    }
}
