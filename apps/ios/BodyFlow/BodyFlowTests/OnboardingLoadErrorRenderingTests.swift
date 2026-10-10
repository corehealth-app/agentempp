import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// The screen shown when the sign-up of the signed-in account cannot be
/// loaded. Reported on 2026-10-10 11:55: an account that administers the
/// team's panel landed here with only "Tentar novamente", forever.
///
/// What is probed is the screen's content (`OnboardingLoadErrorContent`),
/// without the scroll view the screen wraps it in: the in-process
/// accessibility probe does not see inside a SwiftUI `ScrollView` (it came
/// back empty for the wrapped screen). Reaching both actions by scrolling at
/// the largest text size is proven by `OnboardingEligibilityUITests`.
@MainActor
final class OnboardingLoadErrorRenderingTests: XCTestCase {
    private struct Wording {
        let locale: Locale
        let teamTitle: String
        let teamMessage: String
        let title: String
        let message: String
        let retry: String
        let signOut: String
    }

    private let wordings = [
        Wording(
            locale: Locale(identifier: "pt-BR"),
            teamTitle: "Use outro e-mail no app",
            teamMessage: "Este e-mail é do painel da equipe. O app precisa de um e-mail diferente. "
                + "Saia desta conta e entre com outro e-mail.",
            title: "Não foi possível carregar",
            message: "Tente novamente para continuar seu cadastro.",
            retry: "Tentar novamente",
            signOut: "Sair da conta"
        ),
        Wording(
            locale: Locale(identifier: "en"),
            teamTitle: "Use a different email in the app",
            teamMessage: "This email belongs to the team's panel. The app needs a different email. "
                + "Sign out of this account and sign in with another email.",
            title: "Could not load",
            message: "Try again to continue your setup.",
            retry: "Try again",
            signOut: "Sign out"
        ),
    ]

    func testTeamPanelAccountShowsThePlainMessageAndOnlySignOut() throws {
        for wording in wordings {
            let probes = probe(.teamPanelAccount, locale: wording.locale, width: 393, size: .large)
            let signOut = try XCTUnwrap(
                probes.first { $0.isButton && $0.label == wording.signOut },
                "A team-panel account needs a way out: \(probes)"
            )
            XCTAssertTrue(signOut.isEnabled)
            XCTAssertEqual(probes.filter { $0.isButton && $0.label == wording.signOut }.count, 1)
            XCTAssertTrue(probes.contains { $0.label == wording.teamTitle }, "\(probes)")
            XCTAssertTrue(probes.contains { $0.label == wording.teamMessage }, "\(probes)")
            // Trying again cannot change which account this is.
            XCTAssertFalse(probes.contains { $0.isButton && $0.label == wording.retry }, "\(probes)")
            XCTAssertFalse(probes.contains { $0.label == wording.message }, "\(probes)")
            assertNoInternalNames(probes)
        }
    }

    func testOtherFailuresKeepTheirMessageAndGainSignOut() throws {
        for wording in wordings {
            let probes = probe(.temporary, locale: wording.locale, width: 393, size: .large)
            // Locks: today's words and today's action stay.
            XCTAssertTrue(probes.contains { $0.label == wording.title }, "\(probes)")
            XCTAssertTrue(probes.contains { $0.label == wording.message }, "\(probes)")
            let retry = try XCTUnwrap(
                probes.first { $0.isButton && $0.label == wording.retry }, "\(probes)"
            )
            XCTAssertTrue(retry.isEnabled)
            assertNoInternalNames(probes)
            // New: the same way out.
            let signOut = try XCTUnwrap(
                probes.first { $0.isButton && $0.label == wording.signOut },
                "Every load failure needs a way out: \(probes)"
            )
            XCTAssertTrue(signOut.isEnabled)
            XCTAssertFalse(probes.contains { $0.label == wording.teamMessage }, "\(probes)")
        }
    }

    func testEveryElementStaysInsideTheScreenAtTheLargestTextSize() throws {
        for wording in wordings {
            for width: CGFloat in [375, 393, 430] {
                // Locks first (they hold on today's screen too).
                let temporary = probe(.temporary, locale: wording.locale, width: width, size: .accessibility5)
                assertContained(temporary, width: width)
                XCTAssertTrue(temporary.contains { $0.label == wording.message }, "\(temporary)")
                let retry = try XCTUnwrap(
                    temporary.first { $0.isButton && $0.label == wording.retry }, "\(temporary)"
                )
                assertMinimumTarget(retry)

                // New: the way out is a full target in both failures.
                let temporarySignOut = try XCTUnwrap(
                    temporary.first { $0.isButton && $0.label == wording.signOut },
                    "No way out at the largest text size: \(temporary)"
                )
                assertMinimumTarget(temporarySignOut)

                let team = probe(.teamPanelAccount, locale: wording.locale, width: width, size: .accessibility5)
                assertContained(team, width: width)
                XCTAssertTrue(team.contains { $0.label == wording.teamMessage }, "\(team)")
                let teamSignOut = try XCTUnwrap(
                    team.first { $0.isButton && $0.label == wording.signOut }, "\(team)"
                )
                assertMinimumTarget(teamSignOut)
            }
        }
    }

    // MARK: Support

    private func probe(
        _ failure: OnboardingLoadFailure,
        locale: Locale,
        width: CGFloat,
        size: DynamicTypeSize
    ) -> [PremiumRenderingTestSupport.AccessibilityProbe] {
        PremiumRenderingTestSupport.accessibilityProbe(
            OnboardingLoadErrorContent(failure: failure, retry: {}, signOut: {})
                .environment(\.locale, locale),
            width: width,
            size: size
        )
    }

    private func assertContained(
        _ probes: [PremiumRenderingTestSupport.AccessibilityProbe],
        width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(probes.isEmpty, "Nothing was rendered", file: file, line: line)
        for element in probes {
            XCTAssertGreaterThanOrEqual(element.frame.minX, -0.5, "\(element)", file: file, line: line)
            XCTAssertLessThanOrEqual(element.frame.maxX, width + 0.5, "\(element)", file: file, line: line)
        }
    }

    private func assertMinimumTarget(
        _ element: PremiumRenderingTestSupport.AccessibilityProbe,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(element.frame.width, BodyFlowSpacing.minimumTapTarget,
                                    "\(element)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, BodyFlowSpacing.minimumTapTarget,
                                    "\(element)", file: file, line: line)
    }

    private func assertNoInternalNames(
        _ probes: [PremiumRenderingTestSupport.AccessibilityProbe],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for element in probes {
            for forbidden in ["MPP", "BodyFlow", "admin", "403", "patient_admin_account_conflict"] {
                XCTAssertFalse(
                    element.label.localizedCaseInsensitiveContains(forbidden),
                    "\(forbidden) in \(element.label)", file: file, line: line
                )
            }
        }
    }
}
