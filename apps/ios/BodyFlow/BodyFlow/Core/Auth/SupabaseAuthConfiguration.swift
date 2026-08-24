import Foundation

enum SupabaseAuthConfigurationError: Error, Equatable, Sendable {
    case missingOrigin
    case invalidOrigin
    case missingKey
    case invalidKey
}

struct SupabaseAuthConfiguration: Sendable, Equatable,
    CustomStringConvertible, CustomReflectable {
    let origin: URL
    let authURL: URL
    let key: String

    init(originString: String?, key: String?) throws {
        guard let originString else {
            throw SupabaseAuthConfigurationError.missingOrigin
        }
        let originCandidate = originString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !originCandidate.isEmpty else {
            throw SupabaseAuthConfigurationError.missingOrigin
        }
        guard var components = URLComponents(string: originCandidate),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            throw SupabaseAuthConfigurationError.invalidOrigin
        }
        components.scheme = "https"
        components.path = "/"
        guard let normalizedOrigin = components.url else {
            throw SupabaseAuthConfigurationError.invalidOrigin
        }

        guard let key else {
            throw SupabaseAuthConfigurationError.missingKey
        }
        let keyCandidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyCandidate.isEmpty else {
            throw SupabaseAuthConfigurationError.missingKey
        }
        guard Self.isAllowed(keyCandidate) else {
            throw SupabaseAuthConfigurationError.invalidKey
        }

        components.path = "/auth/v1"
        guard let authURL = components.url else {
            throw SupabaseAuthConfigurationError.invalidOrigin
        }

        origin = normalizedOrigin
        self.authURL = authURL
        self.key = keyCandidate
    }

    var description: String { "SupabaseAuthConfiguration(redacted)" }

    var customMirror: Mirror {
        Mirror(self, children: [:], displayStyle: .struct)
    }

    func approves(_ url: URL) -> Bool {
        url.scheme?.lowercased() == origin.scheme
            && url.host?.lowercased() == origin.host?.lowercased()
            && Self.effectivePort(url) == Self.effectivePort(origin)
            && url.user == nil
            && url.password == nil
            && (url.path == "/auth/v1" || url.path.hasPrefix("/auth/v1/"))
    }

    private static func isAllowed(_ key: String) -> Bool {
        if key.hasPrefix("sb_publishable_") {
            return key.count > "sb_publishable_".count
        }
        if key.hasPrefix("sb_") {
            return false
        }

        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = decodeBase64URL(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: payload),
              let claims = object as? [String: Any],
              claims["role"] as? String == "anon"
        else {
            return false
        }
        return true
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
    }
}
