//
//  BodyFlowApp.swift
//  BodyFlow
//
//  Created by Eduardo Henrique on 26/07/26.
//

import SwiftUI

@main
struct BodyFlowApp: App {
    private let dependencies = AppDependencies.demo(
        configuration: .current()
    )

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .installAppDependencies(dependencies)
        }
    }
}
