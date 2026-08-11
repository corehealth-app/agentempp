import Foundation
import Testing

@testable import BodyFlow

@Suite
struct LocalizationContractTests {
    @Test
    func supportedLocaleSetsStayAligned() {
        let languageIdentifiers = Set(
            SupportedAppLanguage.allCases.map(\.rawValue)
        )

        #expect(languageIdentifiers == OnboardingLocalePolicy.supportedIdentifiers)
        #expect(languageIdentifiers == Set(ContentLocale.allCases.map(\.rawValue)))
    }

    @Test
    func supportedLanguagesMapToCatalogFormattingAndContentLocales() {
        #expect(SupportedAppLanguage.portugueseBrazil.catalogLocalization == "pt-BR")
        #expect(SupportedAppLanguage.portugueseBrazil.formattingLocale.identifier == "pt_BR")
        #expect(SupportedAppLanguage.portugueseBrazil.contentLocale == .ptBR)

        #expect(SupportedAppLanguage.englishUnitedStates.catalogLocalization == "en")
        #expect(SupportedAppLanguage.englishUnitedStates.formattingLocale.identifier == "en_US")
        #expect(SupportedAppLanguage.englishUnitedStates.contentLocale == .enUS)
    }

    @Test(arguments: SupportedAppLanguage.allCases)
    func localizedBundleUsesTheRequestedCatalog(_ language: SupportedAppLanguage) throws {
        let localizedBundle = try AppLocalization.localizedBundle(for: language)

        #expect(localizedBundle.bundleURL.lastPathComponent == "\(language.catalogLocalization).lproj")
    }

    @Test(arguments: SupportedAppLanguage.allCases)
    func reviewedAccessibilityCopyIsAvailable(_ language: SupportedAppLanguage) throws {
        let label = try AppLocalization.string(
            "brand.logo.accessibility-label",
            for: language
        )
        let fallbackLabel = try AppLocalization.string(
            "brand.logo.fallback.accessibility-label",
            for: language
        )

        #expect(label.contains("Better Ahead"))
        #expect(fallbackLabel.contains("Better Ahead"))
        #expect(!label.contains("BodyFlow"))
        #expect(!fallbackLabel.contains("BodyFlow"))
    }

    @Test
    func requestedLanguageOverridesTheOppositeProcessLanguage() throws {
        let fixture = try LocalizationFixture()
        defer { fixture.remove() }

        let processPrefersPortuguese = Locale.preferredLanguages.first?
            .hasPrefix("pt") == true
        let requestedLanguage: SupportedAppLanguage = processPrefersPortuguese
            ? .englishUnitedStates
            : .portugueseBrazil
        let expected = processPrefersPortuguese
            ? "Explicit English"
            : "Português explícito"
        let processLanguageOutput = processPrefersPortuguese
            ? "Português explícito"
            : "Explicit English"

        let output = try AppLocalization.string(
            "fixture.opposite-language",
            for: requestedLanguage,
            in: fixture.bundle
        )

        #expect(output == expected)
        #expect(output != processLanguageOutput)
    }

    @Test
    func dynamicPresentationStringsPreserveInterpolation() throws {
        let fixture = try LocalizationFixture()
        defer { fixture.remove() }
        let name = "Lia"
        let key: String.LocalizationValue = "presentation.greeting \(name)"

        #expect(try AppLocalization.string(
            key,
            for: .portugueseBrazil,
            in: fixture.bundle
        ) == "Olá, Lia!")
        #expect(try AppLocalization.string(
            key,
            for: .englishUnitedStates,
            in: fixture.bundle
        ) == "Hello, Lia!")
    }

    @Test
    func missingBrandKeyIsReportedByTheLocalizationContract() throws {
        let fixture = try LocalizationFixture()
        defer { fixture.remove() }

        #expect(throws: AppLocalizationError.missingLocalizedString(
            key: "brand.missing",
            language: .englishUnitedStates
        )) {
            try AppLocalization.string(
                "brand.missing",
                for: .englishUnitedStates,
                in: fixture.bundle
            )
        }
    }

    @Test
    func brandFallbackIsTheCompleteApprovedPortugueseCopy() throws {
        let fixture = try LocalizationFixture()
        defer { fixture.remove() }

        let output = BrandIdentity.copy(
            for: .englishUnitedStates,
            bundle: fixture.bundle
        )
        let combined = [output.slogan, output.descriptor, output.flowRoleLine]
            .joined(separator: " ")

        #expect(output == BrandCopy(
            slogan: "Melhor a cada dia.",
            descriptor: "Sua jornada personalizada para uma vida mais saudável.",
            flowRoleLine: "Flow, seu guia em cada etapa."
        ))
        #expect(combined.contains("Flow"))
        #expect(!combined.contains("BodyFlow"))
        #expect(!combined.contains("Coach"))
    }
}

private struct LocalizationFixture {
    let bundle: Bundle
    private let rootURL: URL

    init() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "BetterAheadLocalization-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "pt-BR",
            "CFBundleIdentifier": "com.betterahead.localization-fixture.\(UUID().uuidString)",
            "CFBundleLocalizations": ["pt-BR", "en"],
            "CFBundleName": "BetterAheadLocalizationFixture",
            "CFBundlePackageType": "BNDL",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: rootURL.appending(path: "Info.plist"))

        try Self.writeStrings(
            """
            "fixture.opposite-language" = "Português explícito";
            "presentation.greeting %@" = "Olá, %@!";
            """,
            localization: "pt-BR",
            rootURL: rootURL
        )
        try Self.writeStrings(
            """
            "fixture.opposite-language" = "Explicit English";
            "presentation.greeting %@" = "Hello, %@!";
            """,
            localization: "en",
            rootURL: rootURL
        )

        guard let bundle = Bundle(url: rootURL) else {
            throw LocalizationFixtureError.couldNotCreateBundle
        }

        self.bundle = bundle
        self.rootURL = rootURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func writeStrings(
        _ contents: String,
        localization: String,
        rootURL: URL
    ) throws {
        let localizationURL = rootURL.appending(
            path: "\(localization).lproj",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: localizationURL,
            withIntermediateDirectories: true
        )
        try contents.write(
            to: localizationURL.appending(path: "Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private enum LocalizationFixtureError: Error {
    case couldNotCreateBundle
}
