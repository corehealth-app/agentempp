import Foundation
import Testing

@testable import BodyFlow

@Suite("API timestamps")
struct APITimestampTests {
    private func decode(_ literal: String) throws -> Date {
        try JSONDecoder().decode(APITimestamp.self, from: Data("\"\(literal)\"".utf8)).value
    }

    @Test("Postgres-shaped timestamps with microseconds and a +00:00 offset decode")
    func postgresShapedTimestampsDecode() throws {
        let expected = Date(timeIntervalSince1970: 1_784_589_300)
        #expect(try decode("2026-07-20T23:15:00Z") == expected)
        #expect(try decode("2026-07-20T23:15:00+00:00") == expected)
        #expect(try decode("2026-07-20T20:15:00-03:00") == expected)
        #expect(abs(try decode("2026-07-20T23:15:00.5Z").timeIntervalSince(expected) - 0.5) < 0.001)
        #expect(abs(try decode("2026-07-20T23:15:00.123456+00:00").timeIntervalSince(expected) - 0.123) < 0.001)
    }

    @Test("a non-timestamp string fails closed")
    func invalidStringFails() {
        #expect(throws: (any Error).self) { try decode("2026-07-20") }
    }
}
