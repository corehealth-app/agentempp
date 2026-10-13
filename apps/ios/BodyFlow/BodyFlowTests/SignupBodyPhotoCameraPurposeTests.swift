import Foundation
import Testing
@testable import BodyFlow

@Suite("Signup body photos camera purpose")
struct SignupBodyPhotoCameraPurposeTests {
    @Test("Camera purpose includes optional signup photos in both shipped languages",
          arguments: SupportedAppLanguage.allCases)
    func compiledCameraPurposeIncludesSignup(language: SupportedAppLanguage) throws {
        let expected = language == .portugueseBrazil
            ? "O Performe AI usa a câmera para fotografar a refeição que você quer registrar, o plano que você quer importar ou as fotos do corpo que você escolher enviar no cadastro."
            : "Performe AI uses the camera to photograph the meal you want to log, the plan you want to import, or the body photos you choose to send during sign-up."
        let bundle = try AppLocalization.localizedBundle(for: language)
        #expect(bundle.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist") == expected)
        let fallback = Bundle.main.infoDictionary?["NSCameraUsageDescription"] as? String
        #expect(fallback?.contains("fotos do corpo") == true)
    }
}
