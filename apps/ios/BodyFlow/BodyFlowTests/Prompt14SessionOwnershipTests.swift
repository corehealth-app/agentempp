import CoreGraphics
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Prompt 14 authenticated session ownership")
struct Prompt14SessionOwnershipTests {
    @Test("switching users closes A before suspension and suppresses every late A publication")
    func switchingUsersSuppressesLatePublicationsAndFinishesBothLifetimes() async throws {
        let fixture = Prompt14SessionFixture()
        let coordinator = Prompt14AuthenticatedShellCoordinator(
            dependencies: fixture.dependencies
        )
        await coordinator.transition(to: "user-a")
        let ownerA = try #require(coordinator.renderableOwner)
        let sessionA = fixture.factories.session(for: "user-a")
        #expect(coordinator.renderableOwner(for: "user-b") == nil)
        let sink = Prompt14PublicationSink()
        let query = try DemoPrompt14Fixtures.todayQuery()
        let publicationID = DemoPrompt14Fixtures.firstSummary.publicationID
        let readAttempt = try Prompt14SessionFixture.readAttempt(
            publicationID: publicationID
        )
        let cover = try #require(DemoPrompt14Fixtures.firstSummary.cover)
        let image = Prompt14SessionFixture.image()

        let feedTask = Task {
            do {
                let value = try await ownerA.contentListing.content(query)
                await sink.publishFeed(value)
                await sink.publishRecommendation(value)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        let detailTask = Task {
            do {
                let value = try await ownerA.contentDetail.contentDetail(
                    publicationID: publicationID
                )
                await sink.publishDetail(value)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        let mutationTask = Task {
            do {
                let value = try await ownerA.contentState.recordRead(readAttempt)
                await sink.publishMutation(value)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        let coachTask = Task {
            do {
                let value = try await ownerA.coachExperience.coachExperience()
                await sink.publishCoach(value)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        let progressTask = Task {
            do {
                let value = try await ownerA.progress.progress()
                await sink.publishProgress(value)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        let coverTask = Task {
            do {
                let value = try await ownerA.coverLoader.image(
                    publicationID: publicationID,
                    version: DemoPrompt14Fixtures.firstSummary.version,
                    cover: cover,
                    target: ContentCoverTargetSize(widthPixels: 80, heightPixels: 80)
                )
                await sink.publishCover(value)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        await sessionA.listing.waitUntilStarted()
        await sessionA.detail.waitUntilStarted()
        await sessionA.mutation.waitUntilStarted()
        await sessionA.coachOperation.waitUntilStarted()
        await fixture.progressOperation.waitUntilStarted()
        await sessionA.coverOperation.waitUntilStarted()

        let transitionEntered = Prompt14MainActorSignal()
        let transitionB = Task { @MainActor in
            transitionEntered.signal()
            await coordinator.transition(to: "user-b")
        }
        await transitionEntered.wait()

        #expect(ownerA.isInvalidated)
        #expect(coordinator.renderableOwner == nil)
        #expect(coordinator.tearingDownOwner === ownerA)
        #expect(fixture.factories.totalCalls(for: "user-a") == 3)
        #expect(fixture.factories.totalCalls(for: "user-b") == 0)
        #expect(await sessionA.contentEnd.startedCount == 0)
        #expect(await sessionA.coverEnd.startedCount == 0)

        let staleListing = ownerA.contentListing
        let rejectedAfterInvalidation = Task {
            do {
                _ = try await staleListing.content(query)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        #expect(await rejectedAfterInvalidation.value)
        #expect(await sessionA.listing.startedCount == 1)

        await sessionA.listing.resume(returning: DemoPrompt14Fixtures.todayFeed)
        await sessionA.detail.resume(returning: DemoPrompt14Fixtures.validDetailResponse)
        await sessionA.mutation.resume(returning: Prompt14SessionFixture.stateResponse(
            publicationID: publicationID
        ))
        await sessionA.coachOperation.resume(
            returning: DemoPrompt14Fixtures.balancedCoachResponse
        )
        await fixture.progressOperation.resume(
            returning: DemoPrompt14Fixtures.completeProgress
        )
        await sessionA.coverOperation.resume(returning: image)

        let cancelledOrSuppressed = [
            await feedTask.value,
            await detailTask.value,
            await mutationTask.value,
            await coachTask.value,
            await progressTask.value,
            await coverTask.value,
        ]
        #expect(cancelledOrSuppressed.allSatisfy { $0 })
        #expect(await sessionA.repository.storageIsEmpty == false)
        #expect(await sessionA.coverLoader.cacheIsEmpty == false)

        await sessionA.contentEnd.waitUntilStarted()
        await sessionA.coverEnd.waitUntilStarted()
        await sessionA.contentEnd.resume(returning: ())
        await sessionA.contentEnd.waitUntilFinished()
        #expect(fixture.factories.totalCalls(for: "user-b") == 0)
        #expect(coordinator.renderableOwner == nil)

        await sessionA.coverEnd.resume(returning: ())
        await sessionA.coverEnd.waitUntilFinished()
        await transitionB.value

        let ownerB = try #require(coordinator.renderableOwner)
        #expect(ownerB.userID == "user-b")
        #expect(ownerB !== ownerA)
        #expect(fixture.factories.calls(.content, for: "user-a") == 1)
        #expect(fixture.factories.calls(.coach, for: "user-a") == 1)
        #expect(fixture.factories.calls(.cover, for: "user-a") == 1)
        #expect(fixture.factories.calls(.content, for: "user-b") == 1)
        #expect(fixture.factories.calls(.coach, for: "user-b") == 1)
        #expect(fixture.factories.calls(.cover, for: "user-b") == 1)
        #expect(await sessionA.repository.endCount == 1)
        #expect(await sessionA.coverLoader.endCount == 1)
        #expect(await sessionA.repository.storageIsEmpty)
        #expect(await sessionA.coverLoader.cacheIsEmpty)
        #expect(await sink.isEmpty)
        #expect(ownerA.hasRetainedCapabilities == false)

        do {
            _ = try await staleListing.content(query)
            Issue.record("A wrapper published after its underlying capability was released")
        } catch is CancellationError {
            // Expected: the wrapper survives, but its gate and capability are closed.
        } catch {
            Issue.record("Expected publication suppression, got \(error)")
        }
    }

    @Test("concurrent owner end calls join one content and cover teardown")
    func ownerEndSessionIsIdempotentAndJoinable() async throws {
        let fixture = Prompt14SessionFixture()
        let owner = Prompt14SessionOwner(
            userID: "user-a",
            dependencies: fixture.dependencies
        )
        let session = fixture.factories.session(for: "user-a")

        let first = Task { @MainActor in
            await owner.endSession()
        }
        await session.contentEnd.waitUntilStarted()
        await session.coverEnd.waitUntilStarted()

        let secondEntered = Prompt14MainActorSignal()
        let second = Task { @MainActor in
            secondEntered.signal()
            await owner.endSession()
        }
        await secondEntered.wait()
        #expect(owner.isInvalidated)
        #expect(await session.repository.endCount == 1)
        #expect(await session.coverLoader.endCount == 1)

        await session.contentEnd.resume(returning: ())
        await session.coverEnd.resume(returning: ())
        await session.contentEnd.waitUntilFinished()
        await session.coverEnd.waitUntilFinished()
        await first.value
        await second.value
        await owner.endSession()

        #expect(await session.repository.endCount == 1)
        #expect(await session.coverLoader.endCount == 1)
        #expect(owner.hasRetainedCapabilities == false)
    }

    @Test("the cover facade cannot own or partially end the session lifetime")
    func coverFacadeEndSessionCannotInvalidateOrPartiallyTeardownOwner() async throws {
        let fixture = Prompt14SessionFixture()
        let owner = Prompt14SessionOwner(
            userID: "user-a",
            dependencies: fixture.dependencies
        )
        let session = fixture.factories.session(for: "user-a")
        let query = try DemoPrompt14Fixtures.todayQuery()

        let feedTask = Task {
            do {
                _ = try await owner.contentListing.content(query)
                return true
            } catch {
                return false
            }
        }
        let coachTask = Task {
            do {
                _ = try await owner.coachExperience.coachExperience()
                return true
            } catch {
                return false
            }
        }
        let progressTask = Task {
            do {
                _ = try await owner.progress.progress()
                return true
            } catch {
                return false
            }
        }
        await session.listing.waitUntilStarted()
        await session.coachOperation.waitUntilStarted()
        await fixture.progressOperation.waitUntilStarted()

        let facadeEntered = Prompt14MainActorSignal()
        let facadeFinished = Prompt14MainActorSignal()
        let facadeEnd = Task { @MainActor in
            facadeEntered.signal()
            await owner.coverLoader.endSession()
            facadeFinished.signal()
        }
        await facadeEntered.wait()
        let facadeBlockedActiveOperations = !facadeFinished.hasSignaled

        await session.listing.resume(returning: DemoPrompt14Fixtures.todayFeed)
        await session.coachOperation.resume(
            returning: DemoPrompt14Fixtures.balancedCoachResponse
        )
        await fixture.progressOperation.resume(
            returning: DemoPrompt14Fixtures.completeProgress
        )
        let operationsContinued = [
            await feedTask.value,
            await coachTask.value,
            await progressTask.value,
        ]

        if facadeBlockedActiveOperations {
            Issue.record("Cover facade blocked and invalidated the shared session gate")
            await session.coverEnd.waitUntilStarted()
            await session.coverEnd.resume(returning: ())
            await session.coverEnd.waitUntilFinished()
            await facadeEnd.value

            let cleanup = Task { @MainActor in
                await owner.endSession()
            }
            await session.contentEnd.waitUntilStarted()
            await session.contentEnd.resume(returning: ())
            await session.contentEnd.waitUntilFinished()
            await cleanup.value
            return
        }

        await facadeEnd.value
        #expect(owner.isInvalidated == false)
        #expect(operationsContinued.allSatisfy { $0 })
        #expect(await session.repository.endCount == 0)
        #expect(await session.coverLoader.endCount == 0)
        #expect(await session.contentEnd.startedCount == 0)
        #expect(await session.coverEnd.startedCount == 0)

        let ownerEnd = Task { @MainActor in
            await owner.endSession()
        }
        await session.contentEnd.waitUntilStarted()
        await session.coverEnd.waitUntilStarted()
        #expect(await session.repository.endCount == 1)
        #expect(await session.coverLoader.endCount == 1)

        await session.contentEnd.resume(returning: ())
        await session.coverEnd.resume(returning: ())
        await session.contentEnd.waitUntilFinished()
        await session.coverEnd.waitUntilFinished()
        await ownerEnd.value

        #expect(await session.repository.endCount == 1)
        #expect(await session.coverLoader.endCount == 1)
        #expect(owner.hasRetainedCapabilities == false)
    }

    @Test("rapid A to B to C joins A teardown and creates only the latest session")
    func rapidTransitionsSkipIntermediateFactoryCreation() async throws {
        let fixture = Prompt14SessionFixture()
        let coordinator = Prompt14AuthenticatedShellCoordinator(
            dependencies: fixture.dependencies
        )
        await coordinator.transition(to: "user-a")
        let ownerA = try #require(coordinator.renderableOwner)
        let sessionA = fixture.factories.session(for: "user-a")

        let bEntered = Prompt14MainActorSignal()
        let transitionB = Task { @MainActor in
            bEntered.signal()
            await coordinator.transition(to: "user-b")
        }
        await bEntered.wait()
        await sessionA.contentEnd.waitUntilStarted()
        await sessionA.coverEnd.waitUntilStarted()

        let cEntered = Prompt14MainActorSignal()
        let transitionC = Task { @MainActor in
            cEntered.signal()
            await coordinator.transition(to: "user-c")
        }
        await cEntered.wait()

        #expect(coordinator.requestedAuthenticatedUserID == "user-c")
        #expect(coordinator.renderableOwner == nil)
        #expect(coordinator.tearingDownOwner === ownerA)
        #expect(fixture.factories.totalCalls(for: "user-b") == 0)
        #expect(fixture.factories.totalCalls(for: "user-c") == 0)

        await sessionA.contentEnd.resume(returning: ())
        await sessionA.coverEnd.resume(returning: ())
        await sessionA.contentEnd.waitUntilFinished()
        await sessionA.coverEnd.waitUntilFinished()
        await transitionB.value
        await transitionC.value

        let ownerC = try #require(coordinator.renderableOwner)
        let sessionC = fixture.factories.session(for: "user-c")
        #expect(ownerC.userID == "user-c")
        #expect(fixture.factories.users(for: .content) == ["user-a", "user-c"])
        #expect(fixture.factories.users(for: .coach) == ["user-a", "user-c"])
        #expect(fixture.factories.users(for: .cover) == ["user-a", "user-c"])
        #expect(fixture.factories.totalCalls(for: "user-b") == 0)
        #expect(ObjectIdentifier(sessionA.repository) != ObjectIdentifier(sessionC.repository))
        #expect(ObjectIdentifier(sessionA.coach) != ObjectIdentifier(sessionC.coach))
        #expect(ObjectIdentifier(sessionA.coverLoader) != ObjectIdentifier(sessionC.coverLoader))
        #expect(await sessionA.repository.endCount == 1)
        #expect(await sessionA.coverLoader.endCount == 1)
    }

    @Test("cancelled signed-out transition still awaits the shared complete teardown")
    func cancelledNilTransitionCannotAbandonTeardown() async throws {
        let fixture = Prompt14SessionFixture()
        let coordinator = Prompt14AuthenticatedShellCoordinator(
            dependencies: fixture.dependencies
        )
        await coordinator.transition(to: "user-a")
        let ownerA = try #require(coordinator.renderableOwner)
        let sessionA = fixture.factories.session(for: "user-a")

        let entered = Prompt14MainActorSignal()
        let transition = Task { @MainActor in
            entered.signal()
            await coordinator.transition(to: nil)
        }
        await entered.wait()
        await sessionA.contentEnd.waitUntilStarted()
        await sessionA.coverEnd.waitUntilStarted()
        transition.cancel()

        #expect(coordinator.requestedAuthenticatedUserID == nil)
        #expect(coordinator.renderableOwner == nil)
        #expect(coordinator.tearingDownOwner === ownerA)
        #expect(ownerA.isInvalidated)

        await sessionA.contentEnd.resume(returning: ())
        await sessionA.contentEnd.waitUntilFinished()
        #expect(coordinator.tearingDownOwner === ownerA)
        #expect(await sessionA.coverLoader.endCount == 1)

        await sessionA.coverEnd.resume(returning: ())
        await sessionA.coverEnd.waitUntilFinished()
        await transition.value

        #expect(coordinator.renderableOwner == nil)
        #expect(coordinator.tearingDownOwner == nil)
        #expect(await sessionA.repository.endCount == 1)
        #expect(await sessionA.coverLoader.endCount == 1)
        #expect(ownerA.hasRetainedCapabilities == false)
        #expect(fixture.factories.totalCallCount == 3)
    }

    @Test("root presentation stays neutral until every authenticated lifetime settles")
    func rootPresentationPolicyCoversExitInitialLoadAndUserSwap() async throws {
        let fixture = Prompt14SessionFixture()
        let coordinator = Prompt14AuthenticatedShellCoordinator(
            dependencies: fixture.dependencies
        )

        #expect(coordinator.requiresNeutralRoot(for: nil) == false)
        #expect(coordinator.requiresNeutralRoot(for: "user-a"))

        await coordinator.transition(to: "user-a")
        let firstSessionA = fixture.factories.session(for: "user-a")
        #expect(coordinator.requiresNeutralRoot(for: "user-a") == false)
        #expect(coordinator.requiresNeutralRoot(for: "user-b"))
        #expect(coordinator.requiresNeutralRoot(for: nil))

        let signedOutEntered = Prompt14MainActorSignal()
        let signedOutTransition = Task { @MainActor in
            signedOutEntered.signal()
            await coordinator.transition(to: nil)
        }
        await signedOutEntered.wait()
        await firstSessionA.contentEnd.waitUntilStarted()
        await firstSessionA.coverEnd.waitUntilStarted()
        #expect(coordinator.requiresNeutralRoot(for: nil))

        await firstSessionA.contentEnd.resume(returning: ())
        await firstSessionA.contentEnd.waitUntilFinished()
        #expect(coordinator.requiresNeutralRoot(for: nil))

        await firstSessionA.coverEnd.resume(returning: ())
        await firstSessionA.coverEnd.waitUntilFinished()
        await signedOutTransition.value
        #expect(coordinator.requiresNeutralRoot(for: nil) == false)

        #expect(coordinator.requiresNeutralRoot(for: "user-a"))
        await coordinator.transition(to: "user-a")
        let secondSessionA = fixture.factories.session(for: "user-a")
        #expect(coordinator.requiresNeutralRoot(for: "user-a") == false)
        #expect(coordinator.requiresNeutralRoot(for: "user-b"))

        let userBEntered = Prompt14MainActorSignal()
        let userBTransition = Task { @MainActor in
            userBEntered.signal()
            await coordinator.transition(to: "user-b")
        }
        await userBEntered.wait()
        await secondSessionA.contentEnd.waitUntilStarted()
        await secondSessionA.coverEnd.waitUntilStarted()
        #expect(coordinator.requiresNeutralRoot(for: "user-b"))

        await secondSessionA.contentEnd.resume(returning: ())
        await secondSessionA.coverEnd.resume(returning: ())
        await secondSessionA.contentEnd.waitUntilFinished()
        await secondSessionA.coverEnd.waitUntilFinished()
        await userBTransition.value
        #expect(coordinator.requiresNeutralRoot(for: "user-b") == false)
    }

    @Test("a cancelled B waiter finishes A teardown without publishing or creating B")
    func cancelledReplacementWaiterCannotCreateItsSession() async throws {
        let fixture = Prompt14SessionFixture()
        let coordinator = Prompt14AuthenticatedShellCoordinator(
            dependencies: fixture.dependencies
        )
        await coordinator.transition(to: "user-a")
        let sessionA = fixture.factories.session(for: "user-a")

        let entered = Prompt14MainActorSignal()
        let transitionB = Task { @MainActor in
            entered.signal()
            await coordinator.transition(to: "user-b")
        }
        await entered.wait()
        await sessionA.contentEnd.waitUntilStarted()
        await sessionA.coverEnd.waitUntilStarted()
        transitionB.cancel()

        await sessionA.contentEnd.resume(returning: ())
        await sessionA.coverEnd.resume(returning: ())
        await sessionA.contentEnd.waitUntilFinished()
        await sessionA.coverEnd.waitUntilFinished()
        await transitionB.value

        guard fixture.factories.totalCalls(for: "user-b") == 0 else {
            Issue.record("Cancelled waiter B created a session after A teardown")
            return
        }
        #expect(coordinator.renderableOwner == nil)

        await coordinator.transition(to: "user-c")
        #expect(coordinator.renderableOwner?.userID == "user-c")
        #expect(fixture.factories.users(for: .content) == ["user-a", "user-c"])
        #expect(fixture.factories.users(for: .coach) == ["user-a", "user-c"])
        #expect(fixture.factories.users(for: .cover) == ["user-a", "user-c"])
    }

    @Test("an invalidated same-user owner is neutral, torn down, and recreated")
    func disappearedSameUserShellCannotReuseInvalidatedOwner() async throws {
        let fixture = Prompt14SessionFixture()
        let coordinator = Prompt14AuthenticatedShellCoordinator(
            dependencies: fixture.dependencies
        )
        await coordinator.transition(to: "user-a")
        let firstOwner = try #require(coordinator.renderableOwner)
        let firstSession = fixture.factories.session(for: "user-a")

        firstOwner.invalidateSynchronously()
        guard coordinator.renderableOwner(for: "user-a") == nil else {
            Issue.record("Invalidated same-user owner remained renderable")
            return
        }

        let transition = Task { @MainActor in
            await coordinator.transition(to: "user-a")
        }
        await firstSession.contentEnd.waitUntilStarted()
        await firstSession.coverEnd.waitUntilStarted()
        #expect(coordinator.renderableOwner == nil)
        #expect(coordinator.tearingDownOwner === firstOwner)

        await firstSession.contentEnd.resume(returning: ())
        await firstSession.coverEnd.resume(returning: ())
        await firstSession.contentEnd.waitUntilFinished()
        await firstSession.coverEnd.waitUntilFinished()
        await transition.value

        let secondOwner = try #require(coordinator.renderableOwner)
        let secondSession = fixture.factories.session(for: "user-a")
        #expect(secondOwner !== firstOwner)
        #expect(secondOwner.userID == "user-a")
        #expect(
            ObjectIdentifier(secondSession.repository)
                != ObjectIdentifier(firstSession.repository)
        )
        #expect(
            ObjectIdentifier(secondSession.coverLoader)
                != ObjectIdentifier(firstSession.coverLoader)
        )
        #expect(
            ObjectIdentifier(secondSession.coach)
                != ObjectIdentifier(firstSession.coach)
        )
        #expect(fixture.factories.calls(.content, for: "user-a") == 2)
        #expect(fixture.factories.calls(.coach, for: "user-a") == 2)
        #expect(fixture.factories.calls(.cover, for: "user-a") == 2)
        #expect(await firstSession.repository.endCount == 1)
        #expect(await firstSession.coverLoader.endCount == 1)
        #expect(await secondSession.repository.endCount == 0)
        #expect(await secondSession.coverLoader.endCount == 0)
    }

    @Test("the gate reserves before launch and drains cancellation-resistant work")
    func gateReservationClosesAtomicallyAndDrainWaitsForCompletion() async {
        let launchBoundary = Prompt14SuspendedValue<Void>()
        let operationStarted = Prompt14MainActorSignal()
        let reservationGate = Prompt14SessionOperationGate(
            operationStartBoundary: {
                await launchBoundary.suspend()
            }
        )
        let reservedCall = Task { @MainActor in
            do {
                _ = try await reservationGate.perform {
                    await operationStarted.signal()
                    return true
                }
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        await launchBoundary.waitUntilStarted()
        reservationGate.close()
        await launchBoundary.resume(returning: ())

        #expect(await reservedCall.value)
        #expect(operationStarted.hasSignaled == false)
        await reservationGate.drain()

        let lateOperation = Prompt14SuspendedValue<Int>()
        let drainGate = Prompt14SessionOperationGate()
        let attachedCall = Task { @MainActor in
            do {
                _ = try await drainGate.perform {
                    await lateOperation.suspend()
                }
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        await lateOperation.waitUntilStarted()
        drainGate.close()

        let drainEntered = Prompt14MainActorSignal()
        let drainFinished = Prompt14MainActorSignal()
        let drainTask = Task { @MainActor in
            drainEntered.signal()
            await drainGate.drain()
            drainFinished.signal()
        }
        await drainEntered.wait()

        #expect(drainFinished.hasSignaled == false)
        await lateOperation.resume(returning: 42)
        #expect(await attachedCall.value)
        await drainTask.value
        #expect(drainFinished.hasSignaled)
    }
}

private struct Prompt14SessionFixture {
    let factories: Prompt14FactoryRecorder
    let progressOperation: Prompt14SuspendedValue<ProgressResponse>
    let dependencies: AppDependencies

    init() {
        let factories = Prompt14FactoryRecorder()
        let progressOperation = Prompt14SuspendedValue<ProgressResponse>()
        self.factories = factories
        self.progressOperation = progressOperation
        let base = AppDependencies.scaffold()
        dependencies = AppDependencies(
            apiClient: base.apiClient,
            authentication: base.authentication,
            onboarding: base.onboarding,
            coachPersona: base.coachPersona,
            secureStore: base.secureStore,
            telemetry: base.telemetry,
            today: base.today,
            history: base.history,
            plan: base.plan,
            progress: Prompt14ControlledProgress(operation: progressOperation),
            mealDetection: base.mealDetection,
            registration: base.registration,
            hydration: base.hydration,
            weight: base.weight,
            routine: base.routine,
            publishedContentSessions: Prompt14ContentFactory(recorder: factories),
            coachExperienceSessions: Prompt14CoachFactory(recorder: factories),
            contentCoverSessions: Prompt14CoverFactory(recorder: factories),
            timeProvider: base.timeProvider,
            idempotencyKeyProvider: base.idempotencyKeyProvider,
            patientTimeZone: base.patientTimeZone
        )
    }

    static func readAttempt(
        publicationID: String
    ) throws -> MutationAttempt<ContentReadCommand> {
        MutationAttempt(
            operation: .contentRead,
            key: try IdempotencyKey(validating: "prompt14-read-user-a"),
            payload: ContentReadCommand(
                publicationID: publicationID,
                body: ContentReadBody(
                    event: .opened,
                    origin: .library,
                    version: DemoPrompt14Fixtures.firstSummary.version
                )
            ),
            createdAt: DemoPrompt14Fixtures.fixedNow
        )
    }

    static func stateResponse(
        publicationID: String
    ) -> PublishedContentStateResponse {
        PublishedContentStateResponse(
            data: PublishedContentState(
                publicationID: publicationID,
                version: DemoPrompt14Fixtures.firstSummary.version,
                saved: true,
                completed: false,
                changed: true,
                replayed: false
            ),
            meta: DemoPrompt14Fixtures.contentStateMetadata
        )
    }

    static func image() -> ContentCoverImage {
        let bytes = Data([0, 0, 0, 255]) as CFData
        let provider = CGDataProvider(data: bytes)!
        let cgImage = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return ContentCoverImage(cgImage: cgImage)
    }
}

private enum Prompt14FactoryKind: Hashable, Sendable {
    case content
    case coach
    case cover
}

private struct Prompt14FactoryCall: Equatable, Sendable {
    let kind: Prompt14FactoryKind
    let userID: String
}

private final class Prompt14FactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: [Prompt14ControlledSession]] = [:]
    private var factoryCalls: [Prompt14FactoryCall] = []

    var totalCallCount: Int {
        lock.withLock { factoryCalls.count }
    }

    func record(
        _ kind: Prompt14FactoryKind,
        userID: String
    ) -> Prompt14ControlledSession {
        lock.withLock {
            factoryCalls.append(Prompt14FactoryCall(kind: kind, userID: userID))
            if kind == .content {
                let session = Prompt14ControlledSession()
                sessions[userID, default: []].append(session)
                return session
            }
            guard let session = sessions[userID]?.last else {
                preconditionFailure("Content factory must create the session first")
            }
            return session
        }
    }

    func session(for userID: String) -> Prompt14ControlledSession {
        lock.withLock {
            guard let session = sessions[userID]?.last else {
                preconditionFailure("No controlled session for \(userID)")
            }
            return session
        }
    }

    func calls(_ kind: Prompt14FactoryKind, for userID: String) -> Int {
        lock.withLock {
            factoryCalls.count { $0.kind == kind && $0.userID == userID }
        }
    }

    func totalCalls(for userID: String) -> Int {
        lock.withLock {
            factoryCalls.count { $0.userID == userID }
        }
    }

    func users(for kind: Prompt14FactoryKind) -> [String] {
        lock.withLock {
            factoryCalls.compactMap { $0.kind == kind ? $0.userID : nil }
        }
    }
}

private struct Prompt14ContentFactory: PublishedContentSessionCreating {
    let recorder: Prompt14FactoryRecorder

    func makeSession(userID: String) -> PublishedContentSession {
        let session = recorder.record(.content, userID: userID)
        return PublishedContentSession(
            listing: session.repository,
            detail: session.repository,
            state: session.repository,
            lifetime: session.repository
        )
    }
}

private struct Prompt14CoachFactory: CoachExperienceSessionCreating {
    let recorder: Prompt14FactoryRecorder

    func makeCoachExperience(userID: String) -> any CoachExperienceProviding {
        recorder.record(.coach, userID: userID).coach
    }
}

private struct Prompt14CoverFactory: ContentCoverSessionCreating {
    let recorder: Prompt14FactoryRecorder

    func makeLoader(userID: String) -> any ContentCoverLoading {
        recorder.record(.cover, userID: userID).coverLoader
    }
}

private final class Prompt14ControlledSession: @unchecked Sendable {
    let listing = Prompt14SuspendedValue<PublishedContentFeedResponse>()
    let detail = Prompt14SuspendedValue<PublishedContentDetailResponse>()
    let mutation = Prompt14SuspendedValue<PublishedContentStateResponse>()
    let coachOperation = Prompt14SuspendedValue<CoachExperienceResponse>()
    let coverOperation = Prompt14SuspendedValue<ContentCoverImage>()
    let contentEnd = Prompt14SuspendedValue<Void>()
    let coverEnd = Prompt14SuspendedValue<Void>()
    let repository: Prompt14ControlledRepository
    let coach: Prompt14ControlledCoach
    let coverLoader: Prompt14ControlledCoverLoader

    init() {
        repository = Prompt14ControlledRepository(
            listing: listing,
            detail: detail,
            mutation: mutation,
            end: contentEnd
        )
        coach = Prompt14ControlledCoach(operation: coachOperation)
        coverLoader = Prompt14ControlledCoverLoader(
            operation: coverOperation,
            end: coverEnd
        )
    }
}

private actor Prompt14SuspendedValue<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var startedCount = 0
    private var finished = false

    func suspend() async -> Value {
        let value = await withCheckedContinuation {
            (continuation: CheckedContinuation<Value, Never>) in
            precondition(self.continuation == nil, "Controlled operation started twice")
            self.continuation = continuation
            startedCount += 1
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
        finished = true
        let waiters = finishWaiters
        finishWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return value
    }

    func waitUntilStarted() async {
        guard startedCount == 0 else { return }
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            startWaiters.append(continuation)
        }
    }

    func waitUntilFinished() async {
        guard !finished else { return }
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            finishWaiters.append(continuation)
        }
    }

    func resume(returning value: Value) {
        guard let continuation else {
            preconditionFailure("Controlled operation was not started")
        }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}

private actor Prompt14ControlledRepository:
    PublishedContentListing,
    PublishedContentDetailProviding,
    PublishedContentStateRecording,
    PublishedContentSessionLifetime
{
    private let listing: Prompt14SuspendedValue<PublishedContentFeedResponse>
    private let detail: Prompt14SuspendedValue<PublishedContentDetailResponse>
    private let mutation: Prompt14SuspendedValue<PublishedContentStateResponse>
    private let end: Prompt14SuspendedValue<Void>
    private var ledger: [ContentReadCommand] = []
    private var cache: [String: PublishedContentDetailResponse] = [:]
    private var snapshots: [PublishedContentFeedResponse] = []
    private(set) var endCount = 0

    init(
        listing: Prompt14SuspendedValue<PublishedContentFeedResponse>,
        detail: Prompt14SuspendedValue<PublishedContentDetailResponse>,
        mutation: Prompt14SuspendedValue<PublishedContentStateResponse>,
        end: Prompt14SuspendedValue<Void>
    ) {
        self.listing = listing
        self.detail = detail
        self.mutation = mutation
        self.end = end
    }

    var storageIsEmpty: Bool {
        ledger.isEmpty && cache.isEmpty && snapshots.isEmpty
    }

    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse {
        let response = await listing.suspend()
        snapshots.append(response)
        return response
    }

    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse {
        let response = await detail.suspend()
        cache[publicationID] = response
        return response
    }

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        let response = await mutation.suspend()
        ledger.append(attempt.payload)
        return response
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func endSession() async {
        endCount += 1
        _ = await end.suspend()
        ledger.removeAll()
        cache.removeAll()
        snapshots.removeAll()
    }
}

private actor Prompt14ControlledCoach: CoachExperienceProviding {
    private let operation: Prompt14SuspendedValue<CoachExperienceResponse>

    init(operation: Prompt14SuspendedValue<CoachExperienceResponse>) {
        self.operation = operation
    }

    func coachExperience() async throws -> CoachExperienceResponse {
        await operation.suspend()
    }
}

private struct Prompt14ControlledProgress: ProgressProviding {
    let operation: Prompt14SuspendedValue<ProgressResponse>

    func progress() async throws -> ProgressResponse {
        await operation.suspend()
    }
}

private actor Prompt14ControlledCoverLoader: ContentCoverLoading {
    private let operation: Prompt14SuspendedValue<ContentCoverImage>
    private let end: Prompt14SuspendedValue<Void>
    private var cache: [String: ContentCoverImage] = [:]
    private(set) var endCount = 0

    init(
        operation: Prompt14SuspendedValue<ContentCoverImage>,
        end: Prompt14SuspendedValue<Void>
    ) {
        self.operation = operation
        self.end = end
    }

    var cacheIsEmpty: Bool {
        cache.isEmpty
    }

    func image(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage {
        let image = await operation.suspend()
        cache[publicationID] = image
        return image
    }

    func remove(publicationID: String, version: Int) async {
        cache[publicationID] = nil
    }

    func endSession() async {
        endCount += 1
        _ = await end.suspend()
        cache.removeAll()
    }
}

private actor Prompt14PublicationSink {
    private var feeds: [PublishedContentFeedResponse] = []
    private var details: [PublishedContentDetailResponse] = []
    private var mutations: [PublishedContentStateResponse] = []
    private var recommendations: [PublishedContentFeedResponse] = []
    private var coaches: [CoachExperienceResponse] = []
    private var progressSnapshots: [ProgressResponse] = []
    private var covers: [ContentCoverImage] = []

    var isEmpty: Bool {
        feeds.isEmpty
            && details.isEmpty
            && mutations.isEmpty
            && recommendations.isEmpty
            && coaches.isEmpty
            && progressSnapshots.isEmpty
            && covers.isEmpty
    }

    func publishFeed(_ value: PublishedContentFeedResponse) {
        feeds.append(value)
    }

    func publishDetail(_ value: PublishedContentDetailResponse) {
        details.append(value)
    }

    func publishMutation(_ value: PublishedContentStateResponse) {
        mutations.append(value)
    }

    func publishRecommendation(_ value: PublishedContentFeedResponse) {
        recommendations.append(value)
    }

    func publishCoach(_ value: CoachExperienceResponse) {
        coaches.append(value)
    }

    func publishProgress(_ value: ProgressResponse) {
        progressSnapshots.append(value)
    }

    func publishCover(_ value: ContentCoverImage) {
        covers.append(value)
    }
}

@MainActor
private final class Prompt14MainActorSignal {
    private var didSignal = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var hasSignaled: Bool {
        didSignal
    }

    func signal() {
        didSignal = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func wait() async {
        guard !didSignal else { return }
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }
}
