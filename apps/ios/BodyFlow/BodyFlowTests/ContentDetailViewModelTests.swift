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

    // Mutation caught: constructing save from route/origin metadata, skipping
    // canonical reconciliation, patching feeds, or invalidating unrelated reads.
    @Test("save uses its exact body and reconciles only canonical detail state")
    func savesCanonicalDetailState() async throws {
        let recorder = QueueDetailStateRecorder(
            [.success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false
            ))],
            saveResults: [.success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: true
            ))]
        )
        let invalidationCenter = FeatureInvalidationCenter()
        let model = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(
                    version: 4,
                    saved: false
                )),
            ]),
            recorder: recorder,
            invalidationCenter: invalidationCenter
        )

        await model.load(revision: 0)
        #expect(invalidationCenter.revision(for: .contentCatalog) == 0)
        #expect(invalidationCenter.revision(for: .contentDetail(
            Self.routePublicationID
        )) == 0)

        await model.toggleSaved()

        let attempt = try #require(await recorder.saveAttempts.first)
        #expect(attempt.operation == .contentSave)
        #expect(attempt.key.value == "detail-0002")
        #expect(attempt.payload == ContentSaveCommand(
            publicationID: Self.routePublicationID,
            body: ContentSaveBody(saved: true, version: 4)
        ))
        #expect(attempt.createdAt == Self.fixedNow)
        #expect(model.state == .loaded(Prompt14Fixtures.renderable(
            version: 4,
            saved: true
        )))
        #expect(model.contentMutationState.receipt ==
            Prompt14Fixtures.stateResponse(version: 4, saved: true))
        #expect(model.contentMutationPresentation == ContentMutationPresentation(
            message: "Conteúdo salvo",
            systemImage: "bookmark.fill",
            allowsRetry: false
        ))
        #expect(model.accessibilityFocusTarget == .mutationSummary)
        model.consumeAccessibilityFocus()
        #expect(model.accessibilityFocusTarget == nil)
        #expect(invalidationCenter.revision(for: .contentCatalog) == 1)
        #expect(invalidationCenter.revision(for: .contentDetail(
            Self.routePublicationID
        )) == 1)
        #expect(invalidationCenter.revision(for: .today) == 0)
        #expect(invalidationCenter.revision(for: .coachExperience) == 0)
    }

    // Mutation caught: providing an uncomplete path, omitting route identity
    // outside the body, or leaving completion available after canonical success.
    @Test("completion is one way and uses the detail origin and version")
    func completesOnlyOnce() async throws {
        let recorder = QueueDetailStateRecorder([
            .success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false
            )),
            .success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false,
                completed: true
            )),
        ])
        let invalidationCenter = FeatureInvalidationCenter()
        let model = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(
                    version: 4,
                    saved: false
                )),
            ]),
            recorder: recorder,
            origin: .push,
            invalidationCenter: invalidationCenter
        )

        await model.load(revision: 0)
        #expect(model.showsCompletionAction)
        #expect(model.canComplete)

        await model.complete()

        let attempts = await recorder.readAttempts
        #expect(attempts.count == 2)
        #expect(attempts[1].operation == .contentRead)
        #expect(attempts[1].key.value == "detail-0002")
        #expect(attempts[1].payload == ContentReadCommand(
            publicationID: Self.routePublicationID,
            body: ContentReadBody(
                event: .completed,
                origin: .push,
                version: 4
            )
        ))
        #expect(!model.showsCompletionAction)
        #expect(!model.canComplete)
        #expect(model.state == .loaded(Prompt14Fixtures.renderable(
            version: 4,
            saved: false,
            completed: true
        )))
        #expect(invalidationCenter.revision(for: .contentCatalog) == 1)
        #expect(invalidationCenter.revision(for: .contentDetail(
            Self.routePublicationID
        )) == 1)

        await model.complete()
        #expect(await recorder.readAttempts.count == 2)
    }

    // Mutation caught: allowing a second save/completion to create a key while
    // the first request is suspended instead of guarding synchronously on MainActor.
    @Test("one content mutation submits at a time and suppresses double taps")
    func serializesContentMutations() async {
        let recorder = ControlledContentMutationRecorder(
            openedResponse: Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false
            )
        )
        let model = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(
                    version: 4,
                    saved: false
                )),
            ]),
            recorder: recorder
        )
        await model.load(revision: 0)

        let first = Task { await model.toggleSaved() }
        await recorder.waitForSaveAttemptCount(1)
        let doubleTap = Task { await model.toggleSaved() }
        let competingCompletion = Task { await model.complete() }
        await doubleTap.value
        await competingCompletion.value

        #expect(model.isContentMutationSubmitting)
        #expect(!model.canToggleSaved)
        #expect(!model.canComplete)
        #expect(await recorder.saveAttempts.count == 1)
        #expect(await recorder.readAttempts.count == 1)

        await recorder.succeedSave(
            call: 1,
            with: Prompt14Fixtures.stateResponse(version: 4, saved: true)
        )
        await first.value
        #expect(await recorder.saveAttempts.count == 1)
        #expect(await recorder.readAttempts.count == 1)
    }

    // Mutation caught: regenerating a failed attempt on Retry or reusing the
    // failed key/time for a later, distinct user intent.
    @Test("retry preserves attempt while new intent creates a new key and time")
    func retriesImmutableSaveAttempt() async throws {
        let clock = MutableDetailTimeProvider(Self.fixedNow)
        let recorder = QueueDetailStateRecorder(
            [.success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false
            ))],
            saveResults: [
                .failure(.offline),
                .success(Prompt14Fixtures.stateResponse(
                    version: 4,
                    saved: true
                )),
                .success(Prompt14Fixtures.stateResponse(
                    version: 4,
                    saved: false
                )),
            ]
        )
        let model = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(
                    version: 4,
                    saved: false
                )),
            ]),
            recorder: recorder,
            timeProvider: clock
        )
        await model.load(revision: 0)

        await model.toggleSaved()
        let failed = try #require(model.contentMutationState.attempt)
        #expect(model.contentMutationPresentation?.allowsRetry == true)
        #expect(model.accessibilityFocusTarget == .mutationSummary)
        clock.advance(by: 3_600)
        await model.retryContentMutation()

        let saveAttempts = await recorder.saveAttempts
        #expect(saveAttempts.count == 2)
        #expect(ContentDetailMutationAttempt.save(saveAttempts[1]) == failed)
        #expect(model.accessibilityFocusTarget == .mutationSummary)

        clock.advance(by: 60)
        await model.toggleSaved()
        let newIntent = try #require(await recorder.saveAttempts.last)
        #expect(newIntent.key.value == "detail-0003")
        #expect(newIntent.createdAt == Self.fixedNow.addingTimeInterval(3_660))
        #expect(ContentDetailMutationAttempt.save(newIntent) != failed)
    }

    // Mutation caught: accepting a canonical state for another route/version,
    // mutating the rendered detail, or treating a malformed receipt as success.
    @Test("save and completion reject canonical identity or version mismatches")
    func rejectsMutationResponseMismatches() async {
        let mismatches = [
            Prompt14Fixtures.stateResponse(
                publicationID: "10000000-0000-4000-8000-000000000099",
                version: 4,
                saved: true
            ),
            Prompt14Fixtures.stateResponse(version: 99, saved: true),
        ]

        for mismatch in mismatches {
            let invalidationCenter = FeatureInvalidationCenter()
            let recorder = QueueDetailStateRecorder(
                [.success(Prompt14Fixtures.stateResponse(
                    version: 4,
                    saved: false
                ))],
                saveResults: [.success(mismatch)]
            )
            let model = Self.model(
                detailProvider: QueueContentDetailProvider([
                    .success(Prompt14Fixtures.detailResponse(
                        version: 4,
                        saved: false
                    )),
                ]),
                recorder: recorder,
                invalidationCenter: invalidationCenter
            )

            await model.load(revision: 0)
            await model.toggleSaved()

            #expect(model.state == .loaded(Prompt14Fixtures.renderable(
                version: 4,
                saved: false
            )))
            #expect(model.contentMutationState == .failed(
                .save((await recorder.saveAttempts)[0]),
                .invalidContentContract
            ))
            #expect(model.contentMutationPresentation?.allowsRetry == true)
            #expect(model.accessibilityFocusTarget == .mutationSummary)
            #expect(invalidationCenter.revision(for: .contentCatalog) == 0)
            #expect(invalidationCenter.revision(for: .contentDetail(
                Self.routePublicationID
            )) == 0)
        }
    }

    // Mutation caught: invalidating before exact cover eviction, retrying the
    // stale attempt, recursively loading, or locally patching the new version.
    @Test("mutation conflict evicts old cover then waits for explicit reload and intent")
    func mutationVersionConflictRecovery() async throws {
        let detailProvider = QueueContentDetailProvider([
            .success(Prompt14Fixtures.detailResponse(
                version: 4,
                saved: false
            )),
            .success(Prompt14Fixtures.detailResponse(
                version: 5,
                saved: false
            )),
        ])
        let recorder = QueueDetailStateRecorder(
            [.success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false
            ))],
            saveResults: [
                .failure(.contentVersionChanged),
                .success(Prompt14Fixtures.stateResponse(
                    version: 5,
                    saved: true
                )),
            ]
        )
        let invalidationCenter = FeatureInvalidationCenter()
        let coverLoader = ControlledDetailCoverLoader()
        let model = Self.model(
            detailProvider: detailProvider,
            recorder: recorder,
            invalidationCenter: invalidationCenter,
            coverLoader: coverLoader
        )
        await model.load(revision: 0)

        let mutation = Task { await model.toggleSaved() }
        await coverLoader.waitUntilRemovalStarts()

        #expect(await coverLoader.removals == [ContentDetailCoverRemoval(
            publicationID: Self.routePublicationID,
            version: 4
        )])
        #expect(model.contentMutationState.attempt != nil)
        #expect(!model.canRetryContentMutation)
        #expect(!model.canToggleSaved)
        #expect(invalidationCenter.revision(for: .contentCatalog) == 0)
        #expect(invalidationCenter.revision(for: .contentDetail(
            Self.routePublicationID
        )) == 0)
        #expect(await detailProvider.publicationIDs.count == 1)

        await coverLoader.finishRemoval()
        await mutation.value
        #expect(invalidationCenter.revision(for: .contentCatalog) == 1)
        #expect(invalidationCenter.revision(for: .contentDetail(
            Self.routePublicationID
        )) == 1)
        #expect(model.accessibilityFocusTarget == .mutationSummary)

        await model.retryContentMutation()
        #expect(await recorder.saveAttempts.count == 1)
        await model.load(revision: 1)

        #expect(model.state == .loaded(Prompt14Fixtures.renderable(
            version: 5,
            saved: false
        )))
        #expect(model.contentMutationState == .idle)
        #expect(model.accessibilityFocusTarget == .articleHeading)
        #expect(await detailProvider.publicationIDs.count == 2)

        await model.toggleSaved()
        let newAttempt = try #require(await recorder.saveAttempts.last)
        #expect(newAttempt.payload.body.version == 5)
        #expect(newAttempt.key.value == "detail-0003")
        #expect(await recorder.saveAttempts.count == 2)
    }

    // Mutation caught: claiming only after the async hop into the mutation
    // runner, so two MainActor intents both consume keys before one is dropped.
    @Test("competing intents synchronously claim one key and one request")
    func competingIntentsClaimSynchronously() async {
        let keyProvider = CountingDetailKeyProvider()
        let recorder = ControlledContentMutationRecorder(
            openedResponse: Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false
            )
        )
        let model = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(
                    version: 4,
                    saved: false
                )),
            ]),
            recorder: recorder,
            keyProvider: keyProvider
        )
        await model.load(revision: 0)
        #expect(keyProvider.callCount == 1)

        let completions = DetailAsyncCompletionCounter()
        let save = Task {
            await model.toggleSaved()
            await completions.recordCompletion()
        }
        let completion = Task {
            await model.complete()
            await completions.recordCompletion()
        }
        await recorder.waitForMutationAttemptCount(1)
        await completions.waitForCount(1)

        #expect(keyProvider.callCount == 2)
        #expect(await recorder.mutationAttemptCount == 1)

        await recorder.succeedPendingMutation(
            with: Prompt14Fixtures.stateResponse(
                version: 4,
                saved: true,
                completed: true
            )
        )
        await save.value
        await completion.value
    }

    // Mutation caught: delivering a target-only focus value, so Retry assigns
    // the already-focused target and VoiceOver receives no second transition.
    @Test("failure and retry result publish distinct one-shot focus events")
    func retryPublishesDistinctFocusEvents() async throws {
        let recorder = QueueDetailStateRecorder(
            [.success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false
            ))],
            saveResults: [
                .failure(.offline),
                .success(Prompt14Fixtures.stateResponse(
                    version: 4,
                    saved: true
                )),
            ]
        )
        let model = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(
                    version: 4,
                    saved: false
                )),
            ]),
            recorder: recorder
        )
        await model.load(revision: 0)

        await model.toggleSaved()
        let failureEvent = try #require(model.accessibilityFocusEvent)
        #expect(failureEvent.target == .mutationSummary)
        model.consumeAccessibilityFocus(failureEvent)
        #expect(model.accessibilityFocusEvent == nil)

        await model.retryContentMutation()
        let retryEvent = try #require(model.accessibilityFocusEvent)
        #expect(retryEvent.target == .mutationSummary)
        #expect(retryEvent != failureEvent)
        model.consumeAccessibilityFocus(failureEvent)
        #expect(model.accessibilityFocusEvent == retryEvent)
        model.consumeAccessibilityFocus(retryEvent)
        #expect(model.accessibilityFocusEvent == nil)
    }

    // Mutation caught: scheduling same-target refocus with an executor yield
    // instead of waiting until the real accessibility binding observes nil.
    @Test("focus coordinator waits for observed nil before same-target refocus")
    func focusCoordinatorWaitsForObservedNil() {
        var coordinator = ContentDetailAccessibilityFocusCoordinator()
        let first = ContentDetailAccessibilityFocusEvent(
            sequence: 1,
            target: .mutationSummary
        )
        let second = ContentDetailAccessibilityFocusEvent(
            sequence: 2,
            target: .mutationSummary
        )

        #expect(coordinator.receive(first, currentFocus: nil) == .focus(first))
        #expect(coordinator.focusDidChange(to: .mutationSummary) == nil)

        #expect(coordinator.receive(
            second,
            currentFocus: .mutationSummary
        ) == .clear)
        #expect(coordinator.focusDidChange(to: .mutationSummary) == nil)
        #expect(coordinator.focusDidChange(to: nil) == .focus(second))
        #expect(coordinator.focusDidChange(to: nil) == nil)
        #expect(coordinator.focusDidChange(to: .mutationSummary) == nil)

        #expect(coordinator.receive(
            second,
            currentFocus: .mutationSummary
        ) == nil)
        #expect(coordinator.receive(
            first,
            currentFocus: .mutationSummary
        ) == nil)
    }

    // Mutation caught: publishing an error/conflict after cancellation when the
    // recorder ignores cancellation and resumes its continuation with an error.
    @Test("cancelled save and completion errors publish no outcome or side effect")
    func cancelledMutationErrorsAreDiscarded() async {
        for action in DetailMutationTestAction.allCases {
            for error in [
                BodyFlowCapabilityError.offline,
                .contentVersionChanged,
            ] {
                let recorder = ControlledContentMutationRecorder(
                    openedResponse: Prompt14Fixtures.stateResponse(
                        version: 4,
                        saved: false
                    )
                )
                let invalidationCenter = FeatureInvalidationCenter()
                let coverLoader = RecordingDetailCoverLoader()
                let model = Self.model(
                    detailProvider: QueueContentDetailProvider([
                        .success(Prompt14Fixtures.detailResponse(
                            version: 4,
                            saved: false
                        )),
                    ]),
                    recorder: recorder,
                    invalidationCenter: invalidationCenter,
                    coverLoader: coverLoader
                )
                await model.load(revision: 0)

                let mutation = Task {
                    switch action {
                    case .save: await model.toggleSaved()
                    case .completion: await model.complete()
                    }
                }
                await recorder.waitForMutationAttemptCount(1)
                mutation.cancel()
                await recorder.failPendingMutation(with: error)
                await mutation.value

                #expect(model.contentMutationState == .idle)
                #expect(model.accessibilityFocusEvent == nil)
                #expect(await coverLoader.removals.isEmpty)
                #expect(invalidationCenter.revision(for: .contentCatalog) == 0)
                #expect(invalidationCenter.revision(for: .contentDetail(
                    Self.routePublicationID
                )) == 0)
            }
        }
    }

    // Mutation caught: allowing the stale opened snapshot to overwrite a newer
    // save receipt after the two same-version requests overlap.
    @Test("late opened receipt cannot roll back a newer save")
    func lateOpenedCannotRollbackSave() async {
        let recorder = OverlappingOpenedMutationRecorder(
            mutationResponse: Prompt14Fixtures.stateResponse(
                version: 4,
                saved: true,
                completed: false
            )
        )
        let model = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(
                    version: 4,
                    saved: false,
                    completed: false
                )),
            ]),
            recorder: recorder
        )

        let load = Task { await model.load(revision: 0) }
        await recorder.waitForOpenedAttempt()
        await model.toggleSaved()
        #expect(model.state == .loaded(Prompt14Fixtures.renderable(
            version: 4,
            saved: true,
            completed: false
        )))

        await recorder.finishOpened(with: Prompt14Fixtures.stateResponse(
            version: 4,
            saved: false,
            completed: false
        ))
        await load.value

        #expect(model.state == .loaded(Prompt14Fixtures.renderable(
            version: 4,
            saved: true,
            completed: false
        )))
    }

    // Mutation caught: allowing stale opened state to undo completion and make
    // the one-way Complete action available again.
    @Test("late opened receipt cannot roll back a newer completion")
    func lateOpenedCannotRollbackCompletion() async {
        let recorder = OverlappingOpenedMutationRecorder(
            mutationResponse: Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false,
                completed: true
            )
        )
        let model = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(
                    version: 4,
                    saved: false,
                    completed: false
                )),
            ]),
            recorder: recorder
        )

        let load = Task { await model.load(revision: 0) }
        await recorder.waitForOpenedAttempt()
        await model.complete()
        #expect(!model.showsCompletionAction)

        await recorder.finishOpened(with: Prompt14Fixtures.stateResponse(
            version: 4,
            saved: false,
            completed: false
        ))
        await load.value

        #expect(model.state == .loaded(Prompt14Fixtures.renderable(
            version: 4,
            saved: false,
            completed: true
        )))
        #expect(!model.showsCompletionAction)
        #expect(!model.canComplete)
    }

    // Mutation caught: accepting completed=false as completion success instead
    // of failing closed without reconciliation or invalidation.
    @Test("completion requires canonical completed true")
    func completionRequiresCompletedReceipt() async throws {
        let recorder = QueueDetailStateRecorder([
            .success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false,
                completed: false
            )),
            .success(Prompt14Fixtures.stateResponse(
                version: 4,
                saved: false,
                completed: false
            )),
        ])
        let invalidationCenter = FeatureInvalidationCenter()
        let model = Self.model(
            detailProvider: QueueContentDetailProvider([
                .success(Prompt14Fixtures.detailResponse(
                    version: 4,
                    saved: false,
                    completed: false
                )),
            ]),
            recorder: recorder,
            invalidationCenter: invalidationCenter
        )
        await model.load(revision: 0)

        await model.complete()
        let attempt = try #require(await recorder.readAttempts.last)

        #expect(model.contentMutationState == .failed(
            .completion(attempt),
            .invalidContentContract
        ))
        #expect(model.state == .loaded(Prompt14Fixtures.renderable(
            version: 4,
            saved: false,
            completed: false
        )))
        #expect(model.contentMutationPresentation?.message ==
            "Não foi possível atualizar. Tente novamente.")
        #expect(invalidationCenter.revision(for: .contentCatalog) == 0)
        #expect(invalidationCenter.revision(for: .contentDetail(
            Self.routePublicationID
        )) == 0)
    }

    // Mutation caught: deriving save/unsave outcome copy from requested intent
    // when canonical saved state differs from it.
    @Test("save presentation follows canonical returned state")
    func savePresentationUsesCanonicalState() async {
        let cases: [(initial: Bool, canonical: Bool, message: String)] = [
            (false, false, "Conteúdo removido dos salvos"),
            (true, true, "Conteúdo salvo"),
        ]

        for testCase in cases {
            let recorder = QueueDetailStateRecorder(
                [.success(Prompt14Fixtures.stateResponse(
                    version: 4,
                    saved: testCase.initial
                ))],
                saveResults: [.success(Prompt14Fixtures.stateResponse(
                    version: 4,
                    saved: testCase.canonical
                ))]
            )
            let model = Self.model(
                detailProvider: QueueContentDetailProvider([
                    .success(Prompt14Fixtures.detailResponse(
                        version: 4,
                        saved: testCase.initial
                    )),
                ]),
                recorder: recorder
            )
            await model.load(revision: 0)

            await model.toggleSaved()

            #expect(model.contentMutationPresentation?.message == testCase.message)
            #expect(model.state == .loaded(Prompt14Fixtures.renderable(
                version: 4,
                saved: testCase.canonical
            )))
        }
    }

    // Mutation caught: accepting a completion receipt for another publication
    // or version and reconciling/invalidation as though it were canonical.
    @Test("completion rejects canonical ID and version mismatches")
    func completionRejectsIdentityMismatches() async throws {
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
            let recorder = QueueDetailStateRecorder([
                .success(Prompt14Fixtures.stateResponse(
                    version: 4,
                    saved: false,
                    completed: false
                )),
                .success(mismatch),
            ])
            let invalidationCenter = FeatureInvalidationCenter()
            let model = Self.model(
                detailProvider: QueueContentDetailProvider([
                    .success(Prompt14Fixtures.detailResponse(
                        version: 4,
                        saved: false,
                        completed: false
                    )),
                ]),
                recorder: recorder,
                invalidationCenter: invalidationCenter
            )
            await model.load(revision: 0)

            await model.complete()
            let attempt = try #require(await recorder.readAttempts.last)

            #expect(model.contentMutationState == .failed(
                .completion(attempt),
                .invalidContentContract
            ))
            #expect(model.state == .loaded(Prompt14Fixtures.renderable(
                version: 4,
                saved: false,
                completed: false
            )))
            #expect(invalidationCenter.revision(for: .contentCatalog) == 0)
            #expect(invalidationCenter.revision(for: .contentDetail(
                Self.routePublicationID
            )) == 0)
        }
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
        coverLoader: any ContentCoverLoading = ImmediateDetailCoverLoader(),
        timeProvider: any TimeProviding = FixedTimeProvider(value: fixedNow),
        keyProvider: any IdempotencyKeyProviding =
            DeterministicIdempotencyKeyProvider(prefix: "detail")
    ) -> ContentDetailViewModel {
        ContentDetailViewModel(
            publicationID: routePublicationID,
            origin: origin,
            detailProvider: detailProvider,
            stateRecorder: recorder,
            markdownParser: BodyFlowMarkdownParser(),
            keyProvider: keyProvider,
            timeProvider: timeProvider,
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
    private var readResults: [DetailStateRecordingResult]
    private var saveResults: [DetailStateRecordingResult]
    private(set) var readAttempts: [MutationAttempt<ContentReadCommand>] = []
    private(set) var saveAttempts: [MutationAttempt<ContentSaveCommand>] = []

    init(
        _ readResults: [DetailStateRecordingResult] = [],
        saveResults: [DetailStateRecordingResult] = []
    ) {
        self.readResults = readResults
        self.saveResults = saveResults
    }

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        readAttempts.append(attempt)
        guard !readResults.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        switch readResults.removeFirst() {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        saveAttempts.append(attempt)
        guard !saveResults.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        switch saveResults.removeFirst() {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }
}

private actor ControlledContentMutationRecorder: PublishedContentStateRecording {
    private let openedResponse: PublishedContentStateResponse
    private(set) var readAttempts: [MutationAttempt<ContentReadCommand>] = []
    private(set) var saveAttempts: [MutationAttempt<ContentSaveCommand>] = []
    private var completionContinuations: [
        Int: CheckedContinuation<PublishedContentStateResponse, any Error>
    ] = [:]
    private var saveContinuations: [
        Int: CheckedContinuation<PublishedContentStateResponse, any Error>
    ] = [:]
    private var saveAttemptWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var mutationAttemptWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    init(openedResponse: PublishedContentStateResponse) {
        self.openedResponse = openedResponse
    }

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        readAttempts.append(attempt)
        guard attempt.payload.body.event == .completed else {
            return openedResponse
        }
        let call = readAttempts.filter {
            $0.payload.body.event == .completed
        }.count
        resumeMutationAttemptWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            completionContinuations[call] = continuation
        }
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        saveAttempts.append(attempt)
        let call = saveAttempts.count
        resumeSaveAttemptWaiters()
        resumeMutationAttemptWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            saveContinuations[call] = continuation
        }
    }

    func waitForSaveAttemptCount(_ expectedCount: Int) async {
        guard saveAttempts.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            saveAttemptWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func succeedSave(
        call: Int,
        with response: PublishedContentStateResponse
    ) {
        saveContinuations.removeValue(forKey: call)?.resume(returning: response)
    }

    var mutationAttemptCount: Int {
        saveAttempts.count + readAttempts.filter {
            $0.payload.body.event == .completed
        }.count
    }

    func waitForMutationAttemptCount(_ expectedCount: Int) async {
        guard mutationAttemptCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            mutationAttemptWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func succeedPendingMutation(with response: PublishedContentStateResponse) {
        if let call = saveContinuations.keys.sorted().first {
            saveContinuations.removeValue(forKey: call)?.resume(returning: response)
        } else if let call = completionContinuations.keys.sorted().first {
            completionContinuations.removeValue(forKey: call)?.resume(
                returning: response
            )
        }
    }

    func failPendingMutation(with error: BodyFlowCapabilityError) {
        if let call = saveContinuations.keys.sorted().first {
            saveContinuations.removeValue(forKey: call)?.resume(throwing: error)
        } else if let call = completionContinuations.keys.sorted().first {
            completionContinuations.removeValue(forKey: call)?.resume(
                throwing: error
            )
        }
    }

    private func resumeSaveAttemptWaiters() {
        let readyCounts = saveAttemptWaiters.keys.filter {
            $0 <= saveAttempts.count
        }
        for count in readyCounts {
            let waiters = saveAttemptWaiters.removeValue(forKey: count) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    private func resumeMutationAttemptWaiters() {
        let readyCounts = mutationAttemptWaiters.keys.filter {
            $0 <= mutationAttemptCount
        }
        for count in readyCounts {
            let waiters = mutationAttemptWaiters.removeValue(forKey: count) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}

private enum DetailMutationTestAction: CaseIterable, Sendable {
    case save
    case completion
}

private actor DetailAsyncCompletionCounter {
    private var count = 0
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func recordCompletion() {
        count += 1
        let readyCounts = waiters.keys.filter { $0 <= count }
        for readyCount in readyCounts {
            let ready = waiters.removeValue(forKey: readyCount) ?? []
            for waiter in ready { waiter.resume() }
        }
    }

    func waitForCount(_ expectedCount: Int) async {
        guard count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            waiters[expectedCount, default: []].append(continuation)
        }
    }
}

private final class CountingDetailKeyProvider:
    @unchecked Sendable,
    IdempotencyKeyProviding {
    private let lock = NSLock()
    private var count = 0

    var callCount: Int { lock.withLock { count } }

    func nextKey() throws -> IdempotencyKey {
        let sequence = lock.withLock {
            count += 1
            return count
        }
        return try IdempotencyKey(
            validating: "counting-\(String(format: "%04d", sequence))"
        )
    }
}

private actor OverlappingOpenedMutationRecorder: PublishedContentStateRecording {
    private let mutationResponse: PublishedContentStateResponse
    private var openedContinuation: CheckedContinuation<
        PublishedContentStateResponse,
        any Error
    >?
    private var openedWaiters: [CheckedContinuation<Void, Never>] = []

    init(mutationResponse: PublishedContentStateResponse) {
        self.mutationResponse = mutationResponse
    }

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        guard attempt.payload.body.event == .opened else {
            return mutationResponse
        }
        let waiters = openedWaiters
        openedWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            openedContinuation = continuation
        }
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        mutationResponse
    }

    func waitForOpenedAttempt() async {
        guard openedContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            openedWaiters.append(continuation)
        }
    }

    func finishOpened(with response: PublishedContentStateResponse) {
        openedContinuation?.resume(returning: response)
        openedContinuation = nil
    }
}

private actor RecordingDetailCoverLoader: ContentCoverLoading {
    private(set) var removals: [ContentDetailCoverRemoval] = []

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
    }

    func endSession() async {}
}

private final class MutableDetailTimeProvider: @unchecked Sendable, TimeProviding {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            value = value.addingTimeInterval(interval)
        }
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
