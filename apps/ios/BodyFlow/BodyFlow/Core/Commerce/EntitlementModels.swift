import Foundation

typealias EntitlementResponse = MobileResponse<EntitlementSnapshot>

/// The BFF decides access. Status, expiration and checkout availability are
/// presentation data; none of them replaces `hasActiveAccess` on the client.
struct EntitlementSnapshot: Codable, Equatable, Sendable {
    let entitlement: String
    let hasActiveAccess: Bool
    let status: EntitlementStatus
    let source: EntitlementSource?
    let plan: EntitlementPlan?
    let accessExpiresAt: APITimestamp?
    let graceExpiresAt: APITimestamp?
    let cancelAtPeriodEnd: Bool
    let reason: String
    let decisionAt: APITimestamp
    let mobileBilling: MobileBillingAvailability

    private enum CodingKeys: String, CodingKey {
        case entitlement, status, source, plan, reason
        case hasActiveAccess = "has_active_access"
        case accessExpiresAt = "access_expires_at"
        case graceExpiresAt = "grace_expires_at"
        case cancelAtPeriodEnd = "cancel_at_period_end"
        case decisionAt = "decision_at"
        case mobileBilling = "mobile_billing"
    }

    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        entitlement = try fields.decode(String.self, forKey: .entitlement)
        hasActiveAccess = try fields.decode(Bool.self, forKey: .hasActiveAccess)
        status = try fields.decode(EntitlementStatus.self, forKey: .status)
        // The server contract requires these keys, allowing an explicit null.
        // decodeIfPresent would also accept a truncated/missing authority field.
        source = try fields.decode(EntitlementSource?.self, forKey: .source)
        plan = try fields.decode(EntitlementPlan?.self, forKey: .plan)
        accessExpiresAt = try fields.decode(APITimestamp?.self, forKey: .accessExpiresAt)
        graceExpiresAt = try fields.decode(APITimestamp?.self, forKey: .graceExpiresAt)
        cancelAtPeriodEnd = try fields.decode(Bool.self, forKey: .cancelAtPeriodEnd)
        reason = try fields.decode(String.self, forKey: .reason)
        decisionAt = try fields.decode(APITimestamp.self, forKey: .decisionAt)
        mobileBilling = try fields.decode(MobileBillingAvailability.self, forKey: .mobileBilling)
    }

    func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(entitlement, forKey: .entitlement)
        try fields.encode(hasActiveAccess, forKey: .hasActiveAccess)
        try fields.encode(status, forKey: .status)
        try fields.encode(source, forKey: .source)
        try fields.encode(plan, forKey: .plan)
        try fields.encode(accessExpiresAt, forKey: .accessExpiresAt)
        try fields.encode(graceExpiresAt, forKey: .graceExpiresAt)
        try fields.encode(cancelAtPeriodEnd, forKey: .cancelAtPeriodEnd)
        try fields.encode(reason, forKey: .reason)
        try fields.encode(decisionAt, forKey: .decisionAt)
        try fields.encode(mobileBilling, forKey: .mobileBilling)
    }
}

enum EntitlementStatus: String, Codable, Sendable {
    case active, trialing, expired, canceled, grandfathered, blocked
    case gracePeriod = "grace_period"
    case manualComp = "manual_comp"
}

enum EntitlementSource: String, Codable, Sendable {
    case stripe, revenuecat, manual, legacy
    case appleStoreKit = "apple_storekit"
}

enum EntitlementPlan: String, Codable, Sendable {
    case trial
    case monthly = "mensal"
    case annual = "anual"
}

struct MobileBillingAvailability: Codable, Equatable, Sendable {
    let provider: String
    let available: Bool
    let reason: String
}

protocol EntitlementProviding: Sendable {
    func entitlement() async throws -> EntitlementResponse
}
