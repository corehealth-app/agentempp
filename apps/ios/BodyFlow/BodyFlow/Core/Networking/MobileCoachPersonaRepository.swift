import Foundation

/// The Flow persona and mascot state over the mobile BFF (`/coach/persona`,
/// GET and PATCH). The server names and describes the options in the
/// patient's locale; the client only reports the selection.
struct MobileCoachPersonaRepository: CoachPersonaRepository, CoachExperienceProviding {
    static let path = "/api/mobile/v1/coach/persona"

    let transport: any MobileAPIEnvelopeExecuting

    func coachExperience() async throws -> CoachExperienceResponse {
        try await transport.executeCapability {
            try MobileAPIRequest(method: .get, path: Self.path)
        }
    }

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        _ = userID
        do {
            return Self.persona(from: try await coachExperience().data.selected)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CoachPersonaRepositoryError.serviceUnavailable
        }
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        _ = userID
        let body: Data
        do {
            body = try JSONEncoder().encode(["persona": Self.wireValue(persona)])
        } catch {
            throw CoachPersonaRepositoryError.serviceUnavailable
        }
        do {
            let _: CoachExperienceResponse = try await transport.executeCapability {
                try MobileAPIRequest(method: .patch, path: Self.path, body: body)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CoachPersonaRepositoryError.serviceUnavailable
        }
    }

    static func persona(from selectable: SelectableCoachPersona?) -> CoachPersona? {
        switch selectable {
        case .focus: .focus
        case .impulse: .impulse
        case .zen: .zen
        case nil: nil
        }
    }

    static func wireValue(_ persona: CoachPersona) -> String {
        switch persona {
        case .focus: SelectableCoachPersona.focus.rawValue
        case .impulse: SelectableCoachPersona.impulse.rawValue
        case .zen: SelectableCoachPersona.zen.rawValue
        }
    }
}

struct MobileCoachExperienceSessionFactory: CoachExperienceSessionCreating {
    let transport: any MobileAPIEnvelopeExecuting

    func makeCoachExperience(userID: String) -> any CoachExperienceProviding {
        _ = userID
        return MobileCoachPersonaRepository(transport: transport)
    }
}
