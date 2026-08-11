import Foundation

enum SupportedAppLanguage: String, CaseIterable, Sendable {
    case portugueseBrazil = "pt-BR"
    case englishUnitedStates = "en-US"

    var catalogLocalization: String {
        switch self {
        case .portugueseBrazil: "pt-BR"
        case .englishUnitedStates: "en"
        }
    }

    var formattingLocale: Locale {
        switch self {
        case .portugueseBrazil: Locale(identifier: "pt_BR")
        case .englishUnitedStates: Locale(identifier: "en_US")
        }
    }

    var contentLocale: ContentLocale {
        switch self {
        case .portugueseBrazil: .ptBR
        case .englishUnitedStates: .enUS
        }
    }
}

enum AppLocalizationError: Error, Equatable, Sendable {
    case localizedBundleNotFound(
        language: SupportedAppLanguage,
        localization: String
    )
    case missingLocalizedString(
        key: String,
        language: SupportedAppLanguage
    )
}

enum AppLocalization {
    static func localizedBundle(
        for language: SupportedAppLanguage,
        in bundle: Bundle = .main
    ) throws -> Bundle {
        let localization = language.catalogLocalization
        guard let path = bundle.path(
            forResource: localization,
            ofType: "lproj"
        ), let localizedBundle = Bundle(path: path) else {
            throw AppLocalizationError.localizedBundleNotFound(
                language: language,
                localization: localization
            )
        }

        return localizedBundle
    }

    static func string(
        _ key: String.LocalizationValue,
        for language: SupportedAppLanguage,
        in bundle: Bundle = .main
    ) throws -> String {
        let localizedBundle = try localizedBundle(for: language, in: bundle)
        let resource = LocalizedStringResource(
            key,
            locale: language.formattingLocale,
            bundle: localizedBundle
        )
        let missingValue = "\u{1F}BetterAhead.MissingLocalization\u{1F}"
        let format = localizedBundle.localizedString(
            forKey: resource.key,
            value: missingValue,
            table: resource.table
        )
        guard format != missingValue else {
            throw AppLocalizationError.missingLocalizedString(
                key: resource.key,
                language: language
            )
        }

        return String(localized: resource)
    }
}
