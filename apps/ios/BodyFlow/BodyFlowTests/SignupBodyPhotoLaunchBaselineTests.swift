#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@Suite("Signup photo launch baseline")
struct SignupBodyPhotoLaunchBaselineTests {
    @Test("Read fixture exposes the usable server aggregate")
    func usableReadFixture() async {
        let provider = SignupBodyPhotoPreviewProvider(scenario: .read, mode: .demo, buildFlavor: .debug)
        let state = try? await provider.state()
        #expect(state?.available == true)
        #expect(state?.estimate?.bySex.masculine.bodyFatPercent == 24)
    }

    @Test("Photo flag starts fresh without a prefilled percentage")
    func freshPhotoFlag() {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing", "--ui-testing-signup-body-photos-read"],
            buildFlavor: .debug
        )
        #expect(configuration.mode == .demo)
        #expect(configuration.startsWithCompletedFixture == false)
        #expect(configuration.preloadsSyntheticOnboardingValues == false)
    }
}
#endif
