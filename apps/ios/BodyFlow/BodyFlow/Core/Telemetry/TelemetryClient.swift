enum TelemetryEventName: String, Sendable {
    case appLaunched = "app_launched"
    case tabSelected = "tab_selected"
    case retryRequested = "retry_requested"
}

enum TelemetryValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case decimal(Double)
    case boolean(Bool)

    init?(_ value: any Sendable) {
        switch value {
        case let value as String:
            self = .string(value)
        case let value as Int:
            self = .integer(value)
        case let value as Double:
            self = .decimal(value)
        case let value as Bool:
            self = .boolean(value)
        default:
            return nil
        }
    }
}

struct TelemetryEvent: Equatable, Sendable {
    let name: TelemetryEventName
    let metadata: [String: TelemetryValue]

    init(
        name: TelemetryEventName,
        metadata: [String: any Sendable] = [:]
    ) {
        self.name = name
        self.metadata = metadata.reduce(into: [:]) { filtered, entry in
            if let value = TelemetryValue(entry.value) {
                filtered[entry.key] = value
            }
        }
    }
}

protocol TelemetryClient: Sendable {
    func record(_ event: TelemetryEvent) async
}

actor InMemoryTelemetryClient: TelemetryClient {
    private var events: [TelemetryEvent] = []

    func record(_ event: TelemetryEvent) {
        events.append(event)
    }

    func snapshot() -> [TelemetryEvent] {
        events
    }
}
