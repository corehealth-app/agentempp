#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// Actual view wiring. No estimation, camera, producer or legal fallback.
@MainActor
final class SignupBodyPhotoFormWiringRenderingTests: XCTestCase {
    func testFractionalManualFieldsUseTheViewLanguageForTheirActualText() async throws {
        for language in SupportedAppLanguage.allCases {
            let h = try await PresentationHarness(manual: 24)
            defer { h.clean() }
            h.flow.updateWeightKG(83.5)
            let live = PremiumRenderingTestSupport.liveAccessibilityHost(
                BodyDataStepView(model: h.flow)
                    .environment(\.locale, language.formattingLocale), width: 393)
            defer { live.detach() }
            let fields = live.nativeViews(UITextField.self)
            XCTAssertEqual(fields.count, 3)
            let actual = fields.compactMap(\.text).sorted()
            let values = [h.flow.draft.heightCM, h.flow.draft.weightKG,
                h.flow.draft.bodyFatPercent].compactMap { $0 }
            XCTAssertEqual(values.count, 3)
            let expected = values.map {
                $0.formatted(.number.locale(language.formattingLocale)
                    .precision(.fractionLength(0...2)))
            }.sorted()
            XCTAssertEqual(actual, expected, "Numeric text must use \(language), including 83.5")
            let trace = await h.peer.snapshot()
            XCTAssertTrue(trace.calls.isEmpty)
        }
    }

    func testBodyDataUsesTheRetainedParentForChoicesAndUnavailableFallback() async throws {
        for available in [true, false] {
            let h = try await PresentationHarness(manual: 24, installsCapability: available)
            defer { h.clean() }
            await h.model.load()
            let core = h.model.capture
            for language in SupportedAppLanguage.allCases {
                let view = BodyDataStepView(model: h.flow, photos: h.model)
                    .environment(\.locale, language.formattingLocale)
                let host = SignUpRenderingProbe.host(view, width: 393, height: 3_000)
                defer { host.detach() }
                let nodes = host.nodes()
                let ids = ["onboarding.body-fat.choice.photos", "onboarding.body-fat.choice.typed", "onboarding.body-fat.choice.skip"]
                let rows = try ids.map { id in try XCTUnwrap(nodes.first { $0.identifier == id },
                    "BodyData must forward its retained photos parent: \(id)") }
                XCTAssertEqual(rows.map(\.label), language == .portugueseBrazil
                    ? ["Estimar por fotos", "Já sei meu percentual", "Agora não"]
                    : ["Estimate from photos", "I know my percentage", "Not now"])
                XCTAssertEqual(rows.map(\.frame.minY), rows.map(\.frame.minY).sorted())
                XCTAssertEqual(rows[0].isEnabled, available)
                XCTAssertTrue(rows[1].isEnabled && rows[2].isEnabled && rows[1].isSelected)
                for row in rows { XCTAssertGreaterThanOrEqual(row.frame.height, 44) }
                // This in-process AX walk does not expose SwiftUI numeric
                // field identifiers. Verify the entire native projection;
                // the UI test separately exercises each field by its ID.
                let live = PremiumRenderingTestSupport.liveAccessibilityHost(view, width: 393)
                defer { live.detach() }
                let fields = live.nativeViews(UITextField.self)
                XCTAssertEqual(fields.count, 3, "All existing numeric fields remain")
                let formatter = NumberFormatter()
                formatter.locale = language.formattingLocale
                formatter.numberStyle = .decimal
                let actualValues = fields.compactMap { field in
                    field.text.flatMap { formatter.number(from: $0)?.doubleValue }
                }.sorted()
                let expectedValues = [h.flow.draft.heightCM, h.flow.draft.weightKG,
                    h.flow.draft.bodyFatPercent].compactMap { $0 }.sorted()
                XCTAssertEqual(actualValues.count, 3)
                XCTAssertEqual(expectedValues.count, 3)
                XCTAssertEqual(actualValues, expectedValues,
                    "No field is assigned an identity by its order or value")
                h.flow.updateWeightKG(83.5)
                _ = host.nodes() // same host, ordinary observation update
                XCTAssertTrue(h.model.capture === core)
                XCTAssertEqual(h.flow.draft.bodyFatPercent, 24)
                XCTAssertEqual(h.flow.draft.bodyFatOrigin, .typed)
            }
            let factory = await h.factory.snapshot(), trace = await h.peer.snapshot()
            XCTAssertEqual(factory, available ? [h.owner.userID] : [])
            XCTAssertEqual(trace.count(.state), available ? 1 : 0)
            XCTAssertTrue(trace.mutationAndStageSteps.isEmpty)
        }
    }

    func testContainerKeepsOneStackAndColumnWithoutLoadingTheParentAgain() async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load()
        let core = try XCTUnwrap(h.model.capture)
        let before = await h.peer.snapshot()
        XCTAssertEqual(before.count(.state), 1, "One explicit load is the fixture prerequisite")
        let live = PremiumRenderingTestSupport.liveAccessibilityHost(
            OnboardingContainerView(model: h.flow, photos: h.model)
                .environment(\.locale, SupportedAppLanguage.portugueseBrazil.formattingLocale), width: 393)
        defer { live.detach() }
        let initialControllers = Self.navigationControllers(in: live.nativeViews(UIView.self))
        XCTAssertEqual(initialControllers.count, 1,
            "The signup container must keep one actual native navigation controller")
        let navigation = try XCTUnwrap(initialControllers.first)
        XCTAssertEqual(navigation.viewControllers.count, 1,
            "The one controller contains one signup stack root")
        XCTAssertEqual(live.nativeViews(UIScrollView.self).count, 1,
            "One scrolling column; no nested body form or photos stack")
        h.flow.updateHeightCM(179.5)
        h.model.select(.photos)
        h.model.select(.typed)
        live.settle()
        XCTAssertTrue(h.model.capture === core && core.isActive)
        XCTAssertEqual(h.flow.draft.heightCM, 179.5)
        XCTAssertEqual(h.flow.draft.bodyFatPercent, 24)
        let updatedControllers = Self.navigationControllers(in: live.nativeViews(UIView.self))
        XCTAssertEqual(updatedControllers.count, 1)
        XCTAssertTrue(updatedControllers.first === navigation,
            "Changing mode and fields retains the same actual navigation controller")
        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertEqual(live.nativeViews(UIScrollView.self).count, 1)
        let trace = await h.peer.snapshot(), factory = await h.factory.snapshot()
        XCTAssertEqual(trace.count(.state), before.count(.state),
            "Container appearance, mode and field changes do not trigger another GET")
        XCTAssertEqual(factory, [h.owner.userID])
        XCTAssertTrue(trace.mutationAndStageSteps.isEmpty)
    }

    func testConsentRouteUsesCurrentParentDocumentAndStopsAfterConsentOrOwnerChange() async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos)
        let core = try XCTUnwrap(h.model.capture), document = try XCTUnwrap(h.model.capture?.state?.consent)
        XCTAssertEqual(h.model.route, .consent)
        for language in SupportedAppLanguage.allCases {
            let nodes = SignUpRenderingProbe.nodes(
                SignupBodyPhotoConsentRouteView(photos: h.model)
                    .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
            let body = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.consent.body" })
            XCTAssertEqual(body.label, document.body, "Caller must pass current server body verbatim")
            let accept = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.consent.accept" })
            let decline = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.consent.decline" })
            XCTAssertTrue(accept.isEnabled && decline.isEnabled)
            XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.result.confirm" })
        }
        // Consent uses the actual existing method, not a fake response or BF apply.
        await h.model.acceptConsent()
        XCTAssertTrue(core.hasAcceptedConsent)
        XCTAssertEqual(h.flow.draft.bodyFatPercent, 24)
        XCTAssertEqual(h.flow.draft.bodyFatOrigin, .typed)
        XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
        let accepted = SignUpRenderingProbe.nodes(SignupBodyPhotoConsentRouteView(photos: h.model),
            width: 393, height: 3_000)
        XCTAssertFalse(accepted.contains { $0.identifier == "onboarding.photos.consent.body" },
            "The consent route must follow Parent.route, not retain an old document screen")
        h.ownerBox.current = .init(userID: h.owner.userID, restoreGeneration: 2)
        let obsolete = SignUpRenderingProbe.nodes(SignupBodyPhotoConsentRouteView(photos: h.model),
            width: 393, height: 3_000)
        XCTAssertFalse(obsolete.contains { $0.identifier.hasPrefix("onboarding.photos.consent.") })
        let trace = await h.peer.snapshot()
        XCTAssertEqual(trace.consents.count, 1)
        XCTAssertEqual(trace.consents.first?.payload.version, document.version)
        XCTAssertEqual(trace.consents.first?.payload.bodyHash, document.bodyHash)
        XCTAssertEqual(trace.count(.stage), 0)
        XCTAssertEqual(trace.count(.create), 0)
        XCTAssertEqual(trace.count(.put), 0)
        XCTAssertEqual(trace.count(.complete), 0)
        XCTAssertEqual(trace.count(.delete), 0)
        XCTAssertEqual(trace.count(.repair), 0)
    }
    /// Real responder/containment objects under this hosted view. A hidden
    /// navigation bar is not a count of NavigationStacks. No private class names.
    private static func navigationControllers(in inspectedViews: [UIView]) -> [UINavigationController] {
        let inspectedIDs = Set(inspectedViews.map { ObjectIdentifier($0) })
        var seenControllers: Set<ObjectIdentifier> = []
        var found: [UINavigationController] = []
        func collect(_ controller: UIViewController) {
            guard seenControllers.insert(ObjectIdentifier(controller)).inserted else { return }
            if let navigation = controller as? UINavigationController,
               let nativeView = navigation.viewIfLoaded,
               inspectedIDs.contains(ObjectIdentifier(nativeView)), nativeView.window != nil {
                found.append(navigation)
            }
            controller.children.forEach(collect)
        }
        for nativeView in inspectedViews {
            var responder: UIResponder? = nativeView
            var visited: Set<ObjectIdentifier> = []
            while let current = responder,
                  visited.insert(ObjectIdentifier(current)).inserted {
                if let controller = current as? UIViewController { collect(controller) }
                responder = current.next
            }
        }
        return found
    }
}
#endif
