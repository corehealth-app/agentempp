struct ContentCoverPath: Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let rawValue: String

    init(validating rawValue: String) throws {
        let prefix = "/api/mobile/v1/content/covers/"
        let prefixBytes = Array(prefix.utf8)
        let rawBytes = Array(rawValue.utf8)

        guard rawBytes.starts(with: prefixBytes) else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        let capability = rawBytes.dropFirst(prefixBytes.count)
        guard !capability.isEmpty, capability.allSatisfy(Self.isCapabilityByte) else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        self.rawValue = rawValue
    }

    var description: String {
        "ContentCoverPath(redacted)"
    }

    var debugDescription: String {
        description
    }

    private static func isCapabilityByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 48...57, 65...90, 95, 97...122, 45:
            true
        default:
            false
        }
    }
}
