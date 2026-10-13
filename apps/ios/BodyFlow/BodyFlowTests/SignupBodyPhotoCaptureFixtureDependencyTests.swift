#if DEBUG
import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

@Suite("Signup photo capture fixture dependency boundary", .serialized)
struct SignupBodyPhotoCaptureFixtureDependencyTests {
    @Test("Both DEBUG consent documents preserve the exact approved bytes",
          arguments: ["pt-BR", "en-US"])
    func exactApprovedConsent(locale: String) throws {
        let document = try #require(SignupBodyPhotoCaptureFixtureConsent.document(for: locale))
        let expectedHash = locale == "pt-BR"
            ? "e45e4a38adbeab144430a9fd33df59d1754ecf154c7871d358cb0ad17762210d"
            : "a72cad69b3040007c81b38ab56b1b22bfc9b45c56a966e91b29bcaf45484b9e2"
        #expect(document.bodyHash == expectedHash)
        #expect(document.locale == locale && document.acceptedAt == nil)
        #expect(SignupBodyPhotoCaptureFixtureConsent.document(for: "unsupported") == nil)
    }

    @Test("Only the fresh capture launch supplies a synthetic empty photo scope")
    func freshCaptureDIHasExactConsentAndNoPreloadedResult() async throws {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing-signup-body-photos-capture"], buildFlavor: .debug)
        let dependencies = AppDependencies.make(configuration: configuration)
        let capability = try #require(dependencies.signupBodyPhotoCapture)
        #expect(dependencies.signupBodyPhotoCleanup == nil)
        let scope = try await capability.scoped(DemoUser.id)
        #expect(scope.camera.origin == .synthetic)
        let state = try await scope.photos.state()
        #expect(state.poses.count == 3 && state.poses.allSatisfy { $0.photo == nil })
        #expect(state.estimate == nil)
        let document = try #require(state.consent)
        #expect(document.documentKey == "body_photo_estimate_consent")
        #expect(document.acceptedAt == nil)
        let hashes = [
            "pt-BR": "e45e4a38adbeab144430a9fd33df59d1754ecf154c7871d358cb0ad17762210d",
            "en-US": "a72cad69b3040007c81b38ab56b1b22bfc9b45c56a966e91b29bcaf45484b9e2",
        ]
        #expect(document.bodyHash == hashes[document.locale])
        #expect(document.bodyHash == SHA256.hash(data: Data(document.body.utf8))
            .map { String(format: "%02x", $0) }.joined())
        await #expect(throws: SignupBodyPhotoFailure.sessionChanged) {
            try await capability.scoped("other-synthetic-owner")
        }
    }

    @Test("Generic, state-only and Release launches never adopt the capture fixture")
    func otherLaunchesStayUnavailable() {
        for configuration in [
            AppLaunchConfiguration.resolve(arguments: ["--ui-testing"], buildFlavor: .debug),
            AppLaunchConfiguration.resolve(arguments: ["--ui-testing-signup-body-photos-read"], buildFlavor: .debug),
            AppLaunchConfiguration.resolve(arguments: ["--ui-testing-signup-body-photos-capture"], buildFlavor: .release),
        ] {
            #expect(!configuration.usesSignupBodyPhotoCaptureFixture)
            #expect(AppDependencies.make(configuration: configuration).signupBodyPhotoCapture == nil)
        }
    }
}
#endif
