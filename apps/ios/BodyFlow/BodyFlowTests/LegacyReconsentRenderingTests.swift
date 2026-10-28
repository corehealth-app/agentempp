import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class LegacyReconsentRenderingTests: XCTestCase {
    func testOfficialTextsActionsAndWayOutInBothLanguagesWithoutSignupFields() throws {
        for locale in ["pt-BR", "en-US"] {
            let state = try LegacyDocumentsFixtures.state(locale: locale)
            let model = LegacyReconsentModel(ownerToken: .init(userID: "auth-A", restoreGeneration: 1),
                presentation: try .init(state: state), repository: UnavailableOnboardingRepository(),
                isCurrentOwner: { _ in true }, onReconcile: {})
            let view = LegacyReconsentContent(model: model, signOut: {})
                .environment(\.locale, Locale(identifier: locale))
            let probes = PremiumRenderingTestSupport.accessibilityProbe(view, width: 393, size: .large)
            // SwiftUI accessibility elements expose identifiers through their
            // selector, without conforming to UIAccessibilityIdentification.
            // Use the existing selector-based tree for identity assertions;
            // keep the native probes for enabled state and target geometry.
            let tree = RealAccountSampleDataTests.accessibilityTree(view, height: 2_400)
            XCTAssertFalse(probes.isEmpty)
            for document in state.requirements.documents {
                XCTAssertTrue(probes.contains { $0.label.contains(document.body!) }, "Missing official text: \(probes)")
                XCTAssertTrue(tree.identifiers.contains(OnboardingConsentAccessibilityID.officialAction(document.documentKey)))
                let labels: [OnboardingLegalAction: String] = locale == "pt-BR"
                    ? [.acceptance: "Aceitar", .acknowledgement: "Confirmar ciência", .consent: "Consentir"]
                    : [.acceptance: "Accept", .acknowledgement: "Acknowledge", .consent: "Consent"]
                let action = try XCTUnwrap(probes.first {
                    $0.isButton && $0.label == labels[document.action]
                }, "Missing action: \(probes)")
                XCTAssertTrue(action.isButton && action.isEnabled)
                XCTAssertGreaterThanOrEqual(action.frame.height, BodyFlowSpacing.minimumTapTarget)
            }
            XCTAssertTrue(tree.identifiers.contains("onboarding.legacy.continue"))
            let confirm = try XCTUnwrap(probes.first { $0.isButton && $0.label == (locale == "pt-BR" ? "Continuar" : "Continue") })
            XCTAssertFalse(confirm.isEnabled)
            XCTAssertEqual(confirm.label, locale == "pt-BR" ? "Continuar" : "Continue")
            XCTAssertTrue(probes.contains { $0.isButton && $0.label == (locale == "pt-BR" ? "Sair da conta" : "Sign out") })
            XCTAssertTrue(PremiumRenderingTestSupport.nativeFields(view, width: 393, size: .large).isEmpty)
            for forbidden in ["onboarding.health", "onboarding.body", "onboarding.objective", "onboarding.persona", "photo", "development-consent"] {
                XCTAssertFalse(tree.identifiers.contains { $0.contains(forbidden) })
            }
            for document in state.requirements.documents { model.update(document.explicitAction, selected: true) }
            let selected = PremiumRenderingTestSupport.accessibilityProbe(view, width: 393, size: .large)
            XCTAssertTrue(selected.first { $0.isButton && $0.label == (locale == "pt-BR" ? "Continuar" : "Continue") }?.isEnabled == true)
        }
    }

    func testDocumentCardsRemainWithinTheColumnAtLargestTextSize() throws {
        for locale in ["pt-BR", "en-US"] {
            let state = try LegacyDocumentsFixtures.state(locale: locale)
            let cards = OnboardingLegalDocumentsView(documents: state.requirements.documents,
                selectedActions: [], allowsEditing: true, onChange: { _, _ in })
                .environment(\.locale, Locale(identifier: locale))
            let probes = PremiumRenderingTestSupport.accessibilityProbe(cards, width: 375, size: .accessibility5)
            XCTAssertFalse(probes.isEmpty)
            for probe in probes {
                XCTAssertGreaterThanOrEqual(probe.frame.minX, -0.5)
                XCTAssertLessThanOrEqual(probe.frame.maxX, 375.5)
            }
        }
    }
}
