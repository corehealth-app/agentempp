import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// The staged loading block of the design system: one title, one stage line,
/// one animation, an optional cancel — and nothing that moves when the line
/// changes.
@MainActor
final class BodyFlowStagedLoaderRenderingTests: XCTestCase {
    private typealias Probe = PremiumRenderingTestSupport.AccessibilityProbe

    private struct Wording {
        let locale: Locale
        let title: String
        let cancel: String
        /// The five lines of the meal analysis (the reviewed wording).
        let stages: [String]
    }

    private let wordings = [
        Wording(
            locale: Locale(identifier: "pt-BR"),
            title: "Analisando sua refeição",
            cancel: "Cancelar",
            stages: [
                "Preparando o arquivo…", "Enviando…", "Analisando a foto…",
                "Transcrevendo o áudio…", "Lendo os alimentos…",
            ]
        ),
        Wording(
            locale: Locale(identifier: "en"),
            title: "Analyzing your meal",
            cancel: "Cancel",
            stages: [
                "Preparing the file…", "Uploading…", "Analyzing the photo…",
                "Transcribing the audio…", "Reading the foods…",
            ]
        ),
    ]

    private let widths: [CGFloat] = [375, 393, 430]
    private let sizes: [DynamicTypeSize] = [.large, .accessibility5]

    func testEveryStageLineKeepsTheSameHeight() {
        for wording in wordings {
            for width in widths {
                for size in sizes {
                    for dark in [false, true] {
                        let heights = wording.stages.map { stage in
                            PremiumRenderingTestSupport.fittingSize(
                                loader(wording, stage: stage), width: width, dark: dark,
                                size: size, locale: wording.locale
                            ).height
                        }
                        XCTAssertEqual(
                            Set(heights.map { ($0 * 10).rounded() }).count, 1,
                            "The block changes height with the stage line "
                                + "(\(wording.locale.identifier) \(Int(width)) \(size) dark=\(dark)): \(heights)"
                        )
                    }
                }
            }
        }
    }

    func testVoiceOverReadsTitleAndStageAndNeverTheAnimation() throws {
        for wording in wordings {
            for stage in wording.stages {
                let probes = probe(loader(wording, stage: stage), wording, width: 393, size: .large)
                let status = try XCTUnwrap(
                    probes.first { !$0.isButton && $0.label == wording.title && $0.value == stage },
                    "Title and stage are not one status element (\(stage)): \(describe(probes))"
                )
                XCTAssertFalse(status.isButton)
                XCTAssertEqual(probes.filter { !$0.isButton }.count, 1, describe(probes))
                XCTAssertEqual(probes.filter { $0.isButton && $0.label == wording.cancel }.count, 1)
                // Title/stage and the cancel action: nothing for the animation.
                XCTAssertEqual(probes.count, 2, describe(probes))
                XCTAssertFalse(probes.contains { $0.label.contains("%") || $0.value.contains("%") })
            }
        }
    }

    func testCancelKeepsItsPlaceWhetherEnabledOrNot() throws {
        for wording in wordings {
            for size in sizes {
                let stage = wording.stages[1]
                let enabled = probe(loader(wording, stage: stage), wording, width: 393, size: size)
                let disabled = probe(
                    loader(wording, stage: stage, cancelEnabled: false), wording, width: 393, size: size
                )
                let on = try XCTUnwrap(enabled.first { $0.isButton && $0.label == wording.cancel })
                let off = try XCTUnwrap(disabled.first { $0.isButton && $0.label == wording.cancel })
                XCTAssertTrue(on.isEnabled)
                XCTAssertFalse(off.isEnabled)
                XCTAssertEqual(on.frame, off.frame, "The cancel action moved when it was disabled")
                XCTAssertGreaterThanOrEqual(on.frame.width, BodyFlowSpacing.minimumTapTarget)
                XCTAssertGreaterThanOrEqual(on.frame.height, BodyFlowSpacing.minimumTapTarget)

                // No cancel where there is nothing to cancel.
                let none = probe(
                    BodyFlowStagedLoader(title: wording.title, stage: stage, reservedStages: wording.stages),
                    wording, width: 393, size: size
                )
                XCTAssertFalse(none.contains { $0.isButton }, describe(none))
            }
        }
    }

    func testGrowsWithDynamicTypeAndNeverOverflows() throws {
        for wording in wordings {
            for width in widths {
                let stage = wording.stages[3]
                let regular = PremiumRenderingTestSupport.fittingSize(
                    loader(wording, stage: stage), width: width, dark: false,
                    size: .large, locale: wording.locale
                )
                let large = PremiumRenderingTestSupport.fittingSize(
                    loader(wording, stage: stage), width: width, dark: false,
                    size: .accessibility5, locale: wording.locale
                )
                XCTAssertGreaterThan(large.height, regular.height)
                XCTAssertLessThanOrEqual(large.width, width + 1)
                let probes = probe(loader(wording, stage: stage), wording, width: width, size: .accessibility5)
                XCTAssertFalse(probes.isEmpty)
                for element in probes {
                    XCTAssertGreaterThanOrEqual(element.frame.minX, -0.5, "\(element)")
                    XCTAssertLessThanOrEqual(element.frame.maxX, width + 0.5, "\(element)")
                }
                // The animation is part of the block at every size.
                XCTAssertGreaterThan(
                    regular.height,
                    BodyFlowLiquidLoaderMetrics.size.height + BodyFlowSpacing.minimumTapTarget
                )
            }
        }
    }

    // MARK: Support

    private func loader(
        _ wording: Wording,
        stage: String,
        cancelEnabled: Bool = true
    ) -> BodyFlowStagedLoader {
        BodyFlowStagedLoader(
            title: wording.title,
            stage: stage,
            reservedStages: wording.stages,
            cancel: BodyFlowStagedLoader.CancelAction(
                title: wording.cancel, isEnabled: cancelEnabled, perform: {}
            )
        )
    }

    private func probe(
        _ view: some View,
        _ wording: Wording,
        width: CGFloat,
        size: DynamicTypeSize
    ) -> [Probe] {
        PremiumRenderingTestSupport.accessibilityProbe(
            view.environment(\.locale, wording.locale), width: width, size: size
        )
    }

    private func describe(_ probes: [Probe]) -> String {
        probes.map { "[\($0.label) | \($0.value) | button=\($0.isButton)]" }.joined(separator: " ")
    }
}
