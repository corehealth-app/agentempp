import Foundation

/// Meal/workout proposals and hydration over the mobile BFF. The server
/// prices every item and owns the pending lifecycle; the client carries
/// only the patient's input and the attempt's idempotency key, so a retry
/// replays the same request instead of duplicating it.
struct MobileRegistrationRepository: RegistrationProviding, WorkoutRegistrationReading, HydrationRecording, WeightRecording {
    let transport: any MobileAPIEnvelopeExecuting

    func propose(
        _ attempt: MutationAttempt<RegistrationProposalRequest>
    ) async throws -> RegistrationProposalResponse {
        try await send(
            .post,
            path: "/api/mobile/v1/registrations/propose",
            body: try encode(attempt.payload),
            key: attempt.key
        )
    }

    func edit(
        _ attempt: MutationAttempt<RegistrationEditCommand>
    ) async throws -> RegistrationProposalResponse {
        try await send(
            .patch,
            path: try Self.registrationPath(attempt.payload.registrationID),
            body: try encode(attempt.payload),
            key: attempt.key
        )
    }

    func confirm(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationConfirmationResponse {
        try await send(
            .post,
            path: try Self.registrationPath(attempt.payload.registrationID, suffix: "/confirm"),
            body: try selectionBody(attempt.payload),
            key: attempt.key
        )
    }

    func cancel(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationCancellationResponse {
        try await send(
            .delete,
            path: try Self.registrationPath(attempt.payload.registrationID),
            body: try selectionBody(attempt.payload),
            key: attempt.key
        )
    }

    /// Re-read the owned projection after a version conflict. The transport
    /// carries the session; no owner or revision is supplied by a query.
    func loadWorkoutRegistration(id: String) async throws -> RegistrationProposalResponse {
        try await send(.get, path: try Self.registrationPath(id), body: nil)
    }

    func record(
        _ attempt: MutationAttempt<HydrationCommand>
    ) async throws -> HydrationReceipt {
        try await send(
            .post,
            path: "/api/mobile/v1/routine/hydration",
            body: try encode(attempt.payload),
            key: attempt.key
        )
    }

    func record(
        _ attempt: MutationAttempt<WeightCommand>
    ) async throws -> WeightDemoReceipt {
        let response: WeightRecordResponse = try await send(
            .post,
            path: "/api/mobile/v1/weight",
            body: try encode(WeightRecordRequest(command: attempt.payload)),
            key: attempt.key
        )
        return WeightDemoReceipt(
            weightKG: NSDecimalNumber(decimal: response.data.weightKG).doubleValue,
            recordedAt: response.data.measuredAt.value,
            label: "",
            outcome: WeightRecordOutcome(rawValue: response.data.reason),
            isServerRecord: true
        )
    }

    /// Registration IDs come from the server and go back into a path, so
    /// only the UUID alphabet is allowed there.
    static func registrationPath(_ id: String, suffix: String = "") throws -> String {
        "/api/mobile/v1/registrations/\(try MobileAPIPathSegment.identifier(id))\(suffix)"
    }

    private func encode(_ value: some Encodable) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw BodyFlowCapabilityError.invalidInput
        }
    }

    private func selectionBody(_ command: RegistrationIDCommand) throws -> Data? {
        guard let version = command.workoutVersion else { return nil }
        return try encode(WorkoutRegistrationSelectionBody(version: version))
    }

    private func send<Payload: Codable & Sendable>(
        _ method: HTTPMethod,
        path: String,
        body: Data?,
        key: IdempotencyKey? = nil
    ) async throws -> MobileResponse<Payload> {
        try await transport.executeCapability {
            try MobileAPIRequest(
                method: method,
                path: path,
                body: body,
                idempotencyKey: key
            )
        }
    }
}

private struct WorkoutRegistrationSelectionBody: Encodable {
    let version: WorkoutRegistrationVersion

    func encode(to encoder: any Encoder) throws {
        try version.encodeSelection(to: encoder)
    }
}
