import Foundation
import Testing

@testable import BodyFlow

@Suite("Telemetry")
struct TelemetryTests {
    @Test("filters unsupported metadata before recording")
    func filtersUnsupportedMetadata() async {
        let metadata: [String: any Sendable] = [
            "screen": "tab.hoje",
            "attempt": 2,
            "duration": 1.5,
            "success": true,
            "timestamp": Date(timeIntervalSince1970: 0),
            "labels": ["fixture", "private"],
        ]
        let event = TelemetryEvent(name: .tabSelected, metadata: metadata)

        #expect(event.metadata.count == 4)
        #expect(event.metadata["screen"] == .string("tab.hoje"))
        #expect(event.metadata["attempt"] == .integer(2))
        #expect(event.metadata["duration"] == .decimal(1.5))
        #expect(event.metadata["success"] == .boolean(true))
        #expect(event.metadata["timestamp"] == nil)
        #expect(event.metadata["labels"] == nil)

        let client = InMemoryTelemetryClient()
        await client.record(event)

        let snapshot = await client.snapshot()
        #expect(snapshot == [event])
    }
}
