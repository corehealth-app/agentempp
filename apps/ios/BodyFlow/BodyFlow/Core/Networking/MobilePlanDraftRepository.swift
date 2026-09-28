import Foundation

/// Plan drafts over the mobile BFF. The content rules (what is complete,
/// what is uncertain) are the server's; the client sends the patient's edits
/// and the version the patient reviewed.
struct MobilePlanDraftRepository: PlanDraftProviding {
    let transport: any MobileAPIEnvelopeExecuting

    func openDrafts() async throws -> [PlanDraftSummary] {
        let list: PlanDraftList = try await execute {
            try MobileAPIRequest(
                method: .get,
                path: "/api/mobile/v1/plan-drafts",
                queryItems: [URLQueryItem(name: "status", value: "open")]
            )
        }
        return list.items
    }

    func draft(id: String) async throws -> PlanDraftSnapshot {
        try await execute {
            try MobileAPIRequest(method: .get, path: try Self.draftPath(id))
        }
    }

    func update(
        _ attempt: MutationAttempt<PlanDraftEdit>
    ) async throws -> PlanDraftSnapshot {
        let body = try Self.encode(attempt.payload)
        return try await execute {
            try MobileAPIRequest(
                method: .patch,
                path: try Self.draftPath(attempt.payload.draftID),
                body: body,
                idempotencyKey: attempt.key
            )
        }
    }

    func confirm(
        _ attempt: MutationAttempt<PlanDraftConfirmation>
    ) async throws -> PlanDraftSnapshot {
        let body = try Self.encode(["payload_version": attempt.payload.payloadVersion])
        return try await execute {
            try MobileAPIRequest(
                method: .post,
                path: try Self.draftPath(attempt.payload.draftID, suffix: "/confirm"),
                body: body,
                idempotencyKey: attempt.key
            )
        }
    }

    func discard(
        _ attempt: MutationAttempt<PlanDraftCommand>
    ) async throws -> PlanDraftSnapshot {
        try await execute {
            try MobileAPIRequest(
                method: .delete,
                path: try Self.draftPath(attempt.payload.draftID),
                idempotencyKey: attempt.key
            )
        }
    }

    func startImport(
        _ attempt: MutationAttempt<PlanImportRequest>
    ) async throws -> PlanImportReceipt {
        _ = try Self.identifier(attempt.payload.mediaAssetID)
        let body = try Self.encode(attempt.payload)
        return try await execute {
            try MobileAPIRequest(
                method: .post,
                path: "/api/mobile/v1/plan-imports",
                body: body,
                idempotencyKey: attempt.key
            )
        }
    }

    /// Draft IDs come from the server and go back into a path, so only the
    /// UUID alphabet is allowed there.
    static func draftPath(_ id: String, suffix: String = "") throws -> String {
        "/api/mobile/v1/plan-drafts/\(try identifier(id))\(suffix)"
    }

    private static func identifier(_ id: String) throws -> String {
        do {
            return try MobileAPIPathSegment.identifier(id)
        } catch {
            throw PlanDraftFailure.invalidInput
        }
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw PlanDraftFailure.invalidInput
        }
    }

    private func execute<Payload: Codable & Sendable>(
        _ request: () throws -> MobileAPIRequest<Payload>
    ) async throws -> Payload {
        do {
            return try await transport.executeEnvelope(try request()).data
        } catch is CancellationError {
            throw CancellationError()
        } catch is MobileAPIRequestError {
            throw PlanDraftFailure.invalidInput
        } catch {
            throw PlanDraftFailure(error)
        }
    }
}
