import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// The review of a plan draft with the longer texts the server may send now
/// (second update, 2026-10-10): a phrase of up to 40 characters in the
/// effort and in the repetitions, and longer names such as "Músculos de trás
/// da coxa/Glúteos" and "Elevação pélvica com barra (Hip Thrust)".
@MainActor
final class PlanDraftReviewRenderingTests: XCTestCase {
    private let widths: [CGFloat] = [320, 375, 393, 402]
    private let sizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]
    private let locale = Locale(identifier: "pt-BR")

    private var texts: [String] {
        [
            DemoPlanDraftScenario.longFocus,
            DemoPlanDraftScenario.longExerciseName,
            DemoPlanDraftScenario.repetitionsPhrase,
            DemoPlanDraftScenario.longestExerciseName,
        ]
    }

    /// An editable field shows ALL of its text: it is at least as tall as
    /// the same text laid out freely in the same width, with the same font
    /// and the same padding. A field capped at three lines is shorter than
    /// that wherever the text needs a fourth line.
    func testLongTextsAreNeverCutInsideTheirField() throws {
        var cut: [String] = []
        var compared = 0
        for text in texts {
            for width in widths {
                for size in sizes {
                    let field = PremiumRenderingTestSupport.fittingSize(
                        PlanDraftTextField(title: "Exercício", text: .constant(text), keyboard: .default)
                            .bodyFlowField(),
                        width: width, dark: false, size: size, locale: locale
                    )
                    let free = PremiumRenderingTestSupport.fittingSize(
                        Text(verbatim: text)
                            .font(BodyFlowTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .bodyFlowField(),
                        width: width, dark: false, size: size, locale: locale
                    )
                    compared += 1
                    XCTAssertLessThanOrEqual(field.width, width + 0.5, "\(text.count) chars \(Int(width)) \(size)")
                    if field.height < free.height - 2 {
                        cut.append("\(text.count) chars at \(Int(width)) pt \(size): field \(field.height) < text \(free.height)")
                    }
                }
            }
        }
        XCTAssertEqual(compared, texts.count * widths.count * sizes.count)
        XCTAssertTrue(
            cut.isEmpty,
            "\(cut.count) of \(compared) fields hide part of their text; the first: \(cut.prefix(4))"
        )
    }

    /// The native control of a hosted field has nothing left to scroll: what
    /// it holds is not taller than what it shows.
    func testTheNativeFieldHasNothingLeftToScroll() throws {
        var overflowing: [String] = []
        var found = 0
        for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
            for width in [CGFloat(320), 402] {
                let text = DemoPlanDraftScenario.longestExerciseName
                let host = PremiumRenderingTestSupport.liveAccessibilityHost(
                    ScrollView {
                        PlanDraftTextField(title: "Exercício", text: .constant(text), keyboard: .default)
                            .bodyFlowField()
                    }
                    .environment(\.locale, locale),
                    width: width, size: size
                )
                defer { host.detach() }
                for input in host.nativeViews(UITextView.self) where input.text == text {
                    found += 1
                    if input.contentSize.height > input.bounds.height + 1 {
                        overflowing.append(
                            "\(Int(width)) pt \(size): holds \(input.contentSize.height), shows \(input.bounds.height)"
                        )
                    }
                    XCTAssertLessThanOrEqual(input.frame.maxX, width + 0.5)
                }
            }
        }
        // Without the native control this would prove nothing.
        XCTAssertEqual(found, 6, "The vertical field is not the native text view this test reads")
        XCTAssertTrue(overflowing.isEmpty, "The field scrolls inside itself: \(overflowing)")
    }

    /// LOCK: the effort row holds a grade beside its label and a phrase
    /// below it, inside the card, at every size.
    func testEffortRowFitsAGradeAndAPhrase() {
        for width in widths {
            for size in sizes {
                let grade = PremiumRenderingTestSupport.fittingSize(
                    FixtureMetricRow(title: "Esforço", value: "9 de 10", layout: .row),
                    width: width, dark: false, size: size, locale: locale
                )
                XCTAssertLessThanOrEqual(grade.width, width + 0.5, "\(Int(width)) \(size)")
                let phrase = PremiumRenderingTestSupport.fittingSize(
                    FixtureMetricRow(
                        title: "Esforço", value: DemoPlanDraftScenario.effortPhrase, layout: .stacked
                    ),
                    width: width, dark: false, size: size, locale: locale
                )
                let value = PremiumRenderingTestSupport.fittingSize(
                    Text(verbatim: DemoPlanDraftScenario.effortPhrase)
                        .font(BodyFlowTypography.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading),
                    width: width, dark: false, size: size, locale: locale
                )
                XCTAssertLessThanOrEqual(phrase.width, width + 0.5, "\(Int(width)) \(size)")
                XCTAssertGreaterThan(
                    phrase.height, value.height,
                    "The phrase is whole, below its label (\(Int(width)) \(size))"
                )
            }
        }
    }
}
