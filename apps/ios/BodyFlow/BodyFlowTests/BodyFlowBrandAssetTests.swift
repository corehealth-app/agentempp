import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

@MainActor
@Suite("BodyFlow brand assets")
struct BodyFlowBrandAssetTests {
    @Test(arguments: [
        (BodyFlowBrandAsset.symbol, "BodyFlowSymbol", BodyFlowBrandVariant.original),
        (BodyFlowBrandAsset.wordmark, "BodyFlowWordmark", BodyFlowBrandVariant.original),
        (BodyFlowBrandAsset.horizontal, "BodyFlowHorizontal", BodyFlowBrandVariant.original),
        (BodyFlowBrandAsset.monochrome, "BodyFlowMonochrome", BodyFlowBrandVariant.template),
        (BodyFlowBrandAsset.negative, "BodyFlowNegative", BodyFlowBrandVariant.template),
        (BodyFlowBrandAsset.launch, "BodyFlowLaunch", BodyFlowBrandVariant.original),
    ])
    func catalogNamesAndRenderingIntents(
        asset: BodyFlowBrandAsset,
        catalogName: String,
        variant: BodyFlowBrandVariant
    ) {
        #expect(asset.catalogName == catalogName)
        #expect(asset.variant == variant)
    }

    @Test(arguments: BodyFlowBrandAsset.allCases)
    func everyBrandAssetLoadsFromTheApplicationBundle(_ asset: BodyFlowBrandAsset) {
        #expect(UIImage(named: asset.catalogName) != nil)
    }

    @Test(arguments: [
        (BodyFlowBrandAsset.symbol, nil),
        (BodyFlowBrandAsset.wordmark, "BodyFlow"),
        (BodyFlowBrandAsset.horizontal, "BodyFlow"),
        (BodyFlowBrandAsset.monochrome, nil),
        (BodyFlowBrandAsset.negative, nil),
        (BodyFlowBrandAsset.launch, "BodyFlow"),
    ])
    func accessibilityLabelsKeepSymbolsDecorative(
        asset: BodyFlowBrandAsset,
        label: String?
    ) {
        #expect(asset.accessibilityLabel == label)
    }

    @Test(arguments: [
        (
            BodyFlowBrandAsset.symbol,
            ImageResource.bodyFlowSymbol,
            Image.TemplateRenderingMode.original
        ),
        (
            BodyFlowBrandAsset.wordmark,
            ImageResource.bodyFlowWordmark,
            Image.TemplateRenderingMode.original
        ),
        (
            BodyFlowBrandAsset.horizontal,
            ImageResource.bodyFlowHorizontal,
            Image.TemplateRenderingMode.original
        ),
        (
            BodyFlowBrandAsset.monochrome,
            ImageResource.bodyFlowMonochrome,
            Image.TemplateRenderingMode.template
        ),
        (
            BodyFlowBrandAsset.negative,
            ImageResource.bodyFlowNegative,
            Image.TemplateRenderingMode.template
        ),
        (
            BodyFlowBrandAsset.launch,
            ImageResource.bodyFlowLaunch,
            Image.TemplateRenderingMode.original
        ),
    ])
    func swiftUIBoundaryUsesTheExactResourceAndRenderingMode(
        asset: BodyFlowBrandAsset,
        imageResource: ImageResource,
        renderingMode: Image.TemplateRenderingMode
    ) {
        #expect(asset.imageResource == imageResource)
        #expect(asset.variant.renderingMode == renderingMode)
    }

    @Test(arguments: BodyFlowBrandAsset.allCases)
    func swiftUIBoundaryBuildsEachTypedAsset(_ asset: BodyFlowBrandAsset) {
        let image: Image = asset.image

        #expect(String(describing: image).isEmpty == false)
    }
}
