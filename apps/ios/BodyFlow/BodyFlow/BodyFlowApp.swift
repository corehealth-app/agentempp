//
//  BodyFlowApp.swift
//  BodyFlow
//
//  Created by Eduardo Henrique on 26/07/26.
//

import SwiftUI

@main
@MainActor
struct BodyFlowApp: App {
    private let configuration: AppLaunchConfiguration
    private let dependencies: AppDependencies
    private let mealRecordLifetime: MealRecordAuthenticationLifetime?
    #if DEBUG
    private let c11NavigationFixture: C11RootNavigationFixture?
    #endif
    @State private var model: AppFlowModel

    init() {
        // Before any scene: a tap on a local reminder must reach the app.
        LocalReminderNotificationDelegate.shared.install()
        #if DEBUG
        let navigationFixture: C11RootNavigationFixture?
        if let selection = C11RootNavigationSelection.resolve(arguments: ProcessInfo.processInfo.arguments) {
            do { navigationFixture = try C11RootNavigationFixture.make(selection: selection) }
            catch { preconditionFailure("Synthetic C11 navigation fixture setup failed") }
        } else { navigationFixture = nil }
        self.c11NavigationFixture = navigationFixture
        let configuration = navigationFixture?.configuration ?? AppLaunchConfiguration.current()
        let dependencies: AppDependencies
        if let navigationFixture { dependencies = navigationFixture.dependencies }
        else {
            let runtime = PerformeRuntimeConfiguration.load(
                from: Bundle.main.infoDictionary
            )
            dependencies = AppDependencies.make(
                configuration: configuration,
                mobileAPIConfigurationProvider: runtime.map {
                    StaticMobileAPIConfigurationProvider(
                        configuration: $0.mobileAPI
                    )
                },
                supabaseAuthConfiguration: runtime?.supabase
            )
        }
        #else
        let configuration = AppLaunchConfiguration.current()
        let runtime = PerformeRuntimeConfiguration.load(
            from: Bundle.main.infoDictionary
        )
        let dependencies = AppDependencies.make(
            configuration: configuration,
            mobileAPIConfigurationProvider: runtime.map {
                StaticMobileAPIConfigurationProvider(
                    configuration: $0.mobileAPI
                )
            },
            supabaseAuthConfiguration: runtime?.supabase
        )
        #endif
        let mealRecordLifetime = dependencies.mealRecordBindingSource.map { _ in
            MealRecordAuthenticationLifetime()
        }
        self.mealRecordLifetime = mealRecordLifetime
        self.configuration = configuration
        self.dependencies = dependencies
        _model = State(initialValue: AppFlowModel(
            authentication: dependencies.authentication,
            onboarding: dependencies.onboarding,
            persona: dependencies.coachPersona,
            telemetry: dependencies.telemetry,
            signupBodyPhotoCleanup: dependencies.signupBodyPhotoCleanup,
            mealRecordAuthenticationLifetime: mealRecordLifetime,
            developmentConsentAvailability: configuration.developmentConsentAvailability
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                model: model,
                dependencies: dependencies,
                configuration: configuration,
                mealRecordLifetime: mealRecordLifetime
            )
            #if DEBUG
            .modifier(C11ForegroundRestoreModifier(originalModel: model, fixture: c11NavigationFixture))
            .overlay(alignment: .bottomLeading) {
                if let fixture = c11NavigationFixture {
                    C11RootNavigationDiagnosticView(selection: fixture.selection, probe: fixture.probe)
                }
            }
            #endif
        }
    }
}
