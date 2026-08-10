import Foundation

struct ContentCoverTrustedOrigin: Equatable, Hashable, Sendable {
    let url: URL

    init(validating url: URL) throws {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              Self.hasValidPortSyntax(in: url, components: components)
        else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        components.scheme = "https"
        components.host = host.lowercased()

        guard let normalizedURL = components.url else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        self.url = normalizedURL
    }

    private static func hasValidPortSyntax(in url: URL, components: URLComponents) -> Bool {
        guard let authority = authority(in: url.absoluteString) else {
            return false
        }

        guard let explicitPort = explicitPort(in: authority) else {
            return components.port == nil
        }

        guard !explicitPort.isEmpty,
              explicitPort.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = Int(explicitPort),
              (1...65_535).contains(port)
        else {
            return false
        }

        return components.port == port
    }

    private static func authority(in absoluteString: String) -> Substring? {
        guard let separator = absoluteString.range(of: "://") else {
            return nil
        }

        let afterSeparator = absoluteString[separator.upperBound...]
        let authorityEnd = afterSeparator.firstIndex {
            $0 == "/" || $0 == "?" || $0 == "#"
        } ?? afterSeparator.endIndex
        return afterSeparator[..<authorityEnd]
    }

    private static func explicitPort(in authority: Substring) -> Substring? {
        if authority.first == "[" {
            guard let closingBracket = authority.firstIndex(of: "]") else {
                return ""
            }

            let suffix = authority[authority.index(after: closingBracket)...]
            guard !suffix.isEmpty else {
                return nil
            }
            guard suffix.first == ":" else {
                return ""
            }
            return suffix.dropFirst()
        }

        guard let delimiter = authority.lastIndex(of: ":") else {
            return nil
        }
        return authority[authority.index(after: delimiter)...]
    }
}

struct ContentCoverTransportRequest: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let path: ContentCoverPath
    let url: URL

    fileprivate init(path: ContentCoverPath, url: URL) {
        self.path = path
        self.url = url
    }

    var description: String {
        "ContentCoverTransportRequest(redacted)"
    }

    var debugDescription: String {
        description
    }
}

struct ContentCoverRequestResolver: Sendable {
    private let trustedOrigin: ContentCoverTrustedOrigin

    init(trustedOrigin: ContentCoverTrustedOrigin) {
        self.trustedOrigin = trustedOrigin
    }

    func resolve(_ path: ContentCoverPath) throws -> ContentCoverTransportRequest {
        guard let resolvedURL = URL(
            string: path.rawValue,
            relativeTo: trustedOrigin.url
        )?.absoluteURL,
              let resolvedComponents = URLComponents(
                url: resolvedURL,
                resolvingAgainstBaseURL: false
              ),
              let originComponents = URLComponents(
                url: trustedOrigin.url,
                resolvingAgainstBaseURL: false
              ),
              resolvedComponents.scheme?.lowercased() == "https",
              resolvedComponents.host?.lowercased() == originComponents.host?.lowercased(),
              Self.effectivePort(of: resolvedComponents) == Self.effectivePort(of: originComponents),
              resolvedComponents.user == nil,
              resolvedComponents.password == nil,
              resolvedComponents.query == nil,
              resolvedComponents.fragment == nil,
              resolvedURL.path == path.rawValue
        else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        return ContentCoverTransportRequest(path: path, url: resolvedURL)
    }

    private static func effectivePort(of components: URLComponents) -> Int? {
        components.port ?? (components.scheme?.lowercased() == "https" ? 443 : nil)
    }

}

struct ContentCoverByteStream: Sendable {
    let statusCode: Int
    let declaredLength: Int64?
    let mimeType: String?
    let cacheMaxAgeSeconds: Int?
    let redirectLocation: URL?
    let chunks: AsyncThrowingStream<Data, any Error>
    let cancel: @Sendable () async -> Void

    init(
        statusCode: Int,
        declaredLength: Int64?,
        mimeType: String?,
        cacheMaxAgeSeconds: Int?,
        redirectLocation: URL?,
        chunks: AsyncThrowingStream<Data, any Error>,
        cancel: @escaping @Sendable () async -> Void
    ) {
        self.statusCode = statusCode
        self.declaredLength = declaredLength
        self.mimeType = mimeType
        self.cacheMaxAgeSeconds = cacheMaxAgeSeconds
        self.redirectLocation = redirectLocation
        self.chunks = chunks
        self.cancel = cancel
    }
}

protocol ContentCoverByteStreaming: Sendable {
    func stream(_ request: ContentCoverTransportRequest) async throws -> ContentCoverByteStream
    func cancelAll() async
}
