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

    @Test("Ending a loading session cancels late reads and prevents all later publication")
    func endSessionCancelsLateRead() async throws {
        let repository = DemoPrompt14Repository(scenario: .loading)
        let pending = Task {
            try await repository.content(DemoPrompt14Fixtures.todayQuery())
        }
        await Task.yield()

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

    @Test("Task 13 mutations stay unavailable before session end")
    func mutationsRemainUnavailable() async throws {
        let repository = DemoPrompt14Repository(scenario: .loaded)

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await repository.recordRead(prompt14ReadAttempt())
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await repository.setSaved(prompt14SaveAttempt())
        }
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
    }
}

private let prompt14AttemptDate = Date(timeIntervalSince1970: 1_784_589_300)

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
