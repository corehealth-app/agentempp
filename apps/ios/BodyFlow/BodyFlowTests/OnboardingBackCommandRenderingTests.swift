import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// P-BACK. Reported by the physician on build 1.0 (3), 2026-10-10 18:56,
/// on the step "Sua rotina": "Passei pra frente e ele não deixa voltar" —
/// he circled the TOP of the screen, where there was no way back. The only
/// "Voltar" was the last item of the scrolling column, and the review step
/// had none.
///
/// These tests read the sign-up container as it is drawn. The in-process
/// walk does not see inside a SwiftUI `ScrollView` (see
/// `SignUpRenderingProbe`), so what it reads of the container is exactly
/// what sits OUTSIDE the scrolling column: before this change, nothing;
/// after it, the one way back. The column itself is read as geometry (its
/// scroll view) here and as a screen by `OnboardingBackUITests`.
@MainActor
final class OnboardingBackCommandRenderingTests: XCTestCase {
    private static let topIdentifier = "onboarding.back.top"
    private static let stepsAfterTheFirst: [OnboardingStep] = [
        .bodyData, .routine, .persona, .consent, .objective, .completion,
    ]

    private func container(
        _ model: OnboardingFlowModel,
        _ language: SupportedAppLanguage = .portugueseBrazil
    ) -> some View {
        OnboardingContainerView(model: model)
            .environment(\.locale, language.formattingLocale)
            .environment(\.bodyFlowReduceMotion, true)
    }

    private func spoken(_ language: SupportedAppLanguage) -> String {
        language == .portugueseBrazil ? "Voltar para a etapa anterior" : "Back to the previous step"
    }

    /// The scrolling column of the hosted container, proof that the screen
    /// is drawn, and its frame in the window.
    private func scrollingColumn(
        _ host: SignUpRenderingProbe.Host, _ context: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> (scroll: UIScrollView, frame: CGRect) {
        let scroll = try XCTUnwrap(
            host.scrollViews().max { $0.contentSize.height < $1.contentSize.height },
            "\(context): the sign-up column is not drawn", file: file, line: line
        )
        XCTAssertGreaterThan(
            scroll.contentSize.height, BodyFlowSpacing.minimumTapTarget,
            "\(context): the sign-up column is empty", file: file, line: line
        )
        return (scroll, scroll.convert(scroll.bounds, to: nil))
    }

    /// The buttons that do not scroll with the column.
    private func fixedCommands(_ nodes: [SignUpRenderingProbe.Node]) -> [SignUpRenderingProbe.Node] {
        nodes.filter { $0.isElement && $0.isButton }
    }

    // MARK: Presence

    func testEveryStepAfterTheFirstHasOneBackCommandAboveTheScrollingColumn() throws {
        for language in SupportedAppLanguage.allCases {
            for step in Self.stepsAfterTheFirst {
                let context = "\(step) / \(language)"
                let model = OnboardingFlowModel.preview(step: step)
                XCTAssertEqual(model.step, step, "The fixture must open on \(step)")
                let host = SignUpRenderingProbe.host(container(model, language), width: 393)
                defer { host.detach() }
                let column = try scrollingColumn(host, context)
                let nodes = host.nodes()
                let fixed = fixedCommands(nodes)
                XCTAssertEqual(
                    fixed.count, 1,
                    "\(context): exactly one command must sit outside the scrolling column. Outside it: \(nodes)"
                )
                guard let top = fixed.first else { continue }
                XCTAssertEqual(top.identifier, Self.topIdentifier, context)
                XCTAssertEqual(top.label, spoken(language), context)
                XCTAssertTrue(top.isEnabled, "\(context): \(top)")
                XCTAssertGreaterThanOrEqual(top.frame.width, BodyFlowSpacing.minimumTapTarget, context)
                XCTAssertGreaterThanOrEqual(top.frame.height, BodyFlowSpacing.minimumTapTarget, context)
                XCTAssertGreaterThanOrEqual(top.frame.minX, -0.5, context)
                XCTAssertLessThanOrEqual(top.frame.maxX, 393.5, context)
                XCTAssertGreaterThanOrEqual(top.frame.minY, -0.5, context)
                XCTAssertLessThanOrEqual(
                    top.frame.maxY, column.frame.minY + 0.5,
                    "\(context): the way back must end where the scrolling column begins (\(top) / column \(column.frame))"
                )
            }
        }
    }

    /// The reported screen. "Fixed" is read, not assumed: the column is
    /// scrolled to its end and the command has not moved.
    func testTheBackCommandOfSuaRotinaDoesNotScrollAway() throws {
        let model = OnboardingFlowModel.preview(step: .routine)
        let host = SignUpRenderingProbe.host(container(model), width: 393, height: 800)
        defer { host.detach() }
        let column = try scrollingColumn(host, "Sua rotina")
        let distance = column.scroll.contentSize.height - column.scroll.bounds.height
        XCTAssertGreaterThan(
            distance, BodyFlowSpacing.minimumTapTarget,
            "“Sua rotina” must be longer than the screen for this test to prove anything"
        )
        let before = host.nodes()
        let topBefore = try XCTUnwrap(
            fixedCommands(before).first { $0.identifier == Self.topIdentifier },
            "No way back outside the scrolling column of “Sua rotina”. Outside it: \(before)"
        )

        column.scroll.setContentOffset(CGPoint(x: 0, y: distance), animated: false)
        let after = host.nodes()
        XCTAssertEqual(column.scroll.contentOffset.y, distance, accuracy: 1, "The column did not keep the scroll")
        let topAfter = try XCTUnwrap(
            fixedCommands(after).first { $0.identifier == Self.topIdentifier },
            "The way back left the screen when the column scrolled: \(after)"
        )
        XCTAssertEqual(topAfter.frame.minY, topBefore.frame.minY, accuracy: 0.5)
        XCTAssertEqual(topAfter.frame.minX, topBefore.frame.minX, accuracy: 0.5)
        XCTAssertEqual(topAfter.frame.height, topBefore.frame.height, accuracy: 0.5)
    }

    /// pt-BR and en × 375/393/430 × default and the largest text size: the
    /// command never leaves the width and grows with the text.
    func testTheBackCommandFitsTheWidthAndGrowsWithTheText() throws {
        for language in SupportedAppLanguage.allCases {
            for width: CGFloat in [375, 393, 430] {
                var heights: [DynamicTypeSize: CGFloat] = [:]
                for size in [DynamicTypeSize.large, .accessibility5] {
                    let context = "\(language) / \(Int(width)) / \(size)"
                    let model = OnboardingFlowModel.preview(step: .routine)
                    let host = SignUpRenderingProbe.host(
                        container(model, language), width: width, height: 874, size: size
                    )
                    defer { host.detach() }
                    let column = try scrollingColumn(host, context)
                    let nodes = host.nodes()
                    let top = try XCTUnwrap(
                        fixedCommands(nodes).first { $0.identifier == Self.topIdentifier },
                        "No way back outside the scrolling column (\(context)). Outside it: \(nodes)"
                    )
                    XCTAssertGreaterThanOrEqual(top.frame.minX, -0.5, context)
                    XCTAssertLessThanOrEqual(top.frame.maxX, width + 0.5, context)
                    XCTAssertGreaterThanOrEqual(top.frame.width, BodyFlowSpacing.minimumTapTarget, context)
                    XCTAssertGreaterThanOrEqual(top.frame.height, BodyFlowSpacing.minimumTapTarget, context)
                    XCTAssertLessThanOrEqual(top.frame.maxY, column.frame.minY + 0.5, context)
                    // The column keeps most of the screen even at the
                    // largest text size.
                    XCTAssertGreaterThan(column.frame.height, 874 / 2, context)
                    heights[size] = top.frame.height
                }
                let regular = try XCTUnwrap(heights[.large])
                let largest = try XCTUnwrap(heights[.accessibility5])
                XCTAssertGreaterThan(
                    largest, regular,
                    "\(language) / \(Int(width)): the command must grow at the largest text size"
                )
            }
        }
    }

    /// The command that was already there, below "Continuar", stays in the
    /// column with its one identifier: `BodyFlowUITests` measures that single
    /// element, and `OnboardingBackUITests` finds it on the screen.
    func testTheCommandBelowContinueKeepsItsSingleIdentifier() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("BodyFlow/Features/Onboarding/OnboardingContainerView.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(
            source.components(separatedBy: ".accessibilityIdentifier(\"onboarding.back\")").count - 1, 1
        )
        XCTAssertTrue(source.contains("BodyFlowButtonStyle(role: .secondary)"))
    }

    // MARK: Absences

    func testTheFirstStepHasNoBackCommand() throws {
        let host = SignUpRenderingProbe.host(container(.preview(step: .welcome)), width: 393)
        defer { host.detach() }
        _ = try scrollingColumn(host, "Boas-vindas")
        let nodes = host.nodes()
        XCTAssertTrue(fixedCommands(nodes).isEmpty, "\(nodes)")
    }

    /// A new acceptance of the documents (an account that had already
    /// finished) opens on the documents: its first screen has no way back,
    /// its review has one.
    func testANewAcceptanceHasNoBackOnItsFirstScreenAndOneOnItsReview() async throws {
        let model = OnboardingFlowModel(
            userID: "qa-a", initialDraft: E3Fixtures.draft(step: .consent),
            repository: E3Repository(), personaRepository: E3Persona(),
            developmentConsentAvailability: .unavailable,
            requirements: E3Fixtures.requirements,
            historicalCompletedAt: "2026-10-01T12:00:00Z",
            onStepChanged: { _ in }, onCompleted: {}
        )
        XCTAssertTrue(model.isReacceptance)
        XCTAssertEqual(model.step, .consent)
        // One hosted screen for the whole test: a container that leaves the
        // screen cancels the step change in flight, as it must.
        let host = SignUpRenderingProbe.host(container(model), width: 393)
        defer { host.detach() }
        _ = try scrollingColumn(host, "new acceptance, documents")
        let first = host.nodes()
        XCTAssertTrue(fixedCommands(first).isEmpty, "\(first)")

        await model.continueFromCurrentStep()
        XCTAssertEqual(model.step, .completion)
        let review = host.nodes()
        XCTAssertEqual(
            fixedCommands(review).map(\.identifier), [Self.topIdentifier],
            "The review of a new acceptance leads back to the documents. Outside the column: \(review)"
        )
        await model.back()
        XCTAssertEqual(model.step, .consent)
        XCTAssertTrue(fixedCommands(host.nodes()).isEmpty)
    }

    /// While the answer of "Concluir cadastro" is unknown the draft is
    /// locked: no way back.
    func testAPendingCompletionHasNoBackCommand() async throws {
        let model = await E3Fixtures.model(
            draft: E3Fixtures.draft(step: .completion),
            repository: E3Repository(completionErrors: [.serviceUnavailable])
        )
        XCTAssertEqual(model.step, .completion)
        await model.complete()
        XCTAssertTrue(model.unresolvedCompletion, "The fixture must leave the completion pending")
        let host = SignUpRenderingProbe.host(container(model), width: 393)
        defer { host.detach() }
        _ = try scrollingColumn(host, "pending completion")
        let nodes = host.nodes()
        XCTAssertTrue(fixedCommands(nodes).isEmpty, "\(nodes)")
    }

    /// The entry message is shown after the sign-up was accepted: nothing
    /// leads back into it.
    func testTheEntryMessageHasNoBackCommand() async throws {
        let model = await E3Fixtures.model(
            draft: E3Fixtures.draft(step: .completion),
            repository: E3Repository(welcome: true)
        )
        await model.complete()
        XCTAssertNotNil(model.pendingProtocolWelcome, "The fixture must show the entry message")
        let host = SignUpRenderingProbe.host(container(model), width: 393)
        defer { host.detach() }
        _ = try scrollingColumn(host, "entry message")
        let nodes = host.nodes()
        XCTAssertTrue(fixedCommands(nodes).isEmpty, "\(nodes)")
    }

    // MARK: What going back keeps

    /// The review had no way back at all. Going back from it lands on the
    /// objective with nothing lost and without asking the server again.
    func testBackFromTheReviewReturnsToTheObjectiveWithTheDraftIntact() async {
        let repository = E3Repository()
        let model = await E3Fixtures.model(
            draft: E3Fixtures.draft(step: .completion), repository: repository
        )
        XCTAssertEqual(model.step, .completion)
        XCTAssertNotNil(model.draft.objective, "The fixture must reach the review with an objective")
        var expected = model.draft
        let checksBefore = await repository.inputs.count

        await model.back()

        expected.currentStep = .objective
        XCTAssertEqual(model.step, .objective)
        XCTAssertEqual(model.draft, expected)
        XCTAssertTrue(model.hasCurrentEligibilityDecision)
        let checksAfter = await repository.inputs.count
        XCTAssertEqual(checksAfter, checksBefore, "Going back must not ask for a new decision")
        XCTAssertTrue(model.validationIssues.isEmpty)
    }
}
