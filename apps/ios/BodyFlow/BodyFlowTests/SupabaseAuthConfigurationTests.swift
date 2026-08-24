import Foundation
import Testing

@testable import BodyFlow

@Suite("Supabase Auth Configuration")
struct SupabaseAuthConfigurationTests {
    @Test("accepts a root HTTPS origin and normalizes its trailing slash")
    func acceptsRootHTTPSOrigin() throws {
        let configuration = try SupabaseAuthConfiguration(
            originString: "https://project.example.test",
            key: "sb_publishable_synthetic"
        )

        #expect(configuration.origin.absoluteString == "https://project.example.test/")
        #expect(configuration.authURL.absoluteString == "https://project.example.test/auth/v1")
    }

    @Test("rejects missing or empty inputs", arguments: [
        (nil, "sb_publishable_synthetic"),
        ("", "sb_publishable_synthetic"),
        ("   ", "sb_publishable_synthetic"),
        ("https://project.example.test", nil),
        ("https://project.example.test", ""),
        ("https://project.example.test", "   "),
    ] as [(String?, String?)])
    func rejectsMissingOrEmptyInputs(origin: String?, key: String?) {
        #expect(throws: SupabaseAuthConfigurationError.self) {
            _ = try SupabaseAuthConfiguration(originString: origin, key: key)
        }
    }

    @Test("rejects non-root or unsafe origins", arguments: [
        "http://project.example.test",
        "https:///",
        "https://member@project.example.test",
        "https://member:password@project.example.test",
        "https://project.example.test?mode=test",
        "https://project.example.test#fragment",
        "https://project.example.test/base",
    ])
    func rejectsUnsafeOrigin(_ origin: String) {
        #expect(throws: SupabaseAuthConfigurationError.invalidOrigin) {
            _ = try SupabaseAuthConfiguration(
                originString: origin,
                key: "sb_publishable_synthetic"
            )
        }
    }

    @Test("accepts a synthetic legacy anon JWT")
    func acceptsLegacyAnonJWT() throws {
        let configuration = try SupabaseAuthConfiguration(
            originString: "https://project.example.test",
            key: syntheticJWT(role: "anon")
        )

        #expect(configuration.origin.host == "project.example.test")
    }

    @Test("rejects privileged and malformed keys", arguments: [
        "sb_secret_synthetic",
        "sb_unknown_synthetic",
        "not-a-jwt",
    ])
    func rejectsPrivilegedOrMalformedKey(_ key: String) {
        #expect(throws: SupabaseAuthConfigurationError.invalidKey) {
            _ = try SupabaseAuthConfiguration(
                originString: "https://project.example.test",
                key: key
            )
        }
    }

    @Test("rejects a synthetic service-role JWT")
    func rejectsServiceRoleJWT() {
        #expect(throws: SupabaseAuthConfigurationError.invalidKey) {
            _ = try SupabaseAuthConfiguration(
                originString: "https://project.example.test",
                key: syntheticJWT(role: "service_role")
            )
        }
    }

    @Test("errors and configuration descriptions do not reveal input values")
    func descriptionsAreRedacted() {
        let secret = "sb_secret_do-not-print"

        do {
            _ = try SupabaseAuthConfiguration(
                originString: "https://sensitive.example.test",
                key: secret
            )
            Issue.record("Expected invalid key")
        } catch {
            #expect(!String(describing: error).contains(secret))
            #expect(!String(reflecting: error).contains(secret))
        }
    }

    @Test("project and lock pin only the Auth product at the authorized revision")
    func packagePinIsExact() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectDirectory = testDirectory.deletingLastPathComponent()
        let project = try String(
            contentsOf: projectDirectory.appending(path: "BodyFlow.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let lock = try String(
            contentsOf: projectDirectory.appending(
                path: "BodyFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            ),
            encoding: .utf8
        )

        #expect(project.contains("https://github.com/supabase/supabase-swift.git"))
        #expect(project.contains("""
			requirement = {
				kind = exactVersion;
				version = 2.55.1;
			};
"""))
        #expect(project.contains("productName = Auth;"))
        #expect(!project.contains("productName = Supabase;"))
        #expect(lock.contains("21d3aaf21ee98f41611f9f75070489fc8b23d882"))
        #expect(lock.contains(#""version" : "2.55.1""#))
    }

    @Test("production auth source contains no forbidden SDK session authority")
    func productionSourceKeepsSDKIsolated() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let source = try String(
            contentsOf: testDirectory.deletingLastPathComponent().appending(
                path: "BodyFlow/Core/Auth/SupabaseAuthService.swift"
            ),
            encoding: .utf8
        )
        let forbidden = [
            "import Supabase", "SupabaseClient", "authStateChanges",
            "refreshSession(", "startAutoRefresh(", "stopAutoRefresh(",
            "currentSession", "setSession(", "defaultLocalStorage",
            "KeychainLocalStorage",
        ]

        for symbol in forbidden {
            #expect(!source.contains(symbol))
        }
    }
}

private func syntheticJWT(role: String) -> String {
    let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8).base64URLEncoded
    let payload = Data(#"{"iss":"fixture.invalid","sub":"00000000-0000-4000-8000-000000000001","role":"\#(role)"}"#.utf8).base64URLEncoded
    return "\(header).\(payload).synthetic"
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
