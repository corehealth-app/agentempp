import Foundation
import Testing

@testable import BodyFlow

@Suite("Official mobile entitlement")
struct MobileEntitlementRepositoryTests {
    private static let fixture = """
    {"data":{"entitlement":"bodyflow_full","has_active_access":true,
      "status":"active","source":"revenuecat","plan":"mensal",
      "access_expires_at":"2026-10-29T16:00:00.125+00:00","grace_expires_at":null,
      "cancel_at_period_end":true,"reason":"active_subscription",
      "decision_at":"2026-10-29T12:00:00-03:00",
      "mobile_billing":{"provider":"revenuecat","available":false,"reason":"provider_not_configured"}},
     "meta":{"api_version":"v1","request_id":"qa-entitlement-read-1"}}
    """

    @Test("reads the official access decision and preserves metadata without sending a user identifier")
    func readsOfficialDecision() async throws {
        let boundary = EntitlementEnvelopeBoundary(json: Self.fixture)
        let response = try await MobileEntitlementRepository(transport: boundary).entitlement()
        let request = try #require(await boundary.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/entitlements")
        #expect(request.queryItems.isEmpty)
        #expect(request.body == nil)
        #expect(request.idempotency == .notRequired)
        #expect(await boundary.requests.count == 1)
        #expect(response.meta.requestID == "qa-entitlement-read-1")
        #expect(response.data.entitlement == "bodyflow_full")
        #expect(response.data.hasActiveAccess)
        #expect(response.data.status == .active)
        #expect(response.data.source == .revenuecat)
        #expect(response.data.plan == .monthly)
        #expect(response.data.cancelAtPeriodEnd)
        #expect(response.data.reason == "active_subscription")
        #expect(response.data.mobileBilling.provider == "revenuecat")
        #expect(!response.data.mobileBilling.available)
        // Checkout availability must not revoke an existing official access grant.
        #expect(response.data.hasActiveAccess)
        let expiry = try #require(response.data.accessExpiresAt)
        #expect(abs(expiry.value.timeIntervalSince(response.data.decisionAt.value) - 3_600.125) < 0.001)
        #expect(response.data.graceExpiresAt == nil)
    }

    @Test("status and a future expiration never replace the server's denied access flag")
    func deniedAccessStaysDenied() async throws {
        let json = Self.fixture.replacingOccurrences(of: "\"has_active_access\":true", with: "\"has_active_access\":false")
        let response = try await MobileEntitlementRepository(transport: EntitlementEnvelopeBoundary(json: json)).entitlement()
        #expect(response.data.status == .active)
        #expect(response.data.accessExpiresAt != nil)
        #expect(!response.data.hasActiveAccess)
    }

    @Test("null source, plan and dates are preserved for an official manual grant")
    func preservesNullableManualGrant() async throws {
        let json = """
        {"data":{"entitlement":"bodyflow_full","has_active_access":true,
          "status":"manual_comp","source":null,"plan":null,
          "access_expires_at":null,"grace_expires_at":null,"cancel_at_period_end":false,
          "reason":"manual_grant","decision_at":"2026-10-29T15:00:00Z",
          "mobile_billing":{"provider":"revenuecat","available":false,"reason":"provider_not_configured"}},
         "meta":{"api_version":"v1","request_id":"qa-manual"}}
        """
        let response = try await MobileEntitlementRepository(transport: EntitlementEnvelopeBoundary(json: json)).entitlement()
        #expect(response.data.status == .manualComp)
        #expect(response.data.source == nil)
        #expect(response.data.plan == nil)
        #expect(response.data.accessExpiresAt == nil)
        #expect(response.data.graceExpiresAt == nil)
        #expect(response.data.hasActiveAccess)
    }

    @Test("all documented server status values decode without deriving access", arguments: [
        "active", "trialing", "grace_period", "expired", "canceled", "grandfathered", "manual_comp", "blocked"
    ])
    func documentedStatuses(_ status: String) throws {
        let json = Self.fixture.replacingOccurrences(of: "\"status\":\"active\"", with: "\"status\":\"\(status)\"")
        let response = try JSONDecoder().decode(EntitlementResponse.self, from: Data(json.utf8))
        #expect(response.data.status.rawValue == status)
        #expect(response.data.hasActiveAccess)
    }

    @Test("malformed or missing authority fields fail closed", arguments: [
        ("\"has_active_access\":true,", ""),
        ("\"decision_at\":\"2026-10-29T12:00:00-03:00\"", "\"decision_at\":\"yesterday\""),
        ("\"status\":\"active\"", "\"status\":\"unknown_state\""),
        ("\"source\":\"revenuecat\"", "\"source\":\"unrecognized_source\""),
        ("\"plan\":\"mensal\"", "\"plan\":\"invented_plan\""),
        ("\"available\":false", "\"available\":\"false\"")
    ])
    func invalidAuthority(_ replacement: (String, String)) async {
        let json = Self.fixture.replacingOccurrences(of: replacement.0, with: replacement.1)
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await MobileEntitlementRepository(transport: EntitlementEnvelopeBoundary(json: json)).entitlement()
        }
    }

    @Test("required nullable fields may be null but cannot be missing", arguments: [
        "\"source\":\"revenuecat\",", "\"plan\":\"mensal\",",
        "\"access_expires_at\":\"2026-10-29T16:00:00.125+00:00\",", "\"grace_expires_at\":null,"
    ])
    func rejectsMissingNullableAuthority(_ field: String) async {
        let json = Self.fixture.replacingOccurrences(of: field, with: "")
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await MobileEntitlementRepository(transport: EntitlementEnvelopeBoundary(json: json)).entitlement()
        }
    }

    @Test("re-encoding the contract keeps required null fields instead of omitting them")
    func keepsExplicitNullWhenEncoding() throws {
        let response = try JSONDecoder().decode(EntitlementResponse.self, from: Data(Self.fixture.utf8))
        let encoded = try JSONEncoder().encode(response)
        let envelope = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let data = try #require(envelope["data"] as? [String: Any])
        #expect(data.keys.contains("grace_expires_at"))
        #expect(data["grace_expires_at"] is NSNull)
    }

    @Test("a response for another entitlement cannot be used as Performe access")
    func rejectsWrongEntitlement() async {
        let json = Self.fixture.replacingOccurrences(of: "bodyflow_full", with: "other_product")
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await MobileEntitlementRepository(transport: EntitlementEnvelopeBoundary(json: json)).entitlement()
        }
    }

    @Test("network and subscription failures remain failures instead of cached grants")
    func preservesErrors() async {
        let cases: [(MobileAPITransportError, BodyFlowCapabilityError)] = [
            (.network, .offline),
            (.http(status: 402, code: "subscription_required", requestID: "qa-denied"), .subscriptionRequired)
        ]
        for (failure, expected) in cases {
            let boundary = EntitlementEnvelopeBoundary(json: Self.fixture, failure: failure)
            await #expect(throws: expected) {
                try await MobileEntitlementRepository(transport: boundary).entitlement()
            }
        }
    }

    @Test("cancellation never becomes a recoverable access response")
    func preservesCancellation() async {
        await #expect(throws: CancellationError.self) {
            try await MobileEntitlementRepository(transport: EntitlementEnvelopeBoundary(json: Self.fixture, cancelled: true)).entitlement()
        }
    }
}

/// The BFF response is external; decoding, mapping and request creation remain real.
private actor EntitlementEnvelopeBoundary: MobileAPIEnvelopeExecuting {
    struct Request: Sendable {
        let method: HTTPMethod
        let path: String
        let queryItems: [URLQueryItem]
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }

    private(set) var requests: [Request] = []
    let json: String
    let failure: MobileAPITransportError?
    let cancelled: Bool

    init(json: String, failure: MobileAPITransportError? = nil, cancelled: Bool = false) {
        self.json = json
        self.failure = failure
        self.cancelled = cancelled
    }

    func executeEnvelope<Response: Codable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> MobileResponse<Response> {
        requests.append(Request(method: request.method, path: request.path,
                                queryItems: request.queryItems, body: request.body, idempotency: request.idempotency))
        if cancelled { throw CancellationError() }
        if let failure { throw failure }
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: Data(json.utf8))
    }
}
