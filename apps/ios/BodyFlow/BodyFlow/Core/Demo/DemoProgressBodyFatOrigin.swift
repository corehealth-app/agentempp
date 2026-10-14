#if DEBUG
import Foundation

/// An explicit synthetic API contract sample, not evidence inferred from
/// a profile value or from the three public photo readings. The server
/// owns that decision; this provider exercises only the iOS projection.
enum DemoProgressBodyFatOriginScenario: String, CaseIterable, Sendable {
    case photos, manual, legacy, unknown

    var argument: String { "--ui-testing-progress-body-fat-origin-\(rawValue)" }

    static func resolve(arguments: [String]) -> Self? {
        guard arguments.contains("--ui-testing"),
              arguments.contains("--ui-testing-prompt13-loaded") else { return nil }
        let selected = allCases.filter { arguments.contains($0.argument) }
        return selected.count == 1 ? selected[0] : nil
    }

    func response() throws -> ProgressResponse {
        let originField: String = switch self {
        case .photos: #""current_bf_origin": "signup_photos","#
        case .manual: #""current_bf_origin": null,"#
        case .legacy: ""
        case .unknown: #""current_bf_origin": "future_origin","#
        }
        // Decode through the existing public DTO. Before the actual fix,
        // Swift's decoder ignores current_bf_origin, while 24 still reaches
        // the real model and real ProgressRootView. No future API is used.
        let json = """
        {
          "data": {
            "xp_total": 0,
            "level": 1,
            "current_streak": 1,
            "longest_streak": 1,
            "blocks_completed": 0,
            "deficit_block": 0,
            "current_weight": 80,
            "current_bf_percent": 24,
            \(originField)
            "badges_earned": [],
            "last_active_date": null,
            "next_reevaluation": null,
            "updated_at": "2026-10-14T12:00:00.000Z",
            "current_protocol": "manutencao",
            "block_7700_enabled": false
          },
          "meta": {
            "api_version": "v1",
            "request_id": "synthetic-progress-body-fat-origin-\(rawValue)"
          }
        }
        """
        return try JSONDecoder().decode(ProgressResponse.self, from: Data(json.utf8))
    }
}

struct DemoProgressBodyFatOriginProvider: ProgressProviding {
    let scenario: DemoProgressBodyFatOriginScenario
    func progress() async throws -> ProgressResponse { try scenario.response() }
    // No profile read and no fabricated trend history. Protocol defaults
    // retain their existing honest empty behavior.
}
#endif
