import Foundation
import Testing

@testable import BodyFlow

@Suite("Coach persona public contract")
struct CoachPersonaTests {
    @Test("public personas expose the approved neutral summaries")
    func approvedSummaries() {
        #expect(CoachPersona.focus.summary == "Direto, firme e objetivo.")
        #expect(CoachPersona.impulse.summary == "Motivador, positivo e energético.")
        #expect(CoachPersona.zen.summary == "Calmo, didático e acolhedor.")
    }

    @Test("only Focus, Impulse and Zen are publicly presented")
    func excludesInternalFallback() {
        #expect(CoachPersona.allCases == [.focus, .impulse, .zen])

        let publicStrings = CoachPersona.allCases.flatMap {
            [$0.displayName, $0.summary]
        } + [
            AppFixtures.profile.title,
            AppFixtures.profile.notifications,
        ]

        #expect(publicStrings.allSatisfy {
            !$0.localizedCaseInsensitiveContains("balanced")
                && !$0.localizedCaseInsensitiveContains("Equilibrado")
        })
    }

    @Test("development consent IDs are typed and versioned")
    func developmentConsentIDs() {
        #expect(DevelopmentConsentDocumentID.terms.rawValue == "dev.terms.v1")
        #expect(DevelopmentConsentDocumentID.privacy.rawValue == "dev.privacy.v1")
        #expect(Set(DevelopmentConsentDocumentID.allCases) == [
            .terms,
            .privacy,
        ])
    }
}
