import Foundation
import Testing

@testable import BodyFlow

@Suite("Workout Registration Model")
@MainActor
struct WorkoutRegistrationModelTests {
    @Test("the form and proposal attempt use the fixed performed time")
    func fixedTimeDefault() async throws {
        let harness = Self.makeHarness()

        #expect(harness.model.initialPerformedAt == Self.fixedDate)
        await harness.model.submit(Self.request)

        let attempt = try #require(await harness.service.proposeAttempts.first)
        #expect(attempt.createdAt == Self.fixedDate)
        #expect(attempt.payload == .workout(Self.request))
    }

    @Test("a workout must receive a pending proposal before confirmation")
    func proposalPrecedesConfirmation() async {
        let harness = Self.makeHarness()

        await harness.model.confirm()
        #expect(await harness.service.confirmAttempts.isEmpty)

        await harness.model.submit(Self.request)
        #expect(await harness.service.calls == [.propose])
        #expect(harness.model.phase == .proposal)
        #expect(harness.model.currentProposal == Self.pendingResponse.data)
    }

    @Test("confirmation ignores a snapshot that is no longer pending")
    func confirmationRequiresPendingSnapshot() async {
        let harness = Self.makeHarness(
            propose: [.success(Self.nonPendingResponse)],
            confirm: [.success(Self.confirmedResponse)]
        )

        await harness.model.submit(Self.request)
        await harness.model.confirm()

        #expect(await harness.service.confirmAttempts.isEmpty)
        #expect(harness.model.currentProposal == Self.nonPendingResponse.data)
    }

    @Test("cancellation ignores a snapshot that is no longer pending")
    func cancellationRequiresPendingSnapshot() async {
        let harness = Self.makeHarness(
            propose: [.success(Self.nonPendingResponse)],
            cancel: [.success(Self.cancelledResponse)]
        )

        await harness.model.submit(Self.request)
        await harness.model.cancel()

        #expect(await harness.service.calls == [.propose])
        #expect(harness.model.currentProposal == Self.nonPendingResponse.data)
    }

    @Test("estimated calories are preserved literally from the proposal response")
    func proposalCaloriesAreLiteral() async {
        let harness = Self.makeHarness()

        await harness.model.submit(Self.request)

        guard case let .workout(proposal) = harness.model.currentProposal?.proposal else {
            Issue.record("Expected the provider workout proposal")
            return
        }
        #expect(proposal.estimatedKcal == 333)
        #expect(proposal.durationMin == 47)
    }

    @Test("editing replaces the complete workout proposal response")
    func editReplacesWholeResponse() async throws {
        let harness = Self.makeHarness(edit: [.success(Self.editedResponse)])
        await harness.model.submit(Self.request)

        await harness.model.saveEdit(Self.editedRequest)

        let attempt = try #require(await harness.service.editAttempts.first)
        #expect(attempt.payload == RegistrationEditCommand(
            registrationID: Self.pendingResponse.data.id,
            proposal: .workout(Self.editedRequest)
        ))
        #expect(harness.model.currentProposal == Self.editedResponse.data)
    }

    @Test("the editor keeps the exact submitted workout draft, not a sanitized response")
    func editingUsesAuthoredPendingRequest() async {
        let authored = WorkoutProposalRequest(
            workoutType: "corrida intervalada",
            durationMin: 47,
            intensity: .high,
            performedAt: APITimestamp(value: Self.fixedDate.addingTimeInterval(321))
        )
        let edited = WorkoutProposalRequest(
            workoutType: "caminhada inclinada",
            durationMin: 61,
            intensity: .light,
            performedAt: APITimestamp(value: Self.fixedDate.addingTimeInterval(654))
        )
        let harness = Self.makeHarness(
            propose: [.success(Self.sanitizedResponse)],
            edit: [.success(Self.sanitizedEditedResponse)]
        )

        await harness.model.submit(authored)
        #expect(harness.model.pendingDraft == authored)

        await harness.model.saveEdit(edited)
        #expect(harness.model.pendingDraft == edited)
    }

    @Test("a failed workout proposal retains its exact typed attempt for retry")
    func failedProposalRetainsAttempt() async throws {
        let harness = Self.makeHarness(propose: [
            .failure(.serviceUnavailable), .success(Self.pendingResponse),
        ])

        await harness.model.submit(Self.request)

        let retained: MutationAttempt<RegistrationProposalRequest>
        guard case let .failed(.propose(attempt), error) = harness.model.mutationState else {
            Issue.record("Expected the typed proposal attempt to be retained")
            return
        }
        retained = attempt
        #expect(error == .serviceUnavailable)
        #expect(harness.model.accessibilityFocusTarget == .operationSummary)

        await harness.model.retry()
        #expect(await harness.service.proposeAttempts == [retained, retained])
        #expect(harness.model.currentProposal == Self.pendingResponse.data)
    }

    @Test("proposal edit and cancellation invalidate Today only")
    func pendingChangesInvalidateTodayOnly() async {
        let harness = Self.makeHarness(
            edit: [.success(Self.editedResponse)],
            cancel: [.success(Self.cancelledResponse)]
        )

        await harness.model.submit(Self.request)
        await harness.model.saveEdit(Self.editedRequest)
        await harness.model.cancel()

        #expect(harness.center.revision(for: .today) == 3)
        #expect(harness.center.revision(for: .history) == 0)
        #expect(harness.model.phase == .cancelled)
    }

    @Test("confirmation invalidates Today and History and leaves a read-only receipt")
    func confirmationInvalidatesTodayAndHistory() async {
        let harness = Self.makeHarness(confirm: [.success(Self.confirmedResponse)])
        await harness.model.submit(Self.request)

        await harness.model.confirm()

        #expect(harness.center.revision(for: .today) == 2)
        #expect(harness.center.revision(for: .history) == 1)
        #expect(harness.model.phase == .confirmed)
        #expect(harness.model.currentProposal == nil)
        #expect(harness.model.confirmedRegistration == Self.confirmedResponse.data.registration)
    }

    @Test("successful and failed operations target only the operation summary for accessibility")
    func operationSummaryFocusTarget() async {
        let success = Self.makeHarness()
        await success.model.submit(Self.request)
        #expect(success.model.accessibilityFocusTarget == .operationSummary)
        success.model.consumeAccessibilityFocus()
        #expect(success.model.accessibilityFocusTarget == nil)

        let failure = Self.makeHarness(propose: [.failure(.serviceUnavailable)])
        await failure.model.submit(Self.request)
        #expect(failure.model.accessibilityFocusTarget == .operationSummary)
    }

    @Test("a cancelled proposal task cannot publish a late proposal navigation or invalidation")
    func cancelledProposalCannotPublishLateResult() async {
        let service = ControlledWorkoutRegistrationService()
        let center = FeatureInvalidationCenter()
        let model = WorkoutRegistrationModel(
            registration: service,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "workout-cancel"),
            invalidationCenter: center
        )

        let task = Task { await model.submit(Self.request) }
        await service.waitUntilProposeStarted()
        model.discardSheet()
        await service.succeed(with: Self.pendingResponse)
        await task.value

        #expect(model.currentProposal == nil)
        #expect(model.phase == .form)
        #expect(model.accessibilityFocusTarget == nil)
        #expect(center.revision(for: .today) == 0)
    }

    @Test("a superseded proposal task cannot publish after a new workout intention")
    func supersededProposalCannotPublishLateResult() async {
        let service = ControlledWorkoutRegistrationService()
        let model = WorkoutRegistrationModel(
            registration: service,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "workout-supersede"),
            invalidationCenter: FeatureInvalidationCenter()
        )

        let task = Task { await model.submit(Self.request) }
        await service.waitUntilProposeStarted()
        model.startNewProposal()
        await service.succeed(with: Self.pendingResponse)
        await task.value

        #expect(model.currentProposal == nil)
        #expect(model.phase == .form)
        #expect(model.accessibilityFocusTarget == nil)
    }

    private static func makeHarness(
        propose: [WorkoutOutcome<RegistrationProposalResponse>] = [.success(pendingResponse)],
        edit: [WorkoutOutcome<RegistrationProposalResponse>] = [],
        confirm: [WorkoutOutcome<RegistrationConfirmationResponse>] = [],
        cancel: [WorkoutOutcome<RegistrationCancellationResponse>] = []
    ) -> WorkoutHarness {
        let service = WorkoutRegistrationServiceSpy(
            propose: propose, edit: edit, confirm: confirm, cancel: cancel
        )
        let center = FeatureInvalidationCenter()
        return WorkoutHarness(
            model: WorkoutRegistrationModel(
                registration: service,
                timeProvider: FixedTimeProvider(value: fixedDate),
                keyProvider: DeterministicIdempotencyKeyProvider(prefix: "workout"),
                invalidationCenter: center
            ),
            service: service,
            center: center
        )
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_784_589_300)
    private static let request = WorkoutProposalRequest(
        workoutType: "musculacao", durationMin: 47, intensity: .moderate,
        performedAt: APITimestamp(value: fixedDate)
    )
    private static let editedRequest = WorkoutProposalRequest(
        workoutType: "ciclismo", durationMin: 61, intensity: .high,
        performedAt: APITimestamp(value: fixedDate.addingTimeInterval(600))
    )
    private static let pendingResponse = response(
        id: "workout-pending", status: "pending", type: "musculacao",
        duration: 47, calories: 333, intensity: "moderada"
    )
    private static let editedResponse = response(
        id: "workout-pending", status: "pending", type: "ciclismo",
        duration: 61, calories: 444, intensity: "alta"
    )
    private static let nonPendingResponse = response(
        id: "workout-confirmed", status: "confirmed", type: "musculacao",
        duration: 47, calories: 333, intensity: "moderada"
    )
    private static let sanitizedResponse = workoutResponse(
        id: "workout-pending", workoutType: nil, duration: 47.5, intensity: nil
    )
    private static let sanitizedEditedResponse = workoutResponse(
        id: "workout-pending", workoutType: nil, duration: 61.5, intensity: nil
    )
    private static let cancelledResponse = RegistrationCancellationResponse(
        data: RegistrationSnapshot(
            id: pendingResponse.data.id, status: "cancelled",
            createdAt: pendingResponse.data.createdAt,
            expiresAt: pendingResponse.data.expiresAt,
            resolvedAt: APITimestamp(value: fixedDate),
            proposal: pendingResponse.data.proposal
        ), meta: MobileResponseMetadata(apiVersion: "v1", requestID: "cancel")
    )
    private static let confirmedResponse = DemoBodyFlowFixtures
        .confirmedWorkoutRegistration

    private static func response(
        id: String, status: String, type: String, duration: Decimal,
        calories: Decimal, intensity: String
    ) -> RegistrationProposalResponse {
        RegistrationProposalResponse(
            data: RegistrationSnapshot(
                id: id, status: status, createdAt: APITimestamp(value: fixedDate),
                expiresAt: APITimestamp(value: fixedDate.addingTimeInterval(3_600)),
                resolvedAt: nil,
                proposal: .workout(WorkoutProposalSnapshot(
                    workoutType: type, durationMin: duration,
                    estimatedKcal: calories, intensity: intensity
                ))
            ), meta: MobileResponseMetadata(apiVersion: "v1", requestID: id)
        )
    }

    private static func workoutResponse(
        id: String,
        workoutType: String?,
        duration: Decimal?,
        intensity: String?
    ) -> RegistrationProposalResponse {
        RegistrationProposalResponse(
            data: RegistrationSnapshot(
                id: id,
                status: "pending",
                createdAt: APITimestamp(value: fixedDate),
                expiresAt: APITimestamp(value: fixedDate.addingTimeInterval(3_600)),
                resolvedAt: nil,
                proposal: .workout(WorkoutProposalSnapshot(
                    workoutType: workoutType,
                    durationMin: duration,
                    estimatedKcal: 333,
                    intensity: intensity
                ))
            ),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: id)
        )
    }
}

@MainActor
private struct WorkoutHarness {
    let model: WorkoutRegistrationModel
    let service: WorkoutRegistrationServiceSpy
    let center: FeatureInvalidationCenter
}

private enum WorkoutOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(BodyFlowCapabilityError)

    func get() throws -> Value {
        switch self {
        case let .success(value): value
        case let .failure(error): throw error
        }
    }
}

private actor WorkoutRegistrationServiceSpy: RegistrationProviding {
    enum Call: Equatable, Sendable { case propose, edit, confirm, cancel }
    private var proposeOutcomes: [WorkoutOutcome<RegistrationProposalResponse>]
    private var editOutcomes: [WorkoutOutcome<RegistrationProposalResponse>]
    private var confirmOutcomes: [WorkoutOutcome<RegistrationConfirmationResponse>]
    private var cancelOutcomes: [WorkoutOutcome<RegistrationCancellationResponse>]
    private(set) var calls: [Call] = []
    private(set) var proposeAttempts: [MutationAttempt<RegistrationProposalRequest>] = []
    private(set) var editAttempts: [MutationAttempt<RegistrationEditCommand>] = []
    private(set) var confirmAttempts: [MutationAttempt<RegistrationIDCommand>] = []

    init(propose: [WorkoutOutcome<RegistrationProposalResponse>], edit: [WorkoutOutcome<RegistrationProposalResponse>], confirm: [WorkoutOutcome<RegistrationConfirmationResponse>], cancel: [WorkoutOutcome<RegistrationCancellationResponse>]) {
        proposeOutcomes = propose; editOutcomes = edit; confirmOutcomes = confirm; cancelOutcomes = cancel
    }

    func propose(_ attempt: MutationAttempt<RegistrationProposalRequest>) async throws -> RegistrationProposalResponse {
        calls.append(.propose); proposeAttempts.append(attempt)
        return try proposeOutcomes.removeFirst().get()
    }
    func edit(_ attempt: MutationAttempt<RegistrationEditCommand>) async throws -> RegistrationProposalResponse {
        calls.append(.edit); editAttempts.append(attempt)
        return try editOutcomes.removeFirst().get()
    }
    func confirm(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationConfirmationResponse {
        calls.append(.confirm); confirmAttempts.append(attempt)
        return try confirmOutcomes.removeFirst().get()
    }
    func cancel(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationCancellationResponse {
        calls.append(.cancel)
        return try cancelOutcomes.removeFirst().get()
    }
}

private actor ControlledWorkoutRegistrationService: RegistrationProviding {
    private var continuation: CheckedContinuation<RegistrationProposalResponse, Never>?
    private var started = false

    func propose(_ attempt: MutationAttempt<RegistrationProposalRequest>) async throws -> RegistrationProposalResponse {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func edit(_ attempt: MutationAttempt<RegistrationEditCommand>) async throws -> RegistrationProposalResponse { fatalError("unused") }
    func confirm(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationConfirmationResponse { fatalError("unused") }
    func cancel(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationCancellationResponse { fatalError("unused") }

    func waitUntilProposeStarted() async {
        while !started { await Task.yield() }
    }
    func succeed(with response: RegistrationProposalResponse) { continuation?.resume(returning: response) }
}
