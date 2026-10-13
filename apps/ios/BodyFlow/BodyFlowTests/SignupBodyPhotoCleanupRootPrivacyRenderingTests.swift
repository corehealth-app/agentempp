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

#if DEBUG
// Additive Root-autoload test. The existing pixel/Auth tests above are intact.
extension SignupBodyPhotoCleanupRootPrivacyRenderingTests {
    func testAppRootAutoloadsPhotosOncePerFullOwnerAndNilKeepsManualUI() async throws {
        for installsCapability in [true, false] {
            let h = try await PresentationHarness(manual: 24)
            defer { h.clean() }
            let firstGET = XCTestExpectation(description: "Real Root-owned first signup photo GET")
            let nextGET = XCTestExpectation(description: "Real Root-owned fresh-token signup photo GET")
            let events = RootPhotoAutoloadEvents(first: .init(firstGET), next: .init(nextGET))
            let factory = RootPhotoAutoloadCaptureFactory(base: h.scope, events: events)
            let authentication = CleanupRootPrivacyAuthentication() // original private peer, no new Auth factory
            var draft = h.flow.draft
            draft.currentStep = .bodyData
            draft.displayName = "ROOT AUTOLOAD SYNTHETIC QA"
            draft.bodyFatPercent = 24; draft.bodyFatOrigin = .typed
            var freshDraft = draft
            freshDraft.bodyFatPercent = 17
            let initial = OnboardingServerState(locale: "pt-BR",
                completion: .init(completed: false, completedAt: nil),
                requirements: .unavailable, acceptedActions: [], draft: draft)
            let freshState = OnboardingServerState(locale: "pt-BR",
                completion: .init(completed: false, completedAt: nil),
                requirements: .unavailable, acceptedActions: [], draft: freshDraft)
            let repository = CleanupModelReplyRepository(replies: [.success(initial), .success(freshState)])
            var dependencies = AppDependencies.scaffold()
            dependencies.signupBodyPhotoCapture = installsCapability ? factory.capability : nil
            let model = AppFlowModel(authentication: authentication, onboarding: repository,
                persona: dependencies.coachPersona, telemetry: DisabledTelemetryClient(),
                developmentConsentAvailability: .syntheticDevelopment)
            let configuration = AppLaunchConfiguration(mode: .demo, shouldResetDemoState: true,
                startsWithCompletedFixture: false, preloadsSyntheticOnboardingValues: false,
                authBehavior: .succeed(after: nil))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
            let host = RootPhotoAutoloadHostingController(
                rootView: AppRootView(model: model, dependencies: dependencies, configuration: configuration)
                    .environment(\.locale, Locale(identifier: "pt_BR")),
                model: model)
            window.rootViewController = host; window.makeKeyAndVisible()
            defer {
                model.setCleanupActive(false)
                host.view.endEditing(true)
                window.isHidden = true; window.rootViewController = nil
                previousWindow?.makeKey()
            }
            // Only AppRoot's own .task invokes start. No manual start/load.
            await waitForRootManualForm(host, model: model, expectedOwner: h.owner)
            let owner = try XCTUnwrap(model.onboardingOwnerToken)
            XCTAssertEqual(owner.userID, h.owner.userID)
            XCTAssertEqual(model.state, .onboarding(userID: owner.userID, step: .bodyData))
            if installsCapability {
                await waitForRootAutoloadSignal(firstGET)
            }
            let first = await events.snapshot()
            XCTAssertEqual(first.bindings.count, installsCapability ? 1 : 0)
            XCTAssertEqual(first.reads.count, installsCapability ? 1 : 0,
                "A published owner must trigger actual Root autoload, not an explicit test load")
            if installsCapability && (first.bindings.count != 1 || first.reads.count != 1) {
                // A missing autoload is the semantic RED. Finish this case
                // without indexing absent fixture events or waiting again.
                continue
            }
            // Real laid-out native form, without inferring any field's identity
            // from order or value. Focus every field; the UITest owns field-ID taps.
            let fields = host.manualFormFields()
            XCTAssertEqual(fields.count, 3)
            XCTAssertTrue(host.matchesCurrentRestoredForm(fields))
            for field in fields {
                XCTAssertTrue(field.becomeFirstResponder())
                XCTAssertTrue(field.isFirstResponder)
                XCTAssertTrue(field.resignFirstResponder())
            }
            model.updateOnboardingStep(.routine, ownerToken: owner)
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            let unchanged = await events.snapshot()
            XCTAssertEqual(unchanged.bindings, first.bindings)
            XCTAssertEqual(unchanged.reads, first.reads)
            let initialRestoreCount = await authentication.restoreCount
            XCTAssertEqual(initialRestoreCount, 1)
            let initialRepo = await repository.snapshot()
            XCTAssertEqual(initialRepo.stateReads, 1)
            // Actual retry restore gives the same user a new full owner token.
            await model.retryOnboardingRestore()
            let later = try XCTUnwrap(model.onboardingOwnerToken)
            await waitForRootManualForm(host, model: model, expectedOwner: later)
            XCTAssertEqual(later.userID, owner.userID)
            XCTAssertNotEqual(later, owner)
            if installsCapability { await waitForRootAutoloadSignal(nextGET) }
            let finished = await events.snapshot()
            XCTAssertEqual(finished.bindings.count, installsCapability ? 2 : 0)
            XCTAssertEqual(finished.reads.count, installsCapability ? 2 : 0)
            if installsCapability {
                guard finished.bindings.count == 2 else {
                    XCTFail("Fresh full-token capture binding is missing")
                    continue
                }
                XCTAssertNotEqual(finished.bindings[0], finished.bindings[1])
                XCTAssertEqual(finished.reads, finished.bindings,
                    "Each distinct owner binding performs exactly one GET; no old binding is reused")
            }
            let laterFields = host.manualFormFields()
            XCTAssertEqual(laterFields.count, 3)
            XCTAssertTrue(host.matchesCurrentRestoredForm(laterFields),
                "All three native values match the current fresh-token restored draft")
            let laterNumbers = try XCTUnwrap(host.numbers(in: laterFields))
            XCTAssertTrue(laterNumbers.contains(17),
                "The aggregate includes the fresh synthetic value; the old aggregate contains 24")
            let trace = await h.peer.snapshot()
            XCTAssertEqual(trace.count(.state), installsCapability ? 2 : 0)
            XCTAssertTrue(trace.mutationAndStageSteps.isEmpty)
            let repo = await repository.snapshot()
            XCTAssertEqual(repo.stateReads, 2)
            XCTAssertEqual(repo.technicalReads, 0)
            XCTAssertEqual(repo.completionPosts, 0)
            let finalRestoreCount = await authentication.restoreCount
            XCTAssertEqual(finalRestoreCount, 1,
                "Retry restores onboarding; it does not add a synthetic authentication factory")
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        }
    }

    /// XCTNSPredicateExpectation can evaluate away from MainActor. Its
    /// block reads only a lock-protected Bool; UIKit/model sampling hops safely.
    private func waitForRootManualForm<Content: View>(
        _ host: RootPhotoAutoloadHostingController<Content>,
        model: AppFlowModel, expectedOwner: OnboardingOwnerToken
    ) async {
        let condition: @MainActor @Sendable () -> Bool = {
            model.onboardingOwnerToken == expectedOwner
                && host.matchesCurrentRestoredForm(host.manualFormFields())
        }
        let bridge = RootPhotoAutoloadPredicateBridge()
        defer { bridge.close() }
        let predicate = NSPredicate { _, _ in bridge.sample(condition) }
        let form = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let outcome = await XCTWaiter.fulfillment(of: [form], timeout: 5)
        XCTAssertEqual(outcome, .completed, "Actual current-owner native form did not occur")
        // A cached positive sample cannot authorize an obsolete form after await.
        XCTAssertTrue(condition(), "Current full token and all three native values must still match")
    }

    private func waitForRootAutoloadSignal(_ signal: XCTestExpectation) async {
        let outcome = await XCTWaiter.fulfillment(of: [signal], timeout: 5)
        XCTAssertEqual(outcome, .completed, "Actual Root provider/layout event did not occur")
    }
}

/// XCTestExpectation.fulfill is a thread-safe notification. The wrapper is
/// test-only Sendable; signals originate from real provider/layout events.
private final class RootPhotoAutoloadSignal: @unchecked Sendable {
    private let value: XCTestExpectation
    init(_ value: XCTestExpectation) { self.value = value }
    func fire() { value.fulfill() }
}
private struct RootPhotoAutoloadReport: Sendable {
    let bindings: [UUID]
    let reads: [UUID]
}
private actor RootPhotoAutoloadEvents {
    let first: RootPhotoAutoloadSignal
    let next: RootPhotoAutoloadSignal
    private var bindings: [UUID] = [], reads: [UUID] = []
    init(first: RootPhotoAutoloadSignal, next: RootPhotoAutoloadSignal) { self.first = first; self.next = next }
    func bound(_ id: UUID) { bindings.append(id) }
    func read(_ id: UUID) {
        let initialRead = !reads.contains(id)
        reads.append(id)
        guard initialRead else { return }
        if bindings.first == id { first.fire() }
        else if bindings.count >= 2 && bindings[1] == id { next.fire() }
    }
    func snapshot() -> RootPhotoAutoloadReport { .init(bindings: bindings, reads: reads) }
}
/// Capture-only decoration below the real Parent/Core. Same original lease,
/// uploader/staging/registry; every mutation delegates to the existing peer.
private struct RootPhotoAutoloadPhotos: SignupBodyPhotosProviding {
    let base: any SignupBodyPhotosProviding
    let id: UUID
    let events: RootPhotoAutoloadEvents
    func state() async throws -> SignupBodyPhotoState {
        let answer = try await base.state()
        await events.read(id)
        return answer
    }
    func consent(_ a: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt { try await base.consent(a) }
    func create(_ a: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await base.create(a) }
    func complete(_ a: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await base.complete(a) }
    func delete(_ a: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.delete(a) }
    func repair(_ a: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.repair(a) }
}
private actor RootPhotoAutoloadCaptureFactory {
    let base: SignupBodyPhotoCaptureScope
    let events: RootPhotoAutoloadEvents
    init(base: SignupBodyPhotoCaptureScope, events: RootPhotoAutoloadEvents) { self.base = base; self.events = events }
    func bind(_ userID: String) async throws -> SignupBodyPhotoCaptureScope {
        guard userID == base.userID else { throw SessionLifecycleError.sessionSuperseded }
        let id = UUID()
        await events.bound(id)
        return .init(userID: base.userID,
            photos: RootPhotoAutoloadPhotos(base: base.photos, id: id, events: events),
            uploader: base.uploader, staging: base.staging, camera: base.camera,
            validateSession: base.validateSession, stagePhoto: base.stagePhoto,
            performWork: base.performWork, discardStaged: base.discardStaged,
            rememberUnboundCreate: base.rememberUnboundCreate)
    }
    nonisolated var capability: SignupBodyPhotoCaptureCapability {
        .init(scoped: { userID in try await self.bind(userID) })
    }
}
/// Hosts the actual laid-out three-field form. Bounded predicate sampling
/// observes field updates without relying on this controller receiving layout.
/// No native field identity or body-fat-only tap is inferred.
@MainActor
private final class RootPhotoAutoloadHostingController<Content: View>: UIHostingController<Content> {
    private let model: AppFlowModel
    init(rootView: Content, model: AppFlowModel) {
        self.model = model
        super.init(rootView: rootView)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }
    func manualFormFields() -> [UITextField] {
        guard view.window != nil else { return [] }
        var found: [UITextField] = []
        func visit(_ nativeView: UIView) {
            guard !nativeView.isHidden, nativeView.alpha > 0 else { return }
            if let field = nativeView as? UITextField,
               field.window === view.window, !field.bounds.isEmpty {
                found.append(field)
            }
            nativeView.subviews.forEach(visit)
        }
        visit(view)
        return found
    }
    func numbers(in fields: [UITextField]) -> [Double]? {
        let values = fields.compactMap { Self.number($0.text) }
        return values.count == fields.count ? values.sorted() : nil
    }
    func matchesCurrentRestoredForm(_ fields: [UITextField]) -> Bool {
        guard fields.count == 3,
              let token = model.onboardingOwnerToken,
              case .onboarding(let userID, .bodyData) = model.state,
              token.userID == userID,
              let draft = model.restoredOnboardingDraft,
              draft.currentStep == .bodyData,
              let rendered = numbers(in: fields) else { return false }
        let expected = [draft.heightCM, draft.weightKG, draft.bodyFatPercent].compactMap { $0 }.sorted()
        return expected.count == 3 && rendered == expected
    }
    static func number(_ text: String?) -> Double? {
        guard let text else { return nil }
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        return formatter.number(from: text)?.doubleValue
    }
}
/// Test-only cross-executor snapshot. All mutable flags are under the lock;
/// only the explicit MainActor task evaluates the captured UI/model condition.
private final class RootPhotoAutoloadPredicateBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = false
    private var matched = false
    private var closed = false
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
    func close() {
        lock.lock(); closed = true; lock.unlock()
    }
    private func isOpen() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !closed
    }
    private func complete(_ answer: Bool) {
        lock.lock(); defer { lock.unlock() }
        if !closed { matched = answer }
        inFlight = false
    }
}
#endif
