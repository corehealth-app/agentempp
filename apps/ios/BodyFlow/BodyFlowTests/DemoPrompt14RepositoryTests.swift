#if DEBUG
import CoreGraphics
import Foundation
import Testing

@testable import BodyFlow

@Suite("Prompt 14 deterministic Debug repository")
struct DemoPrompt14RepositoryTests {
    @Test("Exact queries select complete pre-authored feed envelopes")
    func exactQueriesSelectAuthoredFeeds() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)

        let today = try await repository.content(
            DemoPrompt14Fixtures.todayQuery()
        )
        let library = try await repository.content(
            DemoPrompt14Fixtures.libraryQuery()
        )
        let next = try await repository.content(
            DemoPrompt14Fixtures.libraryNextQuery()
        )
        let saved = try await repository.content(
            DemoPrompt14Fixtures.savedQuery()
        )
        let nutrition = try await repository.content(
            DemoPrompt14Fixtures.nutritionQuery()
        )
        let sleep = try await repository.content(
            DemoPrompt14Fixtures.sleepQuery()
        )

        #expect(today == DemoPrompt14Fixtures.todayFeed)
        #expect(library == DemoPrompt14Fixtures.libraryFeed)
        #expect(next == DemoPrompt14Fixtures.libraryNextFeed)
        #expect(saved == DemoPrompt14Fixtures.savedFeed)
        #expect(nutrition == DemoPrompt14Fixtures.nutritionFeed)
        #expect(sleep == DemoPrompt14Fixtures.sleepFeed)
        #expect(today.meta.apiVersion == "1")
        #expect(today.meta.requestID == "90000000-0000-4000-8000-000000000001")
        #expect(
            today.data.items.map(\.publicationID) == [
                "10000000-0000-4000-8000-000000000001",
                "10000000-0000-4000-8000-000000000003",
                "10000000-0000-4000-8000-000000000005",
            ]
        )
        #expect(
            library.data.items.map(\.publicationID) == [
                "10000000-0000-4000-8000-000000000001",
                "10000000-0000-4000-8000-000000000002",
                "10000000-0000-4000-8000-000000000003",
                "10000000-0000-4000-8000-000000000004",
            ]
        )
        #expect(
            next.data.items.map(\.publicationID) == [
                "10000000-0000-4000-8000-000000000005",
                "10000000-0000-4000-8000-000000000006",
            ]
        )
        #expect(library.data.nextCursor == "opaque 🧭 / + = ? keep-byte-for-byte")
        #expect(next.data.nextCursor == nil)
        #expect(saved.data.items.map(\.saved) == [true, true])
        #expect(saved.data.items.map(\.completed) == [true, false])
        #expect(nutrition.data.items.map(\.category) == [.nutrition, .nutrition])
        #expect(sleep.data.items.map(\.category) == [.sleep])
    }

    @Test("Query selection compares every field and never decodes the opaque cursor")
    func querySelectionIsExactAndCursorIsOpaque() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)
        let authored = try DemoPrompt14Fixtures.libraryNextQuery()

        #expect(authored.cursor == "opaque 🧭 / + = ? keep-byte-for-byte")
        #expect(try await repository.content(authored) == DemoPrompt14Fixtures.libraryNextFeed)

        let changedLimit = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 19,
            cursor: authored.cursor
        )
        let changedCategory = try ContentFeedQuery(
            surface: .library,
            category: .nutrition,
            limit: 20,
            cursor: authored.cursor
        )
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.content(changedLimit)
        }
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.content(changedCategory)
        }
    }

    @Test("Every valid content fixture passes contract and Markdown validation")
    func validFixturesPassBoundariesBeforePublication() throws {
        for response in DemoPrompt14Fixtures.validFeedResponses {
            try PublishedContentContractValidator.validate(response.data)
        }
        for response in DemoPrompt14Fixtures.validDetailResponses {
            try PublishedContentContractValidator.validate(response.data)
            _ = try BodyFlowMarkdownParser().parse(response.data.bodyMarkdown)
        }

        #expect(
            DemoPrompt14Fixtures.validDetail.bodyMarkdown
                .contains("CONTEÚDO SINTÉTICO PROMPT 14")
        )
        #expect(
            DemoPrompt14Fixtures.validFeedResponses
                .flatMap(\.data.items)
                .allSatisfy { $0.title.contains("Sintétic") }
        )
        #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try BodyFlowMarkdownParser().parse(
                DemoPrompt14Fixtures.invalidMarkdownDetail.bodyMarkdown
            )
        }
    }

    @Test("Detail read publishes authored content and maps guarded failures")
    func detailReadAndGuardedFailures() async throws {
        let loaded = DemoPrompt14Repository(scenario: .loaded)
        let detail = try await loaded.contentDetail(
            publicationID: "10000000-0000-4000-8000-000000000001"
        )
        #expect(detail == DemoPrompt14Fixtures.validDetailResponse)
        #expect(detail.data.summary.version == 4)
        #expect(
            detail.data.summary.cover?.url
                == "/api/mobile/v1/content/covers/50000000-0000-4000-8000-000000000001"
        )

        let missing = DemoPrompt14Repository(scenario: .contentNotFound)
        await #expect(throws: BodyFlowCapabilityError.contentNotFound) {
            try await missing.contentDetail(
                publicationID: "10000000-0000-4000-8000-000000000001"
            )
        }

        let gated = DemoPrompt14Repository(scenario: .subscriptionRequired)
        await #expect(throws: BodyFlowCapabilityError.subscriptionRequired) {
            try await gated.contentDetail(
                publicationID: "10000000-0000-4000-8000-000000000001"
            )
        }

        let invalidMarkdown = DemoPrompt14Repository(scenario: .markdownInvalid)
        await #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try await invalidMarkdown.contentDetail(
                publicationID: "10000000-0000-4000-8000-000000000001"
            )
        }
    }

    @Test("Valid detail publishes the exact canonical mobile Markdown")
    func validDetailUsesCanonicalMobileMarkdown() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)
        let expected = """
        ## CONTEÚDO SINTÉTICO PROMPT 14

        Este texto é uma amostra inteiramente sintética, criada apenas para validar a leitura determinística no aplicativo BodyFlow.

        * Nenhuma pessoa real é descrita.
        * Nenhuma recomendação clínica é oferecida.
        * Nenhum dado sai deste cenário local.

        **Resultado esperado:** uma apresentação visivelmente fictícia e segura para testes.
        """ + "\n"

        let response = try await repository.contentDetail(
            publicationID: "10000000-0000-4000-8000-000000000001"
        )

        #expect(response.data.bodyMarkdown == expected)
    }

    @Test("Coach fixtures author balanced and all selectable snapshots")
    func coachFixturesAreCompleteAndLossless() throws {
        let snapshots = DemoPrompt14Fixtures.coachResponses.map(\.data)

        #expect(snapshots.count == 6)
        #expect(snapshots.map(\.selected) == [nil, .focus, .impulse, .zen, .focus, nil])
        #expect(snapshots.map(\.effective) == [.balanced, .focus, .impulse, .zen, .focus, .balanced])
        #expect(
            snapshots.map(\.mascot.state) == [
                .inactive,
                .reactivating,
                .active,
                .evolving,
                .neglected,
                .unknown("future-synthetic"),
            ]
        )
        #expect(
            snapshots[0].options.map(\.name)
                == ["Foco", "Impulso", "Zen"]
        )
        #expect(
            snapshots.allSatisfy {
                $0.contractVersion == "bodyflow.coach-persona.v1"
                    && CoachExperienceV1PresentationContract.validatedSnapshot(
                        from: MobileResponse(data: $0, meta: DemoPrompt14Fixtures.coachMetadata)
                    ) == $0
            }
        )

        let encoded = try JSONEncoder().encode(snapshots[5].mascot.state)
        #expect(
            try JSONDecoder().decode(MascotWireState.self, from: encoded)
                == .unknown("future-synthetic")
        )
    }

    @Test("Coach factory returns one authored snapshot without deriving persona")
    func coachProviderReturnsAuthoredSnapshot() async throws {
        let provider = DemoPrompt14CoachProvider(scenario: .loaded)
        #expect(
            try await provider.coachExperience()
                == DemoPrompt14Fixtures.balancedCoachResponse
        )
    }

    @Test("Stateful persona provider reads the same persisted session state")
    func statefulPersonaProviderReadsPersistedSessionState() async throws {
        let state = DemoPrompt14PersonaSessionState()
        let factory = DemoPrompt14CoachExperienceSessionFactory(
            selection: .personaStateful,
            personaState: state
        )
        let provider = factory.makeCoachExperience(userID: DemoUser.id)

        #expect(try await state.selectedPersona(for: DemoUser.id) == nil)
        #expect(
            try await provider.coachExperience()
                == DemoPrompt14Fixtures.balancedCoachResponse
        )

        try await state.setPersona(.zen, for: DemoUser.id)

        #expect(try await state.selectedPersona(for: DemoUser.id) == .zen)
        #expect(
            try await provider.coachExperience()
                == DemoPrompt14Fixtures.zenCoachResponse
        )
    }

    @Test("A new stateful persona session resets while loaded stays static")
    func statefulPersonaResetsWithoutChangingLoaded() async throws {
        let firstState = DemoPrompt14PersonaSessionState()
        let secondState = DemoPrompt14PersonaSessionState()
        let firstProvider = DemoPrompt14CoachExperienceSessionFactory(
            selection: .personaStateful,
            personaState: firstState
        ).makeCoachExperience(userID: DemoUser.id)
        let secondProvider = DemoPrompt14CoachExperienceSessionFactory(
            selection: .personaStateful,
            personaState: secondState
        ).makeCoachExperience(userID: DemoUser.id)
        let loaded = DemoPrompt14CoachProvider(scenario: .loaded)

        try await firstState.setPersona(.zen, for: DemoUser.id)

        #expect(
            try await firstProvider.coachExperience()
                == DemoPrompt14Fixtures.zenCoachResponse
        )
        #expect(
            try await secondProvider.coachExperience()
                == DemoPrompt14Fixtures.balancedCoachResponse
        )
        #expect(
            try await loaded.coachExperience()
                == DemoPrompt14Fixtures.balancedCoachResponse
        )
    }

    @Test("Mascot variants provider cycles through the six authored snapshots")
    func mascotVariantsProviderCyclesAuthoredSnapshots() async throws {
        let variants = DemoPrompt14CoachProvider(scenario: .mascotVariants)
        var firstCycle: [CoachExperienceResponse] = []
        var repeatedCycle: [CoachExperienceResponse] = []

        for _ in 0..<6 {
            firstCycle.append(try await variants.coachExperience())
        }
        for _ in 0..<6 {
            repeatedCycle.append(try await variants.coachExperience())
        }

        #expect(firstCycle == DemoPrompt14Fixtures.coachResponses)
        #expect(repeatedCycle == DemoPrompt14Fixtures.coachResponses)
    }

    @Test("Progress fixtures preserve complete minimum null and streak-zero envelopes")
    func progressFixturesAreComplete() {
        let complete = DemoPrompt14Fixtures.completeProgress
        let minimum = DemoPrompt14Fixtures.minimumProgress
        let empty = DemoPrompt14Fixtures.emptyProgress
        let zero = DemoPrompt14Fixtures.streakZeroProgress

        #expect(complete.data?.xpTotal == 2_450)
        #expect(complete.data?.level == 7)
        #expect(complete.data?.currentStreak == 12)
        #expect(complete.data?.deficitBlock == 735)
        #expect(
            complete.data?.badgesEarned == [
                "70000000-0000-4000-8000-000000000001",
                "70000000-0000-4000-8000-000000000002",
            ]
        )
        #expect(minimum.data?.xpTotal == 0)
        #expect(minimum.data?.level == 1)
        #expect(minimum.data?.deficitBlock == 0)
        #expect(minimum.data?.badgesEarned == [])
        #expect(empty.data == nil)
        #expect(zero.data?.xpTotal == 980)
        #expect(zero.data?.currentStreak == 0)
        #expect(zero.data?.longestStreak == 9)
        #expect(zero.data?.deficitBlock == 210)
        #expect(
            [complete, minimum, empty, zero].map(\.meta.requestID) == [
                "92000000-0000-4000-8000-000000000001",
                "92000000-0000-4000-8000-000000000002",
                "92000000-0000-4000-8000-000000000003",
                "92000000-0000-4000-8000-000000000004",
            ]
        )
    }

    @Test("Empty offline error unavailable and stale behavior is deterministic")
    func readScenarioBehaviorIsDeterministic() async throws {
        let empty = DemoPrompt14Repository(scenario: .empty)
        #expect(
            try await empty.content(DemoPrompt14Fixtures.todayQuery())
                == DemoPrompt14Fixtures.emptyTodayFeed
        )
        #expect(
            try await empty.content(DemoPrompt14Fixtures.libraryQuery())
                == DemoPrompt14Fixtures.emptyLibraryFeed
        )

        let offline = DemoPrompt14Repository(scenario: .offline)
        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await offline.content(DemoPrompt14Fixtures.todayQuery())
        }

        let error = DemoPrompt14Repository(scenario: .error)
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await error.content(DemoPrompt14Fixtures.todayQuery())
        }

        let unavailable = DemoPrompt14Repository(scenario: .unavailable)
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await unavailable.content(DemoPrompt14Fixtures.todayQuery())
        }

        let stale = DemoPrompt14Repository(scenario: .stale)
        #expect(
            try await stale.content(DemoPrompt14Fixtures.todayQuery())
                == DemoPrompt14Fixtures.todayFeed
        )
        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await stale.content(DemoPrompt14Fixtures.todayQuery())
        }
    }

    @Test("Empty saved sleep initial query returns its authored empty envelope")
    func emptySavedSleepInitialQueryReturnsAuthoredEmptyEnvelope() async throws {
        let repository = DemoPrompt14Repository(scenario: .empty)
        let query = try ContentFeedQuery(
            surface: .saved,
            category: .sleep,
            limit: 20,
            cursor: nil
        )

        #expect(
            try await repository.content(query)
                == DemoPrompt14Fixtures.emptySleepFeed
        )
    }

    @Test("Ending a loading session cancels late reads and prevents all later publication")
    func endSessionCancelsLateRead() async throws {
        let repository = DemoPrompt14Repository(scenario: .loading)
        let pending = Task {
            try await repository.content(DemoPrompt14Fixtures.todayQuery())
        }
        await repository.waitUntilPendingReadCountForTesting(1)

        await repository.endSession()

        await #expect(throws: CancellationError.self) {
            try await pending.value
        }
        await #expect(throws: CancellationError.self) {
            try await repository.content(DemoPrompt14Fixtures.todayQuery())
        }
        await #expect(throws: CancellationError.self) {
            try await repository.contentDetail(
                publicationID: "10000000-0000-4000-8000-000000000001"
            )
        }
        await #expect(throws: CancellationError.self) {
            try await repository.recordRead(prompt14ReadAttempt())
        }
    }

    @Test("Read events record canonical state and replay their exact attempts")
    func readEventsAndExactReplay() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)
        let impression = try Prompt14Attempts.read(
            .impression,
            origin: .today,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-impression-0001"
        )
        let opened = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-opened-0001"
        )
        let completed = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-completed-0001"
        )

        let impressionState = try await repository.recordRead(impression)
        let openedState = try await repository.recordRead(opened)
        let completedState = try await repository.recordRead(completed)
        let replay = try await repository.recordRead(completed)

        #expect(impressionState.data.changed)
        #expect(!impressionState.data.replayed)
        #expect(openedState.data.changed)
        #expect(!openedState.data.completed)
        #expect(completedState.data.changed)
        #expect(completedState.data.completed)
        #expect(!replay.data.changed)
        #expect(replay.data.replayed)
        #expect(replay.data.publicationID == completed.payload.publicationID)
        #expect(replay.data.version == completed.payload.body.version)
    }

    @Test("Save and unsave reconcile canonical feed state without changing official fixtures")
    func saveAndUnsaveReconcileOnlyContentState() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)
        let publicationID = DemoPrompt14Fixtures.secondSummary.publicationID
        let saved = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-save-0001"
        )
        let unchangedSave = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-save-0002"
        )
        let unsaved = try Prompt14Attempts.saved(
            false,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-unsave-0001"
        )

        let saveState = try await repository.setSaved(saved)
        let noOpState = try await repository.setSaved(unchangedSave)
        let unsaveState = try await repository.setSaved(unsaved)
        let library = try await repository.content(DemoPrompt14Fixtures.libraryQuery())

        #expect(saveState.data.changed)
        #expect(saveState.data.saved)
        #expect(!noOpState.data.changed)
        #expect(noOpState.data.saved)
        #expect(unsaveState.data.changed)
        #expect(!unsaveState.data.saved)
        #expect(
            library.data.items.first { $0.publicationID == publicationID }?.saved == false
        )
        #expect(DemoPrompt14Fixtures.completeProgress.data?.xpTotal == 2_450)
        #expect(DemoPrompt14Fixtures.completeProgress.data?.level == 7)
        #expect(DemoPrompt14Fixtures.completeProgress.data?.currentStreak == 12)
        #expect(DemoPrompt14Fixtures.balancedCoachResponse.data.mascot.state == .inactive)
        #expect(DemoPrompt14Fixtures.todayFeed.data.items.count == 3)
    }

    @Test("Completed content is one-way and future completion attempts are no-ops")
    func completionIsOneWay() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)
        let publicationID = DemoPrompt14Fixtures.secondSummary.publicationID
        let completion = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-complete-one-way-0001"
        )
        let laterCompletion = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-complete-one-way-0002"
        )

        let first = try await repository.recordRead(completion)
        let second = try await repository.recordRead(laterCompletion)
        let library = try await repository.content(DemoPrompt14Fixtures.libraryQuery())

        #expect(first.data.changed)
        #expect(first.data.completed)
        #expect(!second.data.changed)
        #expect(second.data.completed)
        #expect(
            library.data.items.first { $0.publicationID == publicationID }?.completed == true
        )
    }

    @Test("Mutable content state overlays authored detail without changing body metadata or version")
    func mutableStateOverlaysOnlyAuthoredDetailState() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)
        let unsave = try Prompt14Attempts.saved(
            false,
            publicationID: DemoPrompt14Fixtures.firstSummary.publicationID,
            version: DemoPrompt14Fixtures.firstSummary.version,
            key: "content-detail-unsave-0001"
        )

        _ = try await repository.setSaved(unsave)
        let detail = try await repository.contentDetail(
            publicationID: DemoPrompt14Fixtures.firstSummary.publicationID
        )

        #expect(!detail.data.summary.saved)
        #expect(detail.data.summary.completed)
        #expect(detail.data.summary.version == DemoPrompt14Fixtures.firstSummary.version)
        #expect(detail.data.bodyMarkdown == DemoPrompt14Fixtures.validDetail.bodyMarkdown)
        #expect(detail.meta == DemoPrompt14Fixtures.validDetailResponse.meta)
    }

    @Test("A globally reused key conflicts for changed operation route payload or timestamp")
    func idempotencyKeyRequiresExactGlobalAttemptIdentity() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)
        let first = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-global-key-0001"
        )
        _ = try await repository.recordRead(first)

        let differentRoute = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.firstSummary.publicationID,
            version: DemoPrompt14Fixtures.firstSummary.version,
            key: first.key.value
        )
        let differentBody = try Prompt14Attempts.read(
            .impression,
            origin: .library,
            publicationID: first.payload.publicationID,
            version: first.payload.body.version,
            key: first.key.value
        )
        let differentTimestamp = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: first.payload.publicationID,
            version: first.payload.body.version,
            key: first.key.value,
            createdAt: prompt14AttemptDate.addingTimeInterval(1)
        )
        let differentOperation = try Prompt14Attempts.saved(
            true,
            publicationID: first.payload.publicationID,
            version: first.payload.body.version,
            key: first.key.value
        )

        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.recordRead(differentRoute)
        }
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.recordRead(differentBody)
        }
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.recordRead(differentTimestamp)
        }
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.setSaved(differentOperation)
        }
    }

    @Test("Identical in-progress attempts return the bounded retryable error")
    func identicalInProgressAttemptIsRejected() async throws {
        let gate = DemoPrompt14MutationGate()
        let repository = DemoPrompt14Repository(
            scenario: .loaded,
            mutationGate: gate
        )
        let attempt = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-in-progress-0001"
        )
        let first = Task {
            return try await repository.recordRead(attempt)
        }
        await gate.waitUntilStarted()

        await #expect(throws: BodyFlowCapabilityError.idempotencyRequestInProgress) {
            try await repository.recordRead(attempt)
        }

        await repository.endSession()
        await gate.finish()
        await #expect(throws: CancellationError.self) {
            try await first.value
        }
        #expect(await repository.mutationLedgerCountForTesting() == 0)
    }

    @Test("Version and deterministic one-shot scenario conflicts do not mutate or complete a ledger entry")
    func versionAndScenarioConflictAreOneShotAndSafe() async throws {
        let publicationID = DemoPrompt14Fixtures.secondSummary.publicationID
        let stale = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version + 1,
            key: "content-stale-version-0001"
        )
        let loaded = DemoPrompt14Repository(scenario: .loaded)
        await #expect(throws: BodyFlowCapabilityError.contentVersionChanged) {
            try await loaded.setSaved(stale)
        }
        #expect(
            try await loaded.content(DemoPrompt14Fixtures.libraryQuery())
                .data.items.first { $0.publicationID == publicationID }?.saved == false
        )

        let conflict = DemoPrompt14Repository(scenario: .conflict)
        let mutation = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-scenario-conflict-0001"
        )
        await #expect(throws: BodyFlowCapabilityError.contentVersionChanged) {
            try await conflict.setSaved(mutation)
        }
        let retry = try await conflict.setSaved(mutation)
        #expect(retry.data.changed)
        #expect(retry.data.saved)

        let completionConflict = DemoPrompt14Repository(scenario: .conflict)
        let completion = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-completion-conflict-0001"
        )
        await #expect(throws: BodyFlowCapabilityError.contentVersionChanged) {
            try await completionConflict.recordRead(completion)
        }
        #expect(try await completionConflict.recordRead(completion).data.changed)
    }

    @Test("Opened error is one-shot and leaves no completed replay before its retry")
    func openedErrorIsOneShot() async throws {
        let repository = DemoPrompt14Repository(scenario: .openedError)
        let opened = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-opened-error-0001"
        )

        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await repository.recordRead(opened)
        }
        let retry = try await repository.recordRead(opened)
        #expect(retry.data.changed)
        #expect(!retry.data.replayed)
    }

    @Test("Ending a controlled mutation rejects its late completion and isolates a fresh user session")
    func endingControlledMutationClearsSessionState() async throws {
        let gate = DemoPrompt14MutationGate()
        let firstRepository = DemoPrompt14Repository(
            scenario: .loaded,
            mutationGate: gate
        )
        let factory = DemoPrompt14PublishedContentSessionFactory(scenario: .loaded)
        let second = factory.makeSession(userID: "prompt14-user-b")
        let secondRepository = try #require(second.state as? DemoPrompt14Repository)
        let attempt = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-end-session-0001"
        )
        let late = Task {
            return try await firstRepository.setSaved(attempt)
        }
        await gate.waitUntilStarted()

        await firstRepository.endSession()
        await gate.finish()
        await #expect(throws: CancellationError.self) {
            try await late.value
        }
        await #expect(throws: CancellationError.self) {
            try await firstRepository.setSaved(attempt)
        }
        #expect(await firstRepository.mutationLedgerCountForTesting() == 0)

        let fresh = try await secondRepository.setSaved(attempt)
        #expect(fresh.data.changed)
        #expect(!fresh.data.replayed)
    }

    @Test("Saved surface derives membership from authored candidates and session state")
    func savedSurfaceTracksSaveAndUnsaveMembership() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)
        let secondID = DemoPrompt14Fixtures.secondSummary.publicationID
        let firstID = DemoPrompt14Fixtures.firstSummary.publicationID
        let thirdID = DemoPrompt14Fixtures.thirdSummary.publicationID
        let initial = try await repository.content(DemoPrompt14Fixtures.savedQuery())

        #expect(initial.data.items.map(\.publicationID) == [firstID, thirdID])

        _ = try await repository.setSaved(
            Prompt14Attempts.saved(
                true,
                publicationID: secondID,
                version: DemoPrompt14Fixtures.secondSummary.version,
                key: "content-saved-membership-0001"
            )
        )
        let afterSave = try await repository.content(DemoPrompt14Fixtures.savedQuery())

        #expect(
            afterSave.data.items.map(\.publicationID)
                == [firstID, secondID, thirdID]
        )
        #expect(afterSave.meta == initial.meta)
        #expect(afterSave.data.nextCursor == initial.data.nextCursor)

        _ = try await repository.setSaved(
            Prompt14Attempts.saved(
                false,
                publicationID: firstID,
                version: DemoPrompt14Fixtures.firstSummary.version,
                key: "content-saved-membership-0002"
            )
        )
        let afterUnsave = try await repository.content(DemoPrompt14Fixtures.savedQuery())

        #expect(afterUnsave.data.items.map(\.publicationID) == [secondID, thirdID])

        let empty = DemoPrompt14Repository(scenario: .empty)
        _ = try await empty.setSaved(
            Prompt14Attempts.saved(
                true,
                publicationID: secondID,
                version: DemoPrompt14Fixtures.secondSummary.version,
                key: "content-empty-saved-0001"
            )
        )
        #expect(
            try await empty.content(DemoPrompt14Fixtures.savedQuery())
                == DemoPrompt14Fixtures.emptySavedFeed
        )
    }

    @Test("Replay preserves its original consolidated state after an intervening mutation")
    func replayPreservesOriginalConsolidatedState() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)
        let publicationID = DemoPrompt14Fixtures.secondSummary.publicationID
        let save = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-historical-save-0001"
        )
        let completion = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-historical-completion-0001"
        )
        let unsave = try Prompt14Attempts.saved(
            false,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-historical-unsave-0001"
        )

        let original = try await repository.setSaved(save)
        _ = try await repository.recordRead(completion)
        _ = try await repository.setSaved(unsave)
        let library = try await repository.content(
            DemoPrompt14Fixtures.libraryQuery()
        )
        let current = try #require(
            library.data.items.first { $0.publicationID == publicationID }
        )

        #expect(!current.saved)
        #expect(current.completed)

        let replay = try await repository.setSaved(save)

        #expect(original.data.saved)
        #expect(!original.data.completed)
        #expect(replay.data.saved)
        #expect(!replay.data.completed)
        #expect(!replay.data.changed)
        #expect(replay.data.replayed)
        #expect(replay.meta == original.meta)
    }

    @Test("An incompatible in-progress attempt conflicts while an identical one is retryable")
    func incompatibleInProgressAttemptConflicts() async throws {
        let gate = DemoPrompt14MutationGate()
        let repository = DemoPrompt14Repository(
            scenario: .loaded,
            mutationGate: gate
        )
        let first = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-in-progress-conflict-0001"
        )
        let incompatible = try Prompt14Attempts.saved(
            false,
            publicationID: first.payload.publicationID,
            version: first.payload.body.version,
            key: first.key.value
        )
        let pending = Task { try await repository.setSaved(first) }
        await gate.waitUntilStarted()

        await #expect(throws: BodyFlowCapabilityError.idempotencyRequestInProgress) {
            try await repository.setSaved(first)
        }
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.setSaved(incompatible)
        }

        await repository.endSession()
        await gate.finish()
        await #expect(throws: CancellationError.self) {
            try await pending.value
        }
    }

    @Test("Completed session A state and replay key never cross into session B")
    func completedSessionIsFullyIsolated() async throws {
        let factory = DemoPrompt14PublishedContentSessionFactory(scenario: .loaded)
        let sessionA = factory.makeSession(userID: "prompt14-complete-user-a")
        let repositoryA = try #require(sessionA.state as? DemoPrompt14Repository)
        let publicationID = DemoPrompt14Fixtures.secondSummary.publicationID
        let attempt = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-complete-session-0001"
        )

        let completed = try await repositoryA.setSaved(attempt)
        let replay = try await repositoryA.setSaved(attempt)
        #expect(completed.data.changed)
        #expect(replay.data.replayed)
        await sessionA.lifetime.endSession()

        let sessionB = factory.makeSession(userID: "prompt14-complete-user-b")
        let repositoryB = try #require(sessionB.state as? DemoPrompt14Repository)
        let before = try await sessionB.listing.content(
            DemoPrompt14Fixtures.libraryQuery()
        )
        #expect(
            before.data.items.first { $0.publicationID == publicationID }?.saved
                == false
        )

        let fresh = try await repositoryB.setSaved(attempt)
        #expect(fresh.data.changed)
        #expect(!fresh.data.replayed)
    }

    @Test("Invalid attempts fail guards without consuming one-shot scenarios")
    func invalidAttemptsDoNotConsumeOneShotFailures() async throws {
        let wrongReadOperation = MutationAttempt(
            operation: MutationOperation.contentSave,
            key: try IdempotencyKey(
                validating: "content-wrong-read-operation-0001"
            ),
            payload: ContentReadCommand(
                publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
                body: ContentReadBody(
                    event: .opened,
                    origin: .library,
                    version: DemoPrompt14Fixtures.secondSummary.version
                )
            ),
            createdAt: prompt14AttemptDate
        )
        let openedError = DemoPrompt14Repository(scenario: .openedError)
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await openedError.recordRead(wrongReadOperation)
        }

        let unknownOpened = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: "10000000-0000-4000-8000-999999999999",
            version: 1,
            key: "content-unknown-opened-publication-0001"
        )
        await #expect(throws: BodyFlowCapabilityError.contentNotFound) {
            try await openedError.recordRead(unknownOpened)
        }

        let staleOpened = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version + 1,
            key: "content-invalid-opened-error-0001"
        )
        await #expect(throws: BodyFlowCapabilityError.contentVersionChanged) {
            try await openedError.recordRead(staleOpened)
        }
        #expect(await openedError.mutationLedgerCountForTesting() == 0)
        let validOpened = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-valid-opened-error-0001"
        )
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await openedError.recordRead(validOpened)
        }
        #expect(try await openedError.recordRead(validOpened).data.changed)

        let conflict = DemoPrompt14Repository(scenario: .conflict)
        let wrongSaveOperation = MutationAttempt(
            operation: MutationOperation.contentRead,
            key: try IdempotencyKey(
                validating: "content-wrong-save-operation-0001"
            ),
            payload: ContentSaveCommand(
                publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
                body: ContentSaveBody(
                    saved: true,
                    version: DemoPrompt14Fixtures.secondSummary.version
                )
            ),
            createdAt: prompt14AttemptDate
        )
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await conflict.setSaved(wrongSaveOperation)
        }

        let unknownSave = try Prompt14Attempts.saved(
            true,
            publicationID: "10000000-0000-4000-8000-999999999999",
            version: 1,
            key: "content-unknown-save-publication-0001"
        )
        await #expect(throws: BodyFlowCapabilityError.contentNotFound) {
            try await conflict.setSaved(unknownSave)
        }

        let staleSave = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version + 1,
            key: "content-invalid-conflict-0001"
        )
        await #expect(throws: BodyFlowCapabilityError.contentVersionChanged) {
            try await conflict.setSaved(staleSave)
        }
        #expect(await conflict.mutationLedgerCountForTesting() == 0)
        let validSave = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-valid-conflict-0001"
        )
        await #expect(throws: BodyFlowCapabilityError.contentVersionChanged) {
            try await conflict.setSaved(validSave)
        }
        #expect(try await conflict.setSaved(validSave).data.changed)
    }

    @Test("A pre-cancelled opened request does not consume the openedError one-shot")
    func cancelledOpenedRequestPreservesOneShotFailure() async throws {
        let repository = DemoPrompt14Repository(scenario: .openedError)
        let attempt = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-cancelled-opened-error-0001"
        )
        let cancelled = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await repository.recordRead(attempt)
        }

        await #expect(throws: CancellationError.self) {
            try await cancelled.value
        }
        #expect(await repository.mutationLedgerCountForTesting() == 0)
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await repository.recordRead(attempt)
        }
        #expect(try await repository.recordRead(attempt).data.changed)
    }

    @Test("A pre-cancelled save does not consume the conflict one-shot")
    func cancelledSavePreservesOneShotFailure() async throws {
        let repository = DemoPrompt14Repository(scenario: .conflict)
        let attempt = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-cancelled-save-conflict-0001"
        )
        let cancelled = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await repository.setSaved(attempt)
        }

        await #expect(throws: CancellationError.self) {
            try await cancelled.value
        }
        #expect(await repository.mutationLedgerCountForTesting() == 0)
        await #expect(throws: BodyFlowCapabilityError.contentVersionChanged) {
            try await repository.setSaved(attempt)
        }
        #expect(try await repository.setSaved(attempt).data.changed)
    }

    @Test("Content mutation leaves real Today Progress and coach providers unchanged")
    func contentMutationDoesNotPatchRealGraphProviders() async throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt14-loaded"],
                buildFlavor: .debug
            )
        )
        let userID = "prompt14-real-graph-user"
        let session = dependencies.publishedContentSessions.makeSession(
            userID: userID
        )
        let coach = dependencies.coachExperienceSessions.makeCoachExperience(
            userID: userID
        )
        let beforeToday = try await dependencies.today.today()
        let beforeProgress = try await dependencies.progress.progress()
        let beforeCoach = try await coach.coachExperience()

        _ = try await session.state.setSaved(
            Prompt14Attempts.saved(
                true,
                publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
                version: DemoPrompt14Fixtures.secondSummary.version,
                key: "content-real-graph-save-0001"
            )
        )

        #expect(try await dependencies.today.today() == beforeToday)
        #expect(try await dependencies.progress.progress() == beforeProgress)
        #expect(try await coach.coachExperience() == beforeCoach)
    }

    @Test("Two controlled mutations coexist and session end cancels both exactly once")
    func endSessionCancelsAllConcurrentMutations() async throws {
        let gate = DemoPrompt14MutationGate()
        let repository = DemoPrompt14Repository(
            scenario: .loaded,
            mutationGate: gate
        )
        let save = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-concurrent-save-0001"
        )
        let completion = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.fourthSummary.publicationID,
            version: DemoPrompt14Fixtures.fourthSummary.version,
            key: "content-concurrent-complete-0001"
        )
        let pendingSave = Task { try await repository.setSaved(save) }
        let pendingCompletion = Task { try await repository.recordRead(completion) }
        await gate.waitUntilStarted(count: 2)

        #expect(await repository.mutationLedgerCountForTesting() == 2)
        await repository.endSession()
        await gate.finish()

        await #expect(throws: CancellationError.self) {
            try await pendingSave.value
        }
        await #expect(throws: CancellationError.self) {
            try await pendingCompletion.value
        }
        #expect(await repository.mutationLedgerCountForTesting() == 0)
    }

    @Test("Cancelling one controlled task frees its ledger entry for an exact retry")
    func individualCancellationAllowsRetry() async throws {
        let gate = DemoPrompt14MutationGate()
        let repository = DemoPrompt14Repository(
            scenario: .loaded,
            mutationGate: gate
        )
        let attempt = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-cancel-retry-0001"
        )
        let cancelled = Task { try await repository.setSaved(attempt) }
        await gate.waitUntilStarted(count: 1)

        cancelled.cancel()
        await #expect(throws: CancellationError.self) {
            try await cancelled.value
        }
        #expect(await repository.mutationLedgerCountForTesting() == 0)

        let retry = Task { try await repository.setSaved(attempt) }
        await gate.waitUntilStarted(count: 2)
        await gate.finish()
        let response = try await retry.value

        #expect(response.data.changed)
        #expect(response.data.saved)
        #expect(!response.data.replayed)
    }

    @Test("Computed mutation state stays private until the final generation check")
    func mutationCommitIsAtomic() async throws {
        let commitGate = DemoPrompt14MutationGate()
        let repository = DemoPrompt14Repository(
            scenario: .loaded,
            mutationCommitGate: commitGate
        )
        let publicationID = DemoPrompt14Fixtures.secondSummary.publicationID
        let attempt = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-atomic-commit-0001"
        )
        let pending = Task { try await repository.setSaved(attempt) }
        await commitGate.waitUntilStarted(count: 1)

        let whilePending = try await repository.content(
            DemoPrompt14Fixtures.libraryQuery()
        )
        #expect(
            whilePending.data.items.first { $0.publicationID == publicationID }?.saved
                == false
        )

        pending.cancel()
        await #expect(throws: CancellationError.self) {
            try await pending.value
        }
        #expect(await repository.mutationLedgerCountForTesting() == 0)
        let afterCancellation = try await repository.content(
            DemoPrompt14Fixtures.libraryQuery()
        )
        #expect(
            afterCancellation.data.items.first { $0.publicationID == publicationID }?.saved
                == false
        )
    }

    @Test("Concurrent save and completion merge the latest state at commit")
    func concurrentSaveAndCompletionDoNotLoseState() async throws {
        let commitGate = DemoPrompt14MutationGate()
        let repository = DemoPrompt14Repository(
            scenario: .loaded,
            mutationCommitGate: commitGate
        )
        let publicationID = DemoPrompt14Fixtures.secondSummary.publicationID
        let save = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-concurrent-merge-save-0001"
        )
        let completion = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-concurrent-merge-completion-0001"
        )
        let pendingSave = Task { try await repository.setSaved(save) }
        let pendingCompletion = Task { try await repository.recordRead(completion) }
        await commitGate.waitUntilStarted(count: 2)

        await commitGate.finish()
        let saveResponse = try await pendingSave.value
        let completionResponse = try await pendingCompletion.value
        let library = try await repository.content(
            DemoPrompt14Fixtures.libraryQuery()
        )
        let consolidated = try #require(
            library.data.items.first { $0.publicationID == publicationID }
        )

        #expect(saveResponse.data.saved)
        #expect(completionResponse.data.completed)
        #expect(consolidated.saved)
        #expect(consolidated.completed)
    }

    @Test("Cover stream serves neutral local bytes and invalid scenario is rejected")
    func coverStreamIsSyntheticAndScenarioBound() async throws {
        let loaded = DemoPrompt14ContentCoverSessionFactory(
            scenario: .loaded,
            timeProvider: FixedTimeProvider(value: DemoPrompt14Fixtures.fixedNow)
        ).makeLoader(userID: "30000000-0000-4000-8000-000000000001")
        let cover = try #require(DemoPrompt14Fixtures.firstSummary.cover)
        let image = try await loaded.image(
            publicationID: DemoPrompt14Fixtures.firstSummary.publicationID,
            version: DemoPrompt14Fixtures.firstSummary.version,
            cover: cover,
            target: ContentCoverTargetSize(widthPixels: 8, heightPixels: 8)
        )
        #expect(image.cgImage.width > 0)
        #expect(image.cgImage.height > 0)

        let invalid = DemoPrompt14ContentCoverSessionFactory(
            scenario: .coverInvalid,
            timeProvider: FixedTimeProvider(value: DemoPrompt14Fixtures.fixedNow)
        ).makeLoader(userID: "30000000-0000-4000-8000-000000000002")
        await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try await invalid.image(
                publicationID: DemoPrompt14Fixtures.firstSummary.publicationID,
                version: DemoPrompt14Fixtures.firstSummary.version,
                cover: cover,
                target: ContentCoverTargetSize(widthPixels: 8, heightPixels: 8)
            )
        }

        let sessionStream = DemoContentCoverByteStream(scenario: .loaded)
        let sessionLoader = try prompt14CoverLoader(stream: sessionStream)
        _ = try await sessionLoader.image(
            publicationID: DemoPrompt14Fixtures.firstSummary.publicationID,
            version: DemoPrompt14Fixtures.firstSummary.version,
            cover: cover,
            target: ContentCoverTargetSize(widthPixels: 8, heightPixels: 8)
        )
        #expect(await sessionStream.streamCallCountForTesting() == 1)
        await sessionLoader.endSession()
        #expect(await sessionStream.streamCallCountForTesting() == 0)
    }

    @Test("Today recommendation staleness is isolated to the second identical content query")
    func todayRecommendationsBecomeStaleOnlyAfterInitialSuccess() async throws {
        let repository = DemoPrompt14Repository(
            selection: resolvedPrompt14Selection(
                "--ui-testing-prompt14-today-recommendations-stale"
            )
        )
        let query = try ContentFeedQuery(
            surface: .today,
            category: nil,
            limit: 3,
            cursor: nil
        )
        let unsupportedTodayQuery = try ContentFeedQuery(
            surface: .today,
            category: nil,
            limit: 2,
            cursor: nil
        )

        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.content(unsupportedTodayQuery)
        }
        #expect(try await repository.content(query) == DemoPrompt14Fixtures.todayFeed)
        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await repository.content(query)
        }
    }

    @Test("First next-page failure retries the exact same opaque query successfully")
    func nextPageFailureRetriesIdenticalOpaqueCursor() async throws {
        let repository = DemoPrompt14Repository(
            selection: resolvedPrompt14Selection(
                "--ui-testing-prompt14-next-page-failure-once"
            )
        )
        let firstPage = try await repository.content(
            DemoPrompt14Fixtures.libraryQuery()
        )
        let opaqueCursor = try #require(firstPage.data.nextCursor)
        let retryQuery = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: opaqueCursor
        )

        #expect(opaqueCursor == "opaque 🧭 / + = ? keep-byte-for-byte")
        do {
            _ = try await repository.content(retryQuery)
            Issue.record("Expected the first exact opaque-cursor request to fail")
        } catch {
            #expect(error as? BodyFlowCapabilityError == .serviceUnavailable)
        }

        let retry = try await repository.content(retryQuery)
        #expect(retry == DemoPrompt14Fixtures.libraryNextFeed)
        #expect(retryQuery.cursor == opaqueCursor)
    }

    @Test("Invalid next-page cursor recovers through a cursor-nil first page")
    func invalidCursorRecoversWithCursorNilQuery() async throws {
        let repository = DemoPrompt14Repository(
            selection: resolvedPrompt14Selection(
                "--ui-testing-prompt14-invalid-cursor-recovery"
            )
        )
        let invalidCursorQuery = try DemoPrompt14Fixtures.libraryNextQuery()

        await #expect(throws: BodyFlowCapabilityError.invalidContentCursor) {
            try await repository.content(invalidCursorQuery)
        }

        let recoveryQuery = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: nil
        )
        #expect(recoveryQuery.cursor == nil)
        #expect(
            try await repository.content(recoveryQuery)
                == DemoPrompt14Fixtures.libraryFeed
        )
    }

    @Test("Incomplete authorized detail is reachable saveable and explicitly completable")
    func incompleteDetailCanBeSavedAndCompleted() async throws {
        let publicationID = "10000000-0000-4000-8000-000000000007"
        let version = 5
        let repository = DemoPrompt14Repository(
            selection: resolvedPrompt14Selection(
                "--ui-testing-prompt14-incomplete-detail"
            )
        )
        let feed = try await repository.content(DemoPrompt14Fixtures.libraryQuery())
        let summary = try #require(
            feed.data.items.first { $0.publicationID == publicationID }
        )

        #expect(summary.version == version)
        #expect(!summary.saved)
        #expect(!summary.completed)
        let detail = try await repository.contentDetail(publicationID: publicationID)
        #expect(detail.data.summary == summary)
        _ = try BodyFlowMarkdownParser().parse(detail.data.bodyMarkdown)

        let saveAttempt = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: version,
            key: "content-incomplete-save-0001"
        )
        let completionAttempt = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: publicationID,
            version: version,
            key: "content-incomplete-complete-0001"
        )
        let saved = try await repository.setSaved(saveAttempt)
        let completed = try await repository.recordRead(completionAttempt)

        #expect(saved.data.saved)
        #expect(!saved.data.completed)
        #expect(completed.data.saved)
        #expect(completed.data.completed)
        #expect(completed.data.changed)
    }

    @Test("Recoverable mutation failure retries the same immutable save and completion attempts")
    func recoverableMutationFailurePreservesExactAttemptIdentity() async throws {
        let scenario = resolvedPrompt14Selection(
            "--ui-testing-prompt14-mutation-failure-once"
        )
        let publicationID = DemoPrompt14Fixtures.secondSummary.publicationID
        let version = DemoPrompt14Fixtures.secondSummary.version

        let saveRepository = DemoPrompt14Repository(selection: scenario)
        let saveAttempt = try Prompt14Attempts.saved(
            true,
            publicationID: publicationID,
            version: version,
            key: "content-recoverable-save-0001"
        )
        do {
            _ = try await saveRepository.setSaved(saveAttempt)
            Issue.record("Expected the first immutable save attempt to fail")
        } catch {
            #expect(error as? BodyFlowCapabilityError == .serviceUnavailable)
        }
        let saved = try await saveRepository.setSaved(saveAttempt)
        #expect(saved.data.changed)
        #expect(saved.data.saved)
        #expect(!saved.data.replayed)

        let completionRepository = DemoPrompt14Repository(selection: scenario)
        let completionAttempt = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: publicationID,
            version: version,
            key: "content-recoverable-completion-0001"
        )
        do {
            _ = try await completionRepository.recordRead(completionAttempt)
            Issue.record("Expected the first immutable completion attempt to fail")
        } catch {
            #expect(error as? BodyFlowCapabilityError == .serviceUnavailable)
        }
        let completed = try await completionRepository.recordRead(completionAttempt)
        #expect(completed.data.changed)
        #expect(completed.data.completed)
        #expect(!completed.data.replayed)
    }

    @Test(
        "Recoverable save rejects a regenerated identity before the exact retry",
        arguments: RecoverableMutationIdentityDivergence.allCases
    )
    func recoverableSaveRejectsRegeneratedIdentity(
        _ divergence: RecoverableMutationIdentityDivergence
    ) async throws {
        let repository = DemoPrompt14Repository(
            selection: resolvedPrompt14Selection(
                "--ui-testing-prompt14-mutation-failure-once"
            )
        )
        let original = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-recoverable-save-identity-0001"
        )

        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await repository.setSaved(original)
        }
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.setSaved(
                divergence.regeneratedSave(from: original)
            )
        }

        let retried = try await repository.setSaved(original)
        #expect(retried.data.changed)
        #expect(retried.data.saved)
        #expect(!retried.data.replayed)
    }

    @Test(
        "Recoverable completion rejects a regenerated identity before the exact retry",
        arguments: RecoverableMutationIdentityDivergence.allCases
    )
    func recoverableCompletionRejectsRegeneratedIdentity(
        _ divergence: RecoverableMutationIdentityDivergence
    ) async throws {
        let repository = DemoPrompt14Repository(
            selection: resolvedPrompt14Selection(
                "--ui-testing-prompt14-mutation-failure-once"
            )
        )
        let original = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-recoverable-completion-identity-0001"
        )

        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await repository.recordRead(original)
        }
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.recordRead(
                divergence.regeneratedCompletion(from: original)
            )
        }

        let retried = try await repository.recordRead(original)
        #expect(retried.data.changed)
        #expect(retried.data.completed)
        #expect(!retried.data.replayed)
    }

    @Test("Independent save key does not consume the original recoverable retry")
    func recoverableSaveAllowsIndependentKey() async throws {
        let repository = DemoPrompt14Repository(
            selection: resolvedPrompt14Selection(
                "--ui-testing-prompt14-mutation-failure-once"
            )
        )
        let original = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-recoverable-save-key-a-0001"
        )
        let independent = try Prompt14Attempts.saved(
            true,
            publicationID: DemoPrompt14Fixtures.fourthSummary.publicationID,
            version: DemoPrompt14Fixtures.fourthSummary.version,
            key: "content-recoverable-save-key-b-0001"
        )

        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await repository.setSaved(original)
        }

        let independentResult = try await repository.setSaved(independent)
        #expect(independentResult.data.changed)
        #expect(independentResult.data.saved)
        #expect(!independentResult.data.replayed)

        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.setSaved(
                RecoverableMutationIdentityDivergence.payload
                    .regeneratedSave(from: original)
            )
        }

        let retried = try await repository.setSaved(original)
        #expect(retried.data.changed)
        #expect(retried.data.saved)
        #expect(!retried.data.replayed)
    }

    @Test("Independent completion key does not consume the original recoverable retry")
    func recoverableCompletionAllowsIndependentKey() async throws {
        let repository = DemoPrompt14Repository(
            selection: resolvedPrompt14Selection(
                "--ui-testing-prompt14-mutation-failure-once"
            )
        )
        let original = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.secondSummary.publicationID,
            version: DemoPrompt14Fixtures.secondSummary.version,
            key: "content-recoverable-completion-key-a-0001"
        )
        let independent = try Prompt14Attempts.read(
            .completed,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.fourthSummary.publicationID,
            version: DemoPrompt14Fixtures.fourthSummary.version,
            key: "content-recoverable-completion-key-b-0001"
        )

        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await repository.recordRead(original)
        }

        let independentResult = try await repository.recordRead(independent)
        #expect(independentResult.data.changed)
        #expect(independentResult.data.completed)
        #expect(!independentResult.data.replayed)

        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.recordRead(
                RecoverableMutationIdentityDivergence.payload
                    .regeneratedCompletion(from: original)
            )
        }

        let retried = try await repository.recordRead(original)
        #expect(retried.data.changed)
        #expect(retried.data.completed)
        #expect(!retried.data.replayed)
    }

    @Test("External absolute HTTPS link remains valid article Markdown")
    func externalHTTPSLinkIsOnlyCanonicalArticleContent() async throws {
        let repository = DemoPrompt14Repository(
            selection: resolvedPrompt14Selection(
                "--ui-testing-prompt14-markdown-external-link"
            )
        )
        let expectedDestination = "https" + "://example.invalid/prompt14/reference"

        let detail = try await repository.contentDetail(
            publicationID: DemoPrompt14Fixtures.firstSummary.publicationID
        )

        #expect(detail.data.bodyMarkdown.contains("[Referência externa](\(expectedDestination))"))
        _ = try BodyFlowMarkdownParser().parse(detail.data.bodyMarkdown)
        #expect(detail.data.summary.cover?.url.hasPrefix("/api/mobile/v1/content/covers/") == true)
    }

    @Test("Expired oversized MIME-mismatched and abusive-dimension covers fail at their real boundaries")
    func addedCoverScenariosFailAtRealLoaderAndDecoderBoundaries() async throws {
        let cases: [(String, BodyFlowCapabilityError, Int)] = [
            ("--ui-testing-prompt14-cover-expired", .contentCoverNotFound, 0),
            ("--ui-testing-prompt14-cover-too-large", .contentCoverTooLarge, 1),
            ("--ui-testing-prompt14-cover-mime-mismatch", .invalidContentCover, 1),
            ("--ui-testing-prompt14-cover-abusive-dimensions", .invalidContentCover, 1),
        ]

        for (argument, expectedError, expectedStreamCalls) in cases {
            let scenario = resolvedPrompt14Selection(argument)
            let repository = DemoPrompt14Repository(selection: scenario)
            let detail = try await repository.contentDetail(
                publicationID: DemoPrompt14Fixtures.firstSummary.publicationID
            )
            let cover = try #require(detail.data.summary.cover)
            let stream = DemoContentCoverByteStream(selection: scenario)
            let loader = try prompt14CoverLoader(stream: stream)

            await #expect(throws: expectedError) {
                try await loader.image(
                    publicationID: detail.data.summary.publicationID,
                    version: detail.data.summary.version,
                    cover: cover,
                    target: ContentCoverTargetSize(widthPixels: 8, heightPixels: 8)
                )
            }
            #expect(await reflectedStreamCallCount(stream) == expectedStreamCalls)
        }
    }

    @Test("External absolute cover path is rejected before any stream attempt")
    func externalCoverPathNeverReachesTransport() async throws {
        let scenario = resolvedPrompt14Selection(
            "--ui-testing-prompt14-cover-external-path"
        )
        let repository = DemoPrompt14Repository(selection: scenario)
        let detail = try await repository.contentDetail(
            publicationID: DemoPrompt14Fixtures.firstSummary.publicationID
        )
        let cover = try #require(detail.data.summary.cover)
        let stream = DemoContentCoverByteStream(selection: scenario)
        let loader = try prompt14CoverLoader(stream: stream)

        #expect(cover.url.hasPrefix("https" + "://"))
        await #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try await loader.image(
                publicationID: detail.data.summary.publicationID,
                version: detail.data.summary.version,
                cover: cover,
                target: ContentCoverTargetSize(widthPixels: 8, heightPixels: 8)
            )
        }
        #expect(await reflectedStreamCallCount(stream) == 0)
    }

    @Test("Focus Active and Zen Neglected coach responses are explicit authored pairs")
    func addedCoachPairsAreExplicitAndContractValid() async throws {
        let cases: [(
            String,
            SelectableCoachPersona,
            EffectiveCoachPersona,
            MascotWireState
        )] = [
            (
                "--ui-testing-prompt14-mascot-focus-active",
                .focus,
                .focus,
                .active
            ),
            (
                "--ui-testing-prompt14-mascot-zen-neglected",
                .zen,
                .zen,
                .neglected
            ),
        ]

        for (argument, selected, effective, mascot) in cases {
            let provider = DemoPrompt14CoachProvider(
                selection: resolvedPrompt14Selection(argument)
            )
            let response = try await provider.coachExperience()

            #expect(response.data.selected == selected)
            #expect(response.data.effective == effective)
            #expect(response.data.mascot.state == mascot)
            #expect(response.data.options.map(\.code) == [.focus, .impulse, .zen])
            #expect(
                CoachExperienceV1PresentationContract.validatedSnapshot(
                    from: response
                ) == response.data
            )
        }
    }

    @Test("Real detail GET completion precedes exactly one real opened mutation")
    func technicalObserverProvesRealGETBeforeOneOpenedMutation() async throws {
        let factory = DemoPrompt14PublishedContentSessionFactory(scenario: .loaded)
        let session = factory.makeSession(userID: "prompt14-observer-user")
        let repository = try #require(session.state as? DemoPrompt14Repository)
        #expect(repository === (session.detail as? DemoPrompt14Repository))
        let publicationID = DemoPrompt14Fixtures.firstSummary.publicationID

        _ = try await session.detail.contentDetail(publicationID: publicationID)
        let opened = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: publicationID,
            version: DemoPrompt14Fixtures.firstSummary.version,
            key: "content-observed-opened-0001"
        )
        _ = try await session.state.recordRead(opened)

        #expect(
            await reflectedTechnicalEventNames(repository)
                == ["detailGETCompleted", "openedMutationStarted"]
        )

        _ = try await session.state.recordRead(opened)
        #expect(
            await reflectedTechnicalEventNames(repository)
                == ["detailGETCompleted", "openedMutationStarted"]
        )
    }

    @Test("Technical observer is bounded and clears on failures replay and session end")
    func technicalObserverIsBoundedAndSessionLocal() async throws {
        let bounded = DemoPrompt14Repository(scenario: .loaded)
        for _ in 0..<12 {
            _ = try await bounded.contentDetail(
                publicationID: DemoPrompt14Fixtures.firstSummary.publicationID
            )
        }
        #expect(await reflectedTechnicalEventNames(bounded).count == 8)

        let failedDetail = DemoPrompt14Repository(scenario: .markdownInvalid)
        await #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try await failedDetail.contentDetail(
                publicationID: DemoPrompt14Fixtures.firstSummary.publicationID
            )
        }
        #expect(await reflectedTechnicalEventNames(failedDetail).isEmpty)

        let failedOpened = DemoPrompt14Repository(scenario: .openedError)
        _ = try await failedOpened.contentDetail(
            publicationID: DemoPrompt14Fixtures.firstSummary.publicationID
        )
        let opened = try Prompt14Attempts.read(
            .opened,
            origin: .library,
            publicationID: DemoPrompt14Fixtures.firstSummary.publicationID,
            version: DemoPrompt14Fixtures.firstSummary.version,
            key: "content-observer-failed-opened-0001"
        )
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await failedOpened.recordRead(opened)
        }
        #expect(
            await reflectedTechnicalEventNames(failedOpened)
                == ["detailGETCompleted"]
        )

        await failedOpened.endSession()
        #expect(await reflectedTechnicalEventNames(failedOpened).isEmpty)
    }
}

private let prompt14AttemptDate = Date(timeIntervalSince1970: 1_784_589_300)

enum RecoverableMutationIdentityDivergence:
    CaseIterable,
    Sendable,
    CustomTestStringConvertible
{
    case route
    case payload
    case createdAt

    var testDescription: String {
        switch self {
        case .route: "route"
        case .payload: "payload"
        case .createdAt: "createdAt"
        }
    }

    func regeneratedSave(
        from original: MutationAttempt<ContentSaveCommand>
    ) -> MutationAttempt<ContentSaveCommand> {
        switch self {
        case .route:
            MutationAttempt(
                operation: .contentRead,
                key: original.key,
                payload: original.payload,
                createdAt: original.createdAt
            )
        case .payload:
            MutationAttempt(
                operation: original.operation,
                key: original.key,
                payload: ContentSaveCommand(
                    publicationID: original.payload.publicationID,
                    body: ContentSaveBody(
                        saved: false,
                        version: original.payload.body.version
                    )
                ),
                createdAt: original.createdAt
            )
        case .createdAt:
            MutationAttempt(
                operation: original.operation,
                key: original.key,
                payload: original.payload,
                createdAt: original.createdAt.addingTimeInterval(1)
            )
        }
    }

    func regeneratedCompletion(
        from original: MutationAttempt<ContentReadCommand>
    ) -> MutationAttempt<ContentReadCommand> {
        switch self {
        case .route:
            MutationAttempt(
                operation: .contentSave,
                key: original.key,
                payload: original.payload,
                createdAt: original.createdAt
            )
        case .payload:
            MutationAttempt(
                operation: original.operation,
                key: original.key,
                payload: ContentReadCommand(
                    publicationID: original.payload.publicationID,
                    body: ContentReadBody(
                        event: original.payload.body.event,
                        origin: .today,
                        version: original.payload.body.version
                    )
                ),
                createdAt: original.createdAt
            )
        case .createdAt:
            MutationAttempt(
                operation: original.operation,
                key: original.key,
                payload: original.payload,
                createdAt: original.createdAt.addingTimeInterval(1)
            )
        }
    }
}

private func resolvedPrompt14Selection(
    _ argument: String
) -> DemoPrompt14ScenarioSelection {
    let configuration = AppLaunchConfiguration.resolve(
        arguments: ["--ui-testing", argument],
        buildFlavor: .debug
    )
    #expect(configuration.prompt14ScenarioSelection != nil)
    return configuration.prompt14ScenarioSelection ?? .loaded
}

private func prompt14CoverLoader(
    stream: DemoContentCoverByteStream
) throws -> ContentCoverLoader {
    let originURL = try #require(
        URL(string: "https" + "://prompt14-fixture.invalid")
    )
    return ContentCoverLoader(
        stream: stream,
        origin: try ContentCoverTrustedOrigin(validating: originURL),
        decoder: ContentCoverDecoder(),
        cache: SessionCoverCache(),
        timeProvider: FixedTimeProvider(value: DemoPrompt14Fixtures.fixedNow)
    )
}

private func reflectedStreamCallCount(
    _ stream: DemoContentCoverByteStream
) async -> Int {
    await stream.streamCallCountForTesting()
}

private func reflectedTechnicalEventNames(
    _ repository: DemoPrompt14Repository
) async -> [String] {
    await repository.technicalEventsForTesting().map(String.init(describing:))
}

private enum Prompt14Attempts {
    static func read(
        _ event: ContentReadEvent,
        origin: ContentOrigin,
        publicationID: String,
        version: Int,
        key: String,
        createdAt: Date = prompt14AttemptDate
    ) throws -> MutationAttempt<ContentReadCommand> {
        MutationAttempt(
            operation: .contentRead,
            key: try IdempotencyKey(validating: key),
            payload: ContentReadCommand(
                publicationID: publicationID,
                body: ContentReadBody(
                    event: event,
                    origin: origin,
                    version: version
                )
            ),
            createdAt: createdAt
        )
    }

    static func saved(
        _ saved: Bool,
        publicationID: String,
        version: Int,
        key: String,
        createdAt: Date = prompt14AttemptDate
    ) throws -> MutationAttempt<ContentSaveCommand> {
        MutationAttempt(
            operation: .contentSave,
            key: try IdempotencyKey(validating: key),
            payload: ContentSaveCommand(
                publicationID: publicationID,
                body: ContentSaveBody(saved: saved, version: version)
            ),
            createdAt: createdAt
        )
    }
}

private func prompt14ReadAttempt() throws -> MutationAttempt<ContentReadCommand> {
    MutationAttempt(
        operation: .contentRead,
        key: try IdempotencyKey(validating: "prompt14-read-0001"),
        payload: ContentReadCommand(
            publicationID: "10000000-0000-4000-8000-000000000001",
            body: ContentReadBody(event: .opened, origin: .library, version: 4)
        ),
        createdAt: prompt14AttemptDate
    )
}

private func prompt14SaveAttempt() throws -> MutationAttempt<ContentSaveCommand> {
    MutationAttempt(
        operation: .contentSave,
        key: try IdempotencyKey(validating: "prompt14-save-0001"),
        payload: ContentSaveCommand(
            publicationID: "10000000-0000-4000-8000-000000000001",
            body: ContentSaveBody(saved: true, version: 4)
        ),
        createdAt: prompt14AttemptDate
    )
}
#endif
