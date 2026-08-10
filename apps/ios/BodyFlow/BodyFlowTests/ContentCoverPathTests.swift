import Foundation
import Testing

@testable import BodyFlow

@Suite("Content Cover Capabilities")
struct ContentCoverPathTests {
    @Test("only the exact relative capability path is accepted")
    func acceptsOnlyExactRelativeCapabilityPath() throws {
        let path = try ContentCoverPath(
            validating: "/api/mobile/v1/content/covers/AbC_123-xyz"
        )

        #expect(path.rawValue == "/api/mobile/v1/content/covers/AbC_123-xyz")
        #expect(Set([path, path]).count == 1)
    }

    @Test("every malformed raw value fails before the transport boundary")
    func rejectsMalformedRawValuesBeforeTransport() async throws {
        let origin = try ContentCoverTrustedOrigin(
            validating: trustedOriginURL("https://covers.bodyflow.example")
        )
        let resolver = ContentCoverRequestResolver(trustedOrigin: origin)
        let transport = RecordingCoverTransport()

        for rawValue in InvalidCoverPath.all {
            await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
                try await streamCover(rawValue, resolver: resolver, transport: transport)
            }
        }

        #expect(await transport.callCount == 0)
    }

    @Test("trusted origins accept HTTPS origin forms with the effective default port")
    func acceptsTrustedHTTPSOrigins() throws {
        let implicitPort = try ContentCoverTrustedOrigin(
            validating: trustedOriginURL("https://covers.bodyflow.example")
        )
        let explicitPort = try ContentCoverTrustedOrigin(
            validating: trustedOriginURL("https://covers.bodyflow.example:443")
        )

        #expect(implicitPort.url.scheme?.lowercased() == "https")
        #expect(implicitPort.url.host?.lowercased() == "covers.bodyflow.example")
        #expect(effectivePort(of: implicitPort.url) == 443)
        #expect(effectivePort(of: explicitPort.url) == 443)
        #expect(Set([implicitPort, implicitPort]).count == 1)
    }

    @Test("trusted origins reject anything other than a pure HTTPS origin")
    func rejectsUntrustedOriginForms() throws {
        for rawValue in InvalidTrustedOrigin.all {
            let url = try #require(URL(string: rawValue))
            #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
                try ContentCoverTrustedOrigin(validating: url)
            }
        }
    }

    @Test("trusted origins reject explicit invalid port delimiters and ranges")
    func rejectsInvalidExplicitPorts() throws {
        for rawValue in InvalidExplicitPort.all {
            let url = try #require(URL(string: rawValue))

            #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
                try ContentCoverTrustedOrigin(validating: url)
            }
        }
    }

    @Test("resolver creates a same-origin request from a validated path")
    func resolverCreatesSameOriginRequest() throws {
        let origin = try ContentCoverTrustedOrigin(
            validating: trustedOriginURL("https://COVERS.bodyflow.example:443")
        )
        let resolver = ContentCoverRequestResolver(trustedOrigin: origin)
        let path = try ContentCoverPath(
            validating: "/api/mobile/v1/content/covers/AbC_123-xyz"
        )

        let request = try resolver.resolve(path)

        #expect(request.path.rawValue == path.rawValue)
        #expect(request.url.scheme?.lowercased() == "https")
        #expect(request.url.host?.lowercased() == "covers.bodyflow.example")
        #expect(effectivePort(of: request.url) == 443)
        #expect(request.url.path == "/api/mobile/v1/content/covers/AbC_123-xyz")
        let repeatedRequest = try resolver.resolve(path)
        #expect(request == repeatedRequest)
    }

    @Test("resolver preserves an explicit non-default trusted port")
    func resolverRechecksExplicitTrustedPort() throws {
        let origin = try ContentCoverTrustedOrigin(
            validating: trustedOriginURL("https://covers.bodyflow.example:8443")
        )
        let resolver = ContentCoverRequestResolver(trustedOrigin: origin)
        let path = try ContentCoverPath(
            validating: "/api/mobile/v1/content/covers/AbC_123-xyz"
        )

        let request = try resolver.resolve(path)

        #expect(effectivePort(of: request.url) == 8443)
        #expect(request.url.host?.lowercased() == origin.url.host?.lowercased())
    }

    @Test("capability values never appear in descriptions")
    func redactsCapabilityDescriptions() throws {
        let path = try ContentCoverPath(
            validating: "/api/mobile/v1/content/covers/AbC_123-xyz"
        )
        let resolver = ContentCoverRequestResolver(
            trustedOrigin: try ContentCoverTrustedOrigin(
                validating: trustedOriginURL("https://covers.bodyflow.example")
            )
        )
        let request = try resolver.resolve(path)
        let token = "AbC_123-xyz"
        let url = request.url.absoluteString

        for value in [
            String(describing: path),
            String(reflecting: path),
            String(describing: request),
            String(reflecting: request),
        ] {
            #expect(!value.contains(token))
            #expect(!value.contains(url))
        }
    }
}

private func streamCover(
    _ rawValue: String,
    resolver: ContentCoverRequestResolver,
    transport: some ContentCoverByteStreaming
) async throws {
    let path = try ContentCoverPath(validating: rawValue)
    let request = try resolver.resolve(path)
    _ = try await transport.stream(request)
}

private actor RecordingCoverTransport: ContentCoverByteStreaming {
    private(set) var callCount = 0

    func stream(_ request: ContentCoverTransportRequest) async throws -> ContentCoverByteStream {
        callCount += 1
        return ContentCoverByteStream(
            statusCode: 200,
            declaredLength: nil,
            mimeType: nil,
            cacheMaxAgeSeconds: nil,
            redirectLocation: nil,
            chunks: AsyncThrowingStream { continuation in
                continuation.finish()
            },
            cancel: {}
        )
    }

    func cancelAll() async {}
}

private func effectivePort(of url: URL) -> Int? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return nil
    }
    return components.port ?? (components.scheme?.lowercased() == "https" ? 443 : nil)
}

private func trustedOriginURL(_ rawValue: String) -> URL {
    URL(string: rawValue)!
}

private enum InvalidCoverPath {
    static let all = [
        "/api/mobile/v1/content/covers/",
        "https://covers.bodyflow.example/api/mobile/v1/content/covers/AbC_123-xyz",
        "https://covers.bodyflow.example:443/api/mobile/v1/content/covers/AbC_123-xyz",
        "//covers.bodyflow.example/api/mobile/v1/content/covers/AbC_123-xyz",
        "http:/api/mobile/v1/content/covers/AbC_123-xyz",
        "https:/api/mobile/v1/content/covers/AbC_123-xyz",
        "covers.bodyflow.example/api/mobile/v1/content/covers/AbC_123-xyz",
        "user@covers.bodyflow.example/api/mobile/v1/content/covers/AbC_123-xyz",
        "https://user:password@covers.bodyflow.example/api/mobile/v1/content/covers/AbC_123-xyz",
        "/api/mobile/v1/content/covers/AbC_123-xyz:443",
        "/api/mobile/v1/content/covers/AbC_123-xyz?size=large",
        "/api/mobile/v1/content/covers/AbC_123-xyz#fragment",
        "/api/mobile/v1/content/covers/AbC%5F123-xyz",
        "/api/mobile/v1/content/covers/AbC\\123-xyz",
        "/api/mobile/v1/content/covers/AbC_123-xyz/extra",
        "/api/mobile/v1/content/covers/./AbC_123-xyz",
        "/api/mobile/v1/content/covers/../AbC_123-xyz",
        "/api/mobile/v1/content/covers/AbC_123-xyz/..",
        "/api/mobile/v1/content/covers/AbC_123-xyz/.",
        "https://external.example/api/mobile/v1/content/covers/AbC_123-xyz",
        "/api/mobile/v1/content/covers/AbC 123-xyz",
        "/api/mobile/v1/content/covers/AbCé123-xyz",
    ]
}

private enum InvalidTrustedOrigin {
    static let all = [
        "http://covers.bodyflow.example",
        "https://user@covers.bodyflow.example",
        "https://user:password@covers.bodyflow.example",
        "https://covers.bodyflow.example?size=large",
        "https://covers.bodyflow.example#fragment",
        "https://covers.bodyflow.example/api/mobile/v1",
        "https:/",
    ]
}

private enum InvalidExplicitPort {
    static let all = [
        "https://covers.bodyflow.example:",
        "https://covers.bodyflow.example:0",
        "https://covers.bodyflow.example:000",
        "https://covers.bodyflow.example:65536",
    ]
}
