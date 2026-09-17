import Foundation

enum BodyFlowPresentationLanguage {
    static func resolve(_ locale: Locale) -> SupportedAppLanguage {
        locale.language.languageCode?.identifier == "en"
            ? .englishUnitedStates : .portugueseBrazil
    }
}
