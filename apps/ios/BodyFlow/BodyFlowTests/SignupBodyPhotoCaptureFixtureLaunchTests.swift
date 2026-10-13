#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@Suite("Signup body-photo full capture DEBUG launch")
struct SignupBodyPhotoCaptureFixtureLaunchTests {
    private let flag = "--ui-testing-signup-body-photos-capture"

    @Test("Capture flag starts fresh, never preloads a body-fat result")
    func captureFlagIsFresh() {
        for arguments in [[flag], ["--ui-testing", flag]] {
            let config = AppLaunchConfiguration.resolve(arguments: arguments, buildFlavor: .debug)
            #expect(config.mode == .demo)
            #expect(config.usesSignupBodyPhotoCaptureFixture)
            #expect(config.shouldResetDemoState)
            #expect(!config.startsWithCompletedFixture)
            #expect(!config.preloadsSyntheticOnboardingValues)
            #expect(config.signupBodyPhotoScenario == nil)
            #expect(!config.usesOnboardingDeviceDraftFixture)
        }
    }

    @Test("Release and real account configurations strip the capture fixture")
    func captureFlagCannotChangeReleaseOrRealConfiguration() {
        let release = AppLaunchConfiguration.resolve(arguments: ["--ui-testing", flag], buildFlavor: .release)
        #expect(release.mode == .releaseUnavailable)
        #expect(!release.usesSignupBodyPhotoCaptureFixture)
        let real = AppLaunchConfiguration(mode: .releaseUnavailable,
            shouldResetDemoState: false, startsWithCompletedFixture: false,
            preloadsSyntheticOnboardingValues: false,
            authBehavior: .fail(.serviceUnavailable, after: nil),
            usesSignupBodyPhotoCaptureFixture: true)
        #expect(!real.usesSignupBodyPhotoCaptureFixture)
    }

    @Test("A completed or prefilled demo cannot adopt the fresh capture fixture")
    func onlyFreshDemoCanRetainFixture() {
        for values in [(true, false), (false, true), (true, true)] {
            let config = AppLaunchConfiguration(mode: .demo,
                shouldResetDemoState: true, startsWithCompletedFixture: values.0,
                preloadsSyntheticOnboardingValues: values.1, authBehavior: .succeed(after: nil),
                usesSignupBodyPhotoCaptureFixture: true)
            #expect(!config.usesSignupBodyPhotoCaptureFixture)
        }
    }

    @Test("The seven state cases and existing launch precedence remain state only",
          arguments: SignupBodyPhotoPreviewScenario.allCases)
    func stateFixturesRemainUnchanged(_ scenario: SignupBodyPhotoPreviewScenario) {
        for args in [[scenario.launchArgument], [scenario.launchArgument, flag]] {
            let config = AppLaunchConfiguration.resolve(arguments: args, buildFlavor: .debug)
            #expect(config.signupBodyPhotoScenario == scenario)
            #expect(!config.usesSignupBodyPhotoCaptureFixture)
            #expect(!config.preloadsSyntheticOnboardingValues)
        }
        let generic = AppLaunchConfiguration.resolve(arguments: ["--ui-testing"], buildFlavor: .debug)
        #expect(generic.startsWithCompletedFixture && !generic.usesSignupBodyPhotoCaptureFixture)
        let draft = AppLaunchConfiguration.resolve(
            arguments: [AppLaunchConfiguration.onboardingDeviceDraftFixtureArgument, flag], buildFlavor: .debug)
        #expect(draft.usesOnboardingDeviceDraftFixture && !draft.usesSignupBodyPhotoCaptureFixture)
    }
}
#endif
