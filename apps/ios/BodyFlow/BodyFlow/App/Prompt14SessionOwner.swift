import Foundation
import Observation

@MainActor
final class Prompt14SessionOwner {
    let userID: String
    let contentListing: any PublishedContentListing
    let contentDetail: any PublishedContentDetailProviding
    let contentState: any PublishedContentStateRecording
    let coachExperience: any CoachExperienceProviding
    let progress: any ProgressProviding
    let coverLoader: any ContentCoverLoading

    private let gate: Prompt14SessionOperationGate
    private let listingReference: Prompt14CapabilityReference<any PublishedContentListing>
    private let detailReference: Prompt14CapabilityReference<any PublishedContentDetailProviding>
    private let stateReference: Prompt14CapabilityReference<any PublishedContentStateRecording>
    private let coachReference: Prompt14CapabilityReference<any CoachExperienceProviding>
    private let progressReference: Prompt14CapabilityReference<any ProgressProviding>
    private let lifetimeEndpoint: Prompt14JoinableEndpoint<any PublishedContentSessionLifetime>
    private let coverEndpoint: Prompt14JoinableEndpoint<any ContentCoverLoading>
    private var endTask: Task<Void, Never>?
    private var ended = false

    init(userID: String, dependencies: AppDependencies) {
        self.userID = userID

        let contentSession = dependencies.publishedContentSessions.makeSession(
            userID: userID
        )
        let coach = dependencies.coachExperienceSessions.makeCoachExperience(
            userID: userID
        )
        let cover = dependencies.contentCoverSessions.makeLoader(userID: userID)
        let gate = Prompt14SessionOperationGate()
        let listingReference = Prompt14CapabilityReference(contentSession.listing)
        let detailReference = Prompt14CapabilityReference(contentSession.detail)
        let stateReference = Prompt14CapabilityReference(contentSession.state)
        let coachReference = Prompt14CapabilityReference(coach)
        let progressReference = Prompt14CapabilityReference(dependencies.progress)
        let lifetimeEndpoint = Prompt14JoinableEndpoint(contentSession.lifetime)
        let coverEndpoint = Prompt14JoinableEndpoint(cover)

        self.gate = gate
        self.listingReference = listingReference
        self.detailReference = detailReference
        self.stateReference = stateReference
        self.coachReference = coachReference
        self.progressReference = progressReference
        self.lifetimeEndpoint = lifetimeEndpoint
        self.coverEndpoint = coverEndpoint
        contentListing = Prompt14ContentListingCapability(
            gate: gate,
            reference: listingReference
        )
        contentDetail = Prompt14ContentDetailCapability(
            gate: gate,
            reference: detailReference
        )
        contentState = Prompt14ContentStateCapability(
            gate: gate,
            reference: stateReference
        )
        coachExperience = Prompt14CoachCapability(
            gate: gate,
            reference: coachReference
        )
        progress = Prompt14ProgressCapability(
            gate: gate,
            reference: progressReference
        )
        coverLoader = Prompt14CoverCapability(
            gate: gate,
            endpoint: coverEndpoint
        )
    }

    var isInvalidated: Bool {
        gate.isClosed
    }

    var hasRetainedCapabilities: Bool {
        listingReference.hasValue
            || detailReference.hasValue
            || stateReference.hasValue
            || coachReference.hasValue
            || progressReference.hasValue
            || lifetimeEndpoint.hasValue
            || coverEndpoint.hasValue
    }

    func invalidateSynchronously() {
        gate.close()
    }

    func endSession() async {
        invalidateSynchronously()
        guard !ended else { return }

        let task: Task<Void, Never>
        if let endTask {
            task = endTask
        } else {
            task = Task {
                await gate.drain()

                async let contentEnd: Void = lifetimeEndpoint.end { lifetime in
                    await lifetime.endSession()
                }
                async let coverEnd: Void = coverEndpoint.end { cover in
                    await cover.endSession()
                }
                _ = await (contentEnd, coverEnd)

                listingReference.release()
                detailReference.release()
                stateReference.release()
                coachReference.release()
                progressReference.release()
                lifetimeEndpoint.release()
                coverEndpoint.release()
            }
            endTask = task
        }

        await task.value
        ended = true
        endTask = nil
    }
}

@MainActor
@Observable
final class Prompt14AuthenticatedShellCoordinator {
    private let dependencies: AppDependencies
    private var transitionGeneration: UInt64 = 0
    private var teardownTask: Task<Void, Never>?

    private(set) var requestedAuthenticatedUserID: String?
    private(set) var renderableOwner: Prompt14SessionOwner?
    private(set) var tearingDownOwner: Prompt14SessionOwner?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func renderableOwner(
        for requestedUserID: String?
    ) -> Prompt14SessionOwner? {
        guard let requestedUserID,
              let renderableOwner,
              renderableOwner.userID == requestedUserID,
              !renderableOwner.isInvalidated else {
            return nil
        }
        return renderableOwner
    }

    func requiresNeutralRoot(for requestedUserID: String?) -> Bool {
        guard requestedAuthenticatedUserID == requestedUserID,
              tearingDownOwner == nil else {
            return true
        }
        guard let requestedUserID else {
            return renderableOwner != nil
        }
        return renderableOwner(for: requestedUserID) == nil
    }

    func transition(to requestedUserID: String?) async {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        requestedAuthenticatedUserID = requestedUserID

        if let owner = renderableOwner,
           owner.userID != requestedUserID || owner.isInvalidated {
            owner.invalidateSynchronously()
            renderableOwner = nil
            tearingDownOwner = owner
        }

        if let owner = tearingDownOwner {
            owner.invalidateSynchronously()
            let task: Task<Void, Never>
            if let teardownTask {
                task = teardownTask
            } else {
                task = Task {
                    await owner.endSession()
                }
                teardownTask = task
            }

            await task.value
            if tearingDownOwner === owner {
                tearingDownOwner = nil
                teardownTask = nil
            }
        }

        guard !Task.isCancelled,
              generation == transitionGeneration,
              requestedAuthenticatedUserID == requestedUserID else {
            return
        }
        guard let requestedUserID else {
            renderableOwner = nil
            return
        }
        guard renderableOwner?.userID != requestedUserID else { return }

        renderableOwner = Prompt14SessionOwner(
            userID: requestedUserID,
            dependencies: dependencies
        )
    }
}

final class Prompt14SessionOperationGate: @unchecked Sendable {
    private enum OperationState {
        case reserved(cancelOnAttach: Bool)
        case attached(cancel: @Sendable () -> Void)
    }

    private let lock = NSLock()
    private let operationStartBoundary: @Sendable () async -> Void
    private var isOpen = true
    private var operations: [UUID: OperationState] = [:]
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        operationStartBoundary: @escaping @Sendable () async -> Void = {}
    ) {
        self.operationStartBoundary = operationStartBoundary
    }

    var isClosed: Bool {
        lock.withLock { !isOpen }
    }

    func close() {
        let pending: [@Sendable () -> Void] = lock.withLock {
            guard isOpen else { return [] }
            isOpen = false

            var pending: [@Sendable () -> Void] = []
            for operationID in Array(operations.keys) {
                guard let state = operations[operationID] else { continue }
                switch state {
                case .reserved:
                    operations[operationID] = .reserved(cancelOnAttach: true)
                case .attached(let cancel):
                    pending.append(cancel)
                }
            }
            return pending
        }
        for cancel in pending {
            cancel()
        }
    }

    func drain() async {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            let canFinishImmediately = lock.withLock {
                guard !operations.isEmpty else { return true }
                drainWaiters.append(continuation)
                return false
            }
            if canFinishImmediately {
                continuation.resume()
            }
        }
    }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard let operationID = reserveOperation() else {
            throw CancellationError()
        }

        await operationStartBoundary()
        guard canStartReservedOperation(operationID), !Task.isCancelled else {
            completeOperation(operationID)
            throw CancellationError()
        }

        let task = Task<Value, any Error> {
            try await operation()
        }
        let canRun = attachOperation(operationID) {
            task.cancel()
        }
        if !canRun {
            task.cancel()
        }
        defer {
            completeOperation(operationID)
        }

        return try await withTaskCancellationHandler {
            let value = try await task.value
            try Task.checkCancellation()
            guard canPublishResult(for: operationID), canRun else {
                throw CancellationError()
            }
            return value
        } onCancel: {
            task.cancel()
        }
    }

    private func reserveOperation() -> UUID? {
        lock.withLock {
            guard isOpen else { return nil }
            let operationID = UUID()
            operations[operationID] = .reserved(cancelOnAttach: false)
            return operationID
        }
    }

    private func canStartReservedOperation(_ operationID: UUID) -> Bool {
        lock.withLock {
            guard isOpen,
                  case .reserved(cancelOnAttach: false) = operations[operationID]
            else {
                return false
            }
            return true
        }
    }

    private func attachOperation(
        _ operationID: UUID,
        cancel: @escaping @Sendable () -> Void
    ) -> Bool {
        lock.withLock {
            guard case .reserved(let cancelOnAttach) = operations[operationID]
            else {
                return false
            }
            operations[operationID] = .attached(cancel: cancel)
            return isOpen && !cancelOnAttach
        }
    }

    private func canPublishResult(for operationID: UUID) -> Bool {
        lock.withLock {
            isOpen && operations[operationID] != nil
        }
    }

    private func completeOperation(_ operationID: UUID) {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard operations.removeValue(forKey: operationID) != nil,
                  operations.isEmpty else {
                return []
            }
            let waiters = drainWaiters
            drainWaiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private final class Prompt14CapabilityReference<Capability: Sendable>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var value: Capability?

    init(_ value: Capability) {
        self.value = value
    }

    var hasValue: Bool {
        lock.withLock { value != nil }
    }

    func current() -> Capability? {
        lock.withLock { value }
    }

    func release() {
        lock.withLock {
            value = nil
        }
    }
}

private final class Prompt14JoinableEndpoint<Capability: Sendable>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var value: Capability?
    private var endTask: Task<Void, Never>?
    private var ended = false

    init(_ value: Capability) {
        self.value = value
    }

    var hasValue: Bool {
        lock.withLock { value != nil }
    }

    func current() -> Capability? {
        lock.withLock { value }
    }

    func end(
        _ operation: @escaping @Sendable (Capability) async -> Void
    ) async {
        let task: Task<Void, Never>? = lock.withLock {
            guard !ended else { return nil }
            if let endTask {
                return endTask
            }
            guard let value else {
                ended = true
                return nil
            }
            let task = Task {
                await operation(value)
            }
            endTask = task
            return task
        }
        guard let task else { return }

        await task.value
        lock.withLock {
            value = nil
            ended = true
            endTask = nil
        }
    }

    func release() {
        lock.withLock {
            value = nil
        }
    }
}

private struct Prompt14ContentListingCapability: PublishedContentListing {
    let gate: Prompt14SessionOperationGate
    let reference: Prompt14CapabilityReference<any PublishedContentListing>

    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse {
        try await gate.perform {
            guard let capability = reference.current() else {
                throw CancellationError()
            }
            return try await capability.content(query)
        }
    }
}

private struct Prompt14ContentDetailCapability: PublishedContentDetailProviding {
    let gate: Prompt14SessionOperationGate
    let reference: Prompt14CapabilityReference<any PublishedContentDetailProviding>

    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse {
        try await gate.perform {
            guard let capability = reference.current() else {
                throw CancellationError()
            }
            return try await capability.contentDetail(publicationID: publicationID)
        }
    }
}

private struct Prompt14ContentStateCapability: PublishedContentStateRecording {
    let gate: Prompt14SessionOperationGate
    let reference: Prompt14CapabilityReference<any PublishedContentStateRecording>

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        try await gate.perform {
            guard let capability = reference.current() else {
                throw CancellationError()
            }
            return try await capability.recordRead(attempt)
        }
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        try await gate.perform {
            guard let capability = reference.current() else {
                throw CancellationError()
            }
            return try await capability.setSaved(attempt)
        }
    }
}

private struct Prompt14CoachCapability: CoachExperienceProviding {
    let gate: Prompt14SessionOperationGate
    let reference: Prompt14CapabilityReference<any CoachExperienceProviding>

    func coachExperience() async throws -> CoachExperienceResponse {
        try await gate.perform {
            guard let capability = reference.current() else {
                throw CancellationError()
            }
            return try await capability.coachExperience()
        }
    }
}

private struct Prompt14ProgressCapability: ProgressProviding {
    let gate: Prompt14SessionOperationGate
    let reference: Prompt14CapabilityReference<any ProgressProviding>

    func progress() async throws -> ProgressResponse {
        try await gate.perform {
            guard let capability = reference.current() else {
                throw CancellationError()
            }
            return try await capability.progress()
        }
    }
}

private struct Prompt14CoverCapability: ContentCoverLoading {
    let gate: Prompt14SessionOperationGate
    let endpoint: Prompt14JoinableEndpoint<any ContentCoverLoading>

    func image(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage {
        try await gate.perform {
            guard let capability = endpoint.current() else {
                throw CancellationError()
            }
            return try await capability.image(
                publicationID: publicationID,
                version: version,
                cover: cover,
                target: target
            )
        }
    }

    func remove(publicationID: String, version: Int) async {
        do {
            try await gate.perform {
                guard let capability = endpoint.current() else {
                    throw CancellationError()
                }
                await capability.remove(
                    publicationID: publicationID,
                    version: version
                )
            }
        } catch {
            return
        }
    }

    func endSession() async {
        // The session owner is the sole authority for both lifetimes.
    }
}
