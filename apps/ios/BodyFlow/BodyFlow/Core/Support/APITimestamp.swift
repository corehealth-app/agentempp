import Foundation

struct APITimestamp: Codable, Hashable, Sendable {
    let value: Date

    init(value: Date) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let encodedValue = try container.decode(String.self)

        guard let value = Self.decode(encodedValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an RFC 3339 timestamp"
            )
        }

        self.value = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let formatter = Self.formatter()

        if value.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) != 0 {
            formatter.formatOptions.insert(.withFractionalSeconds)
        }

        try container.encode(formatter.string(from: value))
    }

    private static func decode(_ value: String) -> Date? {
        let fractionalFormatter = formatter()
        fractionalFormatter.formatOptions.insert(.withFractionalSeconds)

        return fractionalFormatter.date(from: value) ?? formatter().date(from: value)
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
