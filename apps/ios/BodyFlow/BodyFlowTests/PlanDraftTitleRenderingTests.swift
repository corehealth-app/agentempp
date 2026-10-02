import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class PlanDraftTitleRenderingTests: XCTestCase {
    /// Exact label, state, font category and viewport from the twentieth draft
    /// in the real Plan list. Its AX label still says "Plano de treino" when
    /// the visible title is "Plano de…", so existence is not the regression.
    func testTrainingDraftTitlePaintsItsFullWrappedHeightAtAXXXL() throws {
        let title = "Plano de treino"
        let viewport: CGFloat = 440
        let locale = SupportedAppLanguage.portugueseBrazil.formattingLocale
        let row = Button(action: {}) {
            BodyFlowCard {
                FeatureActionLabel(
                    title: title,
                    detail: "Faltam informações",
                    systemImage: "figure.run"
                )
            }
        }
        .buttonStyle(.bodyFlowRow)
        .padding(.horizontal, BodyFlowSpacing.md)

        let actual = PremiumRenderingTestSupport.nativeImage(
            row, width: viewport, dark: false, size: .accessibility5, locale: locale
        )
        // Use the widest possible title column, excluding only the known
        // gutters, minimum icon/spacer widths and HStack gaps. Omitting the
        // chevron width makes this a lower bound on the full wrapped height.
        let widestTitleColumn = viewport - 4 * BodyFlowSpacing.md
            - BodyFlowSpacing.minimumTapTarget - BodyFlowSpacing.xs
            - 3 * BodyFlowSpacing.sm
        let fullTitle = PremiumRenderingTestSupport.nativeImage(
            Text(title)
                .font(BodyFlowTypography.headline)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true),
            width: widestTitleColumn,
            dark: false,
            size: .accessibility5,
            locale: locale
        )
        for (name, image) in [("actual-training-draft-ax5", actual), ("full-training-title-ax5", fullTitle)] {
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let actualInkHeight = try primaryTextInkHeight(actual)
        let fullTitleInkHeight = try primaryTextInkHeight(fullTitle)
        XCTAssertGreaterThan(fullTitleInkHeight, 70, "Fixture must require more than one AX5 title line")
        XCTAssertGreaterThanOrEqual(
            actualInkHeight + 1, fullTitleInkHeight,
            "The rendered draft title must paint every wrapped line, not an ellipsis; actual \(actualInkHeight), full \(fullTitleInkHeight)"
        )
    }

    /// This light-mode fixture paints only the title in the dark primary
    /// color. The secondary detail/chevron and teal icon have green > 90.
    /// Measuring painted pixels catches clipping even when AX has full text.
    private func primaryTextInkHeight(_ image: UIImage) throws -> CGFloat {
        let source = try XCTUnwrap(image.cgImage)
        let width = source.width
        let height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        let rows = (0..<height).filter { y in
            (0..<width).contains { x in
                let offset = (y * width + x) * 4
                return pixels[offset + 3] > 240
                    && pixels[offset] < 90
                    && pixels[offset + 1] < 90
                    && pixels[offset + 2] < 90
            }
        }
        let first = try XCTUnwrap(rows.first, "The native image must contain primary title ink")
        let last = try XCTUnwrap(rows.last)
        return CGFloat(last - first + 1) / image.scale
    }
}
