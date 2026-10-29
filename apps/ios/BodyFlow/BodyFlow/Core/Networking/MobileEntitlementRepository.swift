import Foundation

/// Use the authenticated owner's scoped transport, just like other patient
/// repositories. Identity never comes from a caller-supplied query or body.
struct MobileEntitlementRepository: EntitlementProviding {
    let transport: any MobileAPIEnvelopeExecuting

    func entitlement() async throws -> EntitlementResponse {
        let response: EntitlementResponse = try await transport.executeCapability {
            try MobileAPIRequest(method: .get, path: "/api/mobile/v1/entitlements")
        }
        guard response.data.entitlement == "bodyflow_full" else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return response
    }
}
