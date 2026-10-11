import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// P-ACTIVITY. Reported by the physician on build 1.0 (3), 2026-10-10 18:56,
/// with the menu "Nível de atividade" open on "Sua rotina" (Sedentário, Leve,
/// Moderado, Alto, Atleta — names only): "Aqui ele não diz qual a frequência
/// semanal de atividade física de cada categoria".
///
/// The ranges are the physician's own, written for the sign-up question:
/// "sedentário / leve (1–3x/sem) / moderado (4–5x/sem) / alto (6–7x/sem) /
/// atleta (2x/dia)". The owner asked for them in days of exercise, saying
/// which exercise counts (2026-10-10). The sentence form, the text of
/// "Sedentário" and the line that says which exercise counts are a proposal
/// of the orchestrator, announced to the owner, who can strike any of it.
@MainActor
final class OnboardingActivityLevelRenderingTests: XCTestCase {
    private struct Level {
        let value: ActivityLevel
        let stored: String
        let portuguese: (name: String, detail: String)
        let english: (name: String, detail: String)

        func wording(_ language: SupportedAppLanguage) -> (name: String, detail: String) {
            language == .portugueseBrazil ? portuguese : english
        }
    }

    private let levels: [Level] = [
        Level(value: .sedentary, stored: "sedentario",
              portuguese: ("Sedentário", "Não faz exercício."),
              english: ("Sedentary", "Does not exercise.")),
        Level(value: .light, stored: "leve",
              portuguese: ("Leve", "Exercício de 1 a 3 dias por semana."),
              english: ("Light", "Exercise 1 to 3 days a week.")),
        Level(value: .moderate, stored: "moderado",
              portuguese: ("Moderado", "Exercício de 4 a 5 dias por semana."),
              english: ("Moderate", "Exercise 4 to 5 days a week.")),
        Level(value: .high, stored: "alto",
              portuguese: ("Alto", "Exercício de 6 a 7 dias por semana."),
              english: ("High", "Exercise 6 to 7 days a week.")),
        Level(value: .athlete, stored: "atleta",
              portuguese: ("Atleta", "Treina 2 vezes por dia."),
              english: ("Athlete", "Trains 2 times a day.")),
    ]

    private func whichExerciseCounts(_ language: SupportedAppLanguage) -> String {
        language == .portugueseBrazil
            ? "Conte os dias em que você faz exercício: musculação, corrida, esporte, aula, pedal ou natação."
            : "Count the days you exercise: strength training, running, sports, classes, cycling or swimming."
    }

    private func routineModel(_ change: (inout OnboardingDraft) -> Void = { _ in }) -> OnboardingFlowModel {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        change(&draft)
        return OnboardingFlowModel(
            userID: "qa-a", initialDraft: draft,
            repository: E3Repository(), personaRepository: E3Persona(),
            developmentConsentAvailability: .unavailable,
            onStepChanged: { _ in }, onCompleted: {}
        )
    }

    private func step(_ model: OnboardingFlowModel, _ language: SupportedAppLanguage) -> some View {
        RoutineStepView(model: model).environment(\.locale, language.formattingLocale)
    }

    /// The rows of the five levels, in the order they are drawn. A row is a
    /// button whose spoken text carries the level's name AND what it means.
    private func rows(
        _ nodes: [SignUpRenderingProbe.Node], _ language: SupportedAppLanguage
    ) -> [(level: Level, node: SignUpRenderingProbe.Node)] {
        levels.compactMap { level in
            let wording = level.wording(language)
            let found = nodes.filter {
                $0.isButton && $0.label.contains(wording.name) && $0.label.contains(wording.detail)
            }
            return found.count == 1 ? (level, found[0]) : nil
        }
    }

    private func drawn(_ nodes: [SignUpRenderingProbe.Node]) -> String {
        "\(nodes.filter { $0.isButton || !$0.label.isEmpty })"
    }

    // MARK: The report

    func testEveryLevelSaysItsDaysOfExerciseWithoutOpeningAnything() throws {
        for language in SupportedAppLanguage.allCases {
            let nodes = SignUpRenderingProbe.nodes(step(routineModel(), language), width: 393, height: 3_000)
            let found = rows(nodes, language)
            XCTAssertEqual(
                found.map(\.level.stored), levels.map(\.stored),
                "\(language): each level needs one row with its name and its days of exercise. Drawn: \(drawn(nodes))"
            )
            for (level, node) in found {
                let context = "\(level.stored) / \(language)"
                XCTAssertTrue(node.isElement && node.isEnabled, "\(context): \(node)")
                XCTAssertEqual(node.identifier, "onboarding.activity-level.\(level.stored)", context)
                XCTAssertGreaterThanOrEqual(node.frame.height, BodyFlowSpacing.minimumTapTarget, context)
                XCTAssertGreaterThanOrEqual(node.frame.minX, -0.5, context)
                XCTAssertLessThanOrEqual(node.frame.maxX, 393.5, context)
                // The fixture's level is the chosen one, and only it.
                XCTAssertEqual(node.isSelected, level.value == .moderate, context)
            }
            // Top to bottom in the order of the stored scale.
            XCTAssertEqual(found.map(\.node.frame.minY), found.map(\.node.frame.minY).sorted(), "\(language)")
            // One line, under the field's title and above the rows, says
            // which exercise counts.
            let line = try XCTUnwrap(
                nodes.first { $0.label == whichExerciseCounts(language) },
                "\(language): no line saying which exercise counts. Drawn: \(drawn(nodes))"
            )
            let title = try XCTUnwrap(nodes.first {
                $0.label == (language == .portugueseBrazil ? "Nível de atividade" : "Activity level")
            })
            XCTAssertGreaterThanOrEqual(line.frame.minY, title.frame.maxY - 0.5, "\(language)")
            if let first = found.first {
                XCTAssertLessThanOrEqual(line.frame.maxY, first.node.frame.minY + 0.5, "\(language)")
            }
        }
    }

    func testChoosingALevelMarksOnlyThatRowAndKeepsTheStoredValue() {
        let model = routineModel()
        let host = SignUpRenderingProbe.host(step(model, .portugueseBrazil), width: 393, height: 3_000)
        defer { host.detach() }
        XCTAssertEqual(model.draft.activityLevel, .moderate)

        model.updateActivityLevel(.light)

        let found = rows(host.nodes(), .portugueseBrazil)
        XCTAssertEqual(found.count, levels.count, "Five rows after the choice")
        for (level, node) in found {
            XCTAssertEqual(node.isSelected, level.value == .light, level.stored)
        }
        XCTAssertEqual(model.draft.activityLevel?.rawValue, "leve")
    }

    /// With no level chosen no row is marked, and "Continuar" asks for one.
    func testWithoutALevelNoRowIsChosenAndContinueAsksForOne() async {
        let model = routineModel { $0.activityLevel = nil }
        let host = SignUpRenderingProbe.host(step(model, .portugueseBrazil), width: 393, height: 3_000)
        defer { host.detach() }

        let before = rows(host.nodes(), .portugueseBrazil)
        XCTAssertEqual(before.count, levels.count, "Five rows before any choice: \(drawn(host.nodes()))")
        XCTAssertFalse(before.contains { $0.node.isSelected }, "No level is chosen yet")

        await model.continueFromCurrentStep()

        XCTAssertEqual(model.step, .routine)
        XCTAssertEqual(model.validationIssues, [.activityLevelRequired])
        let after = host.nodes()
        XCTAssertTrue(
            after.contains { $0.label.contains("Selecione seu nível de atividade.") },
            "The step must say what is missing: \(drawn(after))"
        )
        XCTAssertFalse(rows(after, .portugueseBrazil).contains { $0.node.isSelected })
    }

    // MARK: Every size, width, language and appearance

    func testTheRowsFitTheWidthAndGrowWithTheTextAcrossTheMatrix() throws {
        for language in SupportedAppLanguage.allCases {
            let locale = language.formattingLocale
            for width: CGFloat in [375, 393, 430] {
                var rowHeights: [DynamicTypeSize: [CGFloat]] = [:]
                for size in [DynamicTypeSize.large, .accessibility5] {
                    let context = "\(language) / \(Int(width)) / \(size)"
                    let nodes = SignUpRenderingProbe.nodes(
                        step(routineModel(), language), width: width, height: 6_000, size: size
                    )
                    let found = rows(nodes, language)
                    XCTAssertEqual(found.count, levels.count, "\(context): \(drawn(nodes))")
                    for (level, node) in found {
                        XCTAssertGreaterThanOrEqual(node.frame.minX, -0.5, "\(level.stored) \(context)")
                        XCTAssertLessThanOrEqual(node.frame.maxX, width + 0.5, "\(level.stored) \(context)")
                        XCTAssertGreaterThanOrEqual(
                            node.frame.height, BodyFlowSpacing.minimumTapTarget, "\(level.stored) \(context)"
                        )
                    }
                    rowHeights[size] = found.map(\.node.frame.height)
                }
                let regular = try XCTUnwrap(rowHeights[.large])
                let largest = try XCTUnwrap(rowHeights[.accessibility5])
                XCTAssertEqual(regular.count, largest.count, "\(language) / \(Int(width))")
                for (index, pair) in zip(regular, largest).enumerated() {
                    XCTAssertGreaterThan(
                        pair.1, pair.0,
                        "\(language) / \(Int(width)): row \(index) must grow at the largest text size"
                    )
                }
                for dark in [false, true] {
                    let regularStep = PremiumRenderingTestSupport.fittingSize(
                        step(routineModel(), language), width: width, dark: dark, size: .large, locale: locale
                    )
                    let largestStep = PremiumRenderingTestSupport.fittingSize(
                        step(routineModel(), language), width: width, dark: dark, size: .accessibility5, locale: locale
                    )
                    XCTAssertLessThanOrEqual(largestStep.width, width + 1, "\(language) / \(Int(width)) / dark \(dark)")
                    XCTAssertGreaterThan(largestStep.height, regularStep.height)
                }
            }
        }
    }

    func testTheStepNeverCutsOrShrinksItsText() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("BodyFlow/Features/Onboarding/RoutineStepView.swift"),
            encoding: .utf8
        )
        for forbidden in [".lineLimit(", ".minimumScaleFactor(", ".font(.system(size:"] {
            XCTAssertFalse(source.contains(forbidden), "RoutineStepView: \(forbidden)")
        }
    }

    // MARK: Nothing of the calculation changes

    /// The texts are presentation only: what is stored and sent for each
    /// level, and the order of the scale, are the same.
    func testTheStoredValuesOfTheFiveLevelsAreUnchanged() {
        XCTAssertEqual(
            ActivityLevel.allCases.map(\.rawValue),
            ["sedentario", "leve", "moderado", "alto", "atleta"]
        )
        XCTAssertEqual(levels.map(\.value), ActivityLevel.allCases)
        XCTAssertEqual(levels.map(\.stored), ActivityLevel.allCases.map(\.rawValue))
    }
}
