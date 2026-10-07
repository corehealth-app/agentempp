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
    @State private var model: AppFlowModel

    init() {
        // Before any scene: a tap on a local reminder must reach the app.
        LocalReminderNotificationDelegate.shared.install()
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
        self.configuration = configuration
        self.dependencies = dependencies
        _model = State(initialValue: AppFlowModel(
            authentication: dependencies.authentication,
            onboarding: dependencies.onboarding,
            persona: dependencies.coachPersona,
            telemetry: dependencies.telemetry,
            developmentConsentAvailability: configuration.developmentConsentAvailability
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                model: model,
                dependencies: dependencies,
                configuration: configuration
            )
        }
    }
}
