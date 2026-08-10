import SwiftUI

enum BodyFlowBrandVariant: Equatable, Sendable {
    case original
    case template

    var renderingMode: Image.TemplateRenderingMode {
        switch self {
        case .original:
            .original
        case .template:
            .template
        }
    }
}

enum BodyFlowBrandAsset: String, CaseIterable, Sendable {
    case symbol = "BodyFlowSymbol"
    case wordmark = "BodyFlowWordmark"
    case horizontal = "BodyFlowHorizontal"
    case monochrome = "BodyFlowMonochrome"
    case negative = "BodyFlowNegative"
    case launch = "BodyFlowLaunch"

    var catalogName: String { rawValue }

    var imageResource: ImageResource {
        switch self {
        case .symbol:
            .bodyFlowSymbol
        case .wordmark:
            .bodyFlowWordmark
        case .horizontal:
            .bodyFlowHorizontal
        case .monochrome:
            .bodyFlowMonochrome
        case .negative:
            .bodyFlowNegative
        case .launch:
            .bodyFlowLaunch
        }
    }

    var variant: BodyFlowBrandVariant {
        switch self {
        case .symbol, .wordmark, .horizontal, .launch:
            .original
        case .monochrome, .negative:
            .template
        }
    }

    var accessibilityLabel: String? {
        switch self {
        case .wordmark, .horizontal, .launch:
            "BodyFlow"
        case .symbol, .monochrome, .negative:
            nil
        }
    }

    @MainActor
    var image: Image {
        Image(imageResource).renderingMode(variant.renderingMode)
    }
}
