import SwiftUI
import UIKit
import XCTest

@testable import BodyFlow

@MainActor
final class WorkoutStrengthQuestionRenderingTests: XCTestCase {
    func testLocalizedQuestionAndRecoveryCopyExistInBothLanguages() throws {
        for language in SupportedAppLanguage.allCases {
            XCTAssertEqual(try AppLocalization.string("workout.strength.question", for: language),
                           language == .portugueseBrazil ? "Este treino incluiu exercícios de força?" : "Did this workout include strength exercises?")
            for key: String.LocalizationValue in ["workout.strength.saved", "workout.strength.yes", "workout.strength.no",
                "workout.strength.loading", "workout.strength.saving", "workout.strength.retry", "workout.strength.refresh",
                "workout.strength.uncertain", "workout.strength.cancel-hint", "workout.strength.capacity",
                "workout.strength.context-changed", "workout.strength.conflict", "workout.strength.error",
                "workout.strength.read-required", "workout.strength.answer-yes", "workout.strength.answer-no"] {
                XCTAssertFalse(try AppLocalization.string(key, for: language).isEmpty)
            }
        }
    }

    func testDescriptorFeedsNamedDistinctChoicesToTheActualCard() async throws {
        let h = try await harness(.unanswered(Self.question()))
        defer { h.session.close() }
        let d = WorkoutStrengthQuestionDescriptor(presentation: h.presentation, language: .portugueseBrazil)
        XCTAssertFalse(d.isHidden)
        XCTAssertEqual(d.question, "Este treino incluiu exercícios de força?")
        XCTAssertEqual(d.actions.map(\.title), ["Sim, incluiu força", "Não incluiu força"])
        XCTAssertEqual(d.actions.map(\.value), [.answer(.yes), .answer(.no)])
        XCTAssertEqual(d.actions.map(\.id), ["workout.strength.yes", "workout.strength.no"])
        XCTAssertTrue(d.actions.allSatisfy(\.enabled))
        let writes = await h.provider.writes
        XCTAssertEqual(writes, 0)
    }

    func testCachedChoiceIsHiddenUntilThisPresentationFinishesItsRead() async throws {
        let h = try await harness(.unanswered(Self.question()))
        defer { h.session.close() }
        let newer = try h.session.attach(workoutID: Self.id, timeProvider: SystemTimeProvider(),
            keyProvider: RandomIdempotencyKeyProvider(), invalidationCenter: FeatureInvalidationCenter())
        let d = WorkoutStrengthQuestionDescriptor(presentation: newer, language: .portugueseBrazil)
        XCTAssertNil(d.question)
        XCTAssertEqual(d.actions.map(\.value), [.refresh])
        let old = WorkoutStrengthQuestionDescriptor(presentation: h.presentation, language: .portugueseBrazil)
        XCTAssertTrue(old.isHidden)
        XCTAssertTrue(old.actions.isEmpty)
    }

    func testUncertainWriteOffersReadAndOriginalRetryWithoutAnotherYesOrNo() async throws {
        let h = try await harness(.unanswered(Self.question()))
        defer { h.session.close() }
        await h.presentation.answer(.yes)
        XCTAssertNotNil(h.presentation.model.pendingAttempt)
        let d = WorkoutStrengthQuestionDescriptor(presentation: h.presentation, language: .portugueseBrazil)
        XCTAssertNil(d.question)
        XCTAssertEqual(d.actions.map(\.value), [.refresh, .retry])
        XCTAssertTrue(d.actions.allSatisfy(\.enabled))
        let writes = await h.provider.writes
        XCTAssertEqual(writes, 1)
    }

    func testAnsweredNegativeAndDisabledStatesDoNotOfferQuestionActions() async throws {
        for state in [WorkoutStrengthClarification.answered(try Self.receipt(.yes)), .answered(try Self.receipt(.no)),
                      .notApplicable(try Self.question().scope), .unavailable] {
            let h = try await harness(state)
            defer { h.session.close() }
            let d = WorkoutStrengthQuestionDescriptor(presentation: h.presentation, language: .englishUnitedStates)
            XCTAssertTrue(d.actions.isEmpty)
            XCTAssertNil(d.question)
            let size = PremiumRenderingTestSupport.fittingSize(
                WorkoutStrengthQuestionCard(presentation: h.presentation, action: { _ in XCTFail("No action expected") }),
                width: 320, dark: false, size: .large, locale: Locale(identifier: "en_US"))
            if case .answered = state { XCTAssertFalse(d.isHidden); XCTAssertGreaterThan(size.height, 100) }
            else { XCTAssertTrue(d.isHidden); XCTAssertLessThan(size.height, 1) }
        }
        let h = try await harness(.unanswered(Self.question()), readFailure: .disabled)
        defer { h.session.close() }
        XCTAssertTrue(WorkoutStrengthQuestionDescriptor(presentation: h.presentation, language: .portugueseBrazil).isHidden)
        let size = PremiumRenderingTestSupport.fittingSize(
            WorkoutStrengthQuestionCard(presentation: h.presentation, action: { _ in XCTFail("OFF") }),
            width: 320, dark: false, size: .large, locale: Locale(identifier: "pt_BR"))
        XCTAssertLessThan(size.height, 1)
    }

    func testConflictCopyDoesNotInventAnotherPersistedAnswer() throws {
        XCTAssertEqual(try AppLocalization.string("workout.strength.conflict", for: .portugueseBrazil),
                       "A resposta não pôde ser aplicada ao estado atual. Consulte o resultado salvo.")
        XCTAssertEqual(try AppLocalization.string("workout.strength.conflict", for: .englishUnitedStates),
                       "The answer could not be applied to the current state. Check the saved result.")
    }

    func testRealInitiallyEmptyHostStartsExactlyOneGETAndNoPOST() async throws {
        let started = XCTestExpectation(description: "Real strength host .task entered GET")
        let provider = QuestionRenderingProvider(value: .unanswered(try Self.question()), readFailure: nil, started: started)
        let session = WorkoutStrengthQuestionSession(provider: provider, isSessionActive: { true })
        defer { session.close() }
        let configuration = WorkoutStrengthQuestionConfiguration(workoutID: Self.id,
            identity: .init(context: ObjectIdentifier(session), workoutID: Self.id), session: session,
            timeProvider: FixedTimeProvider(value: Date(timeIntervalSince1970: 1_792_500_000)),
            keyProvider: RandomIdempotencyKeyProvider(), invalidationCenter: FeatureInvalidationCenter())
        let host = SignUpRenderingProbe.host(WorkoutStrengthQuestionHost(configuration: configuration), width: 320)
        defer { host.detach() }
        let result = await XCTWaiter.fulfillment(of: [started], timeout: 5)
        XCTAssertEqual(result, .completed, "SETUP_FAIL: real Host did not enter its GET; no UI-liveness claim")
        let reads = await provider.reads
        let writes = await provider.writes
        XCTAssertEqual(reads, [Self.id])
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(session.retainedCount, 1)
        // GET entry proves lifecycle liveness, not AX/clicks or publication readiness.
    }

    func testQuestionFitsBothLanguagesThemesWidthsAndAXXXLAndProducesNativeImages() async throws {
        let h = try await harness(.unanswered(Self.question()))
        defer { h.session.close() }
        for language in SupportedAppLanguage.allCases {
            for dark in [false, true] {
                for size in [DynamicTypeSize.large, .accessibility5] {
                    let view = WorkoutStrengthQuestionCard(presentation: h.presentation, action: { _ in XCTFail("Rendering must not execute actions") })
                    for width in [CGFloat(320), 430] {
                        let measured = PremiumRenderingTestSupport.fittingSize(view, width: width, dark: dark, size: size,
                            locale: language.formattingLocale)
                        XCTAssertEqual(measured.width, width, accuracy: 0.5)
                        XCTAssertGreaterThan(measured.height, 180)
                        XCTAssertLessThan(measured.height, 2_500)
                    }
                    let image = PremiumRenderingTestSupport.nativeImage(view, width: 320, dark: dark, size: size,
                        locale: language.formattingLocale)
                    let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
                    attachment.name = "Strength question \(language.rawValue) \(dark ? "dark" : "light") \(size)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        let writes = await h.provider.writes
        XCTAssertEqual(writes, 0)
    }

    private static let id = "b2800000-0000-4000-8000-000000000001"
    private static func question() throws -> WorkoutStrengthQuestion {
        try XCTUnwrap(WorkoutStrengthQuestion(workoutID: id, lifecycleKey: "c3900000-0000-4000-8000-000000000001",
            factRevision: 0, questionKey: "d4a00000-0000-4000-8000-000000000001"))
    }
    private static func receipt(_ answer: WorkoutStrengthAnswer) throws -> WorkoutStrengthAnswerReceipt {
        let q = try question()
        return try XCTUnwrap(WorkoutStrengthAnswerReceipt(scope: q.scope, questionKey: q.questionKey,
            answer: answer, acceptedAt: "2026-10-21T01:02:03.123456Z"))
    }
    private func harness(_ value: WorkoutStrengthClarification,
                         readFailure: WorkoutStrengthClarificationError? = nil) async throws -> QuestionRenderingHarness {
        let provider = QuestionRenderingProvider(value: value, readFailure: readFailure)
        let session = WorkoutStrengthQuestionSession(provider: provider, isSessionActive: { true })
        let presentation = try session.attach(workoutID: Self.id,
            timeProvider: FixedTimeProvider(value: Date(timeIntervalSince1970: 1_792_500_000)),
            keyProvider: RandomIdempotencyKeyProvider(), invalidationCenter: FeatureInvalidationCenter())
        await presentation.refresh()
        return QuestionRenderingHarness(session: session, presentation: presentation, provider: provider)
    }
}

@MainActor private struct QuestionRenderingHarness {
    let session: WorkoutStrengthQuestionSession
    let presentation: WorkoutStrengthQuestionPresentation
    let provider: QuestionRenderingProvider
}
private actor QuestionRenderingProvider: WorkoutStrengthClarificationProviding {
    let value: WorkoutStrengthClarification
    let readFailure: WorkoutStrengthClarificationError?
    private(set) var writes = 0
    private(set) var reads: [String] = []
    private let started: XCTestExpectation?
    private var signalled = false
    init(value: WorkoutStrengthClarification, readFailure: WorkoutStrengthClarificationError?, started: XCTestExpectation? = nil) {
        self.value = value; self.readFailure = readFailure; self.started = started
    }
    func load(workoutID: String) throws -> WorkoutStrengthClarificationResponse {
        reads.append(workoutID)
        if !signalled { signalled = true; started?.fulfill() }
        if let readFailure { throw readFailure }
        return MobileResponse(data: value, meta: MobileResponseMetadata(apiVersion: "v1", requestID: "synthetic-render"))
    }
    func answer(_ attempt: MutationAttempt<WorkoutStrengthAnswerCommand>) throws -> WorkoutStrengthClarificationResponse {
        writes += 1
        throw BodyFlowCapabilityError.offline
    }
}
