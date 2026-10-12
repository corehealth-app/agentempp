import Foundation

/// Dedicated signup routes. The capture coordinator must retain a transport
/// scoped to its owner/lease for the whole operation (integration in B7).
struct MobileSignupBodyPhotoRepository: SignupBodyPhotosProviding {
    let transport: any MobileAPIEnvelopeExecuting
    private static let path = "/api/mobile/v1/onboarding/body-photos"

    func state() async throws -> SignupBodyPhotoState {
        try await execute { try MobileAPIRequest(method: .get, path: Self.path) }
    }

    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws
        -> SignupBodyPhotoConsentReceipt {
        guard attempt.payload.version.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil,
              attempt.payload.bodyHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              OnboardingCivilDate.date(from: attempt.payload.birthDate, timeZoneIdentifier: "UTC") != nil
        else { throw SignupBodyPhotoFailure.invalidInput }
        return try await execute {
            try MobileAPIRequest(
                method: .post, path: Self.path + "/consent",
                body: try JSONEncoder().encode(attempt.payload), idempotencyKey: attempt.key
            )
        }
    }

    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws
        -> SignupBodyPhotoCreateReceipt {
        guard attempt.payload.mimeType == "image/jpeg",
              (1...MealMediaLimits.maximumPhotoBytes).contains(attempt.payload.sizeBytes)
        else { throw SignupBodyPhotoFailure.invalidInput }
        return try await execute {
            try MobileAPIRequest(
                method: .post, path: Self.path,
                body: try JSONEncoder().encode(attempt.payload), idempotencyKey: attempt.key
            )
        }
    }

    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws
        -> SignupBodyPhotoCompleteReceipt {
        guard UUID(uuidString: attempt.payload.assetID) != nil else {
            throw SignupBodyPhotoFailure.invalidInput
        }
        return try await execute {
            try MobileAPIRequest(
                method: .post,
                path: Self.path + "/" + (try MobileAPIPathSegment.identifier(attempt.payload.assetID)) + "/complete",
                idempotencyKey: attempt.key
            )
        }
    }

    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws
        -> SignupBodyPhotoDeleteReceipt {
        try await execute {
            try MobileAPIRequest(method: .delete, path: Self.path, idempotencyKey: attempt.key)
        }
    }

    private func execute<Response: Codable & Sendable>(
        _ request: () throws -> MobileAPIRequest<Response>
    ) async throws -> Response {
        do {
            return try await transport.executeEnvelope(try request()).data
        } catch is CancellationError {
            throw CancellationError()
        } catch is MobileAPIRequestError {
            throw SignupBodyPhotoFailure.invalidInput
        } catch {
            throw SignupBodyPhotoFailure(error)
        }
    }
}
