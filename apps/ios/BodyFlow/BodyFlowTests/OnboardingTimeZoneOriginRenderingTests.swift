import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// P-TIMEZONE. Reported by the physician on build 1.0 (3), 2026-10-10
/// 18:54–18:55: "Ele já colocou aqui o fuso dos eua" / "Não se se ele pegou
/// pela minha localização". Nothing was wrong with the value — the sign-up
/// starts from the phone's own clock setting — but nothing on the screen
/// said where it came from, nor that it can be changed.
@MainActor
final class OnboardingTimeZoneOriginRenderingTests: XCTestCase {
    private static let originIdentifier = "onboarding.timezone.origin"
    private static let zoneIdentifier = "onboarding.timezone"

    private func line(_ language: SupportedAppLanguage) -> String {
        language == .portugueseBrazil
            ? "O app começa com o fuso do relógio do seu aparelho. Não usa a sua localização. Toque para trocar."
            : "The app starts with the time zone of your device's clock. It does not use your location. Tap to change."
    }

    /// His scenario: the first step opened with a United States time zone.
    private func welcomeModel(issues: [OnboardingValidationIssue] = []) -> OnboardingFlowModel {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome)
        draft.countryCode = "US"
        draft.timeZoneIdentifier = "America/New_York"
        return OnboardingFlowModel(
            userID: "qa-a", initialDraft: draft,
            repository: E3Repository(), personaRepository: E3Persona(),
            developmentConsentAvailability: .unavailable,
            onStepChanged: { _ in }, onCompleted: {},
            initialValidationIssues: issues
        )
    }

    private func welcome(
        _ model: OnboardingFlowModel, _ language: SupportedAppLanguage
    ) -> some View {
        NavigationStack { WelcomeStepView(model: model) }
            .environment(\.locale, language.formattingLocale)
    }

    private func zoneControl(
        _ nodes: [SignUpRenderingProbe.Node], _ context: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> SignUpRenderingProbe.Node {
        try XCTUnwrap(
            nodes.first { $0.identifier == Self.zoneIdentifier && $0.isButton },
            "\(context): the time zone control is not drawn: \(nodes)", file: file, line: line
        )
    }

    func testTheFirstStepSaysWhereTheTimeZoneComesFromRightUnderIt() throws {
        for language in SupportedAppLanguage.allCases {
            let context = "\(language)"
            let nodes = SignUpRenderingProbe.nodes(
                welcome(welcomeModel(), language), width: 393, height: 2_400
            )
            let zone = try zoneControl(nodes, context)
            XCTAssertTrue(
                zone.label.contains(language == .portugueseBrazil ? "Nova York" : "New York"),
                "\(context): \(zone)"
            )
            let origins = nodes.filter { $0.identifier == Self.originIdentifier }
            XCTAssertEqual(
                origins.count, 1,
                "\(context): one line under the time zone must say where it comes from. Drawn: \(nodes)"
            )
            guard let origin = origins.first else { continue }
            XCTAssertEqual(origin.label, line(language), context)
            XCTAssertFalse(origin.isButton, context)
            XCTAssertGreaterThanOrEqual(
                origin.frame.minY, zone.frame.maxY - 0.5,
                "\(context): the line sits under the time zone (\(origin) / \(zone))"
            )
            XCTAssertLessThanOrEqual(
                origin.frame.minY - zone.frame.maxY, BodyFlowSpacing.lg,
                "\(context): the line belongs to the time zone, not to what comes after it"
            )
            // Whoever does not see the line hears it on the control itself.
            XCTAssertEqual(zone.hint, line(language), context)
        }
    }

    /// An invalid time zone keeps saying its error, and the origin with it.
    func testAnInvalidTimeZoneSaysItsErrorAndStillWhereTheValueComesFrom() throws {
        let language = SupportedAppLanguage.portugueseBrazil
        let nodes = SignUpRenderingProbe.nodes(
            welcome(welcomeModel(issues: [.timeZoneInvalid]), language), width: 393, height: 2_400
        )
        let zone = try zoneControl(nodes, "invalid time zone")
        XCTAssertFalse(zone.hint.isEmpty, "The control must say its error")
        XCTAssertTrue(
            zone.hint.hasSuffix(line(language)),
            "The hint must keep the origin after the error: «\(zone.hint)»"
        )
        XCTAssertGreaterThan(zone.hint.count, line(language).count, "The error must still be said: «\(zone.hint)»")
    }

    /// pt-BR and en × 375/393/430 × default and the largest text size: the
    /// line never leaves the width, is never cut, and grows with the text.
    func testTheLineFitsTheWidthAndGrowsWithTheText() throws {
        for language in SupportedAppLanguage.allCases {
            for width: CGFloat in [375, 393, 430] {
                var heights: [DynamicTypeSize: CGFloat] = [:]
                for size in [DynamicTypeSize.large, .accessibility5] {
                    let context = "\(language) / \(Int(width)) / \(size)"
                    let nodes = SignUpRenderingProbe.nodes(
                        welcome(welcomeModel(), language), width: width, height: 6_000, size: size
                    )
                    let origin = try XCTUnwrap(
                        nodes.first { $0.identifier == Self.originIdentifier },
                        "\(context): no line under the time zone. Drawn: \(nodes)"
                    )
                    XCTAssertEqual(origin.label, line(language), context)
                    XCTAssertGreaterThanOrEqual(origin.frame.minX, -0.5, context)
                    XCTAssertLessThanOrEqual(origin.frame.maxX, width + 0.5, context)
                    heights[size] = origin.frame.height
                }
                let regular = try XCTUnwrap(heights[.large])
                let largest = try XCTUnwrap(heights[.accessibility5])
                XCTAssertGreaterThan(largest, regular, "\(language) / \(Int(width))")
            }
        }
    }

    // MARK: The sentence is true

    /// "O app começa com o fuso do relógio do seu aparelho": the sign-up of
    /// a real account starts from the system's current time zone.
    func testTheSignUpStartsFromThePhonesOwnClockSetting() {
        XCTAssertEqual(OnboardingDraft.currentDeviceWelcome.timeZoneIdentifier, TimeZone.current.identifier)
    }

    /// "Não usa a sua localização": no file of the app reaches for the
    /// location, and the project declares no location permission.
    func testNothingInTheAppReadsTheLocation() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let sources = projectRoot.appendingPathComponent("BodyFlow", isDirectory: true)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil
        ))
        var read = 0
        var offenders: [String] = []
        for case let url as URL in enumerator
        where ["swift", "plist", "entitlements"].contains(url.pathExtension) {
            let text = try String(contentsOf: url, encoding: .utf8)
            read += 1
            for needle in ["CoreLocation", "CLLocation", "CLGeocoder", "NSLocation"] where text.contains(needle) {
                offenders.append("\(url.lastPathComponent): \(needle)")
            }
        }
        XCTAssertGreaterThan(read, 100, "The app's sources were not found at \(sources.path)")
        let project = try String(
            contentsOf: projectRoot.appendingPathComponent("BodyFlow.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        for needle in ["NSLocation", "CoreLocation"] where project.contains(needle) {
            offenders.append("project.pbxproj: \(needle)")
        }
        XCTAssertEqual(offenders, [], "The line under the time zone would not be true")
    }
}
