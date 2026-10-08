import SwiftUI
import XCTest

@testable import BodyFlow

/// Exercises the actual SwiftUI content, including legacy stored figures
/// that must remain intact when the current objective hides the block.
@MainActor
final class Block7700EligibilityRenderingTests: XCTestCase {
    private struct Context {
        let protocolName: String?
        let flag: Bool?
        let blockVisible: Bool
        let explanationVisible: Bool
    }

    private let contexts = [
        Context(protocolName: "recomposicao", flag: true, blockVisible: true, explanationVisible: false),
        Context(protocolName: "ganho_massa", flag: false, blockVisible: false, explanationVisible: true),
        Context(protocolName: "manutencao", flag: false, blockVisible: false, explanationVisible: true),
        Context(protocolName: nil, flag: nil, blockVisible: false, explanationVisible: false),
    ]

    func testProgressKeepsOfficialValuesAndOnlyHidesBlockRowsAndMedal() throws {
        for language in SupportedAppLanguage.allCases {
            for context in contexts {
                let snapshot = progress(context)
                let view = ProgressContentView(
                    presentation: ProgressPresentation(snapshot: snapshot, language: language),
                    selectedTab: .constant(.progress)
                ).environment(\.locale, language.formattingLocale)
                for size in [DynamicTypeSize.large, .accessibility5] {
                    let labels = PremiumRenderingTestSupport.accessibilityProbe(
                        view.fixedSize(horizontal: false, vertical: true), width: 375, size: size
                    ).map(\.label)
                    let text = labels.joined(separator: "\n")
                    XCTAssertTrue(text.contains(language == .portugueseBrazil ? "1.240 XP" : "1,240 XP"), text)
                    XCTAssertTrue(text.contains("80 kg"), text)
                    XCTAssertTrue(text.contains("Primeira Semana"), text)
                    XCTAssertTrue(text.contains("badge-z"), text)
                    XCTAssertEqual(text.contains("Primeiro Bloco"), context.blockVisible, text)
                    XCTAssertEqual(text.contains(copy("progress.metric.completed-blocks", language)), context.blockVisible, text)
                    XCTAssertEqual(text.contains(copy("progress.metric.reported-deficit", language)), context.blockVisible, text)
                    let explanation = copy("progress.block.ineligible", language)
                    XCTAssertEqual(labels.filter { $0.contains(explanation) }.count, context.explanationVisible ? 1 : 0, text)
                    for dark in [false, true] {
                        let fit = PremiumRenderingTestSupport.fittingSize(
                            view, width: 375, dark: dark, size: size, locale: language.formattingLocale
                        )
                        XCTAssertGreaterThan(fit.height, 0)
                        XCTAssertLessThanOrEqual(fit.width, 376)
                    }
                }
                // Rendering is not permission to mutate stored achievements.
                XCTAssertEqual(snapshot.badgesEarned, ["Primeiro Bloco", "Primeira Semana", "badge-z", "Primeira Semana"])
                XCTAssertEqual(snapshot.blocksCompleted, 4)
                XCTAssertEqual(snapshot.deficitBlock, 3_120)
            }
        }
    }

    func testTodayTrailRemovesOnlyBlockAndUsesTheMatchingExplanation() throws {
        for language in SupportedAppLanguage.allCases {
            for blockVisible in [false, true] {
                let descriptor = TodayTrailDescriptor(
                    recordCount: 5, remainingFood: "1.234 kcal", blockPercentage: 50,
                    showsBlock7700: blockVisible, language: language
                )
                let view = TodayTrailSection(descriptor: descriptor)
                    .environment(\.locale, language.formattingLocale)
                for size in [DynamicTypeSize.large, .accessibility5] {
                    let text = PremiumRenderingTestSupport.accessibilityProbe(
                        view.fixedSize(horizontal: false, vertical: true), width: 375, size: size
                    ).map(\.label).joined(separator: "\n")
                    for key in ["today.trail.node.register", "today.trail.node.today", "today.trail.node.progress"] {
                        XCTAssertTrue(text.contains(copy(key, language)), text)
                    }
                    XCTAssertTrue(text.contains("1.234 kcal"), text)
                    XCTAssertEqual(text.contains(copy("today.trail.node.block", language)), blockVisible, text)
                    XCTAssertEqual(text.contains("50%"), blockVisible, text)
                    XCTAssertTrue(text.contains(copy(blockVisible ? "today.trail.detail" : "today.trail.detail.without-block", language)), text)
                }
            }
        }
    }

    func testNullProgressRetainsStoredTrends() async throws {
        let provider = RenderingProgressProvider(response: BodyFlowTestFixtures.emptyProgressResponse)
        let model = ProgressViewModel(provider: provider)
        await model.load()
        XCTAssertEqual(model.state, .empty)
        XCTAssertEqual(model.trends.state, .loaded(DemoBodyFlowFixtures.loadedTrends.data))
        // The root's exact positive/negative UI assertions live in
        // Block7700EligibilityUITests.testNullProgressKeepsOldTrendsWithoutBlock.
        // A UIKit descendant probe cannot enumerate virtual ScrollView rows.
    }

    func testTrendsRetainWeightCaloriesAndRecordedDaysWithOrWithoutTheBlock() async throws {
        let model = ProgressTrendsViewModel(provider: RenderingProgressProvider(response: BodyFlowTestFixtures.emptyProgressResponse))
        await model.load()
        for language in SupportedAppLanguage.allCases {
            for blockVisible in [false, true] {
                let view = ProgressTrendsSection(model: model, showsBlock7700: blockVisible)
                    .environment(\.locale, language.formattingLocale)
                let text = PremiumRenderingTestSupport.accessibilityProbe(
                    view.fixedSize(horizontal: false, vertical: true), width: 430
                ).map(\.label).joined(separator: "\n")
                XCTAssertTrue(text.contains(copy("progress.trends.weight", language)), text)
                XCTAssertTrue(text.contains(String(format: copy("progress.trends.calories", language), 14)), text)
                XCTAssertTrue(text.contains(copy("progress.trends.days", language)), text)
                XCTAssertEqual(text.contains(copy("progress.trends.block", language)), blockVisible, text)
                XCTAssertTrue(text.contains(language == .portugueseBrazil ? "78,4 kg" : "78.4 kg"), text)
            }
        }
        XCTAssertEqual(model.state, .loaded(DemoBodyFlowFixtures.loadedTrends.data))
    }

    private func progress(_ context: Context) -> ProgressSnapshot {
        ProgressSnapshot(
            xpTotal: 1_240, level: 2, currentStreak: 3, longestStreak: 7,
            blocksCompleted: 4, deficitBlock: 3_120, currentWeight: 80,
            currentBodyFatPercent: nil, badgesEarned: ["Primeiro Bloco", "Primeira Semana", "badge-z", "Primeira Semana"],
            lastActiveDate: "2026-10-04", nextReevaluation: "2026-10-18",
            updatedAt: BodyFlowTestFixtures.progressSnapshot.updatedAt,
            currentProtocol: context.protocolName, block7700Enabled: context.flag
        )
    }

    private func copy(_ key: String, _ language: SupportedAppLanguage) -> String {
        // Catalog lookup is independent of the eligibility policy.
        do {
            return try AppLocalization.string(String.LocalizationValue(key), for: language)
        } catch {
            XCTFail("Missing catalog copy for \(key): \(error)")
            return key
        }
    }
}

private struct RenderingProgressProvider: ProgressProviding {
    let response: ProgressResponse
    func progress() async throws -> ProgressResponse { response }
    func trends(days: Int) async throws -> TrendsResponse { DemoBodyFlowFixtures.loadedTrends }
}
