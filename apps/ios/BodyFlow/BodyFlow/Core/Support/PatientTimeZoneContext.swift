import Foundation

/// The patient timezone identifier must come from a documented profile response.
/// Only named IANA database identifiers containing a region separator are accepted;
/// abbreviations and synthetic GMT offsets stay unavailable.
struct PatientTimeZoneContext: Equatable, Sendable {
    let documentedIANAIdentifier: String?

    static var appDefault: PatientTimeZoneContext {
        #if DEBUG
        PatientTimeZoneContext(
            documentedIANAIdentifier: "America/Sao_Paulo"
        )
        #else
        PatientTimeZoneContext(documentedIANAIdentifier: nil)
        #endif
    }

    func requireTimeZone() throws -> TimeZone {
        guard let documentedIANAIdentifier,
              documentedIANAIdentifier.contains("/"),
              TimeZone.knownTimeZoneIdentifiers.contains(documentedIANAIdentifier),
              let timeZone = TimeZone(identifier: documentedIANAIdentifier) else {
            throw BodyFlowCapabilityError.operationUnavailable
        }

        return timeZone
    }
}
