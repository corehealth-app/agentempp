import Foundation

typealias ProgressResponse = MobileResponse<ProgressSnapshot?>

typealias ProfileWeightResponse = MobileResponse<ProfileWeightSnapshot?>

/// C5: the latest official weight is read from `/profile`, independently of
/// the progress ledger. A recorded instant is not a measured instant.
struct ProfileWeightSnapshot: Codable, Equatable, Sendable {
    let weightKG: Decimal?
    let measuredAt: APITimestamp?
    let instantSource: String?

    private enum CodingKeys: String, CodingKey {
        case weightKG = "weight_kg"
        case measuredAt = "weight_measured_at"
        case instantSource = "weight_instant_source"
    }
}

struct ProgressSnapshot: Codable, Equatable, Sendable {
    let xpTotal: Int
    let level: Int
    let currentStreak: Int
    let longestStreak: Int
    let blocksCompleted: Int?
    let deficitBlock: Int?
    let currentWeight: Decimal?
    let currentBodyFatPercent: Decimal?
    let badgesEarned: [String]
    let lastActiveDate: String?
    let nextReevaluation: String?
    let updatedAt: APITimestamp
    var currentProtocol: String? = nil
    var block7700Enabled: Bool? = nil
    var currentBodyFatOrigin: String? = nil
    var clinicalPolicy: CurrentClinicalPolicy? = nil

    var blockPresentationPolicy: Block7700PresentationPolicy {
        if clinicalPolicy?.hide.block == true { return .unknown }
        return Block7700PresentationPolicy(currentProtocol: currentProtocol, enabled: block7700Enabled)
    }

    private enum CodingKeys: String, CodingKey {
        case xpTotal = "xp_total"
        case level
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case blocksCompleted = "blocks_completed"
        case deficitBlock = "deficit_block"
        case currentWeight = "current_weight"
        case currentBodyFatPercent = "current_bf_percent"
        case currentBodyFatOrigin = "current_bf_origin"
        case badgesEarned = "badges_earned"
        case lastActiveDate = "last_active_date"
        case nextReevaluation = "next_reevaluation"
        case updatedAt = "updated_at"
        case currentProtocol = "current_protocol"
        case block7700Enabled = "block_7700_enabled"
        case clinicalPolicy = "clinical_policy"
    }
}
