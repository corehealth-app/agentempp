import Foundation

typealias CoachExperienceResponse = MobileResponse<CoachExperienceSnapshot>

enum SelectableCoachPersona: String, CaseIterable, Codable, Equatable, Sendable {
    case focus
    case impulse
    case zen
}

enum EffectiveCoachPersona: String, CaseIterable, Codable, Equatable, Sendable {
    case focus
    case impulse
    case zen
    case balanced
}

struct CoachPersonaOption: Identifiable, Codable, Equatable, Sendable {
    let code: SelectableCoachPersona
    let name: String
    let description: String

    var id: SelectableCoachPersona { code }
}

struct CoachExperienceSnapshot: Codable, Equatable, Sendable {
    let selected: SelectableCoachPersona?
    let effective: EffectiveCoachPersona
    let options: [CoachPersonaOption]
    let mascot: MascotSnapshot
    let contractVersion: String

    private enum CodingKeys: String, CodingKey {
        case selected
        case effective
        case options
        case mascot
        case contractVersion = "contract_version"
    }
}

struct MascotSnapshot: Codable, Equatable, Sendable {
    let state: MascotWireState
    let changedAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case state
        case changedAt = "changed_at"
    }
}

enum MascotWireState: Equatable, Sendable, Codable {
    case inactive
    case reactivating
    case active
    case evolving
    case neglected
    case unknown(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = switch rawValue {
        case "inactive": .inactive
        case "reactivating": .reactivating
        case "active": .active
        case "evolving": .evolving
        case "neglected": .neglected
        default: .unknown(rawValue)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let rawValue = switch self {
        case .inactive: "inactive"
        case .reactivating: "reactivating"
        case .active: "active"
        case .evolving: "evolving"
        case .neglected: "neglected"
        case let .unknown(value): value
        }
        try container.encode(rawValue)
    }
}
