import Foundation

enum ConversationMealCommandControllerError: Error, Equatable, Sendable {
    case unavailable, reconciliationRequired
}
enum ConversationMealCommandEvent: Sendable {
    enum DeferredReason: Sendable { case offline, rateLimited, changed, storage, unavailable }
    case scopeSuspended
    case snapshot(ConversationOutboxViewSnapshot)
    case queued(UUID)
    case saved(ConversationOutboxSavedPublication)
    case state(ConversationMealCommandStateSnapshot, canResubmit: Bool)
    case deferred(commandID: UUID, reason: DeferredReason)
}

/// Actual authenticated command client, deliberately uncomposed into UI/flags.
/// Every POST is explicit. Unknown outcomes only obtain GET reconciliation;
/// a one-use authoritative-read permission can replay the exact original.
actor ConversationMealCommandController {
    typealias Publisher = @MainActor @Sendable (ConversationMealCommandEvent) -> Void
    private struct ReplayPermission: Sendable {
        let ticket: ConversationOutboxTicket
        let server: ConversationOutboxServerObservation
    }
    private let repository: MobileConversationCommandRepository
    private let lifecycle: any SessionLifecycleProviding
    private let outbox: ConversationOutboxSession
    private let authority: ConversationOutboxObservationAuthority
    private let enqueueAuthority: ConversationOutboxObservationAuthority
    private var lease: SessionLease?
    private var server: ConversationOutboxServerObservation?
    private var enqueueServer: ConversationOutboxServerObservation?
    private var permissions: [UUID: ReplayPermission] = [:]
    private var workID: UUID?
    private var networkCancellations: [UUID: @Sendable () -> Void] = [:]

    private init(repository: MobileConversationCommandRepository, lifecycle: any SessionLifecycleProviding,
                 outbox: ConversationOutboxSession, authority: ConversationOutboxObservationAuthority, enqueueAuthority: ConversationOutboxObservationAuthority, lease: SessionLease) {
        self.repository = repository; self.lifecycle = lifecycle; self.outbox = outbox
        self.authority = authority; self.enqueueAuthority = enqueueAuthority; self.lease = lease
    }
    static func open(transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
                     store: EncryptedConversationOutboxStore = .device, keyVault: ConversationOutboxKeyVault = .init()) async throws -> Self {
        guard transport.configuredOrigin != nil else { throw MobileAPITransportError.unavailableConfiguration }
        let lease = try await lifecycle.leaseForRequest()
        try await lifecycle.validate(lease); try Task.checkCancellation()
        let repository = try await MobileConversationCommandRepository.scoped(transport: transport, lease: lease)
        let outbox = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: store, keyVault: keyVault, expectedLease: lease)
        let authority = ConversationOutboxObservationAuthority(), enqueueAuthority = ConversationOutboxObservationAuthority()
        let controller = Self(repository: repository, lifecycle: lifecycle, outbox: outbox, authority: authority, enqueueAuthority: enqueueAuthority, lease: lease)
        do {
            let id = try await lifecycle.beginPatientWork(lease: lease) { [weak controller] in
                authority.close(); enqueueAuthority.close()
                Task { await controller?.close() }
            }
            try await controller.installWork(id)
            _ = try await controller.refresh(publish: nil)
            _ = try await controller.requireLease()
            return controller
        } catch { await controller.close(); throw error }
    }
    private func installWork(_ id: UUID) async throws {
        do { try authority.checkOpen(); try enqueueAuthority.checkOpen(); workID = id }
        catch { await lifecycle.finishPatientWork(id); throw error }
    }

    /// Active-session offline enqueue retains the last verified owner/epoch.
    /// Cold open without a verified session cannot invent that capability.
    func enqueue(source: ConversationMealCommand.Source, mealType: ConversationMealCommand.MealType? = nil,
                 publish: @escaping Publisher) async throws -> UUID {
        let lease = try await requireLease()
        guard let captured = enqueueServer else { throw ConversationMealCommandControllerError.unavailable }
        let id = try await outbox.enqueue(source: source, mealType: mealType, server: captured)
        if server != nil { try await publishSnapshot(publish) }
        else {
            // A failed/pending refresh grants no raw publication or transport.
            // Keep the new intent encrypted under its last verified binding.
            try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                try Task.checkCancellation(); try captured.withCurrentAuthority { publish(.queued(id)) }
            }
        }
        return id
    }
    func refreshSession(_ publish: @escaping Publisher) async throws { _ = try await refresh(publish: publish) }
    func publishSnapshot(_ publish: @escaping Publisher) async throws {
        _ = try await requireLease()
        guard let server else { throw ConversationMealCommandControllerError.unavailable }
        try await outbox.publishSnapshot(server: server) { publish(.snapshot($0)) }
    }
    func send(commandID: UUID, publish: @escaping Publisher) async throws {
        let server = try await refresh(publish: publish)
        let ticket = try await outbox.prepareDispatch(commandID: commandID, server: server)
        try await transmit(ticket: ticket, server: server, publish: publish)
    }
    func reconcile(commandID: UUID, publish: @escaping Publisher) async throws {
        let server = try await refresh(publish: publish)
        let ticket = try await outbox.reconciliationTicket(commandID: commandID)
        try matches(ticket, server: server)
        let repository = repository
        do {
            let reply = try await network { try await repository.read(ticket) }
            try await receive(reply, ticket: ticket, server: server, fromRead: true, publish: publish)
        } catch { try await handleFailure(error, ticket: ticket, server: server, publish: publish); throw error }
    }
    func resubmit(commandID: UUID, publish: @escaping Publisher) async throws {
        _ = try await requireLease()
        guard let permission = permissions.removeValue(forKey: commandID) else { throw ConversationMealCommandControllerError.reconciliationRequired }
        try matches(permission.ticket, server: permission.server)
        try await outbox.authorizeResubmission(ticket: permission.ticket, server: permission.server)
        try await transmit(ticket: permission.ticket, server: permission.server, publish: publish)
    }
    func discardUnsent(commandID: UUID, publish: @escaping Publisher) async throws {
        _ = try await requireLease()
        try await outbox.discardUnsent(commandID: commandID)
        permissions.removeValue(forKey: commandID)
        try await publishSnapshot(publish)
    }
    func holdForLocalReset(commandID: UUID, publish: @escaping Publisher) async throws {
        _ = try await requireLease()
        let ticket = try await outbox.decisionTicket(commandID: commandID)
        try await outbox.holdForLocalReset(ticket: ticket)
        permissions.removeValue(forKey: commandID)
        try await publishSnapshot(publish)
    }
    func close() async {
        authority.close(); enqueueAuthority.close(); server = nil; enqueueServer = nil; permissions.removeAll(); lease = nil
        let cancellations = networkCancellations.values; networkCancellations.removeAll()
        for cancel in cancellations { cancel() }
        await outbox.invalidate()
        if let id = workID { workID = nil; await lifecycle.finishPatientWork(id) }
    }

    private func refresh(publish: Publisher?) async throws -> ConversationOutboxServerObservation {
        let lease = try await requireLease(), refreshID = try authority.beginRefresh()
        server = nil; permissions.removeAll()
        if let publish {
            let authority = authority
            try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                try authority.withPendingRefresh(refreshID) { try Task.checkCancellation(); publish(.scopeSuspended) }
            }
        }
        let repository = repository
        let value = try await network { try await repository.session() }
        try Task.checkCancellation()
        guard value.authUserID == UUID(uuidString: lease.userID) else { throw MobileAPITransportError.invalidResponse }
        let authority = authority, enqueueAuthority = enqueueAuthority
        let pair = try await lifecycle.performPatientStateOperation(lease: lease) {
            let current = try authority.accept(refreshID: refreshID, authUserID: value.authUserID, ownerID: value.ownerID,
                                               localSessionGeneration: lease.generation, epoch: value.epoch)
            let capturedID = try enqueueAuthority.beginRefresh()
            let captured = try enqueueAuthority.accept(refreshID: capturedID, authUserID: value.authUserID, ownerID: value.ownerID,
                                                       localSessionGeneration: lease.generation, epoch: value.epoch, enqueueOnly: true)
            return (current: current, captured: captured)
        }
        // Enqueue may retain this verified original binding during a later
        // offline refresh; successful new mappings revoke it in the same gate.
        try pair.captured.withCurrentAuthority {}
        enqueueServer = pair.captured
        _ = try await requireLease()
        try pair.current.withCurrentAuthority {}
        server = pair.current
        if let publish { try await outbox.publishSnapshot(server: pair.current) { publish(.snapshot($0)) } }
        return pair.current
    }
    private func transmit(ticket: ConversationOutboxTicket, server: ConversationOutboxServerObservation, publish: @escaping Publisher) async throws {
        try matches(ticket, server: server)
        let repository = repository
        do {
            let reply = try await network { try await repository.submit(ticket) }
            try await receive(reply, ticket: ticket, server: server, fromRead: false, publish: publish)
        } catch { try await handleFailure(error, ticket: ticket, server: server, publish: publish); throw error }
    }
    private func receive(_ reply: ConversationMealCommandReply, ticket: ConversationOutboxTicket,
                         server: ConversationOutboxServerObservation, fromRead: Bool, publish: @escaping Publisher) async throws {
        _ = try await requireLease(); try matches(ticket, server: server)
        switch reply {
        case let .saved(value):
            permissions.removeValue(forKey: ticket.commandID)
            try await outbox.acknowledgeSaved(ticket: ticket, result: value, server: server) { publish(.saved($0)) }
        case let .state(value):
            guard value.matches(ticket, server: server) else { throw MobileAPITransportError.invalidResponse }
            if !fromRead, value.status == .absent { throw MobileAPITransportError.invalidResponse }
            permissions.removeValue(forKey: ticket.commandID)
            try await outbox.markWaiting(ticket: ticket, hold: value.status == .notRecorded ? .notRecorded : .unknownOutcome, server: server)
            var allowed = false
            if fromRead, value.status != .notRecorded {
                do {
                    try await outbox.authorizeResubmission(ticket: ticket, server: server)
                    try server.withCurrentAuthority {}
                    permissions[ticket.commandID] = .init(ticket: ticket, server: server)
                    allowed = true
                } catch ConversationOutboxError.reconciliationRequired { /* Permanent local hold remains authoritative for this queue. */ }
            }
            try await deliver(.state(value, canResubmit: allowed), server: server, publish: publish)
        }
    }
    private func handleFailure(_ error: any Error, ticket: ConversationOutboxTicket,
                               server: ConversationOutboxServerObservation, publish: @escaping Publisher) async throws {
        if error is CancellationError { throw error }
        _ = try await requireLease(); try matches(ticket, server: server)
        // A superseded callback must not consume a newer GET's permission.
        permissions.removeValue(forKey: ticket.commandID)
        let changed: Bool
        if case let MobileAPITransportError.conflict(code, _) = error {
            changed = ["conversation_command_changed", "conversation_patient_changed"].contains(code)
        } else { changed = false }
        var reason: ConversationMealCommandEvent.DeferredReason = .unavailable
        if changed { reason = .changed }
        else if case MobileAPITransportError.rateLimited = error { reason = .rateLimited }
        else if case MobileAPITransportError.network = error { reason = .offline }
        else if case MobileAPITransportError.timeout = error { reason = .offline }
        do { try await outbox.markWaiting(ticket: ticket, hold: changed ? .serverChanged : .unknownOutcome, server: server) }
        catch ConversationOutboxError.storageUnavailable { reason = .storage }
        catch ConversationOutboxError.keyUnavailable { reason = .storage }
        catch ConversationOutboxError.integrityFailure { reason = .storage }
        catch ConversationOutboxError.commandNotFound {
            // Another valid local ACK may already have removed this exact work.
            // Never recreate it or publish a second factual success.
            return
        }
        try await deliver(.deferred(commandID: ticket.commandID, reason: reason), server: server, publish: publish)
    }
    private func matches(_ ticket: ConversationOutboxTicket, server: ConversationOutboxServerObservation) throws {
        try server.withCurrentAuthority {}
        guard ticket.originalPatientOwnerID == server.ownerID, ticket.originalServerEpoch == server.epoch,
              ticket.localSessionGeneration == server.localSessionGeneration else { throw ConversationOutboxError.invalidServerObservation }
    }
    private func deliver(_ event: ConversationMealCommandEvent, server: ConversationOutboxServerObservation, publish: @escaping Publisher) async throws {
        let lease = try await requireLease()
        try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
            try Task.checkCancellation(); try server.withCurrentAuthority { publish(event) }
        }
    }
    private func requireLease() async throws -> SessionLease {
        try Task.checkCancellation(); try authority.checkOpen()
        guard let lease else { throw ConversationOutboxError.sessionClosed }
        try await lifecycle.validate(lease); try Task.checkCancellation(); try authority.checkOpen()
        return lease
    }
    private func network<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        _ = try await requireLease()
        let id = UUID(), task = Task { try await operation() }
        networkCancellations[id] = { task.cancel() }
        defer { networkCancellations.removeValue(forKey: id) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
