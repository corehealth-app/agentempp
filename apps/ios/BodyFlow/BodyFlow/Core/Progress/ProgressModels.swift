import Foundation

typealias ProgressResponse = MobileResponse<ProgressSnapshot?>

struct ProgressSnapshot: Codable, Equatable, Sendable {
    let xpTotal: Int
    let level: Int
    let currentStreak: Int
    let longestStreak: Int
    let blocksCompleted: Int
    let deficitBlock: Int
    let currentWeight: Decimal?
    let currentBodyFatPercent: Decimal?
    let badgesEarned: [String]
    let lastActiveDate: String?
    let nextReevaluation: String?
    let updatedAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case xpTotal = "xp_total"
        case level
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case blocksCompleted = "blocks_completed"
        case deficitBlock = "deficit_block"
        case currentWeight = "current_weight"
        case currentBodyFatPercent = "current_bf_percent"
        case badgesEarned = "badges_earned"
        case lastActiveDate = "last_active_date"
        case nextReevaluation = "next_reevaluation"
        case updatedAt = "updated_at"
    }
}
