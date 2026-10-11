import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// LOCKS (second update, 2026-10-10) of a wiring that was proven only by
/// tables and by reading the source: while the staged loader of a meal
/// analysis is on screen, the brand mark of the sheet's bar draws no second
/// indicator.
@MainActor
final class RegistrationBrandMarkRenderingTests: XCTestCase {
    /// What is drawn, pixel by pixel. Reduce Motion is injected so that the
    /// mark's own indicator, where it exists, is a still glyph: the
    /// comparison never depends on the frame of a spinner.
    func testNoSecondIndicatorWhileTheStagedLoaderShows() throws {
        for dark in [false, true] {
            let idle = try drawn(state: .idle, stage: nil, dark: dark)
            for stage in MealAnalysisStage.allCases {
                let waiting = try drawn(state: .processing, stage: stage, dark: dark)
                XCTAssertEqual(
                    waiting, idle,
                    "The mark draws an indicator of its own while the loader shows \(stage) (dark=\(dark))"
                )
            }
            // Control: without a loader on screen the mark keeps its own
            // indicator — the comparison above can tell the two apart.
            let alone = try drawn(state: .processing, stage: nil, dark: dark)
            XCTAssertNotEqual(alone, idle, "Control: processing with no loader draws the mark's indicator (dark=\(dark))")
        }
    }

    /// The sheet's bar uses this very view, with the stage the sheet decided.
    func testTheToolbarUsesTheMarkWithTheSheetsStage() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("BodyFlow/Features/Register/RegistrationSheet.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: ".toolbar {"))
        let end = try XCTUnwrap(source.range(
            of: "ToolbarItem(placement: .cancellationAction)",
            range: start.upperBound..<source.endIndex
        ))
        let toolbar = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(toolbar.contains("RegistrationBrandMark("), toolbar)
        XCTAssertTrue(toolbar.contains("analysisStage: analysisStage"), toolbar)
        XCTAssertFalse(toolbar.contains("PerformeBrandAction("), "The bar must not build the mark by hand")

        let markStart = try XCTUnwrap(source.range(of: "struct RegistrationBrandMark: View {"))
        let markEnd = try XCTUnwrap(source.range(
            of: "struct MealLiveCapture {", range: markStart.upperBound..<source.endIndex
        ))
        let mark = String(source[markStart.lowerBound..<markEnd.lowerBound])
        XCTAssertTrue(mark.contains("showsProgress: analysisStage == nil"), mark)
    }

    private func drawn(
        state: PerformeBrandState,
        stage: MealAnalysisStage?,
        dark: Bool
    ) throws -> Data {
        let host = PremiumRenderingTestSupport.liveAccessibilityHost(
            RegistrationBrandMark(
                state: state,
                label: "Registrar",
                status: "Processando",
                analysisStage: stage
            )
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.bodyFlowReduceMotion, true),
            width: 120
        )
        defer { host.detach() }
        // The mark's indicator waits a moment before it shows (150 ms).
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        return try XCTUnwrap(host.image().pngData())
    }
}
