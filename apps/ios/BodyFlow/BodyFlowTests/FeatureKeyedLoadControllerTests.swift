import Testing

@testable import BodyFlow

@MainActor
@Suite("Feature keyed load controller")
struct FeatureKeyedLoadControllerTests {
    // Mutation caught: omitting either query or catalog revision from feed-load
    // identity equality or hashing.
    @Test("feed load identity combines query and catalog revision")
    func feedLoadIdentityIsComposite() throws {
        let libraryQuery = try ContentFeedQuery(
            surface: .library,
            category: .nutrition,
            limit: 20,
            cursor: nil
        )
        let savedQuery = try ContentFeedQuery(
            surface: .saved,
            category: .nutrition,
            limit: 20,
            cursor: nil
        )

        let base = FeedLoadKey(query: libraryQuery, catalogRevision: 4)
        let same = FeedLoadKey(query: libraryQuery, catalogRevision: 4)
        let changedQuery = FeedLoadKey(query: savedQuery, catalogRevision: 4)
        let changedRevision = FeedLoadKey(
            query: libraryQuery,
            catalogRevision: 5
        )

        #expect(base == same)
        #expect(base != changedQuery)
        #expect(base != changedRevision)
        #expect(Set([base, same, changedQuery, changedRevision]).count == 3)
    }

    // Mutation caught: starting a second operation for the same completed key.
    @Test("same completed key does not reload")
    func sameCompletedKeyDoesNotReload() async {
        let controller = FeatureKeyedLoadController<String, String>()
        let source = ImmediateKeyedLoadSource()
        var publications: [String] = []

        await controller.load(
            key: "current",
            operation: { await source.load(id: "first", value: "value") },
            publish: { completion in
                if case let .value(value) = completion {
                    publications.append(value)
                }
            }
        )
        await controller.load(
            key: "current",
            operation: { await source.load(id: "duplicate", value: "wrong") },
            publish: { _ in }
        )

        #expect(await source.startedIDs() == ["first"])
        #expect(publications == ["value"])
    }

    // Mutation caught: invalidating only publication ownership without
    // cancelling the older operation task when a newer key takes ownership.
    @Test("newer composite key cancels and suppresses an older late value")
    func newerCompositeKeySuppressesOlderValue() async throws {
        let controller = FeatureKeyedLoadController<FeedLoadKey, String>()
        let source = ControlledKeyedLoadSource()
        var publications: [String] = []
        let query = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: nil
        )
        let keyA = FeedLoadKey(query: query, catalogRevision: 1)
        let keyB = FeedLoadKey(query: query, catalogRevision: 2)

        let taskA = Task { @MainActor in
            await controller.load(
                key: keyA,
                operation: { try await source.load(id: "A") },
                publish: { completion in
                    if case let .value(value) = completion {
                        publications.append(value)
                    }
                }
            )
        }
        await source.waitForCallCount(1)

        let taskB = Task { @MainActor in
            await controller.load(
                key: keyB,
                operation: { try await source.load(id: "B") },
                publish: { completion in
                    if case let .value(value) = completion {
                        publications.append(value)
                    }
                }
            )
        }
        await source.waitForCallCount(2)

        await source.succeed(id: "B", value: "new")
        await taskB.value
        await source.succeed(id: "A", value: "old")
        await taskA.value

        #expect(await source.observedCallCount() == 2)
        #expect(await source.cancellationObserved(id: "A") == true)
        #expect(await source.cancellationObserved(id: "B") == false)
        #expect(publications == ["new"])
    }

    // Mutation caught: publishing an older key's late error after a newer key
    // has completed successfully.
    @Test("newer key suppresses an older late error")
    func newerKeySuppressesOlderError() async {
        let controller = FeatureKeyedLoadController<String, String>()
        let source = ControlledKeyedLoadSource()
        var publications: [String] = []

        let oldTask = Task { @MainActor in
            await controller.load(
                key: "old",
                operation: { try await source.load(id: "old") },
                publish: { completion in
                    switch completion {
                    case let .value(value):
                        publications.append("value:\(value)")
                    case .failure:
                        publications.append("error:old")
                    }
                }
            )
        }
        await source.waitForCallCount(1)

        let newTask = Task { @MainActor in
            await controller.load(
                key: "new",
                operation: { try await source.load(id: "new") },
                publish: { completion in
                    switch completion {
                    case let .value(value):
                        publications.append("value:\(value)")
                    case .failure:
                        publications.append("error:new")
                    }
                }
            )
        }
        await source.waitForCallCount(2)

        await source.succeed(id: "new", value: "new")
        await newTask.value
        await source.fail(id: "old")
        await oldTask.value

        #expect(await source.cancellationObserved(id: "old") == true)
        #expect(await source.cancellationObserved(id: "new") == false)
        #expect(publications == ["value:new"])
    }

    // Mutation caught: allowing retry to run for a key other than the current
    // identity, or preventing an explicit retry of the current key.
    @Test("retry runs only for the current key")
    func retryRunsOnlyForCurrentKey() async {
        let controller = FeatureKeyedLoadController<String, String>()
        let source = ImmediateKeyedLoadSource()
        var publications: [String] = []

        await controller.load(
            key: "A",
            operation: { await source.load(id: "load-A", value: "A") },
            publish: { _ in }
        )
        await controller.load(
            key: "B",
            operation: { await source.load(id: "load-B", value: "B") },
            publish: { _ in }
        )
        await controller.retry(
            key: "A",
            operation: { await source.load(id: "retry-A", value: "wrong") },
            publish: { _ in }
        )
        await controller.retry(
            key: "B",
            operation: { await source.load(id: "retry-B", value: "retry") },
            publish: { completion in
                if case let .value(value) = completion {
                    publications.append(value)
                }
            }
        )

        #expect(await source.startedIDs() == ["load-A", "load-B", "retry-B"])
        #expect(publications == ["retry"])
    }

    // Mutation caught: explicit cancel invalidating only publication ownership
    // without cancelling the operation task or suppressing both late outcomes.
    @Test("explicit cancel cancels and suppresses late values and errors")
    func explicitCancelSuppressesPublication() async {
        let controller = FeatureKeyedLoadController<String, String>()
        let source = ControlledKeyedLoadSource()
        let immediateSource = ImmediateKeyedLoadSource()
        var publications: [String] = []

        let valueTask = Task { @MainActor in
            await controller.load(
                key: "current",
                operation: { try await source.load(id: "cancelled-value") },
                publish: { completion in
                    switch completion {
                    case let .value(value):
                        publications.append(value)
                    case .failure:
                        publications.append("error:cancelled-value")
                    }
                }
            )
        }
        await source.waitForCallCount(1)

        controller.cancel()
        await source.succeed(id: "cancelled-value", value: "forbidden-value")
        await valueTask.value

        #expect(
            await source.cancellationObserved(id: "cancelled-value") == true
        )
        #expect(publications.isEmpty)

        let errorTask = Task { @MainActor in
            await controller.load(
                key: "current",
                operation: { try await source.load(id: "cancelled-error") },
                publish: { completion in
                    switch completion {
                    case let .value(value):
                        publications.append(value)
                    case .failure:
                        publications.append("error:cancelled-error")
                    }
                }
            )
        }
        await source.waitForCallCount(2)

        controller.cancel()
        await source.fail(id: "cancelled-error")
        await errorTask.value

        #expect(
            await source.cancellationObserved(id: "cancelled-error") == true
        )
        #expect(publications.isEmpty)

        await controller.load(
            key: "current",
            operation: {
                await immediateSource.load(id: "replacement", value: "fresh")
            },
            publish: { completion in
                if case let .value(value) = completion {
                    publications.append(value)
                }
            }
        )

        #expect(publications == ["fresh"])
        #expect(await immediateSource.startedIDs() == ["replacement"])
    }

    // Mutation caught: retaining completed values as a multi-key cache instead
    // of retaining only the latest completed identity.
    @Test("completed keys are identities and not a value cache")
    func completedKeysAreNotCached() async {
        let controller = FeatureKeyedLoadController<String, String>()
        let source = ImmediateKeyedLoadSource()
        var publications: [String] = []

        await controller.load(
            key: "A",
            operation: { await source.load(id: "A-1", value: "A-1") },
            publish: { completion in
                if case let .value(value) = completion {
                    publications.append(value)
                }
            }
        )
        await controller.load(
            key: "B",
            operation: { await source.load(id: "B", value: "B") },
            publish: { completion in
                if case let .value(value) = completion {
                    publications.append(value)
                }
            }
        )
        await controller.load(
            key: "A",
            operation: { await source.load(id: "A-2", value: "A-2") },
            publish: { completion in
                if case let .value(value) = completion {
                    publications.append(value)
                }
            }
        )

        #expect(await source.startedIDs() == ["A-1", "B", "A-2"])
        #expect(publications == ["A-1", "B", "A-2"])
    }
}

private actor ImmediateKeyedLoadSource {
    private var ids: [String] = []

    func load(id: String, value: String) -> String {
        ids.append(id)
        return value
    }

    func startedIDs() -> [String] {
        ids
    }
}

private actor ControlledKeyedLoadSource {
    private var callCount = 0
    private var cancellationObservations: [String: Bool] = [:]
    private var continuations: [
        String: CheckedContinuation<String, any Error>
    ] = [:]
    private var callCountWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    func load(id: String) async throws -> String {
        callCount += 1
        defer {
            cancellationObservations[id] = Task.isCancelled
        }
        let readyCounts = callCountWaiters.keys.filter { $0 <= callCount }
        for count in readyCounts {
            let waiters = callCountWaiters.removeValue(forKey: count) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
        }
    }

    func waitForCallCount(_ expectedCount: Int) async {
        guard callCount < expectedCount else { return }

        await withCheckedContinuation { continuation in
            callCountWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func observedCallCount() -> Int {
        callCount
    }

    func cancellationObserved(id: String) -> Bool? {
        cancellationObservations[id]
    }

    func succeed(id: String, value: String) {
        continuations.removeValue(forKey: id)?.resume(returning: value)
    }

    func fail(id: String) {
        continuations.removeValue(forKey: id)?.resume(
            throwing: KeyedLoadFixtureError.failed
        )
    }
}

private enum KeyedLoadFixtureError: Error {
    case failed
}
