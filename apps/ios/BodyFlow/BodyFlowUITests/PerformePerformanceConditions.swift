import UIKit
import XCTest

/// Performance setup establishes portrait once before launching the workload.
/// The subsequent condition captures are read-only runner/simulator evidence.
/// These values do not claim to be the target app's window/SwiftUI traits,
/// physical-device power measurements, or continuous samples during a measure.
extension XCTestCase {
    @MainActor
    func beginPerformanceConditionEvidence() {
        // A freshly booted simulator can report .unknown. Establish the
        // common workload orientation through the public API, then verify
        // the actual getter; never substitute a requested value in evidence.
        let device = XCUIDevice.shared
        device.orientation = .portrait
        XCTAssertEqual(device.orientation, .portrait,
                       "Performance setup must establish portrait before capturing conditions")
        let testName = name
        PerformePerformanceConditionSnapshot.capture(testName: testName, phase: "setup")
        addTeardownBlock {
            await MainActor.run {
                PerformePerformanceConditionSnapshot.capture(testName: testName, phase: "teardown")
            }
        }
    }

    @MainActor
    func capturePerformanceConditionEvidence(phase: String, app: XCUIApplication? = nil) {
        PerformePerformanceConditionSnapshot.capture(testName: name, phase: phase, app: app)
    }
}

@MainActor
private enum PerformePerformanceConditionSnapshot {
    static func capture(testName: String, phase: String, app: XCUIApplication? = nil) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let process = ProcessInfo.processInfo
        let device = XCUIDevice.shared
        let voiceOverService: Any
        if #available(iOS 27.0, *) {
            voiceOverService = device.voiceOverService.isEnabled
        } else {
            voiceOverService = NSNull()
        }
        let snapshot: [String: Any] = [
            "schema": "performe.performance.conditions.v1",
            "test": testName,
            "phase": phase,
            "utc": formatter.string(from: Date()),
            "uptimeSeconds": process.systemUptime,
            "scope": "XCTest UI runner in simulator; not BodyFlow window traits",
            "pid": process.processIdentifier,
            "processName": process.processName,
            "simulatorUDID": process.environment["SIMULATOR_UDID"] as Any? ?? NSNull(),
            "runtimeVersion": UIDevice.current.systemVersion,
            "operatingSystemVersion": process.operatingSystemVersionString,
            "observed": [
                "appearance": device.appearance.rawValue,
                "orientation": device.orientation.rawValue,
                "runnerPreferredContentSizeCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
                "reduceMotion": UIAccessibility.isReduceMotionEnabled,
                "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
                "increaseContrast": UIAccessibility.isDarkerSystemColorsEnabled,
                "differentiateWithoutColor": UIAccessibility.shouldDifferentiateWithoutColor,
                "boldText": UIAccessibility.isBoldTextEnabled,
                "voiceOverUIKit": UIAccessibility.isVoiceOverRunning,
                "voiceOverService27": voiceOverService,
                "lowPowerModeRunner": process.isLowPowerModeEnabled,
                "thermalStateRunner": process.thermalState.rawValue,
            ],
            "requestedAppLaunchArguments": app.map { performanceConditionArguments($0.launchArguments) } as Any? ?? NSNull(),
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
            guard let json = String(data: data, encoding: .utf8) else {
                XCTFail("Performance condition snapshot is not valid UTF-8")
                return
            }
            let attachment = XCTAttachment(string: json)
            attachment.name = "performance-conditions-\(phase).json"
            attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "performance-conditions-\(phase)") { activity in
                activity.add(attachment)
            }
            // A compact duplicate permits strict comparison without extracting
            // binary xcresult attachments. No environment dump is emitted.
            print("PERFORME_PERFORMANCE_CONDITION_JSON:\(json)")
        } catch {
            XCTFail("Performance condition snapshot failed: \(error)")
        }
    }

    private static func performanceConditionArguments(_ arguments: [String]) -> [String] {
        let valuedFlags: Set<String> = [
            "-AppleLanguages", "-AppleLocale", "-AppleInterfaceStyle",
            "-UIPreferredContentSizeCategoryName",
        ]
        var captured: [String] = []
        for (index, value) in arguments.enumerated() {
            if value.hasPrefix("--ui-testing") {
                captured.append(value)
            } else if valuedFlags.contains(value) {
                captured.append(value)
                if index + 1 < arguments.count { captured.append(arguments[index + 1]) }
            }
        }
        return captured
    }
}
