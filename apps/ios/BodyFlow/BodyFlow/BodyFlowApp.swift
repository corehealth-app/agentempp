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
        let configuration = AppLaunchConfiguration.current()
        let dependencies = AppDependencies.demo(configuration: configuration)
        self.configuration = configuration
        self.dependencies = dependencies
        _model = State(initialValue: AppFlowModel(
            authentication: dependencies.authentication,
            onboarding: dependencies.onboarding,
            persona: dependencies.coachPersona,
            telemetry: dependencies.telemetry
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
