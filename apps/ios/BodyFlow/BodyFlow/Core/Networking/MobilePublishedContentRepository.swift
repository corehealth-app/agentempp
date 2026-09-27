import Foundation

/// Published Library content over the mobile BFF (`/content`). The server
/// owns publication, targeting and the read/saved state; the client sends
/// the query it was given and the patient's actions with their attempt keys.
struct MobilePublishedContentRepository:
    PublishedContentListing,
    PublishedContentDetailProviding,
    PublishedContentStateRecording,
    PublishedContentSessionLifetime
{
    let transport: any MobileAPIEnvelopeExecuting

    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse {
        var queryItems = [URLQueryItem(name: "surface", value: query.surface.rawValue)]
        if let category = query.category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(query.limit)))
        if let cursor = query.cursor {
            guard let cursor = try? MobileAPIPathSegment.cursor(cursor) else {
                throw BodyFlowCapabilityError.invalidContentCursor
            }
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        do {
            return try await transport.executeCapability {
                try MobileAPIRequest(
                    method: .get,
                    path: "/api/mobile/v1/content",
                    queryItems: queryItems
                )
            }
        } catch BodyFlowCapabilityError.invalidInput where query.cursor != nil {
            // The transport drops `details`, so a 422 on a cursor page is
            // read as the cursor having expired: the feed reloads page one.
            throw BodyFlowCapabilityError.invalidContentCursor
        }
    }

    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse {
        let path = try Self.publicationPath(publicationID)
        return try await transport.executeCapability {
            try MobileAPIRequest(method: .get, path: path)
        }
    }

    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse {
        try await post(
            path: try Self.publicationPath(attempt.payload.publicationID, suffix: "/read"),
            body: attempt.payload.body,
            key: attempt.key
        )
    }

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse {
        try await post(
            path: try Self.publicationPath(attempt.payload.publicationID, suffix: "/save"),
            body: attempt.payload.body,
            key: attempt.key
        )
    }

    /// The transport is bound to the signed-in session and the session
    /// owner gates every call, so there is nothing else to release here.
    func endSession() async {}

    static func publicationPath(_ id: String, suffix: String = "") throws -> String {
        "/api/mobile/v1/content/\(try MobileAPIPathSegment.identifier(id))\(suffix)"
    }

    private func post<Body: Encodable, Payload: Codable & Sendable>(
        path: String,
        body: Body,
        key: IdempotencyKey
    ) async throws -> MobileResponse<Payload> {
        let data: Data
        do {
            data = try JSONEncoder().encode(body)
        } catch {
            throw BodyFlowCapabilityError.invalidInput
        }
        return try await transport.executeCapability {
            try MobileAPIRequest(method: .post, path: path, body: data, idempotencyKey: key)
        }
    }
}

struct MobilePublishedContentSessionFactory: PublishedContentSessionCreating {
    let transport: any MobileAPIEnvelopeExecuting

    func makeSession(userID: String) -> PublishedContentSession {
        _ = userID
        let repository = MobilePublishedContentRepository(transport: transport)
        return PublishedContentSession(
            listing: repository,
            detail: repository,
            state: repository,
            lifetime: repository
        )
    }
}
