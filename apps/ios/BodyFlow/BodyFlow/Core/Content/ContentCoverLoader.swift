import Foundation

protocol ContentCoverLoading: Sendable {
    func image(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage

    func remove(publicationID: String, version: Int) async
    func endSession() async
}

actor ContentCoverLoader: ContentCoverLoading {
#if DEBUG
    private struct WaiterCountExpectation {
        let key: ContentCoverCacheKey
        let minimumCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct KeyRetirementExpectation {
        let key: ContentCoverCacheKey
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct VersionInvalidationBarrierExpectation {
        let key: ContentVersionKey
        let continuation: CheckedContinuation<Void, Never>
    }
#endif

    private enum LoaderFailure: Error {
        case callerCapabilityExpired
    }

    private struct StableLoadBoundary: Sendable {
        let versionEpoch: UInt64
        let didWait: Bool
    }

    private struct BoundaryOperation: Sendable {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct ContentVersionKey: Hashable, Sendable {
        let publicationID: String
        let version: Int
    }

    private struct LoadedCover: Sendable {
        let image: ContentCoverImage
        let publicationDeadline: Date
        let cacheExpiry: Date?
    }

    private struct Flight: Sendable {
        let id: UUID
        let generation: UInt64
        let versionEpoch: UInt64
        let task: Task<LoadedCover, any Error>
        var publicationTask: Task<Void, any Error>?
        var waiters: Set<UUID>
    }

    private let stream: any ContentCoverByteStreaming
    private let origin: ContentCoverTrustedOrigin?
    private let decoder: ContentCoverDecoder
    private let cache: any SessionCoverCaching
    private let timeProvider: any TimeProviding
    private var flights: [ContentCoverCacheKey: Flight] = [:]
    private var versionEpochs: [ContentVersionKey: UInt64] = [:]
    private var versionInvalidations: [ContentVersionKey: BoundaryOperation] = [:]
    private var keyRetirements: [ContentCoverCacheKey: BoundaryOperation] = [:]
    private var generation: UInt64 = 0
    private var ended = false
    private var endSessionTask: Task<Void, Never>?
#if DEBUG
    private var waiterCountExpectations: [WaiterCountExpectation] = []
    private var keyRetirementExpectations: [KeyRetirementExpectation] = []
    private var observedVersionInvalidationBarriers: Set<ContentVersionKey> = []
    private var versionInvalidationBarrierExpectations: [VersionInvalidationBarrierExpectation] = []
#endif

    init(
        stream: any ContentCoverByteStreaming,
        origin: ContentCoverTrustedOrigin?,
        decoder: ContentCoverDecoder,
        cache: any SessionCoverCaching,
        timeProvider: any TimeProviding
    ) {
        self.stream = stream
        self.origin = origin
        self.decoder = decoder
        self.cache = cache
        self.timeProvider = timeProvider
    }

    func image(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage {
        guard !ended, let origin else {
            throw BodyFlowCapabilityError.operationUnavailable
        }
        try Task.checkCancellation()

        let path = try ContentCoverPath(validating: cover.url)
        let key = ContentCoverCacheKey(
            publicationID: publicationID,
            version: version,
            target: target
        )
        let versionKey = ContentVersionKey(
            publicationID: publicationID,
            version: version
        )
        let requestedGeneration = generation
        let initialBoundary = try await awaitStableLoadBoundary(
            for: key,
            versionKey: versionKey,
            generation: requestedGeneration
        )
        if cover.expiresAt.value <= timeProvider.now {
            await invalidateVersion(versionKey)
            try Task.checkCancellation()
            throw BodyFlowCapabilityError.contentCoverNotFound
        }
        let requestedVersionEpoch = initialBoundary.versionEpoch
        let cached: ContentCoverImage?
        while true {
            let candidate = await cache.image(for: key, now: timeProvider.now)
            let boundary = try await awaitStableLoadBoundary(
                for: key,
                versionKey: versionKey,
                generation: requestedGeneration
            )
            guard boundary.versionEpoch == requestedVersionEpoch else {
                throw CancellationError()
            }
            if boundary.didWait {
                continue
            }
            cached = candidate
            break
        }
        try Task.checkCancellation()
        guard isCurrent(
            generation: requestedGeneration,
            versionKey: versionKey,
            versionEpoch: requestedVersionEpoch
        ) else {
            throw CancellationError()
        }
        if cover.expiresAt.value <= timeProvider.now {
            await invalidateVersion(versionKey)
            try Task.checkCancellation()
            throw BodyFlowCapabilityError.contentCoverNotFound
        }
        if let cached {
            return cached
        }

        let request = try ContentCoverRequestResolver(trustedOrigin: origin).resolve(path)
        let waiterID = UUID()
        let flight = registerFlight(
            for: key,
            versionEpoch: requestedVersionEpoch,
            waiterID: waiterID,
            request: request,
            target: target,
            capabilityExpiry: cover.expiresAt.value
        )

        return try await withTaskCancellationHandler(operation: {
            do {
                let loaded = try await flight.task.value
                try Task.checkCancellation()
                return try await publish(
                    loaded,
                    for: key,
                    versionKey: versionKey,
                    flightID: flight.id,
                    waiterID: waiterID,
                    generation: flight.generation,
                    versionEpoch: flight.versionEpoch,
                    callerCapabilityExpiry: cover.expiresAt.value
                )
            } catch LoaderFailure.callerCapabilityExpired {
                finishWaiter(
                    for: key,
                    flightID: flight.id,
                    waiterID: waiterID
                )
                throw BodyFlowCapabilityError.contentCoverNotFound
            } catch {
                if Task.isCancelled || error is CancellationError {
                    await cancelWaiter(
                        for: key,
                        flightID: flight.id,
                        waiterID: waiterID
                    )
                    throw CancellationError()
                }
                await finishFailure(
                    error,
                    for: key,
                    versionKey: versionKey,
                    flightID: flight.id,
                    waiterID: waiterID
                )
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw error
            }
        }, onCancel: {
            Task {
                await self.cancelWaiter(
                    for: key,
                    flightID: flight.id,
                    waiterID: waiterID
                )
            }
        })
    }

    func remove(publicationID: String, version: Int) async {
        await invalidateVersion(
            ContentVersionKey(publicationID: publicationID, version: version)
        )
    }

    func endSession() async {
        if let endSessionTask {
            await endSessionTask.value
            return
        }

        ended = true
        generation &+= 1
        let activeFlights = Array(flights.values)
        let activeInvalidations = versionInvalidations.values.map(\.task)
        let activeKeyRetirements = keyRetirements.values.map(\.task)
        flights.removeAll(keepingCapacity: false)
        versionEpochs.removeAll(keepingCapacity: false)
        versionInvalidations.removeAll(keepingCapacity: false)
        keyRetirements.removeAll(keepingCapacity: false)
        for flight in activeFlights {
            flight.task.cancel()
            flight.publicationTask?.cancel()
        }

        let stream = stream
        let cache = cache
        let loadTasks = activeFlights.map(\.task)
        let publicationTasks = activeFlights.compactMap(\.publicationTask)
        let teardown = Task.detached {
            await stream.cancelAll()
            for task in loadTasks {
                _ = await task.result
            }
            for task in publicationTasks {
                _ = await task.result
            }
            for invalidation in activeInvalidations {
                await invalidation.value
            }
            for retirement in activeKeyRetirements {
                await retirement.value
            }
            await cache.removeAll()
        }
        endSessionTask = teardown
        await teardown.value
    }

#if DEBUG
    func waitUntilWaiterCount(
        _ minimumCount: Int,
        publicationID: String,
        version: Int,
        target: ContentCoverTargetSize
    ) async {
        let key = ContentCoverCacheKey(
            publicationID: publicationID,
            version: version,
            target: target
        )
        guard (flights[key]?.waiters.count ?? 0) < minimumCount else {
            return
        }
        await withCheckedContinuation { continuation in
            waiterCountExpectations.append(
                WaiterCountExpectation(
                    key: key,
                    minimumCount: minimumCount,
                    continuation: continuation
                )
            )
        }
    }


    func waitUntilKeyRetirementRegistered(
        publicationID: String,
        version: Int,
        target: ContentCoverTargetSize
    ) async {
        let key = ContentCoverCacheKey(
            publicationID: publicationID,
            version: version,
            target: target
        )
        guard keyRetirements[key] == nil else { return }
        await withCheckedContinuation { continuation in
            keyRetirementExpectations.append(
                KeyRetirementExpectation(key: key, continuation: continuation)
            )
        }
    }

    func waitUntilVersionInvalidationBarrierObserved(
        publicationID: String,
        version: Int
    ) async {
        let key = ContentVersionKey(
            publicationID: publicationID,
            version: version
        )
        guard !observedVersionInvalidationBarriers.contains(key) else { return }
        await withCheckedContinuation { continuation in
            versionInvalidationBarrierExpectations.append(
                VersionInvalidationBarrierExpectation(
                    key: key,
                    continuation: continuation
                )
            )
        }
    }
#endif

    private func registerFlight(
        for key: ContentCoverCacheKey,
        versionEpoch: UInt64,
        waiterID: UUID,
        request: ContentCoverTransportRequest,
        target: ContentCoverTargetSize,
        capabilityExpiry: Date
    ) -> Flight {
        if var existing = flights[key],
           existing.generation == generation,
           existing.versionEpoch == versionEpoch {
            existing.waiters.insert(waiterID)
            flights[key] = existing
            resumeWaiterCountExpectations(for: key)
            return existing
        }

        if let stale = flights.removeValue(forKey: key) {
            stale.task.cancel()
            stale.publicationTask?.cancel()
        }

        let flightID = UUID()
        let flightGeneration = generation
        let stream = stream
        let decoder = decoder
        let timeProvider = timeProvider
        let task = Task.detached {
            try Task.checkCancellation()
            let response = try await stream.stream(request)
            let cancellation = ContentCoverResponseCancellation(
                operation: response.cancel
            )
            let guardedResponse = response.replacingCancellation {
                await cancellation.cancel()
            }
            let receiptTime = timeProvider.now

            do {
                try Task.checkCancellation()
                let image = try await decoder.decode(guardedResponse, target: target)
                try Task.checkCancellation()

                let publicationDeadline: Date
                let cacheExpiry: Date?
                if let maxAge = response.cacheMaxAgeSeconds {
                    let headerExpiry = receiptTime.addingTimeInterval(TimeInterval(maxAge))
                    publicationDeadline = min(capabilityExpiry, headerExpiry)
                    cacheExpiry = maxAge > 0 ? publicationDeadline : nil
                } else {
                    publicationDeadline = capabilityExpiry
                    cacheExpiry = nil
                }
                if publicationDeadline <= timeProvider.now {
                    throw BodyFlowCapabilityError.contentCoverNotFound
                }
                return LoadedCover(
                    image: image,
                    publicationDeadline: publicationDeadline,
                    cacheExpiry: cacheExpiry
                )
            } catch {
                await cancellation.cancel()
                throw error
            }
        }
        let flight = Flight(
            id: flightID,
            generation: flightGeneration,
            versionEpoch: versionEpoch,
            task: task,
            publicationTask: nil,
            waiters: [waiterID]
        )
        flights[key] = flight
        resumeWaiterCountExpectations(for: key)
        return flight
    }

    private func publish(
        _ loaded: LoadedCover,
        for key: ContentCoverCacheKey,
        versionKey: ContentVersionKey,
        flightID: UUID,
        waiterID: UUID,
        generation expectedGeneration: UInt64,
        versionEpoch expectedVersionEpoch: UInt64,
        callerCapabilityExpiry: Date
    ) async throws -> ContentCoverImage {
        try Task.checkCancellation()
        guard isCurrentFlight(
            for: key,
            flightID: flightID,
            waiterID: waiterID,
            versionKey: versionKey,
            generation: expectedGeneration,
            versionEpoch: expectedVersionEpoch
        ) else {
            throw CancellationError()
        }
        guard callerCapabilityExpiry > timeProvider.now else {
            throw LoaderFailure.callerCapabilityExpired
        }
        if loaded.publicationDeadline <= timeProvider.now {
            throw BodyFlowCapabilityError.contentCoverNotFound
        }

        if let publicationTask = publicationTask(
            for: key,
            flightID: flightID,
            loaded: loaded
        ) {
            do {
                try await publicationTask.value
            } catch {
                if !isCurrentFlight(
                    for: key,
                    flightID: flightID,
                    waiterID: waiterID,
                    versionKey: versionKey,
                    generation: expectedGeneration,
                    versionEpoch: expectedVersionEpoch
                ) {
                    await cache.remove(key, ifOwnedBy: flightID)
                }
                throw error
            }
        }

        try Task.checkCancellation()
        guard isCurrentFlight(
            for: key,
            flightID: flightID,
            waiterID: waiterID,
            versionKey: versionKey,
            generation: expectedGeneration,
            versionEpoch: expectedVersionEpoch
        ) else {
            await cache.remove(key, ifOwnedBy: flightID)
            throw CancellationError()
        }
        guard callerCapabilityExpiry > timeProvider.now else {
            throw LoaderFailure.callerCapabilityExpired
        }
        if loaded.publicationDeadline <= timeProvider.now {
            await cache.remove(key, ifOwnedBy: flightID)
            throw BodyFlowCapabilityError.contentCoverNotFound
        }

        finishWaiter(for: key, flightID: flightID, waiterID: waiterID)
        return loaded.image
    }

    private func publicationTask(
        for key: ContentCoverCacheKey,
        flightID: UUID,
        loaded: LoadedCover
    ) -> Task<Void, any Error>? {
        guard let expiresAt = loaded.cacheExpiry,
              var flight = flights[key],
              flight.id == flightID
        else {
            return nil
        }
        if let existing = flight.publicationTask {
            return existing
        }

        let cache = cache
        let task = Task.detached {
            try Task.checkCancellation()
            try await cache.insert(
                loaded.image,
                for: key,
                expiresAt: expiresAt,
                ownership: flightID
            )
            try Task.checkCancellation()
        }
        flight.publicationTask = task
        flights[key] = flight
        return task
    }

    private func finishFailure(
        _ error: any Error,
        for key: ContentCoverCacheKey,
        versionKey: ContentVersionKey,
        flightID: UUID,
        waiterID: UUID
    ) async {
        if error as? BodyFlowCapabilityError == .contentCoverNotFound,
           flights[key]?.id == flightID {
            await invalidateVersion(versionKey)
            return
        }
        finishWaiter(for: key, flightID: flightID, waiterID: waiterID)
    }

    private func finishWaiter(
        for key: ContentCoverCacheKey,
        flightID: UUID,
        waiterID: UUID
    ) {
        guard var flight = flights[key], flight.id == flightID else {
            return
        }
        flight.waiters.remove(waiterID)
        if flight.waiters.isEmpty {
            flights.removeValue(forKey: key)
        } else {
            flights[key] = flight
        }
    }

    private func cancelWaiter(
        for key: ContentCoverCacheKey,
        flightID: UUID,
        waiterID: UUID
    ) async {
        if let retirement = keyRetirements[key] {
            await retirement.task.value
            return
        }
        guard var flight = flights[key], flight.id == flightID else {
            return
        }
        flight.waiters.remove(waiterID)
        if flight.waiters.isEmpty {
            flights.removeValue(forKey: key)
            flight.task.cancel()
            flight.publicationTask?.cancel()
            let cache = cache
            let retirement = Task.detached {
                _ = await flight.task.result
                if let publicationTask = flight.publicationTask {
                    _ = await publicationTask.result
                }
                await cache.remove(key, ifOwnedBy: flightID)
            }
            let operation = BoundaryOperation(id: UUID(), task: retirement)
            keyRetirements[key] = operation
            resumeKeyRetirementExpectations(for: key)
            await retirement.value
            if keyRetirements[key]?.id == operation.id {
                keyRetirements.removeValue(forKey: key)
            }
        } else {
            flights[key] = flight
        }
    }

    private func invalidateVersion(_ versionKey: ContentVersionKey) async {
        if let invalidation = versionInvalidations[versionKey] {
            await invalidation.task.value
            return
        }

        versionEpochs[versionKey, default: 0] &+= 1
        let matchingKeys = flights.keys.filter {
            $0.publicationID == versionKey.publicationID
                && $0.version == versionKey.version
        }
        var retiredFlights: [(key: ContentCoverCacheKey, flight: Flight)] = []
        for key in matchingKeys {
            guard let flight = flights.removeValue(forKey: key) else { continue }
            flight.task.cancel()
            flight.publicationTask?.cancel()
            retiredFlights.append((key, flight))
        }
        let matchingKeyRetirements = keyRetirements.filter {
            $0.key.publicationID == versionKey.publicationID
                && $0.key.version == versionKey.version
        }.map(\.value.task)
        let cache = cache
        let invalidation = Task.detached {
            await cache.remove(
                publicationID: versionKey.publicationID,
                version: versionKey.version
            )
            for retired in retiredFlights {
                _ = await retired.flight.task.result
                if let publicationTask = retired.flight.publicationTask {
                    _ = await publicationTask.result
                }
                await cache.remove(retired.key, ifOwnedBy: retired.flight.id)
            }
            for retirement in matchingKeyRetirements {
                await retirement.value
            }
        }
        let operation = BoundaryOperation(id: UUID(), task: invalidation)
        versionInvalidations[versionKey] = operation
        await invalidation.value
        if versionInvalidations[versionKey]?.id == operation.id {
            versionInvalidations.removeValue(forKey: versionKey)
        }
    }

    private func awaitStableLoadBoundary(
        for key: ContentCoverCacheKey,
        versionKey: ContentVersionKey,
        generation expectedGeneration: UInt64
    ) async throws -> StableLoadBoundary {
        var didWait = false
        var completedInvalidationIDs: Set<UUID> = []
        var completedRetirementIDs: Set<UUID> = []
        while true {
            if let invalidation = versionInvalidations[versionKey],
               !completedInvalidationIDs.contains(invalidation.id) {
                didWait = true
                recordVersionInvalidationBarrierObservation(for: versionKey)
                await invalidation.task.value
                completedInvalidationIDs.insert(invalidation.id)
                try Task.checkCancellation()
                guard !ended, generation == expectedGeneration else {
                    throw CancellationError()
                }
                continue
            }
            if let retirement = keyRetirements[key],
               !completedRetirementIDs.contains(retirement.id) {
                didWait = true
                await retirement.task.value
                completedRetirementIDs.insert(retirement.id)
                try Task.checkCancellation()
                guard !ended, generation == expectedGeneration else {
                    throw CancellationError()
                }
                continue
            }
            try Task.checkCancellation()
            guard !ended, generation == expectedGeneration else {
                throw CancellationError()
            }
            return StableLoadBoundary(
                versionEpoch: versionEpochs[versionKey, default: 0],
                didWait: didWait
            )
        }
    }

    private func isCurrent(
        generation expectedGeneration: UInt64,
        versionKey: ContentVersionKey,
        versionEpoch expectedVersionEpoch: UInt64
    ) -> Bool {
        !ended
            && generation == expectedGeneration
            && versionEpochs[versionKey, default: 0] == expectedVersionEpoch
    }

    private func isCurrentFlight(
        for key: ContentCoverCacheKey,
        flightID: UUID,
        waiterID: UUID,
        versionKey: ContentVersionKey,
        generation expectedGeneration: UInt64,
        versionEpoch expectedVersionEpoch: UInt64
    ) -> Bool {
        guard isCurrent(
            generation: expectedGeneration,
            versionKey: versionKey,
            versionEpoch: expectedVersionEpoch
        ),
              let flight = flights[key],
              flight.id == flightID,
              flight.waiters.contains(waiterID)
        else {
            return false
        }
        return true
    }

    private func resumeWaiterCountExpectations(for key: ContentCoverCacheKey) {
#if DEBUG
        let waiterCount = flights[key]?.waiters.count ?? 0
        let ready = waiterCountExpectations.filter {
            $0.key == key && waiterCount >= $0.minimumCount
        }
        waiterCountExpectations.removeAll {
            $0.key == key && waiterCount >= $0.minimumCount
        }
        for expectation in ready {
            expectation.continuation.resume()
        }
#endif
    }

    private func resumeKeyRetirementExpectations(for key: ContentCoverCacheKey) {
#if DEBUG
        let ready = keyRetirementExpectations.filter { $0.key == key }
        keyRetirementExpectations.removeAll { $0.key == key }
        for expectation in ready {
            expectation.continuation.resume()
        }
#endif
    }

    private func recordVersionInvalidationBarrierObservation(
        for key: ContentVersionKey
    ) {
#if DEBUG
        observedVersionInvalidationBarriers.insert(key)
        let ready = versionInvalidationBarrierExpectations.filter { $0.key == key }
        versionInvalidationBarrierExpectations.removeAll { $0.key == key }
        for expectation in ready {
            expectation.continuation.resume()
        }
#endif
    }
}

private actor ContentCoverResponseCancellation {
    private let operation: @Sendable () async -> Void
    private var didCancel = false

    init(operation: @escaping @Sendable () async -> Void) {
        self.operation = operation
    }

    func cancel() async {
        guard !didCancel else { return }
        didCancel = true
        await operation()
    }
}

private extension ContentCoverByteStream {
    func replacingCancellation(
        with cancellation: @escaping @Sendable () async -> Void
    ) -> ContentCoverByteStream {
        ContentCoverByteStream(
            statusCode: statusCode,
            declaredLength: declaredLength,
            mimeType: mimeType,
            cacheMaxAgeSeconds: cacheMaxAgeSeconds,
            redirectLocation: redirectLocation,
            chunks: chunks,
            cancel: cancellation
        )
    }
}
