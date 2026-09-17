import Testing
import UIKit

@testable import BodyFlow

@MainActor
@Suite("Optional Performe AI brand assets")
struct PerformeAIBrandAssetTests {
    @Test(arguments: [
        (PerformeAIBrandAsset.symbolLight, "PerformeAISymbolLightV1"),
        (PerformeAIBrandAsset.symbolDark, "PerformeAISymbolDarkV1"),
        (PerformeAIBrandAsset.symbolMono, "PerformeAISymbolMonoV1"),
        (PerformeAIBrandAsset.symbolNegative, "PerformeAISymbolNegativeV1"),
        (PerformeAIBrandAsset.wordmarkLight, "PerformeAIWordmarkLightV1"),
        (PerformeAIBrandAsset.wordmarkDark, "PerformeAIWordmarkDarkV1"),
        (PerformeAIBrandAsset.lockup, "PerformeAILockupV1"),
    ])
    func exactFutureResourceNames(asset: PerformeAIBrandAsset, name: String) {
        #expect(asset.resourceName == name)
    }

    @Test(arguments: PerformeAIBrandAsset.allCases)
    func missingFinalAssetsAreUnavailableWithoutReplacingThePublicFallback(
        _ asset: PerformeAIBrandAsset
    ) {
        #expect(asset.isAvailable() == false)
        #expect(BrandIdentity.productName == "Performe AI")
    }

    @Test
    func optionalFamilyDoesNotReplaceHistoricalNames() {
        #expect(PerformeAIBrandAsset.allCases.count == 7)
        #expect(Set(PerformeAIBrandAsset.allCases.map(\.resourceName)).count == 7)
        #expect(BodyFlowBrandAsset.allCases.map(\.catalogName) == [
            "BodyFlowSymbol", "BodyFlowWordmark", "BodyFlowHorizontal",
            "BodyFlowMonochrome", "BodyFlowNegative", "BodyFlowLaunch",
        ])
    }
}
