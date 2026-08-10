import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Feature invalidation signals")
struct FeatureInvalidationTests {
    @Test(
        "proposal create edit and cancel invalidate only Today",
        arguments: [
            FeatureInvalidation.proposalCreated,
            .proposalEdited,
            .proposalCancelled,
        ]
    )
    func proposalInvalidation(event: FeatureInvalidation) {
        let center = FeatureInvalidationCenter()

        center.record(event)

        #expect(center.revision(for: .today) == 1)
        #expect(center.revision(for: .history) == 0)
        #expect(center.revision(for: .routineList(kind: .supplement)) == 0)
        #expect(center.revision(for: .routineHistory(
            kind: .supplement,
            itemID: "item-a"
        )) == 0)
    }

    @Test("confirmation invalidates Today and History")
    func confirmationInvalidation() {
        let center = FeatureInvalidationCenter()

        center.record(.registrationConfirmed)

        #expect(center.revision(for: .today) == 1)
        #expect(center.revision(for: .history) == 1)
        #expect(center.revision(for: .routineList(kind: .medication)) == 0)
    }

    @Test("hydration invalidates only Today")
    func hydrationInvalidation() {
        let center = FeatureInvalidationCenter()

        center.record(.hydrationRecorded)

        #expect(center.revision(for: .today) == 1)
        #expect(center.revision(for: .history) == 0)
        #expect(center.revision(for: .routineList(kind: .supplement)) == 0)
    }

    @Test("routine action invalidates its exact Today list and item history keys")
    func routineInvalidation() {
        let center = FeatureInvalidationCenter()
        let exactHistory = FeatureInvalidationKey.routineHistory(
            kind: .supplement,
            itemID: "supplement-a"
        )

        center.record(.routineAction(
            kind: .supplement,
            itemID: "supplement-a"
        ))

        #expect(center.revision(for: .today) == 1)
        #expect(center.revision(for: .routineList(kind: .supplement)) == 1)
        #expect(center.revision(for: exactHistory) == 1)
        #expect(center.revision(for: .history) == 0)
        #expect(center.revision(for: .routineList(kind: .medication)) == 0)
        #expect(center.revision(for: .routineHistory(
            kind: .supplement,
            itemID: "supplement-b"
        )) == 0)
    }

    @Test("weight invalidates no read key")
    func weightInvalidation() {
        let center = FeatureInvalidationCenter()

        center.record(.weightRecorded)

        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
        #expect(center.revision(for: .routineList(kind: .supplement)) == 0)
        #expect(center.revision(for: .routineHistory(
            kind: .supplement,
            itemID: "item-a"
        )) == 0)
    }

    // Mutation caught: adding Today, coach, or unrelated-detail invalidation to
    // a content save, completion, or version-conflict event, or omitting either
    // the catalog or affected-detail invalidation.
    @Test(
        "content mutation invalidation never patches Today",
        arguments: [
            FeatureInvalidation.contentSaved(publicationID: "publication-1"),
            .contentCompleted(publicationID: "publication-1"),
            .contentVersionConflict(publicationID: "publication-1"),
        ]
    )
    func contentInvalidationMatrix(event: FeatureInvalidation) {
        let center = FeatureInvalidationCenter()

        center.record(event)

        #expect(center.revision(for: .contentCatalog) == 1)
        #expect(center.revision(for: .contentDetail("publication-1")) == 1)
        #expect(center.revision(for: .contentDetail("publication-2")) == 0)
        #expect(center.revision(for: .coachExperience) == 0)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
        #expect(center.revision(for: .routineList(kind: .supplement)) == 0)
        #expect(center.revision(for: .routineHistory(
            kind: .supplement,
            itemID: "item-a"
        )) == 0)
    }

    // Mutation caught: invalidating Today or a detail for a persona change, or
    // omitting either coach-experience or catalog invalidation.
    @Test("coach persona changes invalidate coach experience and catalog only")
    func coachPersonaInvalidationMatrix() {
        let center = FeatureInvalidationCenter()

        center.record(.coachPersonaChanged)

        #expect(center.revision(for: .coachExperience) == 1)
        #expect(center.revision(for: .contentCatalog) == 1)
        #expect(center.revision(for: .contentDetail("publication-1")) == 0)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
    }

    // Mutation caught: adding any global cover, impression, opened, or other
    // invalidation event outside the four approved Prompt 14 events.
    @Test("global invalidation contract contains only approved events")
    func globalInvalidationContractContainsOnlyApprovedEvents() {
        let events: [FeatureInvalidation] = [
            .proposalCreated,
            .proposalEdited,
            .proposalCancelled,
            .registrationConfirmed,
            .hydrationRecorded,
            .routineAction(kind: .supplement, itemID: "item-a"),
            .weightRecorded,
            .contentSaved(publicationID: "publication-1"),
            .contentCompleted(publicationID: "publication-1"),
            .contentVersionConflict(publicationID: "publication-1"),
            .coachPersonaChanged,
        ]

        for event in events {
            switch event {
            case .proposalCreated,
                 .proposalEdited,
                 .proposalCancelled,
                 .registrationConfirmed,
                 .hydrationRecorded,
                 .routineAction,
                 .weightRecorded,
                 .contentSaved,
                 .contentCompleted,
                 .contentVersionConflict,
                 .coachPersonaChanged:
                break
            }
        }

        #expect(events.count == 11)
    }

    @Test("cancellation before publication claim wins atomically")
    func cancellationWinsBeforePublicationClaim() {
        let ownership = FeatureLoadOwnership()

        ownership.invalidate()

        #expect(!ownership.claimPublication())
    }

    @Test("publication claim commits once and releases its lock")
    func publicationClaimWinsBeforeCancellation() {
        let ownership = FeatureLoadOwnership()

        #expect(ownership.claimPublication())
        ownership.invalidate()

        #expect(!ownership.claimPublication())
    }

    @Test("unrelated revision and repeated active or completed observation do not reload")
    func deduplicatesObservation() async {
        let center = FeatureInvalidationCenter()
        let controller = FeatureRevisionLoadController<String>()
        let source = ControlledSnapshotSource()
        var published: [String] = []
        let historyRevision = center.revision(for: .history)

        let initialTask = Task { @MainActor in
            await controller.load(
                revision: historyRevision,
                operation: { try await source.load(id: "initial") },
                publish: { completion in
                    if case let .value(value) = completion {
                        published.append(value)
                    }
                }
            )
        }
        await waitUntilStarted(source, count: 1)

        await controller.load(
            revision: historyRevision,
            operation: { try await source.load(id: "active-duplicate") },
            publish: { _ in }
        )
        #expect(await source.startedIDs() == ["initial"])

        await source.succeed(id: "initial", value: "snapshot-0")
        await initialTask.value
        center.record(.hydrationRecorded)
        #expect(center.revision(for: .history) == historyRevision)

        await controller.load(
            revision: center.revision(for: .history),
            operation: { try await source.load(id: "completed-duplicate") },
            publish: { _ in }
        )

        #expect(await source.startedIDs() == ["initial"])
        #expect(published == ["snapshot-0"])
    }

    @Test("one relevant revision performs one complete reload")
    func oneRelevantRevisionReloadsOnce() async {
        let center = FeatureInvalidationCenter()
        let controller = FeatureRevisionLoadController<String>()
        let source = ImmediateSnapshotSource()
        var published: [String] = []

        await controller.load(
            revision: center.revision(for: .today),
            operation: { await source.load(id: "initial") },
            publish: { completion in
                if case let .value(value) = completion {
                    published.append(value)
                }
            }
        )
        center.record(.proposalCreated)
        let relevantRevision = center.revision(for: .today)
        await controller.load(
            revision: relevantRevision,
            operation: { await source.load(id: "revision-1") },
            publish: { completion in
                if case let .value(value) = completion {
                    published.append(value)
                }
            }
        )
        await controller.load(
            revision: relevantRevision,
            operation: { await source.load(id: "revision-1-duplicate") },
            publish: { _ in }
        )

        #expect(await source.startedIDs() == ["initial", "revision-1"])
        #expect(published == ["initial", "revision-1"])
    }

    @Test("newer revisions supersede cancelled loads and block late values and errors")
    func newerRevisionWins() async {
        let center = FeatureInvalidationCenter()
        let controller = FeatureRevisionLoadController<String>()
        let source = ControlledSnapshotSource()
        let publications = PublicationRecorder()

        let lateValueTask = revisionTask(
            revision: center.revision(for: .today),
            id: "late-value",
            controller: controller,
            source: source,
            publications: publications
        )
        await waitUntilStarted(source, count: 1)
        lateValueTask.cancel()

        center.record(.proposalEdited)
        let lateErrorTask = revisionTask(
            revision: center.revision(for: .today),
            id: "late-error",
            controller: controller,
            source: source,
            publications: publications
        )
        await waitUntilStarted(source, count: 2)
        lateErrorTask.cancel()

        center.record(.proposalCancelled)
        let newestTask = revisionTask(
            revision: center.revision(for: .today),
            id: "newest",
            controller: controller,
            source: source,
            publications: publications
        )
        await waitUntilStarted(source, count: 3)

        await source.succeed(id: "newest", value: "complete-newest")
        await newestTask.value
        await source.succeed(id: "late-value", value: "forbidden-old-value")
        await source.fail(id: "late-error")
        await lateValueTask.value
        await lateErrorTask.value

        #expect(publications.values == ["value:complete-newest"])
    }

    @Test("cancelled incomplete revision can load again when visible")
    func cancelledRevisionCanRetryOnVisibility() async {
        let controller = FeatureRevisionLoadController<String>()
        let source = ControlledSnapshotSource()
        var published: [String] = []

        let cancelledTask = Task { @MainActor in
            await controller.load(
                revision: 0,
                operation: { try await source.load(id: "cancelled") },
                publish: { completion in
                    if case let .value(value) = completion {
                        published.append(value)
                    }
                }
            )
        }
        await waitUntilStarted(source, count: 1)
        cancelledTask.cancel()
        await source.succeed(id: "cancelled", value: "forbidden")
        await cancelledTask.value

        await controller.load(
            revision: 0,
            operation: { "visible-again" },
            publish: { completion in
                if case let .value(value) = completion {
                    published.append(value)
                }
            }
        )

        #expect(published == ["visible-again"])
    }

    @Test("cancellation before provider completion cannot publish")
    func cancelledProviderCompletionDoesNotPublish() async {
        let controller = FeatureRevisionLoadController<String>()
        let source = ControlledSnapshotSource()
        let publications = PublicationRecorder()

        let task = revisionTask(
            revision: 0,
            id: "cancel-before-claim",
            controller: controller,
            source: source,
            publications: publications
        )
        await waitUntilStarted(source, count: 1)

        task.cancel()
        await source.succeed(
            id: "cancel-before-claim",
            value: "forbidden-cancelled-value"
        )
        await task.value

        #expect(publications.values.isEmpty)
    }

    @Test("cancelled load yields same revision ownership before its provider returns")
    func cancelledLoadYieldsSameRevisionImmediately() async {
        let controller = FeatureRevisionLoadController<String>()
        let source = ControlledSnapshotSource()
        let publications = PublicationRecorder()

        let oldTask = revisionTask(
            revision: 0,
            id: "old-same-revision",
            controller: controller,
            source: source,
            publications: publications
        )
        await waitUntilStarted(source, count: 1)
        oldTask.cancel()

        let secondTask = revisionTask(
            revision: 0,
            id: "second-same-revision",
            controller: controller,
            source: source,
            publications: publications
        )
        let secondStarted = await waitUntilStarted(source, count: 2)

        if secondStarted {
            await source.succeed(
                id: "second-same-revision",
                value: "fresh-same-revision"
            )
        }
        await secondTask.value
        await source.succeed(
            id: "old-same-revision",
            value: "forbidden-old-value"
        )
        await oldTask.value

        #expect(await source.startedIDs() == [
            "old-same-revision",
            "second-same-revision",
        ])
        #expect(publications.values == ["value:fresh-same-revision"])
    }

    @Test("older loads and retries cannot supersede the current revision")
    func staleIntentionsCannotSupersedeCurrentRevision() async {
        let controller = FeatureRevisionLoadController<String>()
        let currentSource = ControlledSnapshotSource()
        let staleSource = ImmediateSnapshotSource()
        let publications = PublicationRecorder()

        let currentTask = revisionTask(
            revision: 2,
            id: "current-revision",
            controller: controller,
            source: currentSource,
            publications: publications
        )
        await waitUntilStarted(currentSource, count: 1)

        await controller.load(
            revision: 1,
            operation: { await staleSource.load(id: "stale-load") },
            publish: { completion in
                if case let .value(value) = completion {
                    publications.values.append("value:\(value)")
                }
            }
        )
        await controller.retry(
            revision: 1,
            operation: { await staleSource.load(id: "stale-retry") },
            publish: { completion in
                if case let .value(value) = completion {
                    publications.values.append("value:\(value)")
                }
            }
        )

        await currentSource.succeed(
            id: "current-revision",
            value: "current-value"
        )
        await currentTask.value

        #expect(await staleSource.startedIDs().isEmpty)
        #expect(publications.values == ["value:current-value"])
    }

    @Test("task cancelled before controller entry does not start its provider")
    func preCancelledTaskDoesNotStartProvider() async {
        let controller = FeatureRevisionLoadController<String>()
        let source = ImmediateSnapshotSource()
        let publications = PublicationRecorder()

        let task = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                // Continue deliberately so the controller sees a pre-cancelled task.
            }

            await controller.load(
                revision: 0,
                operation: { await source.load(id: "must-not-start") },
                publish: { completion in
                    if case let .value(value) = completion {
                        publications.values.append("value:\(value)")
                    }
                }
            )
        }
        task.cancel()
        await task.value

        #expect(await source.startedIDs().isEmpty)
        #expect(publications.values.isEmpty)
    }

    @Test("explicit Retry is a separate load intention")
    func explicitRetryIsSeparate() async {
        let controller = FeatureRevisionLoadController<String>()
        let source = ImmediateSnapshotSource()
        var published: [String] = []

        await controller.load(
            revision: 0,
            operation: { await source.load(id: "revision") },
            publish: { completion in
                if case let .value(value) = completion {
                    published.append(value)
                }
            }
        )
        await controller.retry(
            revision: 0,
            operation: { await source.load(id: "explicit-retry") },
            publish: { completion in
                if case let .value(value) = completion {
                    published.append(value)
                }
            }
        )

        #expect(await source.startedIDs() == ["revision", "explicit-retry"])
        #expect(published == ["revision", "explicit-retry"])
    }

    private func revisionTask(
        revision: Int,
        id: String,
        controller: FeatureRevisionLoadController<String>,
        source: ControlledSnapshotSource,
        publications: PublicationRecorder
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await controller.load(
                revision: revision,
                operation: { try await source.load(id: id) },
                publish: { completion in
                    switch completion {
                    case let .value(value):
                        publications.values.append("value:\(value)")
                    case .failure:
                        publications.values.append("error:\(id)")
                    }
                }
            )
        }
    }

    @discardableResult
    private func waitUntilStarted(
        _ source: ControlledSnapshotSource,
        count: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while await source.startedIDs().count < count {
            guard clock.now < deadline else {
                let startedIDs = await source.startedIDs()
                Issue.record(
                    "Timed out waiting for \(count) loads; started: \(startedIDs)"
                )
                return false
            }

            await Task.yield()
        }

        return true
    }
}

@MainActor
private final class PublicationRecorder {
    var values: [String] = []
}

private actor ImmediateSnapshotSource {
    private var ids: [String] = []

    func load(id: String) -> String {
        ids.append(id)
        return id
    }

    func startedIDs() -> [String] {
        ids
    }
}

private actor ControlledSnapshotSource {
    private var ids: [String] = []
    private var continuations: [
        String: CheckedContinuation<String, any Error>
    ] = [:]

    func load(id: String) async throws -> String {
        ids.append(id)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
        }
    }

    func startedIDs() -> [String] {
        ids
    }

    func succeed(id: String, value: String) {
        continuations.removeValue(forKey: id)?.resume(returning: value)
    }

    func fail(id: String) {
        continuations.removeValue(forKey: id)?.resume(
            throwing: SnapshotFixtureError.failed
        )
    }
}

private enum SnapshotFixtureError: Error, Sendable {
    case failed
}
