#if DEBUG
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

// Hosts the actual MealRecordDetailView in the native runner in both languages.
// Reads current Form controls; hidden UIKit reuse cells are excluded.
// Authentication, navigation taps and physical accessibility have separate gates.
@MainActor
final class MealRecordAvailabilityRenderingTests: XCTestCase {
    func testOfficialMissingReadShowsContextualBackAndNoMutableControlsInBothLanguages() async throws {
        for language in SupportedAppLanguage.allCases {
            let server = C11L24Fixtures.server()
            let repository = MobileMealRecordRepository(transport: server)
            let held = C11L24HeldReadProvider(base: repository)
            let model = C11L24Fixtures.model(C11L24Fixtures.a, provider: held, keys: C11L24Keys())
            await model.load()
            model.draft?.items[0].quantityText = "25"
            let external = C11L24Fixtures.model(C11L24Fixtures.a, provider: repository)
            await external.load()
            await external.delete()
            XCTAssertNotNil(external.confirmedReceipt)
            await model.save(language: .englishUnitedStates)
            let attempt = try XCTUnwrap(model.retainedAttempt)
            let typed = try XCTUnwrap(model.draft)
            await model.load()
            XCTAssertEqual(model.readFailure, .notFound)
            let mutations = await server.mutationCount
            let viewReadStarted = XCTestExpectation(description: "Missing-record View-owned GET entered provider")
            await held.holdNextRead(signal: C11L24Signal(viewReadStarted))
            let host = SignUpRenderingProbe.host(
                MealRecordDetailView(model: model, localRow: C11L24Fixtures.localRow)
                    .environment(\.locale, language.formattingLocale),
                width: 393, height: 3_000)
            defer { host.detach() }
            let viewReadOutcome = await XCTWaiter.fulfillment(of: [viewReadStarted], timeout: 5)
            guard viewReadOutcome == .completed, model.isLoading else {
                await held.releaseRead()
                XCTFail("SETUP_NOT_RED: actual missing-record View-owned GET did not remain pending")
                throw C11L24RenderingSetupError.viewReadDidNotStart
            }
            await held.releaseRead()
            try await waitForMissingOfficialRead(model)
            let nodes = try renderedFormNodes(host)
            // Catalog/host prerequisites, separate from the causal assertions.
            let expectedMessage = language == .portugueseBrazil
                ? "Este registro não foi encontrado." : "This record was not found."
            XCTAssertEqual(MealRecordCopy.string("confirmed-meal.failure.not-found", language: language), expectedMessage,
                           "Missing catalog is SETUP_NOT_RED, not evidence about the unavailable-record behavior")
            XCTAssertTrue(nodes.contains { $0.label.contains("Synthetic item A") },
                          "The actual existing official rows must be drawn by this real Form")
            XCTAssertEqual(model.readFailure, .notFound,
                           "The View's own .task must finish its actual repeated GET before interpreting nodes")
            XCTAssertEqual(nodes.filter { $0.identifier == "meal-record.unavailable" }.count, 1)
            let back = nodes.filter { $0.identifier == "meal-record.back" }
            XCTAssertEqual(back.count, 1)
            XCTAssertTrue(back.first?.isButton == true && back.first?.isEnabled == true)
            XCTAssertTrue(nodes.contains { $0.label.contains(expectedMessage) })
            for hidden in ["meal-record.field.name", "meal-record.field.quantity", "meal-record.field.kcal",
                           "meal-record.patch", "meal-record.delete", "meal-record.load-current",
                           "meal-record.review-current", "meal-record.retry-read"] {
                XCTAssertFalse(nodes.contains { $0.identifier == hidden },
                               "Missing original record must not offer an editable form or a repeating recovery loop: \(hidden)")
            }
            XCTAssertEqual(model.draft, typed)
            XCTAssertEqual(model.retainedAttempt, attempt)
            let afterRenderMutations = await server.mutationCount
            XCTAssertEqual(afterRenderMutations, mutations)
            // This test verifies the real rendered button, not an actual
            // navigation tap. Back/dismiss -> History is a separate live UI gate.
        }
    }

    func testActualReviewButtonIsDisabledDuringHeldOfficialGETAndEnabledAfterItsSuccess() async throws {
        for language in SupportedAppLanguage.allCases {
            let server = C11L24Fixtures.server()
            let repository = MobileMealRecordRepository(transport: server)
            let held = C11L24HeldReadProvider(base: repository)
            let model = C11L24Fixtures.model(C11L24Fixtures.a, provider: held, keys: C11L24Keys())
            await model.load()
            model.draft?.items[0].quantityText = "25"
            let typed = try XCTUnwrap(model.draft)
            let sibling = C11L24Fixtures.model(C11L24Fixtures.b, provider: repository,
                                            keys: C11L24Keys(prefix: "external-b"))
            await sibling.load()
            sibling.draft?.items[1].quantityText = "55"
            await sibling.save(language: .englishUnitedStates)
            XCTAssertNotNil(sibling.confirmedReceipt)
            await model.save(language: .englishUnitedStates)
            XCTAssertEqual(model.failure, .versionChanged)
            let attempt = try XCTUnwrap(model.retainedAttempt)
            let started = XCTestExpectation(description: "Actual View-owned GET reached controlled provider")
            await held.holdNextRead(signal: C11L24Signal(started))
            let host = SignUpRenderingProbe.host(
                MealRecordDetailView(model: model, localRow: C11L24Fixtures.localRow)
                    .environment(\.locale, language.formattingLocale),
                width: 393, height: 3_000)
            defer { host.detach() }
            do {
                let outcome = await XCTWaiter.fulfillment(of: [started], timeout: 5)
                XCTAssertEqual(outcome, .completed)
                XCTAssertTrue(model.isLoading, "A real pending GET is required before reading disabled traits")
                guard outcome == .completed, model.isLoading else {
                    throw C11L24RenderingSetupError.viewReadDidNotStart
                }
                let pending = try renderedFormNodes(host)
                let review = try XCTUnwrap(pending.first { $0.identifier == "meal-record.review-current" },
                                          "If this real Form's existing button cannot be read, classify SETUP_NOT_RED")
                XCTAssertTrue(review.isButton)
                XCTAssertFalse(review.isEnabled,
                               "Causal L4 assertion: the actual old View exposes this button as enabled")
                XCTAssertEqual(model.draft, typed)
                XCTAssertEqual(model.retainedAttempt, attempt)
                let mutations = await server.mutationCount
                await held.releaseRead()
                await waitForCurrentOfficialRead(model, replacing: typed.expectedVersion)
                let ready = try renderedFormNodes(host)
                let enabled = try XCTUnwrap(ready.first { $0.identifier == "meal-record.review-current" })
                XCTAssertTrue(enabled.isButton && enabled.isEnabled)
                XCTAssertEqual(model.retainedAttempt, attempt,
                               "Successful read alone never clears a declined command or silently reviews typed fields")
                XCTAssertEqual(model.draft, typed)
                let afterReadMutations = await server.mutationCount
                XCTAssertEqual(afterReadMutations, mutations)
                model.reviewLatest()
                XCTAssertEqual(model.archivedDraft, typed)
                XCTAssertNil(model.retainedAttempt)
                XCTAssertNil(model.failure)
            } catch {
                await held.releaseRead()
                throw error
            }
        }
    }

    /// The Form retains old UIKit cells after its rows change. The broad
    /// sign-up probe walks those hidden cells too; this screen's observer
    /// walks the real Form while respecting UIKit visibility and AX hiding.
    private func renderedFormNodes(_ host: SignUpRenderingProbe.Host) throws -> [SignUpRenderingProbe.Node] {
        _ = host.nodes() // Same native layout/AX preparation as the existing probe.
        let form = try XCTUnwrap(host.scrollViews().first {
            $0 is UICollectionView || $0 is UITableView
        }, "SETUP_NOT_RED: actual Form list must be hosted before reading its current controls")
        return C11L24RenderedFormProbe.nodes(in: form)
    }

    private func waitForMissingOfficialRead(_ model: MealRecordModel) async throws {
        let current: @MainActor @Sendable () -> Bool = {
            !model.isLoading && model.readFailure == .notFound
        }
        let bridge = C11L24PredicateBridge()
        defer { bridge.close() }
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in bridge.sample(current) }, object: nil)
        let outcome = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(outcome, .completed, "SETUP_NOT_RED: View-owned missing-record GET did not settle")
        XCTAssertTrue(current(), "SETUP_NOT_RED: cached predicate result cannot authorize stale render state")
        guard outcome == .completed, current() else {
            throw C11L24RenderingSetupError.viewReadDidNotSettle
        }
    }

    private func waitForCurrentOfficialRead(_ model: MealRecordModel, replacing oldVersion: String) async {
        let current: @MainActor @Sendable () -> Bool = {
            !model.isLoading && model.readFailure == nil
                && model.detail?.data.expectedVersion != nil
                && model.detail?.data.expectedVersion != oldVersion
        }
        let bridge = C11L24PredicateBridge()
        defer { bridge.close() }
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in bridge.sample(current) }, object: nil)
        let outcome = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(outcome, .completed, "Current official View-owned GET did not publish")
        XCTAssertTrue(current(), "A cached predicate result does not authorize obsolete model state")
    }
}

private enum C11L24RenderingSetupError: Error { case viewReadDidNotStart, viewReadDidNotSettle }

private final class C11L24Signal: @unchecked Sendable {
    private let expectation: XCTestExpectation
    init(_ expectation: XCTestExpectation) { self.expectation = expectation }
    func fire() { expectation.fulfill() }
}
private actor C11L24HeldReadProvider: MealRecordProviding {
    let base: any MealRecordProviding
    private var signal: C11L24Signal?
    private var continuation: CheckedContinuation<Void, Never>?
    private var releaseRequested = false
    init(base: any MealRecordProviding) { self.base = base }
    func holdNextRead(signal: C11L24Signal) { self.signal = signal; releaseRequested = false }
    func releaseRead() { releaseRequested = true; continuation?.resume(); continuation = nil }
    func mealRecord(id: String) async throws -> MealRecordResponse {
        if let signal {
            self.signal = nil
            if releaseRequested {
                signal.fire()
            } else {
                await withCheckedContinuation { value in
                    continuation = value
                    signal.fire()
                }
            }
        }
        return try await base.mealRecord(id: id)
    }
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        try await base.patch(attempt)
    }
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        try await base.delete(attempt)
    }
}
/// Same bounded cross-executor observation recipe as the existing Root
/// rendering tests. Only MainActor evaluates UIKit/model conditions.
private final class C11L24PredicateBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = false, matched = false, closed = false
    func sample(_ condition: @escaping @MainActor @Sendable () -> Bool) -> Bool {
        lock.lock()
        let answer = matched
        let schedule = !closed && !inFlight && !matched
        if schedule { inFlight = true }
        lock.unlock()
        if schedule {
            Task { @MainActor [weak self] in
                guard let self, self.isOpen() else { return }
                self.complete(condition())
            }
        }
        return answer
    }
    func close() { lock.lock(); closed = true; lock.unlock() }
    private func isOpen() -> Bool { lock.lock(); defer { lock.unlock() }; return !closed }
    private func complete(_ answer: Bool) {
        lock.lock(); defer { lock.unlock() }
        if !closed { matched = answer }
        inFlight = false
    }
}

/// Read the actual Form, excluding hidden reused cells and AX-hidden branches.
/// There is no filter for expected identifiers, disabled controls, text or frames.
@MainActor
private enum C11L24RenderedFormProbe {
    static func nodes(in root: UIView) -> [SignUpRenderingProbe.Node] {
        var result: [SignUpRenderingProbe.Node] = []
        var visited: Set<ObjectIdentifier> = []
        let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
        func collect(_ object: NSObject, depth: Int = 0) {
            guard depth < 48, visited.insert(ObjectIdentifier(object)).inserted else { return }
            if let view = object as? UIView,
               view.isHidden || view.alpha <= 0.01 || view.accessibilityElementsHidden { return }
            var identifier = ""
            if object.responds(to: identifierSelector),
               let value = object.perform(identifierSelector)?.takeUnretainedValue() as? String {
                identifier = value
            }
            if object.isAccessibilityElement || !identifier.isEmpty {
                let traits = object.accessibilityTraits
                result.append(SignUpRenderingProbe.Node(
                    identifier: identifier, isElement: object.isAccessibilityElement,
                    label: object.accessibilityLabel ?? "", hint: object.accessibilityHint ?? "",
                    isButton: traits.contains(.button), isSelected: traits.contains(.selected),
                    isEnabled: !traits.contains(.notEnabled), frame: object.accessibilityFrame
                ))
            }
            if let elements = object.accessibilityElements {
                for case let element as NSObject in elements { collect(element, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count > 0 && count < 2_000 {
                    for index in 0..<count {
                        if let element = object.accessibilityElement(at: index) as? NSObject {
                            collect(element, depth: depth + 1)
                        }
                    }
                }
            }
            if let view = object as? UIView {
                view.subviews.forEach { collect($0, depth: depth + 1) }
            }
        }
        collect(root)
        return result
    }
}
#endif
