import Foundation

/// Meal media over the mobile BFF: the asset's record, the upload ticket and
/// the processing request. The bytes never pass through here — they go
/// straight to storage with the ticket (`StorageUploadTransport`).
struct MobileMediaRepository: MealMediaProviding {
    let transport: any MobileAPIEnvelopeExecuting

    func create(
        _ attempt: MutationAttempt<MediaUploadRequest>
    ) async throws -> MediaCreateSnapshot {
        try await transport.executeMealCapture {
            try MobileAPIRequest(
                method: .post,
                path: "/api/mobile/v1/media",
                body: try Self.encode(attempt.payload),
                idempotencyKey: attempt.key
            )
        }
    }

    func complete(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot {
        try await transport.executeMealCapture {
            try MobileAPIRequest(
                method: .post,
                path: try Self.assetPath(attempt.payload.assetID, suffix: "/complete"),
                idempotencyKey: attempt.key
            )
        }
    }

    func requestProcessing(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot {
        try await transport.executeMealCapture {
            try MobileAPIRequest(
                method: .post,
                path: try Self.assetPath(attempt.payload.assetID, suffix: "/process"),
                idempotencyKey: attempt.key
            )
        }
    }

    func asset(id: String) async throws -> MediaAssetSnapshot {
        try await transport.executeMealCapture {
            try MobileAPIRequest(method: .get, path: try Self.assetPath(id))
        }
    }

    func delete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws {
        let _: MediaAssetSnapshot = try await transport.executeMealCapture {
            try MobileAPIRequest(
                method: .delete,
                path: try Self.assetPath(attempt.payload.assetID),
                idempotencyKey: attempt.key
            )
        }
    }

    /// Asset IDs come from the server and go back into a path, so only the
    /// UUID alphabet is allowed there.
    static func assetPath(_ id: String, suffix: String = "") throws -> String {
        "/api/mobile/v1/media/\(try MobileAPIPathSegment.identifier(id))\(suffix)"
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw MealCaptureFailure.invalidInput
        }
    }
}

/// Candidates for review from free text or processed media.
struct MobileMealDraftRepository: MealDraftProviding {
    let transport: any MobileAPIEnvelopeExecuting

    func draft(
        _ attempt: MutationAttempt<MealDraftRequest>
    ) async throws -> MealDraftSnapshot {
        if case let .media(assetID) = attempt.payload {
            _ = try MobileAPIPathSegment.identifier(assetID)
        }
        let body: Data
        do {
            body = try JSONEncoder().encode(attempt.payload)
        } catch {
            throw MealCaptureFailure.invalidInput
        }
        return try await transport.executeMealCapture {
            try MobileAPIRequest(
                method: .post,
                path: "/api/mobile/v1/meal-drafts",
                body: body,
                idempotencyKey: attempt.key
            )
        }
    }
}

extension MobileAPIEnvelopeExecuting {
    /// Runs one request of the meal capture and names its failure for the
    /// screen. Cancellation passes through untouched.
    func executeMealCapture<Payload: Codable & Sendable>(
        _ request: () throws -> MobileAPIRequest<Payload>
    ) async throws -> Payload {
        do {
            return try await executeEnvelope(try request()).data
        } catch is CancellationError {
            throw CancellationError()
        } catch is MobileAPIRequestError {
            throw MealCaptureFailure.invalidInput
        } catch {
            throw MealCaptureFailure(error)
        }
    }
}
