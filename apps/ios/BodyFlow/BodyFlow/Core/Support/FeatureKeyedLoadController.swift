@MainActor
final class FeatureKeyedLoadController<
    Key: Hashable & Sendable,
    Value: Sendable
> {
    private enum Intention {
        case load
        case retry
    }

    private struct LoadIdentity {
        let key: Key
        let sequence: Int
        let ownership: FeatureLoadOwnership
    }

    private struct ActiveLoad {
        let identity: LoadIdentity
        let operationTask: Task<FeatureLoadCompletion<Value>?, Never>
    }

    private var activeLoad: ActiveLoad?
    private var currentKey: Key?
    private var currentKeyIsCompleted = false
    private var sequence = 0

    func load(
        key: Key,
        operation: @escaping @Sendable () async throws -> Value,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) async {
        await start(
            key: key,
            intention: .load,
            operation: operation,
            publish: publish
        )
    }

    func retry(
        key: Key,
        operation: @escaping @Sendable () async throws -> Value,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) async {
        await start(
            key: key,
            intention: .retry,
            operation: operation,
            publish: publish
        )
    }

    func cancel() {
        cancelActiveLoad()
    }

    private func start(
        key: Key,
        intention: Intention,
        operation: @escaping @Sendable () async throws -> Value,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) async {
        guard !Task.isCancelled else { return }
        let ownership = FeatureLoadOwnership()

        guard !ownership.isInvalidated,
              prepare(key: key, intention: intention)
        else {
            return
        }

        sequence += 1
        let identity = LoadIdentity(
            key: key,
            sequence: sequence,
            ownership: ownership
        )
        cancelActiveLoad()
        let operationTask = Task { () -> FeatureLoadCompletion<Value>? in
            do {
                let value = try await operation()
                try Task.checkCancellation()
                return FeatureLoadCompletion.value(value)
            } catch is CancellationError {
                return nil
            } catch {
                guard !Task.isCancelled else { return nil }
                return FeatureLoadCompletion.failure(error)
            }
        }
        activeLoad = ActiveLoad(
            identity: identity,
            operationTask: operationTask
        )

        let completion = await withTaskCancellationHandler {
            await operationTask.value
        } onCancel: {
            ownership.invalidate()
            operationTask.cancel()
        }

        complete(
            identity: identity,
            completion: completion,
            publish: publish
        )
    }

    private func prepare(key: Key, intention: Intention) -> Bool {
        switch intention {
        case .load:
            if currentKey != key {
                currentKey = key
                currentKeyIsCompleted = false
                return true
            }

            guard !currentKeyIsCompleted else { return false }
            if let activeLoad,
               activeLoad.identity.key == key,
               !activeLoad.identity.ownership.isInvalidated {
                return false
            }
            return true
        case .retry:
            return currentKey == key
        }
    }

    private func complete(
        identity: LoadIdentity,
        completion: FeatureLoadCompletion<Value>?,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) {
        defer {
            clearActiveLoad(ifOwnedBy: identity)
        }

        guard !Task.isCancelled,
              let completion,
              isCurrent(identity),
              identity.ownership.claimPublication()
        else {
            return
        }

        currentKeyIsCompleted = true
        publish(completion)
    }

    private func isCurrent(_ identity: LoadIdentity) -> Bool {
        activeLoad?.identity.sequence == identity.sequence
            && currentKey == identity.key
    }

    private func clearActiveLoad(ifOwnedBy identity: LoadIdentity) {
        if activeLoad?.identity.sequence == identity.sequence {
            activeLoad = nil
        }
    }

    private func cancelActiveLoad() {
        activeLoad?.identity.ownership.invalidate()
        activeLoad?.operationTask.cancel()
        activeLoad = nil
    }
}
