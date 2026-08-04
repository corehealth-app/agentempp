import Foundation
import Testing

@testable import BodyFlow

@Suite("Published content detail view model")
@MainActor
struct ContentDetailViewModelTests {
    private static let routePublicationID =
        "10000000-0000-4000-8000-000000000001"
    private static let fixedNow = Date(timeIntervalSince1970: 1_784_589_300)

    // Mutation caught: constructing `opened` from a card snapshot, dispatching
    // before the authorized detail completes, or using a version other than the
    // one in the validated detail response.
    @Test("opened uses only the authorized detail response version")
    func openedAfterDetail() async throws {
        let detailProvider = ControlledContentDetailProvider()
        let recorder = ControlledDetailStateRecorder()
        let model = Self.model(
            detailProvider: detailProvider,
            recorder: recorder,
            origin: .library
        )

        let load = Task { await model.load(revision: 0) }
        await detailProvider.waitForCallCount(1)

        #expect(model.state == .loading)
        #expect(await recorder.readAttempts.isEmpty)
        #expect(await detailProvider.publicationIDs == [Self.routePublicationID])

        await detailProvider.succeed(
            call: 1,
            with: Prompt14Fixtures.detailResponse(version: 5)
        )
        await recorder.waitForReadAttemptCount(1)

        let attempt = try #require(await recorder.readAttempts.first)
        #expect(attempt.operation == .contentRead)
        #expect(attempt.key.value == "detail-0001")
        #expect(attempt.payload.publicationID == Self.routePublicationID)
        #expect(attempt.payload.body.event == .opened)
        #expect(attempt.payload.body.version == 5)
        #expect(attempt.payload.body.origin == .library)
        #expect(attempt.createdAt == Self.fixedNow)
        #expect(model.state == .loaded(Prompt14Fixtures.renderable(version: 5)))

        await recorder.succeed(
            call: 1,
            with: Prompt14Fixtures.stateResponse(
                version: 5,
                saved: true,
                completed: false
            )
        )
        await load.value
    }

    // Mutation caught: trusting the detail response without both contract
    // validation and BodyFlow AST parsing, or publishing raw Markdown.
    @Test("detail commits only the validated native AST")
    func validatedRenderableDetail() async {
        let response = Prompt14Fixtures.detailResponse(
            version: 7,
            saved: true,
            completed: false
        )
        let detailProvider = QueueContentDetailProvider([.success(response)])
        let recorder = QueueDetailStateRecorder([
            .success(Prompt14Fixtures.stateResponse(
                version: 7,
                saved: true,
                completed: false
            )),
        ])
        let model = Self.model(
            detailProvider: detailProvider,
            recorder: recorder,
            origin: .today
        )

        await model.load(revision: 0)

        #expect(model.state == .loaded(Prompt14Fixtures.renderable(
            version: 7,
            saved: true,
            completed: false
        )))
        #expect(model.openedEventState == .succeeded)
    }

    // Mutation caught: patching optimistic/card state or treating a canonical
    // response for another publication/version as a successful opened event.
    @Test("opened reconciles only an exact canonical publication and version")
    func canonicalStateReconciliation() async {
        let detail = Prompt14Fixtures.detailResponse(
            version: 4,
            saved: true,
            completed: false
        )
        let matchingRecorder = QueueDetailStateRecorder([
            .success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false,
                completed: true
            )),
        ])
        let matchingModel = Self.model(
            detailProvider: QueueContentDetailProvider([.success(detail)]),
            recorder: matchingRecorder
        )

        await matchingModel.load(revision: 0)

        #expect(matchingModel.state == .loaded(Prompt14Fixtures.renderable(
            version: 4,
            saved: false,
            completed: true
        )))

        let mismatches = [
            Prompt14Fixtures.stateResponse(
                publicationID: "10000000-0000-4000-8000-000000000099",
                version: 4,
                saved: false,
                completed: true
            ),
            Prompt14Fixtures.stateResponse(
                version: 99,
                saved: false,
                completed: true
            ),
        ]

        for mismatch in mismatches {
            let invalidationCenter = FeatureInvalidationCenter()
            let mismatchedRecorder = QueueDetailStateRecorder([
                .success(mismatch),
            ])
            let mismatchedModel = Self.model(
                detailProvider: QueueContentDetailProvider([.success(detail)]),
                recorder: mismatchedRecorder,
                invalidationCenter: invalidationCenter
            )

            await mismatchedModel.load(revision: 0)

            #expect(mismatchedModel.state == .loaded(Prompt14Fixtures.renderable(
                version: 4,
                saved: true,
                completed: false
            )))
            #expect(mismatchedModel.openedEventState == .failed(
                .invalidContentContract
            ))
            #expect(await mismatchedRecorder.readAttempts.count == 1)
            #expect(invalidationCenter.revision(for: .contentCatalog) == 0)
            #expect(invalidationCenter.revision(for: .contentDetail(
                Self.routePublicationID
            )) == 0)
        }
    }

    // Mutation caught: keying the opened guard to a render, revision, detail
    // version, or successful dispatch instead of to the route lifetime.
    @Test("rerender and later detail revisions keep one opened attempt")
    func routeLifetimeGuardSurvivesReloads() async {
        let detailProvider = QueueContentDetailProvider([
            .success(Prompt14Fixtures.detailResponse(version: 4)),
            .success(Prompt14Fixtures.detailResponse(version: 5)),
        ])
        let recorder = QueueDetailStateRecorder([
            .success(Prompt14Fixtures.stateResponse(version: 4)),
        ])
        let model = Self.model(
            detailProvider: detailProvider,
            recorder: recorder
        )

        await model.load(revision: 0)
        await model.load(revision: 0)
        await model.load(revision: 1)
        await model.load(revision: 1)

        #expect(await detailProvider.publicationIDs.count == 2)
        #expect(await recorder.readAttempts.count == 1)
        #expect(await recorder.readAttempts.first?.payload.body.version == 4)
        #expect(model.state == .loaded(Prompt14Fixtures.renderable(version: 5)))
    }

    // Mutation caught: resetting the guard after event failure, replacing the
    // authorized article with an event error, or introducing retry/queue work.
    @Test("ordinary opened failure stays bounded and never retries")
    func openedFailureIsNonBlocking() async {
        let detailProvider = QueueContentDetailProvider([
            .success(Prompt14Fixtures.detailResponse(version: 4)),
            .success(Prompt14Fixtures.detailResponse(version: 5)),
        ])
        let recorder = QueueDetailStateRecorder([.failure(.offline)])
        let model = Self.model(
            detailProvider: detailProvider,
            recorder: recorder
        )

        await model.load(revision: 0)

        #expect(model.state == .loaded(Prompt14Fixtures.renderable(version: 4)))
        #expect(model.openedEventState == .failed(.offline))

        await model.load(revision: 1)
        await model.load(revision: 1)

        #expect(model.state == .loaded(Prompt14Fixtures.renderable(version: 5)))
        #expect(model.openedEventState == .failed(.offline))
        #expect(await recorder.readAttempts.count == 1)
    }

    // Mutation caught: wiring the visible read-state retry affordance to a
    // duplicate revision load, or retrying `opened` instead of only the GET.
    @Test("explicit detail retry reloads the same revision before one opened")
    func detailRetry() async {
        let detailProvider = QueueContentDetailProvider([
            .failure(.offline),
            .success(Prompt14Fixtures.detailResponse(version: 4)),
        ])
        let recorder = QueueDetailStateRecorder([
            .success(Prompt14Fixtures.stateResponse(version: 4)),
        ])
        let model = Self.model(
            detailProvider: detailProvider,
            recorder: recorder
        )

        await model.load(revision: 0)

        #expect(model.state == .offline(previousValue: nil))
        #expect(await recorder.readAttempts.isEmpty)

        await model.retry(revision: 0)

        #expect(await detailProvider.publicationIDs.count == 2)
        #expect(await recorder.readAttempts.count == 1)
        #expect(model.state == .loaded(Prompt14Fixtures.renderable(version: 4)))
    }

    // Mutation caught: launching retry in an untracked Task that outlives the
    // route, or allowing its late provider completion to publish/emit opened.
    @Test("route-owned retry cancellation blocks late publication and opened")
    func cancelledRouteOwnedRetry() async {
        let request = ContentDetailRetryRequestPolicy.next(
            revision: 0,
            previousSequence: 8
        )
        #expect(request == ContentDetailRetryRequest(revision: 0, sequence: 9))

        let detailProvider = ControlledContentDetailProvider()
        await detailProvider.setImmediateResult(
            call: 1,
            result: .failure(.offline)
        )
        let recorder = QueueDetailStateRecorder()
        let model = Self.model(
            detailProvider: detailProvider,
            recorder: recorder
        )

        await model.load(revision: 0)
        #expect(model.state == .offline(previousValue: nil))

        let routeOwnedRetry = Task {
            await model.retry(revision: request.revision)
        }
        await detailProvider.waitForCallCount(2)
        routeOwnedRetry.cancel()
        await detailProvider.succeed(
            call: 2,
            with: Prompt14Fixtures.detailResponse(version: 4)
        )
        await routeOwnedRetry.value

        #expect(model.state == .loading)
        #expect(model.openedEventState == .idle)
        #expect(await recorder.readAttempts.isEmpty)
    }

    // Mutation caught: letting a skipped/stale invocation consume the pending
    // opened attempt created by the exact invocation that published `.value`.
    @Test("only the publishing invocation can claim pending opened")
    func exactInvocationOwnsOpenedDispatch() async {
        let stale = ContentDetailLoadInvocationToken(sequence: 1)
        let winner = ContentDetailLoadInvocationToken(sequence: 2)
        var ownership = ContentDetailOpenedDispatchOwnership()
        ownership.registerPending(owner: winner)

        let staleClaimed = ownership.claimPending(for: stale)
        #expect(!staleClaimed)
        #expect(ownership.pendingOwner == winner)
        let winnerClaimed = ownership.claimPending(for: winner)
        #expect(winnerClaimed)
        #expect(ownership.pendingOwner == nil)

        let detailProvider = ControlledContentDetailProvider()
        let recorder = ControlledDetailStateRecorder()
        let model = Self.model(
            detailProvider: detailProvider,
            recorder: recorder
        )
        let staleLoad = Task { await model.load(revision: 0) }
        await detailProvider.waitForCallCount(1)
        let winningLoad = Task { await model.load(revision: 1) }
        await detailProvider.waitForCallCount(2)

        await detailProvider.succeed(
            call: 2,
            with: Prompt14Fixtures.detailResponse(version: 6)
        )
        await recorder.waitForReadAttemptCount(1)
        await detailProvider.succeed(
            call: 1,
            with: Prompt14Fixtures.detailResponse(version: 5)
        )
        await staleLoad.value

        #expect(await recorder.readAttempts.count == 1)
        #expect(await recorder.readAttempts.first?.payload.body.version == 6)

        await recorder.succeed(
            call: 1,
            with: Prompt14Fixtures.stateResponse(version: 6)
        )
        await winningLoad.value

        #expect(model.state == .loaded(Prompt14Fixtures.renderable(version: 6)))
    }

    // Mutation caught: sharing the opened guard across independent navigation
    // destinations rather than owning it in each detail model.
    @Test("a new navigation model owns a new opened attempt")
    func newNavigationGetsNewAttempt() async {
        let recorder = QueueDetailStateRecorder([
            .success(Prompt14Fixtures.stateResponse(version: 4)),
            .success(Prompt14Fixtures.stateResponse(version: 4)),
        ])
        let first = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(version: 4)),
            ]),
            recorder: recorder
        )
        let second = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(version: 4)),
            ]),
            recorder: recorder
        )

        await first.load(revision: 0)
        await second.load(revision: 0)

        #expect(await recorder.readAttempts.count == 2)
        #expect(await recorder.readAttempts.map(\.payload.body.version) == [4, 4])
    }

    // Mutation caught: recording opened after a failed/unavailable load, after
    // invalid contract/Markdown, or for a detail whose identity differs from
    // the route authorization.
    @Test("rejected detail outcomes never attempt opened")
    func rejectedDetailsDoNotOpen() async {
        let invalidContract = Prompt14Fixtures.detailResponse(
            version: 4,
            title: "no"
        )
        let invalidMarkdown = Prompt14Fixtures.detailResponse(
            version: 4,
            markdown: Prompt14Fixtures.invalidMarkdown
        )
        let wrongIdentity = Prompt14Fixtures.detailResponse(
            publicationID: "10000000-0000-4000-8000-000000000099",
            version: 4
        )
        let cases: [(
            Result<PublishedContentDetailResponse, BodyFlowCapabilityError>,
            FeatureReadState<RenderablePublishedContentDetail>
        )] = [
            (.failure(.offline), .offline(previousValue: nil)),
            (.failure(.serviceUnavailable), .failed(
                previousValue: nil,
                error: .serviceUnavailable
            )),
            (.failure(.operationUnavailable), .unavailable),
            (.success(invalidContract), .failed(
                previousValue: nil,
                error: .invalidContentContract
            )),
            (.success(invalidMarkdown), .failed(
                previousValue: nil,
                error: .unsupportedMarkdown
            )),
            (.success(wrongIdentity), .failed(
                previousValue: nil,
                error: .invalidContentContract
            )),
        ]

        for (result, expectedState) in cases {
            let recorder = QueueDetailStateRecorder()
            let model = Self.model(
                detailProvider: QueueContentDetailProvider([result]),
                recorder: recorder
            )

            await model.load(revision: 0)

            #expect(model.state == expectedState)
            #expect(model.openedEventState == .idle)
            #expect(await recorder.readAttempts.isEmpty)
        }
    }

    // Mutation caught: allowing a cancelled or superseded GET to publish and
    // construct an opened event after it loses load ownership.
    @Test("cancelled and superseded details never attempt opened")
    func cancelledAndSupersededDetailsDoNotOpen() async {
        let cancelledProvider = ControlledContentDetailProvider()
        let cancelledRecorder = QueueDetailStateRecorder()
        let cancelledModel = Self.model(
            detailProvider: cancelledProvider,
            recorder: cancelledRecorder
        )
        let cancelledLoad = Task { await cancelledModel.load(revision: 0) }
        await cancelledProvider.waitForCallCount(1)

        cancelledLoad.cancel()
        await cancelledProvider.succeed(
            call: 1,
            with: Prompt14Fixtures.detailResponse(version: 4)
        )
        await cancelledLoad.value

        #expect(await cancelledRecorder.readAttempts.isEmpty)

        let supersededProvider = ControlledContentDetailProvider()
        let supersededRecorder = QueueDetailStateRecorder([
            .success(Prompt14Fixtures.stateResponse(version: 6)),
        ])
        let supersededModel = Self.model(
            detailProvider: supersededProvider,
            recorder: supersededRecorder
        )
        let oldLoad = Task { await supersededModel.load(revision: 0) }
        await supersededProvider.waitForCallCount(1)
        let newLoad = Task { await supersededModel.load(revision: 1) }
        await supersededProvider.waitForCallCount(2)

        await supersededProvider.succeed(
            call: 2,
            with: Prompt14Fixtures.detailResponse(version: 6)
        )
        await newLoad.value
        await supersededProvider.succeed(
            call: 1,
            with: Prompt14Fixtures.detailResponse(version: 5)
        )
        await oldLoad.value

        #expect(await supersededRecorder.readAttempts.count == 1)
        #expect(await supersededRecorder.readAttempts.first?.payload.body.version == 6)
        #expect(supersededModel.state == .loaded(
            Prompt14Fixtures.renderable(version: 6)
        ))
    }

    // Mutation caught: collapsing authorization failures into a generic/raw
    // error or inventing a subscription purchase/upgrade path.
    @Test("not found and subscription failures have distinct bounded copy")
    func boundedAuthorizationPresentations() async {
        let cases: [(
            BodyFlowCapabilityError,
            ContentDetailBoundedPresentation
        )] = [
            (
                .contentNotFound,
                ContentDetailBoundedPresentation(
                    message: "Este conteúdo não está mais disponível",
                    actions: [.back, .library]
                )
            ),
            (
                .subscriptionRequired,
                ContentDetailBoundedPresentation(
                    message: "Conteúdo indisponível para sua assinatura atual",
                    actions: [.back]
                )
            ),
        ]

        for (error, expectedPresentation) in cases {
            let recorder = QueueDetailStateRecorder()
            let model = Self.model(
                detailProvider: QueueContentDetailProvider([.failure(error)]),
                recorder: recorder
            )

            await model.load(revision: 0)

            #expect(model.state == .failed(previousValue: nil, error: error))
            #expect(model.boundedPresentation == expectedPresentation)
            #expect(await recorder.readAttempts.isEmpty)
        }
    }

    // Mutation caught: invalidating before exact cover removal, recursively
    // reloading in the event handler, or dispatching opened after revision reload.
    @Test("version conflict leaves exactly one reload to the revision observer")
    func openedVersionConflictRecovery() async {
        let detailProvider = QueueContentDetailProvider([
            .success(Prompt14Fixtures.detailResponse(version: 4)),
            .success(Prompt14Fixtures.detailResponse(version: 5)),
        ])
        let recorder = QueueDetailStateRecorder([
            .failure(.contentVersionChanged),
        ])
        let invalidationCenter = FeatureInvalidationCenter()
        let coverLoader = ControlledDetailCoverLoader()
        let model = Self.model(
            detailProvider: detailProvider,
            recorder: recorder,
            invalidationCenter: invalidationCenter,
            coverLoader: coverLoader
        )
        let load = Task { await model.load(revision: 0) }
        await coverLoader.waitUntilRemovalStarts()

        #expect(await coverLoader.removals == [ContentDetailCoverRemoval(
            publicationID: Self.routePublicationID,
            version: 4
        )])
        #expect(invalidationCenter.revision(for: .contentCatalog) == 0)
        #expect(invalidationCenter.revision(for: .contentDetail(
            Self.routePublicationID
        )) == 0)

        await coverLoader.finishRemoval()
        await load.value

        #expect(invalidationCenter.revision(for: .contentCatalog) == 1)
        #expect(invalidationCenter.revision(for: .contentDetail(
            Self.routePublicationID
        )) == 1)
        #expect(await detailProvider.publicationIDs.count == 1)
        #expect(model.state == .loaded(Prompt14Fixtures.renderable(version: 4)))

        await model.load(
            revision: invalidationCenter.revision(for: .contentDetail(
                Self.routePublicationID
            ))
        )

        #expect(model.state == .loaded(Prompt14Fixtures.renderable(version: 5)))
        #expect(model.openedEventState == .failed(.contentVersionChanged))
        #expect(await recorder.readAttempts.count == 1)
        #expect(await recorder.readAttempts.first?.payload.body.version == 4)
        #expect(await coverLoader.removals.count == 1)
        #expect(await detailProvider.publicationIDs == [
            Self.routePublicationID,
            Self.routePublicationID,
        ])
    }

    // Mutation caught: giving the rendered OpenURLAction a different handler
    // path, or accepting a non-absolute/non-HTTPS URL in that exact callable.
    @Test("rendered OpenURL handler returns its exact system/discard presentation")
    func renderedOpenURLHandler() {
        let handler = BodyFlowMarkdownOpenURLHandler()
        let approved = URL(
            string: "https://bodyflow.example/guia?fonte=artigo"
        )!
        #expect(handler(approved) ==
            .systemAction(approved)
        )
        for rejected in [
            URL(string: "http://bodyflow.example/guia")!,
            URL(string: "/guia")!,
            URL(string: "https://usuario@bodyflow.example/guia")!,
        ] {
            #expect(handler(rejected) ==
                .discarded
            )
        }
    }

    // Mutation caught: constructing linked Text through a different content
    // path, dropping its actionable URL attribute, or omitting its exact hint.
    @Test("rendered inline presentation owns the attributed link and exact hint")
    func renderedInlineLinkPresentation() {
        let approved = URL(string: "https://bodyflow.example/guia")!
        let presentation = BodyFlowMarkdownInlinePresentation.make([
            .text("Consulte "),
            .link(
                destination: approved.absoluteString,
                children: [.text("o guia")]
            ),
            .text("."),
        ])

        #expect(String(presentation.text.characters) == "Consulte o guia.")
        #expect(presentation.text.runs.compactMap(\.link) == [approved])
        #expect(presentation.accessibilityHint == "Link externo")
    }

    // Mutation caught: exposing visual bullets alone instead of a native List
    // accessibility container with one native row per AST list item.
    @Test("list accessibility policy preserves list and item semantics")
    func listAccessibilityRepresentation() {
        let items: [[BodyFlowMarkdownBlock]] = [
            [.paragraph(children: [.text("Primeiro item controlado.")])],
            [.paragraph(children: [
                .text("Segundo item com "),
                .strong(children: [.text("ênfase forte")]),
                .text("."),
            ])],
        ]

        let ordered = BodyFlowMarkdownListAccessibilityPolicy.presentation(
            items: items,
            ordered: true
        )
        #expect(ordered.semanticRole == .list)
        #expect(ordered.itemCount == 2)
        #expect(ordered.ordered)
        #expect(ordered.items == [
            BodyFlowMarkdownListAccessibilityItem(
                position: 1,
                count: 2,
                blocks: items[0],
                semanticRole: .listItem
            ),
            BodyFlowMarkdownListAccessibilityItem(
                position: 2,
                count: 2,
                blocks: items[1],
                semanticRole: .listItem
            ),
        ])

        let unordered = BodyFlowMarkdownListAccessibilityPolicy.presentation(
            items: items,
            ordered: false
        )
        #expect(unordered.semanticRole == .list)
        #expect(unordered.itemCount == 2)
        #expect(!unordered.ordered)
        #expect(unordered.items.allSatisfy { $0.semanticRole == .listItem })
    }

    // Mutation caught: flattening an accessibility row to plain text, which
    // strips heading traits and the actionable link presentation from its AST.
    @Test("list accessibility rows retain heading and link AST semantics")
    func listAccessibilityRetainsSemanticBlocks() {
        let approved = URL(string: "https://bodyflow.example/guia-seguro")!
        let blocks: [BodyFlowMarkdownBlock] = [
            .heading(level: 3, children: [.text("Antes de começar")]),
            .paragraph(children: [
                .text("Abra "),
                .link(
                    destination: approved.absoluteString,
                    children: [.text("o guia seguro")]
                ),
                .text("."),
            ]),
        ]

        let presentation =
            BodyFlowMarkdownListAccessibilityPolicy.presentation(
                items: [blocks],
                ordered: false
            )

        #expect(presentation.items == [
            BodyFlowMarkdownListAccessibilityItem(
                position: 1,
                count: 1,
                blocks: blocks,
                semanticRole: .listItem
            ),
        ])

        guard let retainedBlocks = presentation.items.first?.blocks else {
            Issue.record("Expected one retained accessibility list row")
            return
        }
        #expect(retainedBlocks == blocks)
        guard case let .paragraph(children) = retainedBlocks[1] else {
            Issue.record("Expected the retained list block to be a paragraph")
            return
        }
        let linkPresentation =
            BodyFlowMarkdownInlinePresentation.make(children)
        #expect(linkPresentation.text.runs.compactMap(\.link) == [approved])
        #expect(linkPresentation.accessibilityHint == "Link externo")
    }
}

private extension ContentDetailViewModelTests {
    static func model(
        detailProvider: any PublishedContentDetailProviding,
        recorder: any PublishedContentStateRecording,
        origin: ContentOrigin = .library,
        invalidationCenter: FeatureInvalidationCenter = FeatureInvalidationCenter(),
        coverLoader: any ContentCoverLoading = ImmediateDetailCoverLoader()
    ) -> ContentDetailViewModel {
        ContentDetailViewModel(
            publicationID: routePublicationID,
            origin: origin,
            detailProvider: detailProvider,
            stateRecorder: recorder,
            markdownParser: BodyFlowMarkdownParser(),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "detail"),
            timeProvider: FixedTimeProvider(value: fixedNow),
            invalidationCenter: invalidationCenter,
            coverLoader: coverLoader
        )
    }
}

private enum Prompt14Fixtures {
    static let validMarkdown = """
    ## Uma seção segura

    Este conteúdo sintético é longo o suficiente para validar o contrato e a conversão para a árvore nativa do BodyFlow.

    * Primeiro item controlado.
    * Segundo item com **ênfase forte**.
    """ + "\n"

    static let invalidMarkdown = """
    # Título de nível um rejeitado

    Este conteúdo sintético continua longo o suficiente para passar a validação contratual antes de o parser rejeitar o nó não suportado.
    """ + "\n"

    static func detailResponse(
        publicationID: String =
            "10000000-0000-4000-8000-000000000001",
        version: Int,
        title: String = "Conteúdo sintético autorizado",
        saved: Bool = true,
        completed: Bool = false,
        markdown: String = validMarkdown
    ) -> PublishedContentDetailResponse {
        PublishedContentDetailResponse(
            data: PublishedContentDetail(
                summary: summary(
                    publicationID: publicationID,
                    version: version,
                    title: title,
                    saved: saved,
                    completed: completed
                ),
                bodyMarkdown: markdown
            ),
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000019"
            )
        )
    }

    static func summary(
        publicationID: String,
        version: Int,
        title: String,
        saved: Bool,
        completed: Bool
    ) -> PublishedContentSummary {
        PublishedContentSummary(
            publicationID: publicationID,
            slug: "conteudo-sintetico-autorizado",
            locale: .ptBR,
            title: title,
            excerpt: "Resumo sintético completo usado para validar o detalhe autorizado sem dados reais.",
            category: .nutrition,
            tags: ["sintetico", "nutricao"],
            readingTimeMinutes: 4,
            publishAt: APITimestamp(
                value: Date(timeIntervalSince1970: 1_784_502_900)
            ),
            featuredToday: false,
            version: version,
            saved: saved,
            completed: completed,
            cover: nil
        )
    }

    static func renderable(
        version: Int,
        saved: Bool = true,
        completed: Bool = false
    ) -> RenderablePublishedContentDetail {
        RenderablePublishedContentDetail(
            publicationID: "10000000-0000-4000-8000-000000000001",
            version: version,
            title: "Conteúdo sintético autorizado",
            categoryLabel: "Nutrição",
            readingTimeLabel: "4 min de leitura",
            saved: saved,
            completed: completed,
            document: BodyFlowMarkdownDocument(blocks: [
                .heading(level: 2, children: [.text("Uma seção segura")]),
                .paragraph(children: [
                    .text(
                        "Este conteúdo sintético é longo o suficiente para validar o contrato e a conversão para a árvore nativa do BodyFlow."
                    ),
                ]),
                .unorderedList(items: [
                    [.paragraph(children: [.text("Primeiro item controlado.")])],
                    [.paragraph(children: [
                        .text("Segundo item com "),
                        .strong(children: [.text("ênfase forte")]),
                        .text("."),
                    ])],
                ]),
            ])
        )
    }

    static func stateResponse(
        publicationID: String =
            "10000000-0000-4000-8000-000000000001",
        version: Int,
        saved: Bool = true,
        completed: Bool = false
    ) -> PublishedContentStateResponse {
        PublishedContentStateResponse(
            data: PublishedContentState(
                publicationID: publicationID,
                version: version,
                saved: saved,
                completed: completed,
                changed: false,
                replayed: false
            ),
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: "90000000-0000-4000-8000-000000000020"
            )
        )
    }
}

private actor QueueContentDetailProvider: PublishedContentDetailProviding {
    private var results: [
        Result<PublishedContentDetailResponse, BodyFlowCapabilityError>
    ]
    private(set) var publicationIDs: [String] = []

    init(_ results: [
        Result<PublishedContentDetailResponse, BodyFlowCapabilityError>
    ]) {
        self.results = results
    }

    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse {
        publicationIDs.append(publicationID)
        guard !results.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return try results.removeFirst().get()
    }
}

private actor ControlledContentDetailProvider: PublishedContentDetailProviding {
    private(set) var publicationIDs: [String] = []
    private var continuations: [
        Int: CheckedContinuation<PublishedContentDetailResponse, any Error>
    ] = [:]
    private var callCountWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var immediateResults: [
        Int: Result<PublishedContentDetailResponse, BodyFlowCapabilityError>
    ] = [:]

    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse {
        publicationIDs.append(publicationID)
        let call = publicationIDs.count
        resumeCallCountWaiters()
        if let result = immediateResults.removeValue(forKey: call) {
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitForCallCount(_ expectedCount: Int) async {
        guard publicationIDs.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callCountWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func succeed(
        call: Int,
        with response: PublishedContentDetailResponse
    ) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }

    func setImmediateResult(
        call: Int,
        result: Result<PublishedContentDetailResponse, BodyFlowCapabilityError>
    ) {
        immediateResults[call] = result
    }

    private func resumeCallCountWaiters() {
        let readyCounts = callCountWaiters.keys.filter {
            $0 <= publicationIDs.count
        }
        for count in readyCounts {
            let waiters = callCountWaiters.removeValue(forKey: count) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}

private enum DetailStateRecordingResult: Sendable {
    case success(PublishedContentStateResponse)
    case failure(BodyFlowCapabilityError)
}

private actor QueueDetailStateRecorder: PublishedContentStateRecording {
    private var results: [DetailStateRecordingResult]
    private(set) var readAttempts: [MutationAttempt<ContentReadCommand>] = []

    init(_ results: [DetailStateRecordingResult] = []) {
        self.results = results
    }

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        readAttempts.append(attempt)
        guard !results.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        switch results.removeFirst() {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}

private actor ControlledDetailStateRecorder: PublishedContentStateRecording {
    private(set) var readAttempts: [MutationAttempt<ContentReadCommand>] = []
    private var continuations: [
        Int: CheckedContinuation<PublishedContentStateResponse, any Error>
    ] = [:]
    private var attemptCountWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        readAttempts.append(attempt)
        let call = readAttempts.count
        resumeAttemptCountWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func waitForReadAttemptCount(_ expectedCount: Int) async {
        guard readAttempts.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            attemptCountWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func succeed(
        call: Int,
        with response: PublishedContentStateResponse
    ) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }

    private func resumeAttemptCountWaiters() {
        let readyCounts = attemptCountWaiters.keys.filter {
            $0 <= readAttempts.count
        }
        for count in readyCounts {
            let waiters = attemptCountWaiters.removeValue(forKey: count) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}

private struct ContentDetailCoverRemoval: Equatable, Sendable {
    let publicationID: String
    let version: Int
}

private actor ImmediateDetailCoverLoader: ContentCoverLoading {
    func image(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func remove(publicationID: String, version: Int) async {}

    func endSession() async {}
}

private actor ControlledDetailCoverLoader: ContentCoverLoading {
    private(set) var removals: [ContentDetailCoverRemoval] = []
    private var removalStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var removalContinuation: CheckedContinuation<Void, Never>?

    func image(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func remove(publicationID: String, version: Int) async {
        removals.append(ContentDetailCoverRemoval(
            publicationID: publicationID,
            version: version
        ))
        let waiters = removalStartedWaiters
        removalStartedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            removalContinuation = continuation
        }
    }

    func waitUntilRemovalStarts() async {
        guard removals.isEmpty else { return }
        await withCheckedContinuation { continuation in
            removalStartedWaiters.append(continuation)
        }
    }

    func finishRemoval() {
        removalContinuation?.resume()
        removalContinuation = nil
    }

    func endSession() async {}
}
