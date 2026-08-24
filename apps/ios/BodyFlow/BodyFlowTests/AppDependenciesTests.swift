import Foundation
import Testing

@testable import BodyFlow

@Suite("App Dependencies", .serialized)
struct AppDependenciesTests {
    @Test("Valid origin and session seam install the real mobile transport")
    func validOriginAndSessionInstallTransport() throws {
        let configuration = try MobileAPIConfiguration(
            originString: "https://staging.example.test"
        )
        let dependencies = AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: configuration
            ),
            sessionTokenProvider: DependencyTokenProvider(token: "session-test-value")
        )

        #expect(dependencies.apiClient is MobileAPITransport)
    }

    @Test("Missing mobile origin keeps the API client unavailable")
    func missingOriginKeepsClientUnavailable() {
        let dependencies = AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: nil,
            sessionTokenProvider: DependencyTokenProvider(token: "session-test-value")
        )

        #expect(dependencies.apiClient is UnavailableAPIClient)
    }

    @Test("Missing mobile session keeps the API client unavailable")
    func missingSessionKeepsClientUnavailable() throws {
        let configuration = try MobileAPIConfiguration(
            originString: "https://staging.example.test"
        )
        let dependencies = AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: configuration
            ),
            sessionTokenProvider: nil
        )

        #expect(dependencies.apiClient is UnavailableAPIClient)
    }

    @Test("Release ignores an explicitly injected synthetic success client")
    func releaseIgnoresSyntheticClientOverride() {
        let dependencies = AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            apiClientOverride: MockAPIClient()
        )

        #expect(dependencies.apiClient is UnavailableAPIClient)
    }

    @Test("Release without Supabase configuration installs unavailable authentication")
    func releaseWithoutSupabaseConfigurationFailsClosed() async {
        let dependencies = releaseDependencies()

        #expect(dependencies.authentication is UnavailableAuthenticationService)
        await #expect(throws: AuthenticationError.operationUnavailable) {
            _ = try await dependencies.authentication.restoreSession()
        }
    }

    @Test("Release with valid Supabase configuration installs isolated authentication")
    func releaseWithSupabaseConfigurationInstallsAuthentication() throws {
        let configuration = try SupabaseAuthConfiguration(
            originString: "https://project.example.test",
            key: "sb_publishable_synthetic"
        )
        let dependencies = AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            supabaseAuthConfiguration: configuration,
            authenticationSessionStore: AuthenticationSessionStore(
                secureStore: InMemorySecureStore()
            ),
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) }
        )

        #expect(dependencies.authentication is SupabaseAuthenticationService)
    }

    @Test("Release auth and Mobile API share one lifecycle instance")
    func releaseAuthAndTransportShareLifecycle() async throws {
        let sessionStore = AuthenticationSessionStore(secureStore: InMemorySecureStore())
        let lifecycle = DependencyLifecycle()
        let dependencies = AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: try MobileAPIConfiguration(
                    originString: "https://mobile.example.test"
                )
            ),
            sessionTokenProvider: DependencyTokenProvider(token: "wrong-provider"),
            supabaseAuthConfiguration: try SupabaseAuthConfiguration(
                originString: "https://project.example.test",
                key: "sb_publishable_synthetic"
            ),
            authenticationSessionStore: sessionStore,
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) },
            sessionLifecycleOverride: lifecycle
        )

        let transportLifecycle = Mirror(reflecting: dependencies.apiClient).children
            .first { $0.label == "sessionLifecycle" }?.value
        #expect((transportLifecycle as? DependencyLifecycle) === lifecycle)
        try await dependencies.authentication.signOut()
        #expect(await lifecycle.signOutCount == 1)
    }

    @Test("Release valid app-owned bearer reaches the CI-0 transport")
    func releaseValidBearerFeedsMobileTransport() async throws {
        let sessionStore = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let record = dependencyAuthenticationRecord(expiresAt: 2_000)
        try await sessionStore.replace(with: record)
        let harness = try await dependencyTransportHarness(sessionStore: sessionStore)

        let payload: DependencyTransportPayload = try await harness.dependencies.apiClient.send(
            APIRequest(method: .get, path: "/api/mobile/v1/probe")
        )
        let requests = await harness.recorder.requests

        #expect(payload == DependencyTransportPayload(value: "ok"))
        #expect(requests.count == 1)
        #expect(
            requests.first?.value(forHTTPHeaderField: "Authorization")
                == "Bearer \(record.accessToken)"
        )
    }

    @Test("Release expired app-owned session never feeds the CI-0 transport")
    func releaseExpiredBearerFailsClosed() async throws {
        let secureStore = InMemorySecureStore()
        let expired = dependencyAuthenticationRecord(expiresAt: 999)
        try await secureStore.store(
            try JSONEncoder().encode(expired),
            forKey: AuthenticationSessionStore.storageKey
        )
        let sessionStore = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        #expect(try await sessionStore.hydrate() == nil)
        let harness = try await dependencyTransportHarness(sessionStore: sessionStore)

        await #expect(throws: MobileAPITransportError.missingSession) {
            let _: DependencyTransportPayload = try await harness.dependencies.apiClient.send(
                APIRequest(method: .get, path: "/api/mobile/v1/probe")
            )
        }
        #expect(await harness.recorder.requests.isEmpty)
    }

    @Test("Release absent app-owned session remains fail closed before CI-0 network activity")
    func releaseAbsentBearerFailsClosed() async throws {
        let sessionStore = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let harness = try await dependencyTransportHarness(sessionStore: sessionStore)

        await #expect(throws: MobileAPITransportError.missingSession) {
            let _: DependencyTransportPayload = try await harness.dependencies.apiClient.send(
                APIRequest(method: .get, path: "/api/mobile/v1/probe")
            )
        }
        #expect(await harness.recorder.requests.isEmpty)
    }

    #if DEBUG
    @Test("Debug demo remains explicit even when Supabase configuration is supplied")
    func debugDemoDoesNotInstallSupabaseAuthentication() throws {
        let configuration = try SupabaseAuthConfiguration(
            originString: "https://project.example.test",
            key: "sb_publishable_synthetic"
        )
        let dependencies = AppDependencies.make(
            configuration: .resolve(arguments: ["--ui-testing"], buildFlavor: .debug),
            supabaseAuthConfiguration: configuration
        )

        #expect(dependencies.authentication is DemoAuthenticationService)
    }
    #endif

    @Test("CI-0 dependency and networking sources contain no candidate product name")
    func ci0SourcesRemainNamingNeutral() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let appDirectory = testDirectory.deletingLastPathComponent().appending(path: "BodyFlow")
        let sourceURLs = [
            appDirectory.appending(path: "App/AppDependencies.swift"),
            appDirectory.appending(path: "Core/Networking/MobileAPIConfiguration.swift"),
            appDirectory.appending(path: "Core/Networking/MobileAPIEnvelope.swift"),
            appDirectory.appending(path: "Core/Networking/MobileAPITransport.swift"),
            appDirectory.appending(path: "Core/Networking/MobileAPITransportError.swift"),
            appDirectory.appending(path: "Core/Networking/SessionTokenProviding.swift"),
        ]
        let forbidden = [
            ["Better", "Ahead"].joined(separator: " "),
            ["Body", "Journey"].joined(),
            ["Be", "Better"].joined(),
            ["Better", "Everyday"].joined(),
        ]

        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for candidate in forbidden {
                #expect(!source.contains(candidate))
            }
        }
    }

    @Test("Release graph installs fail-closed support dependencies")
    func releaseGraphInstallsFailClosedSupportDependencies() {
        let dependencies = releaseDependencies()

        #expect(dependencies.timeProvider is SystemTimeProvider)
        #expect(dependencies.patientTimeZone.documentedIANAIdentifier == nil)
        #expect(dependencies.apiClient is UnavailableAPIClient)
        #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try dependencies.idempotencyKeyProvider.nextKey()
        }
        #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try dependencies.patientTimeZone.requireTimeZone()
        }
    }

    @Test("Release read capabilities fail closed")
    func releaseReadCapabilitiesFailClosed() async {
        let dependencies = releaseDependencies()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.today.today()
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.history.history(.firstPage)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.plan.plan()
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.progress.progress()
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.routine.list(
                kind: .supplement,
                includeArchived: false
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.routine.history(
                kind: .supplement,
                itemID: "release-unavailable-supplement",
                cursor: nil,
                limit: 20
            )
        }
    }

    @Test("Release meal detection fails closed")
    func releaseDetectionIsUnavailable() async {
        let dependencies = releaseDependencies()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.mealDetection.detect(
                BodyFlowTestFixtures.textMealDetectionInput
            )
        }
    }

    @Test("Release registration mutations fail closed")
    func releaseRegistrationMutationsFailClosed() async throws {
        let dependencies = releaseDependencies()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.propose(
                BodyFlowTestFixtures.registrationProposalAttempt()
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.edit(
                BodyFlowTestFixtures.registrationEditAttempt()
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.confirm(
                BodyFlowTestFixtures.registrationConfirmAttempt()
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.cancel(
                BodyFlowTestFixtures.registrationCancelAttempt()
            )
        }
    }

    @Test("Release routine mutations fail closed")
    func releaseRoutineMutationsFailClosed() async throws {
        let dependencies = releaseDependencies()
        let hydrationAttempt = try BodyFlowTestFixtures.hydrationAttempt()
        let weightAttempt = try BodyFlowTestFixtures.weightAttempt()
        let routineAttempt = try BodyFlowTestFixtures.routineAttempt()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.hydration.record(hydrationAttempt)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.weight.record(weightAttempt)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.routine.record(routineAttempt)
        }
    }

    @Test("Release legacy API client fails closed without reaching Today fixture")
    func releaseLegacyAPIClientFailsClosed() async {
        let dependencies = releaseDependencies()
        let request = APIRequest<TodaySummary>(method: .get, path: "/today")

        await #expect(throws: APIClientError.operationUnavailable) {
            try await dependencies.apiClient.send(request)
        }
    }

    @Test("Release Prompt 14 factories expose only fail-closed capabilities")
    func releasePrompt14FactoriesFailClosed() async throws {
        let dependencies = releaseDependencies()
        let content = dependencies.publishedContentSessions.makeSession(
            userID: "40000000-0000-4000-8000-000000000001"
        )
        let coach = dependencies.coachExperienceSessions.makeCoachExperience(
            userID: "40000000-0000-4000-8000-000000000001"
        )
        let cover = dependencies.contentCoverSessions.makeLoader(
            userID: "40000000-0000-4000-8000-000000000001"
        )
        let query = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: nil
        )

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await content.listing.content(query)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await coach.coachExperience()
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await cover.image(
                publicationID: "publication-1",
                version: 4,
                cover: PublishedContentCover(
                    url: "/api/mobile/v1/content/covers/AbC_123-xyz",
                    expiresAt: APITimestamp(value: .distantFuture)
                ),
                target: ContentCoverTargetSize(
                    widthPixels: 240,
                    heightPixels: 160
                )
            )
        }
    }

    #if DEBUG
    @Test("Debug graph accepts an explicitly injected mock API client")
    func debugGraphAcceptsExplicitMockClient() throws {
        let request = APIRequest<TodaySummary>(method: .get, path: "/today")
        let mock = MockAPIClient(payloads: [request.key: AppFixtures.todayPayload])
        let dependencies = AppDependencies.make(
            configuration: AppLaunchConfiguration(
                mode: .demo,
                shouldResetDemoState: true,
                startsWithCompletedFixture: true,
                preloadsSyntheticOnboardingValues: true,
                authBehavior: .succeed(after: nil)
            ),
            apiClientOverride: mock
        )

        #expect((dependencies.apiClient as? MockAPIClient) === mock)
    }

    @Test("Debug make graph preserves Prompt 12 while Prompt 13 is unavailable")
    func debugMakePreservesPrompt12AndFailsPrompt13Closed() async throws {
        let dependencies = AppDependencies.make(
            configuration: AppLaunchConfiguration(
                mode: .demo,
                shouldResetDemoState: true,
                startsWithCompletedFixture: true,
                preloadsSyntheticOnboardingValues: true,
                authBehavior: .succeed(after: nil)
            )
        )
        let legacyRequest = APIRequest<TodaySummary>(method: .get, path: "/today")

        #expect(try await dependencies.authentication.restoreSession()?.userID == "demo-user-v1")
        #expect(try await dependencies.apiClient.send(legacyRequest) == AppFixtures.today)
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.today.today()
        }
    }

    @Test("Debug Prompt 14 factories remain unavailable before fixture composition")
    func debugPrompt14FactoriesRemainUnavailable() async throws {
        let dependencies = AppDependencies.make(
            configuration: AppLaunchConfiguration(
                mode: .demo,
                shouldResetDemoState: true,
                startsWithCompletedFixture: true,
                preloadsSyntheticOnboardingValues: true,
                authBehavior: .succeed(after: nil)
            )
        )
        let content = dependencies.publishedContentSessions.makeSession(
            userID: "40000000-0000-4000-8000-000000000002"
        )

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await content.detail.contentDetail(
                publicationID: "publication-1"
            )
        }
    }

    @Test("Debug Prompt 14 content capabilities share one actor only within a session")
    func debugPrompt14ScopesContentRepositoryToSession() async throws {
        let dependencies = prompt14Dependencies("--ui-testing-prompt14-loaded")
        let first = dependencies.publishedContentSessions.makeSession(
            userID: "40000000-0000-4000-8000-000000000003"
        )
        let sameUserSecondSession = dependencies.publishedContentSessions.makeSession(
            userID: "40000000-0000-4000-8000-000000000003"
        )
        let otherUser = dependencies.publishedContentSessions.makeSession(
            userID: "40000000-0000-4000-8000-000000000004"
        )

        let listing = try #require(first.listing as? DemoPrompt14Repository)
        let detail = try #require(first.detail as? DemoPrompt14Repository)
        let state = try #require(first.state as? DemoPrompt14Repository)
        let lifetime = try #require(first.lifetime as? DemoPrompt14Repository)
        let sameUserSecondListing = try #require(
            sameUserSecondSession.listing as? DemoPrompt14Repository
        )
        let otherUserListing = try #require(
            otherUser.listing as? DemoPrompt14Repository
        )

        #expect(listing === detail)
        #expect(listing === state)
        #expect(listing === lifetime)
        #expect(listing !== sameUserSecondListing)
        #expect(listing !== otherUserListing)

        await first.lifetime.endSession()
        await #expect(throws: CancellationError.self) {
            try await first.listing.content(DemoPrompt14Fixtures.todayQuery())
        }
        #expect(
            try await sameUserSecondSession.listing.content(
                DemoPrompt14Fixtures.todayQuery()
            ) == DemoPrompt14Fixtures.todayFeed
        )
    }

    @Test("Debug Prompt 14 coach and cover factories never cache by user")
    func debugPrompt14ScopesCoachAndCoverPerFactoryCall() throws {
        let dependencies = prompt14Dependencies("--ui-testing-prompt14-loaded")
        let coachA = try #require(
            dependencies.coachExperienceSessions.makeCoachExperience(
                userID: "40000000-0000-4000-8000-000000000005"
            ) as? DemoPrompt14CoachProvider
        )
        let coachSameUser = try #require(
            dependencies.coachExperienceSessions.makeCoachExperience(
                userID: "40000000-0000-4000-8000-000000000005"
            ) as? DemoPrompt14CoachProvider
        )
        let coachOtherUser = try #require(
            dependencies.coachExperienceSessions.makeCoachExperience(
                userID: "40000000-0000-4000-8000-000000000006"
            ) as? DemoPrompt14CoachProvider
        )
        let coverA = try #require(
            dependencies.contentCoverSessions.makeLoader(
                userID: "40000000-0000-4000-8000-000000000005"
            ) as? ContentCoverLoader
        )
        let coverSameUser = try #require(
            dependencies.contentCoverSessions.makeLoader(
                userID: "40000000-0000-4000-8000-000000000005"
            ) as? ContentCoverLoader
        )
        let coverOtherUser = try #require(
            dependencies.contentCoverSessions.makeLoader(
                userID: "40000000-0000-4000-8000-000000000006"
            ) as? ContentCoverLoader
        )

        #expect(coachA !== coachSameUser)
        #expect(coachA !== coachOtherUser)
        #expect(coverA !== coverSameUser)
        #expect(coverA !== coverOtherUser)
    }

    @Test("Stateful persona graph shares mutation state and resets per graph")
    func statefulPersonaGraphSharesAndResetsState() async throws {
        let first = prompt14Dependencies(
            "--ui-testing-prompt14-persona-stateful"
        )
        let firstCoach = first.coachExperienceSessions.makeCoachExperience(
            userID: DemoUser.id
        )

        #expect(try await first.coachPersona.selectedPersona(for: DemoUser.id) == nil)
        #expect(
            try await firstCoach.coachExperience()
                == DemoPrompt14Fixtures.balancedCoachResponse
        )

        try await first.coachPersona.setPersona(.zen, for: DemoUser.id)

        #expect(try await first.coachPersona.selectedPersona(for: DemoUser.id) == .zen)
        #expect(
            try await firstCoach.coachExperience()
                == DemoPrompt14Fixtures.zenCoachResponse
        )
        #expect(
            try await first.coachExperienceSessions.makeCoachExperience(
                userID: DemoUser.id
            ).coachExperience() == DemoPrompt14Fixtures.zenCoachResponse
        )

        let second = prompt14Dependencies(
            "--ui-testing-prompt14-persona-stateful"
        )
        let secondCoach = second.coachExperienceSessions.makeCoachExperience(
            userID: DemoUser.id
        )

        #expect(try await second.coachPersona.selectedPersona(for: DemoUser.id) == nil)
        #expect(
            try await secondCoach.coachExperience()
                == DemoPrompt14Fixtures.balancedCoachResponse
        )
    }

    @Test("Release ignores the stateful persona launch state")
    func releaseStatefulPersonaRemainsFailClosed() async {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: [
                "--ui-testing",
                "--ui-testing-prompt14-persona-stateful",
            ],
            buildFlavor: .release
        )
        let dependencies = AppDependencies.make(configuration: configuration)
        let coach = dependencies.coachExperienceSessions.makeCoachExperience(
            userID: DemoUser.id
        )

        #expect(configuration.mode == .releaseUnavailable)
        #expect(configuration.prompt14ScenarioSelection == nil)
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await coach.coachExperience()
        }
    }

    @Test("Prompt 14 failures do not replace the complete loaded Prompt 13 graph")
    func prompt14KeepsOfficialGraphIndependent() async throws {
        let dependencies = prompt14Dependencies("--ui-testing-prompt14-offline")
        let today = try #require(dependencies.today as? DemoBodyFlowRepository)
        let history = try #require(dependencies.history as? DemoBodyFlowRepository)
        let plan = try #require(dependencies.plan as? DemoBodyFlowRepository)
        let progress = try #require(dependencies.progress as? DemoBodyFlowRepository)
        let routine = try #require(dependencies.routine as? DemoBodyFlowRepository)

        #expect(today === history)
        #expect(today === plan)
        #expect(today === progress)
        #expect(today === routine)
        #expect(try await dependencies.today.today() == DemoBodyFlowFixtures.loadedToday)
        #expect(try await dependencies.progress.progress() == DemoBodyFlowFixtures.loadedProgress)

        let session = dependencies.publishedContentSessions.makeSession(
            userID: "40000000-0000-4000-8000-000000000007"
        )
        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await session.listing.content(DemoPrompt14Fixtures.todayQuery())
        }
    }

    @Test("Only Prompt 14 progress scenarios replace the progress capability")
    func prompt14ProgressReplacementIsNarrow() async throws {
        let cases: [(String, ProgressResponse)] = [
            ("--ui-testing-prompt14-progress-empty", DemoPrompt14Fixtures.emptyProgress),
            ("--ui-testing-prompt14-progress-minimum", DemoPrompt14Fixtures.minimumProgress),
            ("--ui-testing-prompt14-streak-zero", DemoPrompt14Fixtures.streakZeroProgress),
        ]

        for (argument, expected) in cases {
            let dependencies = prompt14Dependencies(argument)
            let today = try #require(dependencies.today as? DemoBodyFlowRepository)
            let history = try #require(dependencies.history as? DemoBodyFlowRepository)
            let plan = try #require(dependencies.plan as? DemoBodyFlowRepository)
            let routine = try #require(dependencies.routine as? DemoBodyFlowRepository)

            #expect(today === history)
            #expect(today === plan)
            #expect(today === routine)
            #expect(dependencies.progress is DemoPrompt14ProgressProvider)
            #expect(try await dependencies.today.today() == DemoBodyFlowFixtures.loadedToday)
            #expect(try await dependencies.progress.progress() == expected)
        }

        let loaded = prompt14Dependencies("--ui-testing-prompt14-loaded")
        #expect(loaded.progress is DemoBodyFlowRepository)
        #expect(try await loaded.progress.progress() == DemoBodyFlowFixtures.loadedProgress)
    }

    @Test("Every added Prompt 14 state keeps official Today loaded and scopes content to one session actor")
    func addedPrompt14StatesKeepOfficialGraphAndContentScope() async throws {
        for argument in addedPrompt14DependencyArguments {
            let dependencies = prompt14Dependencies(argument)
            #expect(try await dependencies.today.today() == DemoBodyFlowFixtures.loadedToday)

            let session = dependencies.publishedContentSessions.makeSession(
                userID: "prompt14-added-scope-user"
            )
            let listing = try #require(session.listing as? DemoPrompt14Repository)
            let detail = try #require(session.detail as? DemoPrompt14Repository)
            let state = try #require(session.state as? DemoPrompt14Repository)
            let lifetime = try #require(session.lifetime as? DemoPrompt14Repository)

            #expect(listing === detail)
            #expect(listing === state)
            #expect(listing === lifetime)
        }
    }

    @Test("Duplicate-badge complete progress replaces only Progress")
    func duplicateBadgeProgressReplacementIsNarrowAndExplicit() async throws {
        let dependencies = prompt14Dependencies(
            "--ui-testing-prompt14-progress-complete-duplicate-badges"
        )
        let today = try #require(dependencies.today as? DemoBodyFlowRepository)
        let history = try #require(dependencies.history as? DemoBodyFlowRepository)
        let plan = try #require(dependencies.plan as? DemoBodyFlowRepository)
        let routine = try #require(dependencies.routine as? DemoBodyFlowRepository)
        let snapshot = try #require(try await dependencies.progress.progress().data)

        #expect(today === history)
        #expect(today === plan)
        #expect(today === routine)
        #expect(dependencies.progress is DemoPrompt14ProgressProvider)
        #expect(try await dependencies.today.today() == DemoBodyFlowFixtures.loadedToday)
        #expect(snapshot.xpTotal == 2_450)
        #expect(snapshot.level == 7)
        #expect(snapshot.currentStreak == 12)
        #expect(snapshot.blocksCompleted == 2)
        #expect(
            snapshot.badgesEarned == [
                "70000000-0000-4000-8000-000000000001",
                "70000000-0000-4000-8000-000000000001",
            ]
        )
    }

    @Test("Added cover and coach states create fresh session-local products")
    func addedCoverAndCoachStatesRemainSessionLocal() throws {
        for argument in [
            "--ui-testing-prompt14-cover-too-large",
            "--ui-testing-prompt14-mascot-focus-active",
            "--ui-testing-prompt14-mascot-zen-neglected",
        ] {
            let dependencies = prompt14Dependencies(argument)
            let coachA = try #require(
                dependencies.coachExperienceSessions.makeCoachExperience(
                    userID: "prompt14-new-user"
                ) as? DemoPrompt14CoachProvider
            )
            let coachB = try #require(
                dependencies.coachExperienceSessions.makeCoachExperience(
                    userID: "prompt14-new-user"
                ) as? DemoPrompt14CoachProvider
            )
            let coverA = try #require(
                dependencies.contentCoverSessions.makeLoader(
                    userID: "prompt14-new-user"
                ) as? ContentCoverLoader
            )
            let coverB = try #require(
                dependencies.contentCoverSessions.makeLoader(
                    userID: "prompt14-new-user"
                ) as? ContentCoverLoader
            )

            #expect(coachA !== coachB)
            #expect(coverA !== coverB)
        }
    }

    @Test("Release ignores every added Prompt 14 state and keeps content unavailable")
    func releaseIgnoresAddedPrompt14States() async throws {
        for argument in addedPrompt14DependencyArguments {
            let dependencies = AppDependencies.make(
                configuration: .resolve(
                    arguments: ["--ui-testing", argument],
                    buildFlavor: .release
                )
            )
            let session = dependencies.publishedContentSessions.makeSession(
                userID: "prompt14-release-user"
            )

            await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
                try await dependencies.today.today()
            }
            await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
                try await dependencies.progress.progress()
            }
            await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
                try await session.listing.content(DemoPrompt14Fixtures.todayQuery())
            }
        }
    }

    @Test("Prompt 14 graph installs the exact deterministic clock and idempotency source")
    func prompt14InstallsDeterministicSupport() throws {
        let dependencies = prompt14Dependencies("--ui-testing-prompt14-loaded")

        #expect(dependencies.timeProvider.now == DemoPrompt14Fixtures.fixedNow)
        #expect(dependencies.timeProvider is FixedTimeProvider)
        #expect(try dependencies.idempotencyKeyProvider.nextKey().value == "prompt14-key-0001")
        #expect(try dependencies.idempotencyKeyProvider.nextKey().value == "prompt14-key-0002")
    }

    @Test("scaffold graph has a completed deterministic demo session")
    func scaffoldGraphDecodesTodayFixture() async throws {
        let dependencies = AppDependencies.scaffold()
        let request = APIRequest<TodaySummary>(method: .get, path: "/today")

        #expect(try await dependencies.authentication.restoreSession() == AuthSession(
            userID: "demo-user-v1",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: true
        ))

        let summary = try await dependencies.apiClient.send(request)
        #expect(summary == AppFixtures.today)
    }

    @Test("UI relaunch seed and preserve modes use the durable Keychain boundary")
    func uiRelaunchUsesDurableBoundary() {
        let seed = AppDependencies.demo(
            configuration: .resolve(
                arguments: ["--ui-testing"],
                buildFlavor: .debug
            )
        )
        let preserveConfiguration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing-preserve-state"],
            buildFlavor: .debug
        )
        let preserve = AppDependencies.demo(
            configuration: preserveConfiguration
        )

        #expect(seed.secureStore is KeychainSecureStore)
        #expect(preserve.secureStore is KeychainSecureStore)
        #expect(!preserveConfiguration.shouldResetDemoState)
        #expect(!preserveConfiguration.startsWithCompletedFixture)
        #expect(!preserveConfiguration.preloadsSyntheticOnboardingValues)
    }

    @Test("normal Debug relaunch uses the durable development boundary")
    func normalDebugRelaunchUsesDurableBoundary() {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: [],
            buildFlavor: .debug
        )
        let dependencies = AppDependencies.demo(configuration: configuration)

        #expect(configuration.demoStorageBoundary == .keychain)
        #expect(dependencies.secureStore is KeychainSecureStore)
        #expect(!configuration.shouldResetDemoState)
    }

    @Test("normal Debug relaunch restores partial onboarding without a password")
    func normalDebugRelaunchRestoresPartialOnboarding() async throws {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: [],
            buildFlavor: .debug
        )
        let first = AppDependencies.demo(configuration: configuration)
        try? await first.authentication.signOut()
        try? await first.onboarding.clear(for: DemoUser.id)

        let password = "local-pass"
        _ = try await first.authentication.signUp(
            email: "person@example.invalid",
            password: password
        )
        let session = try await first.authentication.confirmEmailForDevelopment()
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.displayName = "Pessoa Persistida"
        draft.heightCM = 171
        try await first.onboarding.saveDraft(draft, for: session.userID)

        let relaunched = AppDependencies.demo(configuration: configuration)
        #expect(try await relaunched.authentication.restoreSession() == session)
        #expect(
            try await relaunched.onboarding.loadDraft(for: session.userID)
                == draft
        )

        let persistedKeys = [
            "bodyflow.demo.session.v1",
            "bodyflow.demo.onboarding-draft.v1",
        ]
        for key in persistedKeys {
            let data = try await relaunched.secureStore.data(forKey: key)
            #expect(
                data.flatMap { String(data: $0, encoding: .utf8) }?
                    .contains(password) != true
            )
        }

        try await relaunched.authentication.signOut()
        try await relaunched.onboarding.clear(for: session.userID)
    }

    @Test("fixture catalog exposes the approved server-provided values")
    func fixtureCatalogExposesApprovedValues() {
        #expect(AppFixtures.today.energy.consumedKcal == 1_200)
        #expect(AppFixtures.today.energy.targetKcal == 1_935)
        #expect(AppFixtures.today.energy.remainingFoodKcal == 735)
        #expect(AppFixtures.today.routine.statusLabel == "3 de 5 concluídos")
        #expect(AppFixtures.today.nextAction.title == "Registrar almoço")

        #expect(
            AppFixtures.registration.commands.map(\.title)
                == ["Refeição", "Treino", "Peso", "Hidratação"]
        )
        #expect(
            AppFixtures.registration.commands.map(\.systemImage)
                == ["fork.knife", "figure.run", "scalemass", "drop"]
        )
        #expect(
            AppFixtures.registration.commands.map(\.kindID)
                == ["meal", "training", "weight", "hydration"]
        )
        #expect(
            AppFixtures.registration.disclaimer
                == "Demonstração local. Nenhum registro foi salvo."
        )

        #expect(AppFixtures.plan.title == "Plano semanal")
        #expect(AppFixtures.plan.plannedSessions == 4)
        #expect(AppFixtures.plan.completedSessions == 3)
        #expect(AppFixtures.plan.nextItemLabel == "Mobilidade · 20 min")

        #expect(AppFixtures.progress.level == 7)
        #expect(AppFixtures.progress.streakDays == 12)
        #expect(AppFixtures.progress.completedBlocks == 2)
        #expect(
            AppFixtures.progress.reevaluationLabel
                == "Próxima reavaliação em 9 dias"
        )

        #expect(AppFixtures.profile.title == "Perfil de demonstração")
        #expect(AppFixtures.profile.notifications == "Ativadas")
    }

    @Test("Prompt 13 Debug reads share exactly one repository actor")
    func prompt13DebugReadsShareOneActor() throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                buildFlavor: .debug
            )
        )

        let today = try #require(dependencies.today as? DemoBodyFlowRepository)
        let history = try #require(dependencies.history as? DemoBodyFlowRepository)
        let plan = try #require(dependencies.plan as? DemoBodyFlowRepository)
        let progress = try #require(dependencies.progress as? DemoBodyFlowRepository)
        let routine = try #require(dependencies.routine as? DemoBodyFlowRepository)
        let mealDetection = try #require(
            dependencies.mealDetection as? DemoBodyFlowRepository
        )
        let registration = try #require(
            dependencies.registration as? DemoBodyFlowRepository
        )
        let hydration = try #require(
            dependencies.hydration as? DemoBodyFlowRepository
        )
        let weight = try #require(
            dependencies.weight as? DemoBodyFlowRepository
        )

        #expect(today === history)
        #expect(today === plan)
        #expect(today === progress)
        #expect(today === routine)
        #expect(today === mealDetection)
        #expect(today === registration)
        #expect(today === hydration)
        #expect(today === weight)
    }

    @Test("Prompt 13 Debug graph exposes coherent shared read behavior")
    func prompt13DebugGraphReturnsCoherentReads() async throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                buildFlavor: .debug
            )
        )

        #expect(try await dependencies.today.today() == DemoBodyFlowFixtures.loadedToday)
        #expect(try await dependencies.plan.plan() == DemoBodyFlowFixtures.loadedPlan)
        #expect(try await dependencies.progress.progress() == DemoBodyFlowFixtures.loadedProgress)
        #expect(try await dependencies.history.history(.firstPage) == DemoBodyFlowFixtures.loadedHistory)
        #expect(
            try await dependencies.routine.list(
                kind: .supplement,
                includeArchived: false
            ) == DemoBodyFlowFixtures.loadedSupplementList
        )
    }

    @Test("Prompt 13 hydration weight and routine ports share coherent actor behavior")
    func prompt13Task11MutationPortsUseSharedActor() async throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                buildFlavor: .debug
            )
        )

        let beforeToday = try await dependencies.today.today()
        let beforeProgress = try await dependencies.progress.progress()
        let beforeHistory = try await dependencies.history.history(.firstPage)

        let hydration = try await dependencies.hydration.record(
            dependencyHydrationAttempt()
        )
        #expect(hydration == DemoBodyFlowFixtures.hydrationReceipt)
        #expect(
            try await dependencies.today.today()
                == DemoBodyFlowFixtures.postHydrationToday
        )

        let beforeWeightToday = try await dependencies.today.today()
        let weight = try await dependencies.weight.record(
            dependencyWeightAttempt()
        )
        #expect(weight == DemoBodyFlowFixtures.weightReceipt)
        #expect(try await dependencies.today.today() == beforeWeightToday)
        #expect(try await dependencies.progress.progress() == beforeProgress)
        #expect(try await dependencies.history.history(.firstPage) == beforeHistory)

        let routine = try await dependencies.routine.record(
            dependencyRoutineAttempt()
        )
        #expect(routine == DemoBodyFlowFixtures.routineTakenReceipt)
        #expect(
            try await dependencies.today.today()
                == DemoBodyFlowFixtures.today(
                    confirmation: .none,
                    hydrationRecorded: true,
                    routine: .taken
                )
        )
        #expect(
            try await dependencies.routine.list(
                kind: .supplement,
                includeArchived: false
            ) == DemoBodyFlowFixtures.postRoutineTakenSupplementList
        )
        #expect(
            try await dependencies.routine.history(
                kind: .supplement,
                itemID: "supplement-1",
                cursor: nil,
                limit: 20
            ) == DemoBodyFlowFixtures.postRoutineTakenSupplementHistory
        )
        #expect(beforeToday == DemoBodyFlowFixtures.loadedToday)
    }

    @Test("Prompt 13 registration existential mutates the shared Today and History actor")
    func prompt13RegistrationUsesSharedActorSnapshots() async throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                buildFlavor: .debug
            )
        )
        let registration: any RegistrationProviding = dependencies.registration
        let createdAt = Date(timeIntervalSince1970: 1_784_589_300)
        let detected = try await dependencies.mealDetection.detect(
            .text("texto que não será interpretado")
        )
        let proposed = try await registration.propose(MutationAttempt(
            operation: .proposalCreate,
            key: try IdempotencyKey(validating: "dependency-propose-0001"),
            payload: detected,
            createdAt: createdAt
        ))
        #expect(proposed == DemoBodyFlowFixtures.pendingMealRegistration)

        let confirmed = try await registration.confirm(MutationAttempt(
            operation: .proposalConfirm,
            key: try IdempotencyKey(validating: "dependency-confirm-0001"),
            payload: RegistrationIDCommand(registrationID: proposed.data.id),
            createdAt: createdAt
        ))

        #expect(confirmed == DemoBodyFlowFixtures.confirmedMealRegistration)
        #expect(
            try await dependencies.today.today()
                == DemoBodyFlowFixtures.postMealConfirmationToday
        )
        #expect(
            try await dependencies.history.history(.firstPage)
                == DemoBodyFlowFixtures.postMealConfirmationHistory
        )
    }
    #endif
}

private func releaseDependencies() -> AppDependencies {
    AppDependencies.make(
        configuration: .resolve(
            arguments: ["--ui-testing-prompt13-loaded"],
            buildFlavor: .release
        )
    )
}

private struct DependencyTransportPayload: Codable, Equatable, Sendable {
    let value: String
}

private actor DependencyLifecycle: SessionLifecycleProviding {
    private let lease = SessionLease(
        userID: "00000000-0000-4000-8000-000000000001",
        generation: 1,
        bearer: "dependency-bearer"
    )
    private(set) var signOutCount = 0

    func currentBearerToken() -> String? { lease.bearer }
    func leaseForRequest() -> SessionLease { lease }
    func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease {
        try validate(lease)
        return lease
    }
    func validate(_ candidate: SessionLease) throws {
        guard candidate == lease else {
            throw SessionLifecycleError.sessionSuperseded
        }
    }
    func signOut() -> RemoteRevocationOutcome {
        signOutCount += 1
        return .confirmed
    }
    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) throws -> UUID {
        try validate(lease)
        return UUID()
    }
    func finishPatientWork(_ id: UUID) {}
}

private struct DependencyTransportHarness: Sendable {
    let dependencies: AppDependencies
    let recorder: DependencyTransportRecorder
}

private func dependencyTransportHarness(
    sessionStore: AuthenticationSessionStore
) async throws -> DependencyTransportHarness {
    let recorder = DependencyTransportRecorder()
    await DependencyTransportURLProtocol.install(recorder: recorder)
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [DependencyTransportURLProtocol.self]
    let dependencies = AppDependencies.make(
        configuration: .resolve(arguments: [], buildFlavor: .release),
        mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
            configuration: try MobileAPIConfiguration(
                originString: "https://mobile.example.test"
            )
        ),
        mobileAPISession: URLSession(configuration: sessionConfiguration),
        supabaseAuthConfiguration: try SupabaseAuthConfiguration(
            originString: "https://project.example.test",
            key: "sb_publishable_synthetic"
        ),
        authenticationSessionStore: sessionStore,
        supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) },
        sessionRefreshPolicy: SessionRefreshPolicy(
            now: { Date(timeIntervalSince1970: 1_000) },
            leeway: 60
        )
    )
    return DependencyTransportHarness(dependencies: dependencies, recorder: recorder)
}

private func dependencyAuthenticationRecord(
    expiresAt: TimeInterval
) -> AuthenticationSessionRecord {
    let userID = "00000000-0000-4000-8000-000000000001"
    let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8)
        .dependencyBase64URL
    let payload = Data(#"{"sub":"\#(userID)"}"#.utf8)
        .dependencyBase64URL
    return AuthenticationSessionRecord(
        userID: userID,
        email: "member@fixture.invalid",
        isEmailConfirmed: true,
        isOnboardingCompleted: false,
        accessToken: "\(header).\(payload).synthetic",
        refreshToken: "refresh-synthetic",
        expiresAt: Date(timeIntervalSince1970: expiresAt)
    )
}

private extension Data {
    var dependencyBase64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private actor DependencyTransportRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

private final class DependencyTransportURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registry = DependencyTransportRegistry()
    private var loadingTask: Task<Void, Never>?

    static func install(recorder: DependencyTransportRecorder) async {
        await registry.install(recorder: recorder)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        loadingTask = Task {
            guard let recorder = await Self.registry.current() else { return }
            await recorder.record(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(
                #"{"data":{"value":"ok"},"meta":{"api_version":"v1","request_id":"dependency-request-0001"}}"#.utf8
            )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }
}

private actor DependencyTransportRegistry {
    private var recorder: DependencyTransportRecorder?

    func install(recorder: DependencyTransportRecorder) {
        self.recorder = recorder
    }

    func current() -> DependencyTransportRecorder? {
        recorder
    }
}

#if DEBUG
private let dependencyActionDate = Date(timeIntervalSince1970: 1_784_589_300)

private let addedPrompt14DependencyArguments = [
    "--ui-testing-prompt14-today-recommendations-stale",
    "--ui-testing-prompt14-next-page-failure-once",
    "--ui-testing-prompt14-invalid-cursor-recovery",
    "--ui-testing-prompt14-incomplete-detail",
    "--ui-testing-prompt14-mutation-failure-once",
    "--ui-testing-prompt14-markdown-external-link",
    "--ui-testing-prompt14-cover-expired",
    "--ui-testing-prompt14-cover-too-large",
    "--ui-testing-prompt14-cover-mime-mismatch",
    "--ui-testing-prompt14-cover-abusive-dimensions",
    "--ui-testing-prompt14-cover-external-path",
    "--ui-testing-prompt14-mascot-focus-active",
    "--ui-testing-prompt14-mascot-zen-neglected",
    "--ui-testing-prompt14-progress-complete-duplicate-badges",
    "--ui-testing-prompt14-persona-stateful",
]

private func prompt14Dependencies(_ argument: String) -> AppDependencies {
    AppDependencies.make(
        configuration: .resolve(
            arguments: ["--ui-testing", argument],
            buildFlavor: .debug
        )
    )
}

private func dependencyHydrationAttempt() throws -> MutationAttempt<HydrationCommand> {
    MutationAttempt(
        operation: .hydration,
        key: try IdempotencyKey(validating: "dependency-hydration-0001"),
        payload: try HydrationCommand(
            amountML: 250,
            occurredAt: APITimestamp(value: dependencyActionDate)
        ),
        createdAt: dependencyActionDate
    )
}

private func dependencyWeightAttempt() throws -> MutationAttempt<WeightCommand> {
    MutationAttempt(
        operation: .weight,
        key: try IdempotencyKey(validating: "dependency-weight-0001"),
        payload: try WeightCommand(
            weightKG: 78.4,
            recordedAt: dependencyActionDate
        ),
        createdAt: dependencyActionDate
    )
}

private func dependencyRoutineAttempt() throws
    -> MutationAttempt<RoutineActionCommand> {
    MutationAttempt(
        operation: .routineAction,
        key: try IdempotencyKey(validating: "dependency-routine-0001"),
        payload: try RoutineActionCommand(
            kind: .supplement,
            itemID: "supplement-1",
            status: .taken,
            reminderRuleID: "rule-08",
            scheduledFor: APITimestamp(
                value: Date(timeIntervalSince1970: 1_784_545_200)
            ),
            occurredAt: APITimestamp(value: dependencyActionDate),
            snoozedUntil: nil
        ),
        createdAt: dependencyActionDate
    )
}
#endif

private actor DependencyTokenProvider: SessionTokenProviding {
    private let token: String?

    init(token: String?) {
        self.token = token
    }

    func currentBearerToken() -> String? {
        token
    }
}
