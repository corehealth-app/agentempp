import Foundation
import Testing

@testable import BodyFlow

@Suite
struct BrandIdentityTests {
    @Test(arguments: SupportedAppLanguage.allCases)
    func properNamesNeverChange(_ language: SupportedAppLanguage) {
        #expect(BrandIdentity.productName == "Performe AI")
        #expect(BrandIdentity.agentName == "Flow")
    }

    @Test
    func approvedPortugueseCopy() {
        #expect(BrandIdentity.copy(for: .portugueseBrazil) == BrandCopy(
            slogan: "Melhor a cada dia.",
            descriptor: "Sua jornada personalizada para uma vida mais saudável.",
            flowRoleLine: "Flow, seu guia em cada etapa."
        ))
    }

    @Test
    func approvedEnglishCopy() {
        #expect(BrandIdentity.copy(for: .englishUnitedStates) == BrandCopy(
            slogan: "Better every day.",
            descriptor: "Your personalized journey to a healthier life.",
            flowRoleLine: "Flow, your guide every step of the way."
        ))
    }

    @Test
    func publicBundleNamesUseApprovedBrand() {
        #expect(
            Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
                == "Performe AI"
        )
        #expect(
            Bundle.main.infoDictionary?["CFBundleName"] as? String
                == "Performe AI"
        )
    }
}
