import Foundation
import Testing

@testable import BodyFlow

/// Package A4 (decision D6 of the orchestrator, announced to the owner on
/// 2026-10-10/11, who can strike it): the unfinished sign-up of a real
/// account is kept on the phone, so that leaving the app in the middle does
/// not lose what was typed.
///
/// Until this change the sign-up of a real account kept nothing anywhere
/// (`MobileOnboardingRepository.saveDraft` is empty on purpose and the
/// server only has a draft after the sign-up is finished): a person whose
/// app was ended in the middle came back to "Boas-vindas", blank.
@MainActor
@Suite("Sign-up draft kept on the phone")
struct OnboardingDeviceDraftTests {
    private static let account = "8d0c0c0e-6f1d-4d57-9f0a-000000000a11"
    private static let otherAccount = "8d0c0c0e-6f1d-4d57-9f0a-000000000b22"
    private static let zone = "America/Sao_Paulo"

    // MARK: The scenario

    @Test("filling Boas-vindas and Dados corporais and advancing is still there after a cold start")
    func whatWasFilledSurvivesAColdStart() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let firstTransport = DraftTransportSpy()
        let model = Self.model(Self.blankDraft, repository: try await Self.repository(firstTransport, folder))

        model.updateDisplayName("Pessoa QA")
        await model.continueFromCurrentStep()
        #expect(model.step == .bodyData)
        let birth = try #require(OnboardingCivilDate.date(from: "1982-03-04", timeZoneIdentifier: Self.zone))
        model.updateBiologicalSex(.masculine)
        model.updateBirthDate(birth)
        model.updateHeightCM(180)
        model.updateWeightKG(81)
        await model.continueFromCurrentStep()
        #expect(model.step == .routine)

        // A cold start: nothing of the first run is in memory.
        let secondTransport = DraftTransportSpy()
        let reopened = try await Self.repository(secondTransport, folder)
        let state = try await reopened.loadState(for: Self.account)

        let draft = try #require(state.draft, "Nothing of the sign-up came back")
        #expect(draft.displayName == "Pessoa QA")
        #expect(draft.biologicalSex == .masculine)
        #expect(draft.birthDate == birth)
        #expect(draft.heightCM == 180)
        #expect(draft.weightKG == 81)
        #expect(draft.currentStep == .routine)
        #expect(!state.completion.completed)
        // Nothing of it was sent: the only request of either run is the read.
        #expect(await firstTransport.requests.isEmpty)
        #expect(await secondTransport.requests.map(\.method) == [.get])
        #expect(await secondTransport.requests.allSatisfy { $0.body == nil })
    }

    @Test("what was typed in the current step is kept when the person leaves the app, before any Continuar")
    func leavingTheAppKeepsTheStepBeingFilled() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        var start = Self.blankDraft
        start.displayName = "Pessoa QA"
        start.currentStep = .bodyData
        let model = Self.model(start, repository: try await Self.repository(DraftTransportSpy(), folder))
        model.updateBiologicalSex(.feminine)
        model.updateHeightCM(170)
        model.updateWeightKG(65)

        await model.keepDraftOnDevice()

        let draft = try #require(
            try await Self.repository(DraftTransportSpy(), folder).loadState(for: Self.account).draft,
            "Leaving the app in the middle of a step kept nothing"
        )
        #expect(draft.currentStep == .bodyData)
        #expect(draft.biologicalSex == .feminine)
        #expect(draft.heightCM == 170)
        #expect(draft.weightKG == 65)
        #expect(draft.birthDate == nil)
    }

    @Test("going back is kept too: the sign-up reopens on the step the person was on")
    func goingBackIsKept() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        var start = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        start.consent = nil
        let model = Self.model(start, repository: try await Self.repository(DraftTransportSpy(), folder))
        await model.continueFromCurrentStep()
        #expect(model.step == .persona)

        await model.back()
        #expect(model.step == .routine)

        let draft = try #require(
            try await Self.repository(DraftTransportSpy(), folder).loadState(for: Self.account).draft
        )
        #expect(draft.currentStep == .routine)
    }

    @Test("a cold start reopens the sign-up on the kept step, with the server's language")
    func theAppReopensOnTheKeptStep() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        var kept = Self.blankDraft
        kept.displayName = "Pessoa QA"
        kept.biologicalSex = .feminine
        kept.heightCM = 170
        kept.currentStep = .bodyData
        try Self.keep(kept, in: OnboardingDeviceDraftStore(directory: folder))

        let transport = DraftTransportSpy(state: Self.unfinishedState(locale: "en-US"))
        let app = AppFlowModel(
            authentication: FixedSessionAuthentication(userID: Self.account),
            onboarding: try await Self.repository(transport, folder),
            persona: E3Persona(),
            telemetry: DisabledTelemetryClient()
        )
        await app.start()

        #expect(app.state == .onboarding(userID: Self.account, step: .bodyData))
        #expect(app.restoredOnboardingDraft?.displayName == "Pessoa QA")
        #expect(app.restoredOnboardingDraft?.heightCM == 170)
        #expect(app.restoredOnboardingDraft?.localeIdentifier == "en-US")
        #expect(app.restoredOnboardingRequirements == E3Fixtures.requirements)
    }

    // MARK: What is never kept

    @Test("the acceptance of the documents and the objective are not kept, and no step beyond the documents")
    func acceptancesObjectiveAndLaterStepsAreNotKept() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        for step in [OnboardingStep.consent, .objective, .completion] {
            var draft = E3Fixtures.draft(step: step)
            #expect(draft.documentActions?.isEmpty == false)
            #expect(draft.consent != nil)
            #expect(draft.objective != nil)
            draft.currentStep = step
            try Self.keep(draft, in: store)

            let kept = try #require(store.load(for: Self.account), "\(step): nothing was kept")
            #expect(kept.documentActions == nil, "\(step)")
            #expect(kept.consent == nil, "\(step)")
            #expect(kept.objective == nil, "\(step)")
            #expect(kept.currentStep == .consent, "\(step)")
            #expect(kept.displayName == draft.displayName)
            #expect(kept.persona == draft.persona)
            #expect(kept.activityLevel == draft.activityLevel)

            // Not in the file either.
            let written = try String(contentsOf: store.fileURL, encoding: .utf8)
            for forbidden in [
                E3Fixtures.document.documentKey, E3Fixtures.document.contentHash,
                "documentActions", "dev.terms.v1", BodyFlowObjective.bodyRecomposition.rawValue,
            ] {
                #expect(!written.contains(forbidden), "\(step): the file holds «\(forbidden)»")
            }
        }
    }

    @Test("a kept step never places the person past an earlier step that misses something")
    func aKeptStepNeverSkipsAnIncompleteStep() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .persona)
        draft.heightCM = nil
        try Self.keep(draft, in: store)

        let kept = try #require(store.load(for: Self.account))
        #expect(kept.currentStep == .bodyData)
        #expect(kept.displayName == draft.displayName)
        #expect(kept.activityLevel == draft.activityLevel)
    }

    @Test("a new acceptance of the documents keeps nothing on the phone: that account's data is the server's")
    func aNewAcceptanceKeepsNothing() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        let model = OnboardingFlowModel(
            userID: Self.account, initialDraft: E3Fixtures.draft(step: .consent),
            repository: try await Self.repository(DraftTransportSpy(), folder), personaRepository: E3Persona(),
            developmentConsentAvailability: .unavailable, requirements: E3Fixtures.requirements,
            historicalCompletedAt: "2026-10-01T12:00:00Z",
            onStepChanged: { _ in }, onCompleted: {}
        )
        #expect(model.isReacceptance)

        await model.keepDraftOnDevice()
        await model.continueFromCurrentStep()
        #expect(model.step == .completion)
        await model.keepDraftOnDevice()
        await model.back()

        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.root.path))
    }

    // MARK: When it is removed

    @Test("an accepted completion removes it, and nothing recreates it afterwards")
    func completionRemovesIt() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        let transport = DraftTransportSpy(state: Self.unfinishedState())
        let model = Self.model(
            Self.signUpAtTheReview, repository: try await Self.repository(transport, folder)
        )
        await prepareE3Review(model)
        #expect(model.step == .completion)
        try #require(
            FileManager.default.fileExists(atPath: store.fileURL.path),
            "The walk to the review must have kept a draft, or this test proves nothing"
        )

        await model.complete()

        #expect(model.operationState == .idle)
        #expect(!model.allowsDraftEditing)
        #expect(!FileManager.default.fileExists(atPath: store.root.path))
        // The app leaving the foreground right after cannot bring it back.
        await model.keepDraftOnDevice()
        #expect(!FileManager.default.fileExists(atPath: store.root.path))
    }

    @Test("a sign-up the server already has as finished removes what the phone kept")
    func aFinishedSignUpRemovesIt() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        try Self.keep(BodyFlowTestFixtures.onboardingDraft(currentStep: .routine), in: store)

        let finished = OnboardingServerState(
            completion: OnboardingCompletionState(completed: true, completedAt: "2026-10-11T12:00:00Z"),
            requirements: E3Fixtures.requirements, acceptedActions: []
        )
        let state = try await Self.repository(DraftTransportSpy(state: finished), folder)
            .loadState(for: Self.account)

        #expect(state.completion.completed)
        #expect(state.draft == nil)
        #expect(!FileManager.default.fileExists(atPath: store.root.path))
    }

    @Test("while a new acceptance is due, the server's draft is the one used and the phone's is removed")
    func theServersDraftWinsAndRemovesIt() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        var stale = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        stale.displayName = "Nome antigo"
        try Self.keep(stale, in: store)

        var serverDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .consent)
        serverDraft.consent = nil
        let due = OnboardingServerState(
            completion: OnboardingCompletionState(completed: false, completedAt: "2026-09-20T12:00:00Z"),
            requirements: E3Fixtures.requirements, acceptedActions: [], draft: serverDraft
        )
        let state = try await Self.repository(DraftTransportSpy(state: due), folder)
            .loadState(for: Self.account)

        #expect(state.draft == serverDraft)
        #expect(!FileManager.default.fileExists(atPath: store.root.path))
    }

    @Test("another account never gets it and has no authority to remove the owner's draft")
    func anotherAccountNeverGetsIt() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        try Self.keep(BodyFlowTestFixtures.onboardingDraft(currentStep: .routine), in: store)

        let state = try await Self.repository(DraftTransportSpy(), folder, userID: Self.otherAccount)
            .loadState(for: Self.otherAccount)

        #expect(state.draft == nil)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(store.load(for: Self.account)?.currentStep == .routine)
    }

    @Test("the file names its account only by a digest")
    func theFileDoesNotCarryTheAccountID() throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        try Self.keep(BodyFlowTestFixtures.onboardingDraft(currentStep: .routine), in: store)
        let written = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!written.contains(Self.account))
        #expect(!written.contains("fixture.invalid"))
    }

    @Test("signing out, a session that ended and an account switch remove it")
    func theEndOfTheSessionRemovesIt() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        try Self.keep(BodyFlowTestFixtures.onboardingDraft(currentStep: .routine), in: store)

        await OnboardingDeviceDraftSessionClearer(store: store).clearSensitiveState()

        #expect(!FileManager.default.fileExists(atPath: store.root.path))
    }

    @Test("the app of a real account keeps the draft where it was told, and its own sign-out removes it")
    func theRealGraphKeepsAndRemovesIt() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        let authStore = AuthenticationSessionStore(secureStore: InMemorySecureStore())
        try await authStore.replace(with: Self.authRecord(for: Self.account))
        let dependencies = AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: try MobileAPIConfiguration(originString: "https://mobile.example.test")
            ),
            supabaseAuthConfiguration: try SupabaseAuthConfiguration(
                originString: "https://project.example.test",
                key: "sb_publishable_synthetic"
            ),
            authenticationSessionStore: authStore,
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) },
            onboardingDeviceDraft: store
        )
        let baseRepository = try #require(dependencies.onboarding as? MobileOnboardingRepository)
        #expect(baseRepository.deviceDraft?.root == store.root)
        let repository = try await baseRepository.scoped(for: Self.account)

        await repository.keepDraftOnDevice(
            BodyFlowTestFixtures.onboardingDraft(currentStep: .routine), for: Self.account
        )
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))

        try? await dependencies.authentication.signOut()

        #expect(!FileManager.default.fileExists(atPath: store.root.path))
    }

    // MARK: Failures keep the person's work

    @Test("a read that fails leaves the kept draft where it is")
    func aFailedReadKeepsIt() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        try Self.keep(BodyFlowTestFixtures.onboardingDraft(currentStep: .routine), in: store)

        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            try await Self.repository(DraftTransportSpy(readError: .network), folder)
                .loadState(for: Self.account)
        }
        #expect(store.load(for: Self.account)?.currentStep == .routine)
    }

    @Test("a file that cannot be understood is removed and the sign-up starts clean")
    func anUnreadableFileIsRemoved() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        try Self.keep(BodyFlowTestFixtures.onboardingDraft(currentStep: .routine), in: store)
        try Data("{ not the draft".utf8).write(to: store.fileURL)

        let state = try await Self.repository(DraftTransportSpy(), folder).loadState(for: Self.account)

        #expect(state.draft == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("a pending completion keeps nothing new")
    func aPendingCompletionKeepsNothingNew() async throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        let transport = DraftTransportSpy(
            state: Self.unfinishedState(), completionError: .network
        )
        let model = Self.model(
            Self.signUpAtTheReview, repository: try await Self.repository(transport, folder)
        )
        await prepareE3Review(model)
        await model.complete()
        #expect(model.unresolvedCompletion)
        try #require(
            FileManager.default.fileExists(atPath: store.fileURL.path),
            "The walk to the review must have kept a draft, or this test proves nothing"
        )
        let before = try Data(contentsOf: store.fileURL)
        let stamp = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date

        await model.keepDraftOnDevice()

        #expect(try Data(contentsOf: store.fileURL) == before)
        #expect(
            try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date == stamp
        )
    }

    // MARK: Where and how

    @Test("it is one file in the app's own Application Support, never the Keychain or the preferences")
    func whereItIsKept() throws {
        let device = OnboardingDeviceDraftStore.device
        #expect(device.root.path.hasSuffix("/Library/Application Support/performe-sign-up-draft"))
        #expect(device.root.path.hasPrefix(NSHomeDirectory()))
        #expect(device.fileURL.lastPathComponent == "draft.json")
        #expect(device.fileURL.deletingLastPathComponent().path == device.root.path)

        let source = try Self.source("BodyFlow/Core/Onboarding/OnboardingDeviceDraftStore.swift")
        for forbidden in ["SecItem", "SecureStoring", "KeychainSecureStore", "UserDefaults"] {
            #expect(!source.contains(forbidden), "The draft store reaches for \(forbidden)")
        }
    }

    @Test("it is written with complete protection, in a folder left out of the backups")
    func howItIsProtected() throws {
        let folder = Self.makeFolder()
        defer { Self.remove(folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        try Self.keep(BodyFlowTestFixtures.onboardingDraft(currentStep: .routine), in: store)

        #expect(store.fileURL.path.hasPrefix(folder.path))
        let values = try store.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        // The simulator's disk may not report a protection class; where it
        // does, it is the complete one.
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
        let source = try Self.source("BodyFlow/Core/Onboarding/OnboardingDeviceDraftStore.swift")
        #expect(source.contains(".completeFileProtection"))
        #expect(source.contains("FileProtectionType.complete"))
        #expect(source.contains("isExcludedFromBackup = true"))
    }

    @Test("the screen keeps the draft when the app leaves the foreground")
    func theContainerKeepsTheDraftWhenTheAppLeavesTheForeground() throws {
        let container = try Self.source("BodyFlow/Features/Onboarding/OnboardingContainerView.swift")
        #expect(container.contains("@Environment(\\.scenePhase)"))
        #expect(container.contains(".onChange(of: scenePhase)"))
        #expect(container.contains("model.keepDraftOnDevice()"))
        let dependencies = try Self.source("BodyFlow/App/AppDependencies.swift")
        #expect(dependencies.contains("OnboardingDeviceDraftSessionClearer(store: onboardingDeviceDraft)"))
    }

    // MARK: Nothing of the demonstration goes through it

    #if DEBUG
    @Test("the local demonstration keeps nothing through this path")
    func theDemonstrationIsUntouched() async throws {
        let stateStore = DemoStateStore(secureStore: InMemorySecureStore())
        try await stateStore.saveSession(AuthSession(
            userID: "demo-user-v1", email: "demo-user@fixture.invalid",
            isEmailConfirmed: true, isOnboardingCompleted: false
        ))
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        let demo = DemoOnboardingRepository(stateStore: stateStore, buildFlavor: .debug)
        let preview = OnboardingPreviewRepository(
            stateStore: stateStore, buildFlavor: .debug, preloadsSyntheticOnboardingValues: false
        )

        await demo.keepDraftOnDevice(draft, for: "demo-user-v1")
        await preview.keepDraftOnDevice(draft, for: "demo-user-v1")

        #expect(try await stateStore.loadOnboardingDraft() == nil)
    }

    @Test("the UI-test fixture resolves only in the Debug demonstration and never uses the real folder")
    func theFixtureIsDebugOnly() {
        let flag = "--ui-testing-onboarding-device-draft"
        let first = AppLaunchConfiguration.resolve(arguments: [flag], buildFlavor: .debug)
        #expect(first.mode == .demo)
        #expect(first.usesOnboardingDeviceDraftFixture)
        #expect(first.shouldResetDemoState)
        #expect(!first.preloadsSyntheticOnboardingValues)
        let relaunch = AppLaunchConfiguration.resolve(
            arguments: [flag, "--ui-testing-preserve-state"], buildFlavor: .debug
        )
        #expect(relaunch.usesOnboardingDeviceDraftFixture)
        #expect(!relaunch.shouldResetDemoState)

        let release = AppLaunchConfiguration.resolve(arguments: [flag], buildFlavor: .release)
        #expect(release.mode == .releaseUnavailable)
        #expect(!release.usesOnboardingDeviceDraftFixture)
        #expect(AppDependencies.make(configuration: release).onboarding is UnavailableOnboardingRepository)

        #expect(OnboardingDeviceDraftFixture.store.root != OnboardingDeviceDraftStore.device.root)
        #expect(OnboardingDeviceDraftFixture.store.root.path.contains("/ui-testing/"))
    }
    #endif

    // MARK: Support

    private static var blankDraft: OnboardingDraft {
        OnboardingDraft(
            displayName: nil, localeIdentifier: "pt-BR", countryCode: "BR", timeZoneIdentifier: zone,
            biologicalSex: nil, birthDate: nil, heightCM: nil, weightKG: nil, bodyFatPercent: nil,
            objective: nil, activityLevel: nil, trainingFrequency: nil, waterIntake: nil,
            hungerLevel: nil, wakeTime: nil, bedtime: nil, foodOrganization: nil, persona: nil,
            consent: nil, currentStep: .welcome
        )
    }

    /// A first sign-up (no development consent) that walks from the
    /// documents to the review.
    private static var signUpAtTheReview: OnboardingDraft {
        var draft = E3Fixtures.draft(step: .completion)
        draft.consent = nil
        return draft
    }

    private static func unfinishedState(locale: String = "pt-BR") -> OnboardingServerState {
        OnboardingServerState(
            locale: locale,
            completion: OnboardingCompletionState(completed: false, completedAt: nil),
            requirements: E3Fixtures.requirements, acceptedActions: []
        )
    }

    private static func repository(
        _ transport: DraftTransportSpy, _ folder: URL, userID: String = account
    ) async throws -> MobileOnboardingRepository {
        let deviceDraft = OnboardingDeviceDraftStore(directory: folder)
        let authStore = AuthenticationSessionStore(secureStore: InMemorySecureStore())
        try await authStore.replace(with: authRecord(for: userID))
        let lifecycle = SessionLifecycleCoordinator(
            store: authStore, remote: DeviceDraftOfflineAuthRemote(),
            sensitiveStateClearer: OnboardingDeviceDraftSessionClearer(store: deviceDraft)
        )
        let repository = try await MobileOnboardingRepository(
            transport: transport, deviceDraft: deviceDraft, sessionLifecycle: lifecycle
        ).scoped(for: userID)
        return try #require(repository as? MobileOnboardingRepository)
    }

    private static func authRecord(for userID: String) -> AuthenticationSessionRecord {
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payload = base64URL(Data(#"{"sub":"\#(userID)","marker":"device-draft-test"}"#.utf8))
        return AuthenticationSessionRecord(
            userID: userID, email: "synthetic@example.invalid", isEmailConfirmed: true,
            isOnboardingCompleted: false, accessToken: "\(header).\(payload).synthetic",
            refreshToken: "synthetic-device-draft-refresh", expiresAt: Date().addingTimeInterval(3_600)
        )
    }

    private static func model(
        _ draft: OnboardingDraft, repository: MobileOnboardingRepository
    ) -> OnboardingFlowModel {
        OnboardingFlowModel(
            userID: account, initialDraft: draft, repository: repository,
            personaRepository: E3Persona(), developmentConsentAvailability: .unavailable,
            requirements: E3Fixtures.requirements,
            onStepChanged: { _ in }, onCompleted: {}
        )
    }

    /// Keeps a draft for the test's account, or stops the test: a store
    /// that keeps nothing proves nothing about what happens next.
    private static func keep(_ draft: OnboardingDraft, in store: OnboardingDeviceDraftStore) throws {
        try #require(store.save(draft, for: account), "The store kept nothing")
        try #require(FileManager.default.fileExists(atPath: store.fileURL.path), "No file was written")
    }

    private static func makeFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sign-up-draft-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    private static func source(_ path: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(path),
            encoding: .utf8
        )
    }
}

private struct RecordedDraftRequest: Sendable {
    let method: HTTPMethod
    let path: String
    let body: Data?
}

/// The server of a real account, as far as the sign-up asks it.
private actor DraftTransportSpy: MobileAPIExecuting {
    private let state: OnboardingServerState
    private let readError: MobileAPITransportError?
    private let completionError: MobileAPITransportError?
    private(set) var requests: [RecordedDraftRequest] = []

    init(
        state: OnboardingServerState = OnboardingServerState(
            completion: OnboardingCompletionState(completed: false, completedAt: nil),
            requirements: E3Fixtures.requirements, acceptedActions: []
        ),
        readError: MobileAPITransportError? = nil,
        completionError: MobileAPITransportError? = nil
    ) {
        self.state = state
        self.readError = readError
        self.completionError = completionError
    }

    func execute<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> Response {
        requests.append(RecordedDraftRequest(method: request.method, path: request.path, body: request.body))
        if request.method == .get {
            if let readError { throw readError }
            return state as! Response
        }
        if request.path.hasSuffix("/eligibility") { return E3Fixtures.choice as! Response }
        if let completionError { throw completionError }
        let timestamp = "2026-10-11T15:00:00.000Z"
        return OnboardingCompletionAcknowledgement(
            onboardingCompleted: true, completedAt: timestamp,
            objective: .bodyRecomposition, persona: .focus,
            documentActions: [OnboardingAcceptedAction(
                documentKey: E3Fixtures.document.documentKey, version: E3Fixtures.document.version,
                locale: E3Fixtures.document.locale, contentHash: E3Fixtures.document.contentHash,
                purpose: E3Fixtures.document.purpose, action: E3Fixtures.document.action,
                actedAt: timestamp
            )]
        ) as! Response
    }
}

private struct FixedSessionAuthentication: AuthenticationService {
    let userID: String

    private var session: AuthSession {
        AuthSession(
            userID: userID, email: "person@example.invalid",
            isEmailConfirmed: true, isOnboardingCompleted: false
        )
    }

    func restoreSession() async throws -> AuthSession? { session }
    func signIn(email: String, password: String) async throws -> AuthSession { session }
    func signUp(email: String, password: String) async throws -> AuthSignUpResult { .authenticated(session) }
    func confirmEmailForDevelopment() async throws -> AuthSession { session }
    func requestPasswordRecovery(email: String) async throws {}
    func signOut() async throws {}
}

/// The authenticated test fixture never refreshes or reaches a provider.
private struct DeviceDraftOfflineAuthRemote: SupabaseAuthRemoteOperating {
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}
