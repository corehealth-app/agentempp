import Foundation
import SwiftUI
import XCTest
@testable import BodyFlow

@MainActor
final class MealLiquidQuantityRenderingTests: XCTestCase {
    private func containsVisibleContent(_ image: UIImage) -> Bool {
        guard let source = image.cgImage, source.width > 0, source.height > 0 else { return false }
        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var firstPaintedColor: UInt32?
            for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset + 3] > 0 {
                let color = UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2])
                if let firstPaintedColor, color != firstPaintedColor { return true }
                firstPaintedColor = color
            }
            return false
        }
    }

    func testRenderEvidenceRejectsTransparentAndUniformImages() {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
        let transparent = renderer.image { _ in }
        let uniform = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let visible = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 8, y: 0, width: 8, height: 16))
        }
        XCTAssertFalse(containsVisibleContent(transparent))
        XCTAssertFalse(containsVisibleContent(uniform))
        XCTAssertTrue(containsVisibleContent(visible))
    }

    private func review() throws -> MealDraftReview {
        let data = Data(#"{"source":"text","media_asset_id":null,"transcript":null,"context_note":null,"nutrition_label":null,"items":[{"candidate_id":"c1-12345678","name":"leite integral","quantity_g":206,"quantity_basis":"portion_reference","count":null,"unit_label":null,"confidence":null,"needs_review":true,"review_reason":"estimated_quantity","quantity_display":{"unit":"mL","grams_per_unit":1.03,"reference_id":"fao-infoods-v2-whole-milk-tb","estimated":true}},{"candidate_id":"c2-23456789","name":"whey protein em pó","quantity_g":30,"quantity_basis":"portion_reference","count":null,"unit_label":null,"confidence":null,"needs_review":true,"review_reason":"estimated_quantity"}]}"#.utf8)
        return MealDraftReview(draft:try JSONDecoder().decode(MealDraftSnapshot.self,from:data),source:try XCTUnwrap(MealProposalSource(channel:.text,mediaAssetID:nil)),mealType:.breakfast)
    }

    func testMilkUsesVolumeAndPowderKeepsGramsInRealReviewControls() throws {
        for language in SupportedAppLanguage.allCases {
            let review = try review()
            // RegistrationSheet hosts this content in a padded ScrollView.
            // A bare, height-constrained VStack compresses fields and does
            // not represent the production layout at accessibility sizes.
            let view = ScrollView {
                MealDraftReviewView(review:.constant(review),isSubmitting:false,submit:{},startOver:{})
                    .padding(BodyFlowSpacing.lg)
            }
                .environment(\.locale,language.formattingLocale)
            for size: DynamicTypeSize in [.large,.accessibility5] {
                let host = PremiumRenderingTestSupport.liveAccessibilityHost(view,width:375,size:size)
                defer { host.detach() }
                let fields = host.nativeViews(UITextField.self)
                let diagnostic = fields.map { "placeholder=\($0.placeholder ?? "");text=\($0.text ?? "")" }
                let volumeTitle = language == .portugueseBrazil ? "Quantidade (mL)" : "Quantity (mL)"
                let powderTitle = language == .portugueseBrazil ? "Quantidade em gramas" : "Quantity in grams"
                let milk = try XCTUnwrap(fields.first { $0.placeholder == volumeTitle },"Synthetic native fields: \(diagnostic)")
                XCTAssertEqual(milk.text,"200")
                let powder = try XCTUnwrap(fields.first { $0.placeholder == powderTitle },"Synthetic native fields: \(diagnostic)")
                XCTAssertEqual(powder.text,"30")
                XCTAssertEqual(fields.filter { $0.placeholder == volumeTitle }.count,1)
                XCTAssertEqual(fields.filter { $0.placeholder == powderTitle }.count,1)
                for field in [milk, powder] {
                    let font = try XCTUnwrap(field.font)
                    XCTAssertGreaterThanOrEqual(field.bounds.height + 1, font.lineHeight)
                }
                // Capture the same mounted viewport whose real controls were read.
                // An unbounded offscreen host previously produced transparent PNGs.
                let image = host.image()
                XCTAssertTrue(containsVisibleContent(image), "The PNG must contain painted, nonuniform content before it can be used as visual evidence.")
                let attachment = XCTAttachment(data:try XCTUnwrap(image.pngData()),uniformTypeIdentifier:"public.png")
                let sizeName = size == .large ? "regular" : "axxxl"
                attachment.name="milk-whey-volume-review-\(language.rawValue)-\(sizeName)-viewport"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testInvalidMilkVolumeMessageDoesNotAskForGrams() throws {
        for language in SupportedAppLanguage.allCases {
            var review = try review()
            review.items[0].setQuantityText("9990",language:language)
            let view = MealDraftReviewView(review:.constant(review),isSubmitting:false,submit:{},startOver:{})
                .environment(\.locale,language.formattingLocale)
            let probe = PremiumRenderingTestSupport.accessibilityProbe(view,width:375)
            let expected = language == .portugueseBrazil
                ? "Informe um volume válido usando apenas o separador decimal."
                : "Enter a valid volume using only the decimal separator."
            XCTAssertTrue(probe.contains { $0.label == expected },"Synthetic labels: \(probe.map(\.label))")
            XCTAssertFalse(probe.contains { $0.label.contains("9.999") || $0.label.contains("9,999") })

        }
    }
}
