import Foundation
import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

@MainActor
@Suite("Workout session composition")
struct WorkoutRegistrationSessionCompositionTests {
    @Test("the real workout sheet has no submit control before its original context is ready",
          arguments: [false, true])
    func scopeBeforeReadyControlsTheActualSheet(demo: Bool) throws {
        let dependencies = try demo ? AppDependencies.scaffold() : Self.liveDependencies()
        let sheet = RegistrationSheet(sheet: .registration(.training), dependencies: dependencies,
            invalidationCenter: FeatureInvalidationCenter())
        try RealAccountSampleDataTests.hosted(sheet.environment(AppRouter()), height: 1100) { root in
            var submit: UIButton?
            func collect(_ view: UIView) {
                if let button = view as? UIButton,
                   button.accessibilityIdentifier == "registration.workout.propose" { submit = button }
                view.subviews.forEach(collect)
            }
            collect(root)
            #expect((submit != nil) == demo)
        }
    }

    @Test("a real account without its original ready context cannot construct a workout model")
    func realSheetCannotBorrowTheGlobalProvider() throws {
        let dependencies = try Self.liveDependencies()
        #expect(dependencies.presentsRealAccountIdentity)
        #expect(!(dependencies.registration is UnavailableBodyFlowCapabilities))
        let model = WorkoutRegistrationSheetModelFactory.make(
            dependencies: dependencies, context: nil,
            invalidationCenter: FeatureInvalidationCenter())
        #expect(model == nil)
        #expect(dependencies.workoutRegistrationSessionSource != nil)
        // The shared authentication ticket does not enable meal editing.
        #expect(dependencies.mealRecordBindingSource == nil)
    }

    @Test("the local demonstration can construct its legacy workout without an authenticated scope")
    func demoDoesNotRequireARemoteAnnouncement() {
        let dependencies = AppDependencies.scaffold()
        let model = WorkoutRegistrationSheetModelFactory.make(
            dependencies: dependencies, context: nil,
            invalidationCenter: FeatureInvalidationCenter())
        #expect(model != nil)
        #expect(dependencies.workoutRegistrationSessionSource == nil)
    }

    private static func liveDependencies() throws -> AppDependencies {
        AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: try MobileAPIConfiguration(originString: "https://mobile.example.test")),
            supabaseAuthConfiguration: try SupabaseAuthConfiguration(
                originString: "https://project.example.test", key: "sb_publishable_synthetic"),
            authenticationSessionStore: AuthenticationSessionStore(secureStore: InMemorySecureStore()),
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) })
    }
}
