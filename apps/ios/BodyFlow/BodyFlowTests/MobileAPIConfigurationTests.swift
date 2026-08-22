import Foundation
import Testing

@testable import BodyFlow

@Suite("Mobile API Configuration")
struct MobileAPIConfigurationTests {
    @Test("accepts exactly one absolute HTTPS origin")
    func acceptsHTTPSOrigin() throws {
        let configuration = try MobileAPIConfiguration(
            originString: "https://staging.example.test"
        )

        #expect(configuration.origin.absoluteString == "https://staging.example.test/")
    }

    @Test("same-origin compares the effective HTTPS port")
    func comparesEffectiveHTTPSPort() throws {
        let implicitHTTPS = try MobileAPIConfiguration(
            originString: "https://staging.example.test"
        )
        let explicitHTTPS = try MobileAPIConfiguration(
            originString: "https://staging.example.test:443"
        )

        #expect(implicitHTTPS.approves(
            URL(string: "https://staging.example.test:443/api/mobile/v1/today")!
        ))
        #expect(explicitHTTPS.approves(
            URL(string: "https://staging.example.test/api/mobile/v1/today")!
        ))
        #expect(!implicitHTTPS.approves(
            URL(string: "https://staging.example.test:8443/api/mobile/v1/today")!
        ))
    }

    @Test("rejects a missing or empty origin", arguments: [nil, "", "   "])
    func rejectsMissingOrigin(_ origin: String?) {
        #expect(throws: MobileAPIConfigurationError.self) {
            try MobileAPIConfiguration(originString: origin)
        }
    }

    @Test(
        "rejects malformed or non-HTTPS origins",
        arguments: [
            "not a URL",
            "http://staging.example.test",
            "https://",
        ]
    )
    func rejectsMalformedOrigin(_ origin: String) {
        #expect(throws: MobileAPIConfigurationError.self) {
            try MobileAPIConfiguration(originString: origin)
        }
    }

    @Test(
        "rejects authority decorations and non-root components",
        arguments: [
            "https://user:password@staging.example.test",
            "https://staging.example.test?source=test",
            "https://staging.example.test#fragment",
            "https://staging.example.test/api",
        ]
    )
    func rejectsDecoratedOrigin(_ origin: String) {
        #expect(throws: MobileAPIConfigurationError.self) {
            try MobileAPIConfiguration(originString: origin)
        }
    }

    @Test("builds an API URL only from a validated relative path and structured query")
    func buildsStructuredRequestURL() throws {
        let configuration = try MobileAPIConfiguration(
            originString: "https://staging.example.test"
        )
        let request = try MobileAPIRequest<TestPayload>(
            method: .get,
            path: "/api/mobile/v1/content",
            queryItems: [
                URLQueryItem(name: "surface", value: "library"),
                URLQueryItem(name: "limit", value: "20"),
            ]
        )

        #expect(
            try request.url(using: configuration).absoluteString
                == "https://staging.example.test/api/mobile/v1/content?surface=library&limit=20"
        )
    }

    @Test(
        "rejects absolute network and payload-derived hosts",
        arguments: [
            "https://other.example.test/api/mobile/v1/today",
            "//other.example.test/api/mobile/v1/today",
            "other.example.test/api/mobile/v1/today",
        ]
    )
    func rejectsCallerSuppliedHost(_ path: String) {
        #expect(throws: MobileAPIRequestError.self) {
            try MobileAPIRequest<TestPayload>(method: .get, path: path)
        }
    }

    @Test(
        "rejects paths outside the Mobile API namespace",
        arguments: [
            "/today",
            "/api/mobile/v1/../admin",
            "/api/mobile/v1/%2e%2e/admin",
            "/api/mobile/v1/%2E%2E%2Fadmin",
            "/api/mobile/v1/today?host=other.example.test",
            "/api/mobile/v1/today#fragment",
            "/api/mobile/v1\\today",
        ]
    )
    func rejectsEscapingPath(_ path: String) {
        #expect(throws: MobileAPIRequestError.self) {
            try MobileAPIRequest<TestPayload>(method: .get, path: path)
        }
    }

    @Test("rejects raw host and authorization query controls")
    func rejectsReservedQueryControls() {
        for name in ["host", "Authorization"] {
            #expect(throws: MobileAPIRequestError.self) {
                try MobileAPIRequest<TestPayload>(
                    method: .get,
                    path: "/api/mobile/v1/today",
                    queryItems: [URLQueryItem(name: name, value: "untrusted")]
                )
            }
        }
    }
}

private struct TestPayload: Codable, Equatable, Sendable {
    let value: String
}
