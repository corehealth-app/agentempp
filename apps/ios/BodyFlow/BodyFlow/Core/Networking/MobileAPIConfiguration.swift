import Foundation

struct MobileAPIConfiguration: Sendable, Equatable {
    let origin: URL

    init(originString: String) throws {
        try self.init(originString: Optional(originString))
    }

    init(originString: String?) throws {
        guard let originString else {
            throw MobileAPIConfigurationError.missingOrigin
        }

        let candidate = originString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            throw MobileAPIConfigurationError.missingOrigin
        }
        guard var components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            throw MobileAPIConfigurationError.invalidOrigin
        }

        components.scheme = "https"
        components.path = "/"
        guard let normalized = components.url,
              normalized.scheme == "https",
              normalized.host == host
        else {
            throw MobileAPIConfigurationError.invalidOrigin
        }
        origin = normalized
    }

    func approves(_ url: URL) -> Bool {
        url.scheme?.lowercased() == origin.scheme
            && url.host?.lowercased() == origin.host?.lowercased()
            && Self.effectivePort(of: url) == Self.effectivePort(of: origin)
            && MobileAPIRequestPath.isValid(url.path)
            && url.user == nil
            && url.password == nil
            && url.fragment == nil
    }

    private static func effectivePort(of url: URL) -> Int? {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : nil
    }
}

protocol MobileAPIConfigurationProviding: Sendable {
    func currentConfiguration() -> MobileAPIConfiguration?
}

struct StaticMobileAPIConfigurationProvider: MobileAPIConfigurationProviding {
    let configuration: MobileAPIConfiguration?

    func currentConfiguration() -> MobileAPIConfiguration? {
        configuration
    }
}

enum MobileAPIIdempotency: Hashable, Sendable {
    case notRequired
    case required(IdempotencyKey)
}

struct MobileAPIRequest<Response: Decodable & Sendable>: Sendable {
    let method: HTTPMethod
    let path: String
    let queryItems: [URLQueryItem]
    let body: Data?
    let idempotency: MobileAPIIdempotency

    init(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        idempotencyKey: IdempotencyKey? = nil
    ) throws {
        guard MobileAPIRequestPath.isValid(path) else {
            throw MobileAPIRequestError.invalidPath
        }
        guard queryItems.allSatisfy(Self.isValid(queryItem:)) else {
            throw MobileAPIRequestError.invalidQuery
        }

        let isMutation = method == .post || method == .patch || method == .delete
        guard isMutation || idempotencyKey == nil else {
            throw MobileAPIRequestError.unexpectedIdempotencyKey
        }

        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        if isMutation {
            self.idempotency = .required(
                idempotencyKey ?? Self.makeIdempotencyKey()
            )
        } else {
            self.idempotency = .notRequired
        }
    }

    func url(using configuration: MobileAPIConfiguration) throws -> URL {
        guard var components = URLComponents(
            url: configuration.origin,
            resolvingAgainstBaseURL: false
        ) else {
            throw MobileAPIRequestError.invalidPath
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url,
              url.scheme == configuration.origin.scheme,
              url.host == configuration.origin.host,
              url.port == configuration.origin.port
        else {
            throw MobileAPIRequestError.invalidPath
        }
        return url
    }

    private static func isValid(queryItem: URLQueryItem) -> Bool {
        let reserved = ["authorization", "host"]
        return !queryItem.name.isEmpty
            && !reserved.contains(queryItem.name.lowercased())
            && !queryItem.name.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
            )
            && !(queryItem.value ?? "").unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
            )
    }

    private static func makeIdempotencyKey() -> IdempotencyKey {
        try! IdempotencyKey(validating: "mobile-\(UUID().uuidString.lowercased())")
    }
}

enum MobileAPIRequestPath {
    static func isValid(_ path: String) -> Bool {
        guard path == "/api/mobile/v1"
                || path.hasPrefix("/api/mobile/v1/"),
              !path.hasPrefix("//"),
              !path.contains("?"),
              !path.contains("#"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let decoded = path.removingPercentEncoding,
              decoded == "/api/mobile/v1"
                || decoded.hasPrefix("/api/mobile/v1/")
        else {
            return false
        }

        return !decoded.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0 == "." || $0 == ".." }
    }

}
