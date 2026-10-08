#if DEBUG
import Foundation

/// Explicit synthetic UI contexts. Old demo responses remain legacy unless
/// a test opts in; none of these fixtures exist in a Release build.
enum DemoBlock7700Scenario: String, CaseIterable, Sendable {
    case recomposition, gain, maintenance, legacy, nullProgress
    case currentRecomposition

    var argument: String { "--ui-testing-block-\(rawValue)" }

    static func resolve(arguments: [String]) -> Self? {
        guard arguments.contains("--ui-testing") else { return nil }
        let matches = allCases.filter { arguments.contains($0.argument) }
        return matches.count == 1 ? matches[0] : nil
    }

    private var currentProtocol: String? {
        switch self {
        case .recomposition, .currentRecomposition: "recomposicao"
        case .gain: "ganho_massa"
        case .maintenance: "manutencao"
        case .legacy, .nullProgress: nil
        }
    }

    func today(_ response: TodayResponse) throws -> TodayResponse {
        guard self != .currentRecomposition else {
            var snapshot = response.data
            snapshot.currentProtocol = currentProtocol
            return TodayResponse(data: snapshot, meta: response.meta)
        }
        let encoded = try JSONEncoder().encode(response.data)
        guard var raw = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var targets = raw["targets"] as? [String: Any],
              var consumed = raw["consumed"] as? [String: Any],
              var block = raw["block_7700"] as? [String: Any] else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        raw["protocol"] = "recomposicao" // Historical day, deliberately independent.
        raw["current_protocol"] = currentProtocol.map { $0 as Any } ?? NSNull()
        targets["calories_kcal"] = 1_843
        consumed["calories_kcal"] = 2_076
        raw["targets"] = targets
        raw["consumed"] = consumed
        raw["remaining_food_kcal"] = 0
        raw["food_excess_kcal"] = 233
        raw["exercise_kcal"] = 565
        raw["daily_balance_kcal"] = -832
        raw["daily_balance_reference_kcal"] = 2_343
        raw["daily_balance_includes_exercise"] = true
        block["enabled"] = self == .recomposition || self == .legacy
        block["target_kcal"] = 7_700
        block["current_kcal"] = 3_850
        block["percentage"] = 50
        block["completed_blocks"] = 2
        block["total_credited_kcal"] = 19_250
        raw["block_7700"] = block
        if self == .legacy { raw.removeValue(forKey: "current_protocol") }
        let snapshot = try JSONDecoder().decode(TodaySnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
        return TodayResponse(data: snapshot, meta: response.meta)
    }

    func progress(_ response: ProgressResponse) -> ProgressResponse {
        if self == .nullProgress { return ProgressResponse(data: nil, meta: response.meta) }
        if self == .currentRecomposition {
            var snapshot = response.data
            snapshot?.currentProtocol = currentProtocol
            snapshot?.block7700Enabled = true
            return ProgressResponse(data: snapshot, meta: response.meta)
        }
        let snapshot = ProgressSnapshot(
            xpTotal: 1_240, level: 2, currentStreak: 3, longestStreak: 7,
            blocksCompleted: 4, deficitBlock: 3_120, currentWeight: 80,
            currentBodyFatPercent: nil,
            badgesEarned: ["Primeiro Bloco", "Primeira Semana", "badge-z", "Primeira Semana"],
            lastActiveDate: "2026-10-04", nextReevaluation: "2026-10-18",
            updatedAt: APITimestamp(value: Date(timeIntervalSince1970: 1_791_072_000)),
            currentProtocol: currentProtocol, block7700Enabled: self == .legacy ? nil : self == .recomposition
        )
        return ProgressResponse(data: snapshot, meta: response.meta)
    }
}

struct DemoBlock7700TodayProvider: TodayProviding {
    let base: any TodayProviding
    let scenario: DemoBlock7700Scenario
    func today() async throws -> TodayResponse { try scenario.today(await base.today()) }
}

struct DemoBlock7700ProgressProvider: ProgressProviding {
    let base: any ProgressProviding
    let scenario: DemoBlock7700Scenario
    func progress() async throws -> ProgressResponse { try scenario.progress(await base.progress()) }
    func profileWeight() async throws -> ProfileWeightResponse? { try await base.profileWeight() }
    func trends(days: Int) async throws -> TrendsResponse { try await base.trends(days: days) }
}
#endif
