import Foundation

/// Representation selection only; Auth/lease/clinical policy remain mandatory.
/// The app composition installs v4 only for an explicitly bound QA candidate.
enum TodayEnergyRepresentation: String, Equatable, Sendable {
    case legacy
    case fieldAvailabilityV1 = "field_availability_v1"

    static let infoKey = "PERFORME_TODAY_ENERGY_REPRESENTATION"

    var queryItems: [URLQueryItem] {
        self == .fieldAvailabilityV1 ? [URLQueryItem(name: "day_energy", value: rawValue)] : []
    }
}

/// Closed v4 facts from the same Today observation, never clinical authority.
enum TodayExerciseEnergy: Codable, Equatable, Sendable {
    case available, unavailable

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: EnergyAvailabilityKey.self)
        let status = try c.decode(String.self, forKey: .status)
        switch status {
        case "available" where Set(c.allKeys) == [.status]: self = .available
        case "unavailable" where Set(c.allKeys) == [.status, .reason]:
            guard try c.decode(String.self, forKey: .reason) == "unknown_workout_energy" else {
                throw invalidEnergy(decoder)
            }
            self = .unavailable
        default: throw invalidEnergy(decoder)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: EnergyAvailabilityKey.self)
        try c.encode(self == .available ? "available" : "unavailable", forKey: .status)
        if self == .unavailable { try c.encode("unknown_workout_energy", forKey: .reason) }
    }
}

enum TodayBalanceEnergy: Codable, Equatable, Sendable {
    enum Reason: String, Codable, Sendable {
        case unknownWorkoutEnergy = "unknown_workout_energy"
        case targetUnavailable = "target_unavailable"
    }
    case available, unavailable(Reason), protected

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: EnergyAvailabilityKey.self)
        switch try c.decode(String.self, forKey: .status) {
        case "available" where Set(c.allKeys) == [.status]: self = .available
        case "protected" where Set(c.allKeys) == [.status]: self = .protected
        case "unavailable" where Set(c.allKeys) == [.status, .reason]:
            self = .unavailable(try c.decode(Reason.self, forKey: .reason))
        default: throw invalidEnergy(decoder)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: EnergyAvailabilityKey.self)
        switch self {
        case .available: try c.encode("available", forKey: .status)
        case .protected: try c.encode("protected", forKey: .status)
        case let .unavailable(reason):
            try c.encode("unavailable", forKey: .status)
            try c.encode(reason, forKey: .reason)
        }
    }
}

private struct EnergyAvailabilityKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
    static let status = Self(stringValue: "status")
    static let reason = Self(stringValue: "reason")
}

private func invalidEnergy(_ decoder: any Decoder) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Today energy availability"))
}
