import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// The meal card of the Register screen. Asked for on 2026-10-10: Foto,
/// Texto and Áudio looked like buttons and were decoration — any touch
/// opened the same sheet, which asked the question again.
///
/// The card (`RegisterMealCard`) is probed by itself: the screen wraps it in
/// a `ScrollView`, and the in-process accessibility probe does not see
/// inside one. The card on the real screen is driven by `MealCaptureUITests`.
@MainActor
final class RegisterRootRenderingTests: XCTestCase {
    private typealias Probe = PremiumRenderingTestSupport.AccessibilityProbe

    private struct Wording {
        let locale: Locale
        let meal: String
        let mealHint: String
        /// Label and spoken hint of each way, in the order of the card.
        let ways: [(label: String, hint: String)]
    }

    private let wordings = [
        Wording(
            locale: Locale(identifier: "pt-BR"),
            meal: "Refeição",
            mealHint: "Foto, texto ou áudio. Você confirma antes de salvar.",
            ways: [
                ("Foto", "Registrar a refeição por foto. Você confirma antes de salvar."),
                ("Texto", "Registrar a refeição por texto. Você confirma antes de salvar."),
                ("Áudio", "Registrar a refeição por áudio. Você confirma antes de salvar."),
            ]
        ),
        Wording(
            locale: Locale(identifier: "en"),
            meal: "Meal",
            mealHint: "Photo, text or audio. You confirm before it is saved.",
            ways: [
                ("Photo", "Log the meal with a photo. You confirm before it is saved."),
                ("Text", "Log the meal by writing. You confirm before it is saved."),
                ("Audio", "Log the meal by voice. You confirm before it is saved."),
            ]
        ),
    ]

    private let sizes: [DynamicTypeSize] = [.large, .accessibility5]
    private let widths: [CGFloat] = [375, 393, 430]

    func testMealCardOffersFotoTextoAudioAsRealButtonsAtEverySize() throws {
        for wording in wordings {
            for size in sizes {
                for width in widths {
                    let probes = probe(wording, width: width, size: size)
                    let context = "\(wording.locale.identifier) \(size) \(Int(width))"
                    // Locks first: the card's own action keeps its name, its
                    // hint and a full target.
                    let meal = try XCTUnwrap(
                        probes.first { $0.isButton && $0.label == wording.meal }, context
                    )
                    XCTAssertTrue(meal.isEnabled, context)
                    XCTAssertEqual(meal.hint, wording.mealHint, context)
                    assertMinimumTarget(meal, context)
                    // New: each way is a real button that says what it does.
                    for way in wording.ways {
                        let button = try XCTUnwrap(
                            probes.first { $0.isButton && $0.label == way.label },
                            "\(way.label) is not a button (\(context)): \(probes)"
                        )
                        XCTAssertEqual(
                            probes.filter { $0.isButton && $0.label == way.label }.count, 1, context
                        )
                        XCTAssertTrue(button.isEnabled, context)
                        assertMinimumTarget(button, context)
                        XCTAssertEqual(button.hint, way.hint, context)
                    }
                }
            }
        }
    }

    /// The four touch areas tile the card: wherever a finger lands on it,
    /// one of the four answers, and no two of them overlap.
    func testMealCardLeavesNoDeadZone() throws {
        for wording in wordings {
            for size in sizes {
                for width in widths {
                    let probes = probe(wording, width: width, size: size)
                    let context = "\(wording.locale.identifier) \(size) \(Int(width))"
                    let labels = [wording.meal] + wording.ways.map(\.label)
                    var frames: [CGRect] = []
                    for label in labels {
                        let button = try XCTUnwrap(
                            probes.first { $0.isButton && $0.label == label },
                            "\(label) is not a button (\(context)): \(probes)"
                        )
                        frames.append(button.frame)
                    }
                    let card = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
                    // The targets reach both edges of the card (hosted
                    // here at the full width).
                    XCTAssertEqual(card.minX, 0, accuracy: 0.5, context)
                    XCTAssertEqual(card.maxX, width, accuracy: 0.5, context)
                    // The title is the top of the card, edge to edge.
                    XCTAssertEqual(frames[0].minX, card.minX, accuracy: 0.5, context)
                    XCTAssertEqual(frames[0].maxX, card.maxX, accuracy: 0.5, context)
                    XCTAssertEqual(frames[0].minY, card.minY, accuracy: 0.5, context)
                    // Every point of the card belongs to exactly one target.
                    var uncovered = 0
                    var shared = 0
                    var y = card.minY + 1
                    while y < card.maxY - 1 {
                        var x = card.minX + 1
                        while x < card.maxX - 1 {
                            let point = CGPoint(x: x, y: y)
                            if !frames.contains(where: { $0.insetBy(dx: -0.75, dy: -0.75).contains(point) }) {
                                uncovered += 1
                            }
                            if frames.filter({ $0.insetBy(dx: 0.75, dy: 0.75).contains(point) }).count > 1 {
                                shared += 1
                            }
                            x += 2
                        }
                        y += 2
                    }
                    XCTAssertEqual(uncovered, 0, "Dead zone inside the meal card (\(context)): \(frames)")
                    XCTAssertEqual(shared, 0, "Overlapping targets in the meal card (\(context)): \(frames)")
                }
            }
        }
    }

    // MARK: Support

    private func probe(
        _ wording: Wording,
        width: CGFloat,
        size: DynamicTypeSize
    ) -> [Probe] {
        PremiumRenderingTestSupport.accessibilityProbe(
            RegisterMealCard { _ in }
                .environment(\.locale, wording.locale),
            width: width,
            size: size
        )
    }

    private func assertMinimumTarget(
        _ element: Probe,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            element.frame.width, BodyFlowSpacing.minimumTapTarget,
            "\(element) \(context)", file: file, line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height, BodyFlowSpacing.minimumTapTarget,
            "\(element) \(context)", file: file, line: line
        )
    }
}
