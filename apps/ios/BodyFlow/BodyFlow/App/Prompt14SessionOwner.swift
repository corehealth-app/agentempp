import Foundation
import Observation

@MainActor
@Observable
final class Prompt14SessionOwner {
    let userID: String
    let contentListing: any PublishedContentListing
    let contentDetail: any PublishedContentDetailProviding
    let contentState: any PublishedContentStateRecording
    let coachExperience: any CoachExperienceProviding
    let progress: any ProgressProviding
    let coverLoader: any ContentCoverLoading

    private(set) var mealRecordBinding: MealRecordSessionBinding?
    private(set) var workoutRegistrationBinding: WorkoutRegistrationSessionBinding?
    private(set) var isResolvingWorkoutRegistration = false
    private(set) var workoutRegistrationError: BodyFlowCapabilityError?
    private let workoutRegistrationSource: WorkoutRegistrationSessionBindingSource?
    private var workoutResolutionTask: Task<Void, Never>?
    private var workoutResolutionSequence: UInt64 = 0
    private var retiredWorkouts: Task<Void, Never>?

    private let permitsMealRecordBinding: Bool
    private let gate: Prompt14SessionOperationGate
    private let listingReference: Prompt14CapabilityReference<any PublishedContentListing>
    private let detailReference: Prompt14CapabilityReference<any PublishedContentDetailProviding>
    private let stateReference: Prompt14CapabilityReference<any PublishedContentStateRecording>
    private let coachReference: Prompt14CapabilityReference<any CoachExperienceProviding>
    private let progressReference: Prompt14CapabilityReference<any ProgressProviding>
    private let meReference: Prompt14CapabilityReference<any MeProviding>
    private let lifetimeEndpoint: Prompt14JoinableEndpoint<any PublishedContentSessionLifetime>
    private let coverEndpoint: Prompt14JoinableEndpoint<any ContentCoverLoading>
    private let patientTimeZoneStore: PatientTimeZoneStore
    private var timeZoneResolution: Task<Void, Never>?
    private var endTask: Task<Void, Never>?
    // Join only leaf teardowns; the existing gates still register all operations.
    private var mealRecordRetirementTask: Task<Void, Never>?
    private var ended = false

    init(userID: String, dependencies: AppDependencies, enablesMealRecordBinding: Bool = false) {
        self.userID = userID
        permitsMealRecordBinding = enablesMealRecordBinding
        workoutRegistrationSource = dependencies.workoutRegistrationSessionSource

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
        let meReference = Prompt14CapabilityReference(dependencies.me)
        let lifetimeEndpoint = Prompt14JoinableEndpoint(contentSession.lifetime)
        let coverEndpoint = Prompt14JoinableEndpoint(cover)
        let patientTimeZoneStore = dependencies.patientTimeZoneStore

        self.gate = gate
        self.listingReference = listingReference
        self.detailReference = detailReference
        self.stateReference = stateReference
        self.coachReference = coachReference
        self.progressReference = progressReference
        self.meReference = meReference
        self.lifetimeEndpoint = lifetimeEndpoint
        self.coverEndpoint = coverEndpoint
        self.patientTimeZoneStore = patientTimeZoneStore
        // The documented time zone belongs to this session: it is read from
        // `/me` through the same gate as every other capability, so a closed
        // session never writes it, and `endSession` puts the seed back.
        timeZoneResolution = dependencies.workoutRegistrationSessionSource == nil ? Task {
            let response = try? await gate.perform {
                guard let me = meReference.current() else {
                    throw CancellationError()
                }
                return try await me.me()
            }
            guard let response, !gate.isClosed else { return }
            patientTimeZoneStore.resolve(
                documentedIANAIdentifier: response.data.timezone
            )
        } : nil
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
        // Construction only: no lease, task or meal request is started here.
        if enablesMealRecordBinding {
            mealRecordBinding = MealRecordSessionBinding(owner: self, parentGate: gate)
        }
    }

    /// Admission for one new C11 activation. Retired leaves never reopen;
    /// their original parent and all neighboring capabilities remain alive.
    func reserveNewMealRecordBinding() -> MealRecordSessionBinding? {
        guard permitsMealRecordBinding, !ended, endTask == nil, !gate.isClosed else {
            return nil
        }
        let predecessor = mealRecordBinding
        predecessor?.invalidateSynchronously() // deny old starts before replacement
        let replacement = MealRecordSessionBinding(owner: self, parentGate: gate)
        mealRecordBinding = replacement
        if let predecessor {
            let previousRetirement = mealRecordRetirementTask
            mealRecordRetirementTask = Task {
                await predecessor.endSession()
                await previousRetirement?.value
            }
        }
        return replacement
    }

    /// Uses the existing authentication ticket; a same-user new ticket cannot
    /// revive the previous leaf while its lease resolver is still returning.
    func reserveWorkoutRegistrationBinding(
        activation: MealRecordAuthenticatedActivation,
        lifetime: MealRecordAuthenticationLifetime,
        currentActivation: @escaping @MainActor @Sendable () -> MealRecordAuthenticatedActivation?
    ) -> WorkoutRegistrationSessionBinding? {
        guard !ended, endTask == nil, !gate.isClosed,
              activation.userID == userID, currentActivation() == activation,
              lifetime.currentActivation == activation, lifetime.isCurrent(activation.ticket) else { return nil }
        if let binding = workoutRegistrationBinding, binding.isOpen {
            return binding.activation == activation ? binding : nil
        }
        let old = workoutRegistrationBinding
        let oldResolution = workoutResolutionTask
        old?.invalidateSynchronously()
        oldResolution?.cancel()
        workoutResolutionTask = nil
        workoutResolutionSequence &+= 1
        isResolvingWorkoutRegistration = false
        workoutRegistrationError = nil
        let binding = WorkoutRegistrationSessionBinding(owner: self, parentGate: gate,
            activation: activation, lifetime: lifetime, currentActivation: currentActivation,
            timeZoneStore: patientTimeZoneStore)
        workoutRegistrationBinding = binding
        if let old {
            let predecessor = retiredWorkouts
            retiredWorkouts = Task {
                await predecessor?.value
                await oldResolution?.value
                await old.endSession()
            }
        }
        guard lifetime.registerWorkout(binding: binding, owner: self, activation: activation) else {
            workoutRegistrationBinding = nil
            return nil
        }
        return binding
    }

    var workoutRegistrationContext: WorkoutRegistrationReadyContext? {
        guard let context = workoutRegistrationBinding?.readyContext, context.isActive else { return nil }
        return context
    }

    func resolveWorkoutRegistration(_ binding: WorkoutRegistrationSessionBinding, retrying: Bool = false) async {
        guard workoutRegistrationBinding === binding, binding.isOpen,
              let source = workoutRegistrationSource, workoutRegistrationContext == nil else { return }
        if let task = workoutResolutionTask { await task.value; return }
        guard retrying ? binding.canRetryMe : !binding.canRetryMe else { return }
        workoutResolutionSequence &+= 1
        let sequence = workoutResolutionSequence
        isResolvingWorkoutRegistration = true
        workoutRegistrationError = nil
        let task = Task {
            do {
                if retrying { _ = try await source.retryMe(binding) }
                else { _ = try await source.bind(binding) }
            } catch is CancellationError {
                // The old session can only withdraw its own presentation.
            } catch {
                guard self.workoutRegistrationBinding === binding, binding.isOpen else { return }
                self.workoutRegistrationError = error as? BodyFlowCapabilityError ?? .serviceUnavailable
            }
        }
        workoutResolutionTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard workoutResolutionSequence == sequence else { return }
        workoutResolutionTask = nil
        isResolvingWorkoutRegistration = false
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
            || meReference.hasValue
            || lifetimeEndpoint.hasValue
            || coverEndpoint.hasValue
            || mealRecordBinding?.hasRetainedCapability == true
            || workoutRegistrationBinding?.hasRetainedCapability == true
    }

    /// Lets a caller wait for the `/me` resolution to settle (tests and
    /// diagnostics); the screens simply read the store when they render.
    func awaitPatientTimeZoneResolution() async {
        await timeZoneResolution?.value
        await workoutResolutionTask?.value
    }

    /// Reads `/me` again through the same gate (back in the foreground): a
    /// zone that could not be read offline gets settled, and a change of the
    /// documented zone is followed. A closed session never writes it.
    func refreshPatientTimeZone() async {
        await timeZoneResolution?.value
        guard !ended, !gate.isClosed else { return }
        if workoutRegistrationSource != nil {
            await workoutResolutionTask?.value
            guard !ended, !gate.isClosed else { return }
            if let binding = workoutRegistrationBinding, binding.canRetryMe {
                await resolveWorkoutRegistration(binding, retrying: true)
                return
            }
            await workoutRegistrationBinding?.refreshPatientTimeZone()
            return
        }
        let meReference = meReference
        let gate = gate
        let response = try? await gate.perform {
            guard let me = meReference.current() else {
                throw CancellationError()
            }
            return try await me.me()
        }
        guard let response, !gate.isClosed else { return }
        patientTimeZoneStore.resolve(
            documentedIANAIdentifier: response.data.timezone
        )
    }

    func invalidateSynchronously() {
        mealRecordBinding?.invalidateSynchronously()
        workoutRegistrationBinding?.invalidateSynchronously()
        workoutResolutionTask?.cancel()
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
                timeZoneResolution?.cancel()
                workoutResolutionTask?.cancel()
                await workoutResolutionTask?.value
                workoutResolutionTask = nil
                isResolvingWorkoutRegistration = false
                workoutRegistrationError = nil
                await workoutRegistrationBinding?.endSession()
                workoutRegistrationBinding = nil
                await retiredWorkouts?.value
                retiredWorkouts = nil
                // Invalidation above denies further reservations synchronously.
                let retiredMealRecords = mealRecordRetirementTask
                await mealRecordBinding?.endSession()
                mealRecordBinding = nil
                await retiredMealRecords?.value
                mealRecordRetirementTask = nil
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
                meReference.release()
                lifetimeEndpoint.release()
                coverEndpoint.release()
                patientTimeZoneStore.reset()
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
    private let enablesMealRecordBinding: Bool
    private var transitionGeneration: UInt64 = 0
    private var teardownTask: Task<Void, Never>?

    private(set) var requestedAuthenticatedUserID: String?
    private(set) var renderableOwner: Prompt14SessionOwner?
    private(set) var tearingDownOwner: Prompt14SessionOwner?

    init(dependencies: AppDependencies, enablesMealRecordBinding: Bool = false) {
        self.dependencies = dependencies
        self.enablesMealRecordBinding = enablesMealRecordBinding
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
            dependencies: dependencies,
            enablesMealRecordBinding: enablesMealRecordBinding
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

    func profileWeight() async throws -> ProfileWeightResponse? {
        try await gate.perform {
            guard let capability = reference.current() else {
                throw CancellationError()
            }
            return try await capability.profileWeight()
        }
    }

    func trends(days: Int) async throws -> TrendsResponse {
        try await gate.perform {
            guard let capability = reference.current() else {
                throw CancellationError()
            }
            return try await capability.trends(days: days)
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
