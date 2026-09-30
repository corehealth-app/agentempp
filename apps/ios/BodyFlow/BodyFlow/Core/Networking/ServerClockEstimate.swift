import Foundation

/// The mobile API's clock as last read from a response `Date` header.
///
/// The server accepts a routine action against its own clock
/// (`scheduled_for` may not be after the server's now), so a phone whose
/// clock runs ahead must not offer the action early. The header is whole
/// seconds and stamped before the response travels, so the estimate trails
/// the server: it may open an action a moment late, never early.
final class ServerClockEstimate: @unchecked Sendable {
    private let lock = NSLock()
    private var storedOffset: TimeInterval?

    /// Seconds to add to the phone's clock to read the server's; nil until a
    /// response carried a readable `Date`.
    var offset: TimeInterval? {
        lock.withLock { storedOffset }
    }

    func record(dateHeader: String?, receivedAt: Date) {
        guard let dateHeader, let serverDate = Self.parse(dateHeader) else { return }
        let offset = serverDate.timeIntervalSince(receivedAt)
        lock.withLock { storedOffset = offset }
    }

    func serverNow(deviceNow: Date) -> Date {
        deviceNow.addingTimeInterval(offset ?? 0)
    }

    /// The instant a routine action may be sent: the server checks
    /// `scheduled_for <= min(occurred_at, its own now)` and `occurred_at` is
    /// the phone's clock, so both must have reached the occurrence.
    func actionableNow(deviceNow: Date) -> Date {
        min(deviceNow, serverNow(deviceNow: deviceNow))
    }

    /// RFC 9110 IMF-fixdate, e.g. "Tue, 29 Sep 2026 19:05:00 GMT".
    static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: value)
    }
}
