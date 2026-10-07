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

    private enum CodingKeys: String, CodingKey {
        case currentProtocol = "current_protocol"
        case targets, welcome
    }

    var isEmpty: Bool {
        currentProtocol == nil && targets?.calories == nil
            && targets?.proteinG == nil && welcome == nil
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

    func currentObjective() async throws -> CurrentObjectiveSnapshot {
        do {
            let result: CurrentObjectiveSnapshot = try await transport.execute(
                MobileAPIRequest(method: .get, path: "/api/mobile/v1/protocol")
            )
            return try result.validated()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BodyFlowCapabilityError {
            throw error
        } catch let error as MobileAPITransportError {
            throw error.capabilityError
        } catch {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
    }
}
