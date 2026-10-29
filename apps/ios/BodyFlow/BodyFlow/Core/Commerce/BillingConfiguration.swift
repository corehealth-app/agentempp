import Foundation

struct BillingConfiguration: Equatable, Sendable, CustomStringConvertible, CustomReflectable {
    let publicAPIKey: String

    init?(publicAPIKey: String?) {
        guard let publicAPIKey, publicAPIKey.hasPrefix("appl_") else { return nil }
        let suffix = publicAPIKey.dropFirst(5)
        guard !suffix.isEmpty, suffix.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
        }) else { return nil }
        self.publicAPIKey = publicAPIKey
    }

    var description: String { "BillingConfiguration(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
