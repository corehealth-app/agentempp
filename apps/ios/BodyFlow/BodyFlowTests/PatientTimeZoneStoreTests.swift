import Foundation
import Testing

@testable import BodyFlow

@Suite("Patient time zone store")
struct PatientTimeZoneStoreTests {
    @Test("the store starts on its seed and resolves a documented IANA identifier")
    func seedAndResolve() throws {
        let store = PatientTimeZoneStore(seed: PatientTimeZoneContext(documentedIANAIdentifier: nil))
        #expect(store.current.documentedIANAIdentifier == nil)
        #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try store.current.requireTimeZone()
        }

        store.resolve(documentedIANAIdentifier: "America/Sao_Paulo")

        #expect(store.current.documentedIANAIdentifier == "America/Sao_Paulo")
        #expect(try store.current.requireTimeZone().identifier == "America/Sao_Paulo")
    }

    @Test("an undocumented or unknown identifier keeps the time zone unavailable")
    func invalidIdentifiersStayUnavailable() {
        let store = PatientTimeZoneStore(seed: PatientTimeZoneContext(documentedIANAIdentifier: nil))
        for identifier in [nil, "PST", "GMT+03:00", "Not/A_Time_Zone"] {
            store.resolve(documentedIANAIdentifier: identifier)
            #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
                try store.current.requireTimeZone()
            }
        }
    }

    @Test("reset returns to the seed so the next session never inherits a zone")
    func resetReturnsToSeed() throws {
        let seed = PatientTimeZoneContext(documentedIANAIdentifier: "Europe/Lisbon")
        let store = PatientTimeZoneStore(seed: seed)
        store.resolve(documentedIANAIdentifier: "America/Sao_Paulo")
        #expect(store.current.documentedIANAIdentifier == "America/Sao_Paulo")

        store.reset()

        #expect(store.current == seed)
        #expect(try store.current.requireTimeZone().identifier == "Europe/Lisbon")
    }
}
