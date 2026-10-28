import Foundation

/// Read from GET /protocol. Targets are official values, never calculated here.
struct CurrentObjectiveSnapshot: Codable, Equatable, Sendable {
    struct Targets: Codable, Equatable, Sendable {
        let calories: Decimal?
        let proteinG: Decimal?
        private enum CodingKeys: String, CodingKey {
            case calories
            case proteinG = "protein_g"
        }
    }
    let currentProtocol: BodyFlowObjective?
    let targets: Targets?
    let welcome: ProtocolWelcome?
    var clinicalPolicy: CurrentClinicalPolicy? = nil

    private enum CodingKeys: String, CodingKey {
        case currentProtocol = "current_protocol"
        case targets, welcome
        case clinicalPolicy = "clinical_policy"
    }

    var isEmpty: Bool {
        currentProtocol == nil && targets?.calories == nil
            && targets?.proteinG == nil && welcome == nil
            && clinicalPolicy?.phaseSelectionPending != true
    }

    func validated() throws -> Self {
        guard welcome == nil || welcome?.protocol == currentProtocol,
              targets?.calories?.isNaN != true,
              targets?.proteinG?.isNaN != true else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return self
    }
}

protocol CurrentObjectiveProviding: Sendable {
    func currentObjective() async throws -> CurrentObjectiveSnapshot
}

struct MobileCurrentObjectiveRepository: CurrentObjectiveProviding {
    let transport: any MobileAPIExecuting
    var clinicalRepresentation: CurrentClinicalRepresentation = .legacy

    func currentObjective() async throws -> CurrentObjectiveSnapshot {
        try await clinicalRepresentation.authorizeSession(transport)
        do {
            let result: CurrentObjectiveSnapshot = try await transport.execute(
                MobileAPIRequest(method: .get, path: "/api/mobile/v1/protocol",
                    queryItems: clinicalRepresentation.queryItems)
            )
            try await clinicalRepresentation.authorizeSession(transport)
            try clinicalRepresentation.requirePolicy(result.clinicalPolicy)
            return try result.validated()
        } catch {
            try await clinicalRepresentation.authorizeSession(transport)
            if error is CancellationError { throw CancellationError() }
            if let error = error as? BodyFlowCapabilityError { throw error }
            if let error = error as? MobileAPITransportError { throw error.capabilityError }
            throw BodyFlowCapabilityError.serviceUnavailable
        }
    }
}
