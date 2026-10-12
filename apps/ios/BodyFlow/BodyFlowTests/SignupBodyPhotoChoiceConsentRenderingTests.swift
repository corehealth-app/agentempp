import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

// Component rendering only. Root binding, requests and capture remain later gates.
@MainActor
final class SignupBodyPhotoChoiceConsentRenderingTests: XCTestCase {
    func testAvailableChoicesArePhotosFirstInBothLanguages() throws {
        for language in SupportedAppLanguage.allCases {
            let nodes = choiceNodes(.available, language: language)
            let ids = ["onboarding.body-fat.choice.photos", "onboarding.body-fat.choice.typed", "onboarding.body-fat.choice.skip"]
            let rows = try ids.map { id in try XCTUnwrap(nodes.first { $0.identifier == id }) }
            XCTAssertEqual(rows.map(\.label), labels(language))
            XCTAssertEqual(rows.map(\.frame.minY), rows.map(\.frame.minY).sorted())
            for row in rows {
                XCTAssertTrue(row.isButton && row.isEnabled)
                XCTAssertGreaterThanOrEqual(row.frame.height, BodyFlowSpacing.minimumTapTarget)
            }
        }
    }

    func testUnavailableGatesKeepManualAndSkipWithoutAnEnabledPhotoAction() throws {
        for gate in [SignupBodyPhotoAvailability.unavailable, .loading, .birthDateRequired, .underage, .consentLocaleMismatch] {
            let nodes = choiceNodes(gate)
            let photo = nodes.first { $0.identifier == "onboarding.body-fat.choice.photos" }
            XCTAssertTrue(photo == nil || photo?.isEnabled == false)
            for id in ["onboarding.body-fat.choice.typed", "onboarding.body-fat.choice.skip"] {
                let row = try XCTUnwrap(nodes.first { $0.identifier == id }, "gate=\(gate)")
                XCTAssertTrue(row.isButton && row.isEnabled)
            }
        }
    }

    func testExistingManualSelectionIsSelectedWithoutSelectingPhotos() throws {
        let nodes = choiceNodes(.available, selection: .typed)
        let manual = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.body-fat.choice.typed" })
        let photo = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.body-fat.choice.photos" })
        XCTAssertTrue(manual.isSelected)
        XCTAssertFalse(photo.isSelected)
    }

    func testConsentPresentsTheCurrentServerBodyVerbatimEvenWithAnotherUILanguage() throws {
        for documentLanguage in SupportedAppLanguage.allCases {
            let supplied = document(documentLanguage)
            let uiLanguage: SupportedAppLanguage = documentLanguage == .portugueseBrazil ? .englishUnitedStates : .portugueseBrazil
            let nodes = consentNodes(supplied, language: uiLanguage)
            let body = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.consent.body" })
            XCTAssertEqual(body.label, supplied.body)
            XCTAssertFalse(body.label.contains("Fotos do corpo para estimar o percentual de gordura"))
            // This isolated view never translates/substitutes legal text. The
            // availability/caller must reject mismatched wire locales before route.
        }
    }

    func testConsentHasOnlyConsentAndDeclineCommandsWithoutEstimateConfirmation() throws {
        for language in SupportedAppLanguage.allCases {
            let nodes = consentNodes(document(language), language: language)
            let accept = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.consent.accept" })
            let decline = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.consent.decline" })
            XCTAssertEqual(accept.label, language == .portugueseBrazil ? "Consentir e continuar" : "Consent and continue")
            XCTAssertEqual(decline.label, language == .portugueseBrazil ? "Agora não" : "Not now")
            XCTAssertTrue(accept.isButton && accept.isEnabled)
            XCTAssertTrue(decline.isButton && decline.isEnabled)
            XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.result.confirm" })
        }
    }

    func testPendingConsentDoesNotPermitDuplicateAcceptance() throws {
        let nodes = consentNodes(document(.portugueseBrazil), isAccepting: true)
        let accept = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.consent.accept" })
        XCTAssertFalse(accept.isEnabled)
    }

    private func choiceNodes(_ availability: SignupBodyPhotoAvailability,
                             selection: SignupBodyFatChoice? = nil,
                             language: SupportedAppLanguage = .portugueseBrazil) -> [SignUpRenderingProbe.Node] {
        SignUpRenderingProbe.nodes(
            SignupBodyPhotoChoiceView(availability: availability, selection: selection, select: { _ in })
                .environment(\.locale, language.formattingLocale), width: 393, height: 3_000
        )
    }
    private func consentNodes(_ supplied: SignupBodyPhotoConsent,
                              language: SupportedAppLanguage = .portugueseBrazil,
                              isAccepting: Bool = false) -> [SignUpRenderingProbe.Node] {
        SignUpRenderingProbe.nodes(
            SignupBodyPhotoConsentView(document: supplied, isAccepting: isAccepting, consent: {}, decline: {})
                .environment(\.locale, language.formattingLocale), width: 393, height: 5_000
        )
    }
    private func labels(_ language: SupportedAppLanguage) -> [String] {
        language == .portugueseBrazil
            ? ["Estimar por fotos", "Já sei meu percentual", "Agora não"]
            : ["Estimate from photos", "I know my percentage", "Not now"]
    }
    private func document(_ language: SupportedAppLanguage) -> SignupBodyPhotoConsent {
        let portuguese = language == .portugueseBrazil
        return .init(documentKey: "body_photo_estimate_consent", version: "server-test-current-v2",
            locale: language.rawValue,
            body: portuguese ? "Texto sintético recebido do servidor.\nSegunda linha preservada." : "Synthetic text received from the server.\nThe second line is preserved.",
            bodyHash: portuguese ? "3654d9b42856b0b2ca5dc0bc7cfd6162e0229410d26c49bbc30d86917820a0b7" : "751b3366e9290cfaddf7b1c26db95ab844aea14f0bd0c96ad3ccfac90fde8304", acceptedAt: nil)
    }
}
