#if DEBUG
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class SignupBodyPhotoCleanupRootPrivacyRenderingTests: XCTestCase {
    func testFreshSameAccountBindDoesNotFadeOutPreviousOnboarding() async throws {
        try await assertNoPreviousOnboardingDuringHeldBind(nextUserID: CleanupProcessorHarness.a)
    }

    func testFreshDifferentAccountBindDoesNotFadeOutPreviousOnboarding() async throws {
        try await assertNoPreviousOnboardingDuringHeldBind(nextUserID: CleanupProcessorHarness.b)
    }

    private func assertNoPreviousOnboardingDuringHeldBind(nextUserID: String) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let authentication = CleanupRootPrivacyAuthentication()
        let factory = CleanupRootPrivacyBindingFactory(scope: h.scope)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome)
        draft.displayName = "SYNTHETIC ONBOARDING OWNER A"
        let initial = OnboardingServerState(locale: "pt-BR",
            completion: .init(completed: false, completedAt: nil),
            requirements: .unavailable, acceptedActions: [], draft: draft)
        let repository = CleanupModelReplyRepository(replies: [.success(initial)])
        let dependencies = AppDependencies.scaffold()
        let model = AppFlowModel(authentication: authentication, onboarding: repository,
            persona: dependencies.coachPersona, telemetry: DisabledTelemetryClient(),
            signupBodyPhotoCleanup: factory.capability)
        let configuration = AppLaunchConfiguration(mode: .demo, shouldResetDemoState: true,
            startsWithCompletedFixture: false, preloadsSyntheticOnboardingValues: false,
            authBehavior: .succeed(after: nil))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        let host = UIHostingController(rootView: AppRootView(model: model,
            dependencies: dependencies, configuration: configuration)
            .environment(\.locale, Locale(identifier: "pt_BR")))
        XCTAssertFalse(UIAccessibility.isReduceMotionEnabled,
            "This regression must exercise an animated onboarding exit")
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            model.setCleanupActive(false)
            window.isHidden = true
            window.rootViewController = nil
            originalKeyWindow?.makeKey()
        }

        // AppRoot's own task performs the only initial restore. No manual
        // start before hosting, which would consume the held second bind.
        for _ in 0..<100 where model.onboardingOwnerToken == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let oldOnboarding = try XCTUnwrap(model.onboardingOwnerToken)
        let oldActivation = try XCTUnwrap(model.cleanupOwnerToken)
        XCTAssertEqual(oldOnboarding.userID, CleanupProcessorHarness.a)
        XCTAssertEqual(model.state, .onboarding(userID: CleanupProcessorHarness.a, step: .welcome))
        let initialSource = await repository.snapshot()
        XCTAssertEqual(initialSource.stateReads, 1)
        let initialRestoreCount = await authentication.restoreCount
        XCTAssertEqual(initialRestoreCount, 1)
        let initialBinds = await factory.snapshot()
        XCTAssertEqual(initialBinds, [CleanupProcessorHarness.a])

        // Reuse the committed Shell regression's CG-pixel sentinel: x=16
        // is outside the centered brand, y=400 is the ordinary content area.
        // Warm onboarding differs from deep-teal neutral (0,59,59).
        var before = (0, 59, 59)
        for _ in 0..<50 {
            host.view.layoutIfNeeded()
            before = try Self.pixel(in: host.view, x: 16, y: 400)
            if Self.distance(before, from: (0, 59, 59)) > 30 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(450))
        host.view.layoutIfNeeded()
        before = try Self.pixel(in: host.view, x: 16, y: 400)
        XCTAssertGreaterThan(Self.distance(before, from: (0, 59, 59)), 30,
            "Test must begin with A's onboarding visible, not neutral loading: \(before)")
        XCTAssertEqual(model.onboardingOwnerToken, oldOnboarding)

        await authentication.setRestoredUserID(nextUserID)
        let barrier = factory.secondBindBarrier
        let fresh = Task { await model.start(); await barrier.operationFinished() }
        let entered = await barrier.entryOrOperationEnd()
        guard entered else {
            await barrier.release(); await fresh.value
            XCTFail("The actual fresh restore did not reach the held second bind")
            return
        }
        do {
            let newActivation = try XCTUnwrap(model.cleanupOwnerToken)
            XCTAssertEqual(newActivation.userID, nextUserID)
            XCTAssertNotEqual(newActivation.activationID, oldActivation.activationID)
            XCTAssertNil(model.onboardingOwnerToken)
            // State and draft are deliberately still A until authoritative
            // restore resolves: render ownership, not fake new data, hides A.
            XCTAssertEqual(model.state, .onboarding(userID: CleanupProcessorHarness.a, step: .welcome))
            let heldSource = await repository.snapshot()
            XCTAssertEqual(heldSource.stateReads, 1)
            try await Task.sleep(for: .milliseconds(20))
            host.view.layoutIfNeeded()
            let firstNeutralFrame = try Self.pixel(in: host.view, x: 16, y: 400)
            XCTAssertLessThanOrEqual(Self.distance(firstNeutralFrame, from: (0, 59, 59)), 6,
                "A's onboarding must not fade over neutral loading during held \(nextUserID == CleanupProcessorHarness.a ? "same-account" : "different-account") bind: \(firstNeutralFrame)")
            let heldBinds = await factory.snapshot()
            XCTAssertEqual(heldBinds, [CleanupProcessorHarness.a, nextUserID])
            let source = await repository.snapshot()
            XCTAssertEqual(source.stateReads, 1)
            XCTAssertEqual(source.technicalReads, 0)
            XCTAssertEqual(source.completionPosts, 0)
            let peer = await h.peer.snapshot()
            XCTAssertTrue(peer.reads.isEmpty && peer.repairs.isEmpty)
            try await h.lifecycle.validate(h.lease)
            // We intentionally do not install a B scope or publish an ACK.
            // Cancel before release: only pixels while binding are under test.
            fresh.cancel()
            await barrier.release(); await fresh.value
        } catch {
            fresh.cancel()
            await barrier.release(); await fresh.value
            throw error
        }
    }

    private static func pixel(in view: UIView, x: Int, y: Int) throws -> (Int, Int, Int) {
        let image = UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        var bytes = [UInt8](repeating: 0, count: width * cgImage.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width,
            height: cgImage.height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: cgImage.height))
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    private static func distance(_ pixel: (Int, Int, Int), from expected: (Int, Int, Int)) -> Int {
        max(abs(pixel.0 - expected.0), abs(pixel.1 - expected.1), abs(pixel.2 - expected.2))
    }
}

// Explicitly synthetic Auth peer; no token/credential or real lifecycle switch.
private actor CleanupRootPrivacyAuthentication: AuthenticationService {
    private(set) var restoreCount = 0
    private var restoredUserID = CleanupProcessorHarness.a
    func setRestoredUserID(_ userID: String) { restoredUserID = userID }
    func restoreSession() async throws -> AuthSession? {
        restoreCount += 1
        return .init(userID: restoredUserID, email: "synthetic@example.invalid",
            isEmailConfirmed: true, isOnboardingCompleted: false)
    }
    func signIn(email: String, password: String) async throws -> AuthSession { throw AuthenticationError.operationUnavailable }
    func signUp(email: String, password: String) async throws -> AuthSignUpResult { throw AuthenticationError.operationUnavailable }
    func confirmEmailForDevelopment() async throws -> AuthSession { throw AuthenticationError.operationUnavailable }
    func requestPasswordRecovery(email: String) async throws { throw AuthenticationError.operationUnavailable }
    func signOut() async throws {}
}

// First activation uses the real store/gate scope. The second factory ignores
// cancellation while held. Returning A after cancellation is intentional: no
// B scope/metadata is installed or used; render is inspected before release.
private actor CleanupRootPrivacyBindingFactory {
    let secondBindBarrier = CleanupProcessorBarrier(holds: true)
    private let scope: SignupBodyPhotoCleanupScope
    private var users: [String] = []
    init(scope: SignupBodyPhotoCleanupScope) { self.scope = scope }
    func bind(_ userID: String) async throws -> SignupBodyPhotoCleanupScope {
        users.append(userID)
        let captured = scope
        if users.count == 2 { await secondBindBarrier.enter() }
        return captured
    }
    func snapshot() -> [String] { users }
    nonisolated var capability: SignupBodyPhotoCleanupCapability {
        .init { userID in try await self.bind(userID) }
    }
}
#endif
