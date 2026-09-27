import Foundation
import Testing

@testable import BodyFlow

@Suite("Mobile published content repository")
struct MobilePublishedContentRepositoryTests {
    private static let publicationID = "3f6c2a10-5b1e-4d8f-9a2b-7c4d5e6f8a90"

    private static let summaryJSON = """
    {"publication_id":"3f6c2a10-5b1e-4d8f-9a2b-7c4d5e6f8a90","slug":"hidratacao-no-treino","locale":"pt-BR",
     "title":"Hidratação no treino","excerpt":"Quanto beber antes, durante e depois do treino, sem exagero.",
     "category":"hydration","tags":["agua","treino"],"reading_time_minutes":4,
     "publish_at":"2026-07-01T09:00:00.000000+00:00","featured_today":true,"version":3,"saved":false,"completed":false,
     "cover":{"url":"/api/mobile/v1/content/covers/abc_DEF-123","expires_at":"2026-07-20T23:20:00+00:00"}}
    """

    private static let feedJSON = Data("""
    {"data":{"items":[\(summaryJSON)],"next_cursor":"eyJwIjoyfQ"},
     "meta":{"api_version":"v1","request_id":"req-content-feed-1"}}
    """.utf8)

    private static let detailJSON = Data("""
    {"data":{"publication_id":"3f6c2a10-5b1e-4d8f-9a2b-7c4d5e6f8a90","slug":"hidratacao-no-treino","locale":"pt-BR",
     "title":"Hidratação no treino","excerpt":"Quanto beber antes, durante e depois do treino, sem exagero.",
     "category":"hydration","tags":["agua","treino"],"reading_time_minutes":4,
     "publish_at":"2026-07-01T09:00:00.000000+00:00","featured_today":true,"version":3,"saved":false,"completed":false,
     "cover":null,
     "body_markdown":"# Hidratação\\n\\nBeba água em goles regulares ao longo do treino, ajustando ao calor e à duração da sessão. Prefira água; bebidas esportivas só em sessões longas."},
     "meta":{"api_version":"v1","request_id":"req-content-detail-1"}}
    """.utf8)

    private static let stateJSON = Data("""
    {"data":{"publication_id":"3f6c2a10-5b1e-4d8f-9a2b-7c4d5e6f8a90","version":3,"saved":true,"completed":false,"changed":true,"replayed":false},
     "meta":{"api_version":"v1","request_id":"req-content-state-1"}}
    """.utf8)

    private func key(_ value: String) throws -> IdempotencyKey {
        try IdempotencyKey(validating: value)
    }

    @Test("the feed query becomes exactly the documented parameters")
    func feedQueryParameters() async throws {
        let spy = ContentTransportSpy(responseJSON: Self.feedJSON)
        let repository = MobilePublishedContentRepository(transport: spy)

        let response = try await repository.content(try ContentFeedQuery(
            surface: .library, category: .hydration, limit: 20, cursor: nil
        ))
        _ = try await repository.content(try ContentFeedQuery(
            surface: .saved, category: nil, limit: 10, cursor: response.data.nextCursor
        ))

        let requests = await spy.requests
        #expect(requests.count == 2)
        #expect(requests[0].method == .get)
        #expect(requests[0].path == "/api/mobile/v1/content")
        #expect(requests[0].queryItems == [
            URLQueryItem(name: "surface", value: "library"),
            URLQueryItem(name: "category", value: "hydration"),
            URLQueryItem(name: "limit", value: "20"),
        ])
        #expect(requests[1].queryItems == [
            URLQueryItem(name: "surface", value: "saved"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "cursor", value: "eyJwIjoyfQ"),
        ])
        #expect(response.data.items.first?.publicationID == Self.publicationID)
        #expect(response.data.items.first?.category == .hydration)
        #expect(response.data.items.first?.cover?.url == "/api/mobile/v1/content/covers/abc_DEF-123")
        #expect(response.meta.requestID == "req-content-feed-1")
    }

    @Test("a cursor outside the base64url alphabet, or rejected by the server, reloads page one")
    func cursorFailuresBecomeInvalidCursor() async throws {
        let spy = ContentTransportSpy(responseJSON: Self.feedJSON)
        let repository = MobilePublishedContentRepository(transport: spy)
        await #expect(throws: BodyFlowCapabilityError.invalidContentCursor) {
            try await repository.content(try ContentFeedQuery(
                surface: .library, category: nil, limit: 20, cursor: "AbC_-09+/=.%2F?keep-byte-for-byte"
            ))
        }
        #expect(await spy.requests.isEmpty)

        let rejecting = ContentTransportSpy(
            responseJSON: Self.feedJSON,
            failure: .validation(code: "validation_failed", requestID: nil)
        )
        let rejectingRepository = MobilePublishedContentRepository(transport: rejecting)
        await #expect(throws: BodyFlowCapabilityError.invalidContentCursor) {
            try await rejectingRepository.content(try ContentFeedQuery(
                surface: .library, category: nil, limit: 20, cursor: "eyJwIjoyfQ"
            ))
        }
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await rejectingRepository.content(try ContentFeedQuery(
                surface: .library, category: nil, limit: 20, cursor: nil
            ))
        }
    }

    @Test("detail reads the publication by id and fails closed on a bad id")
    func detailReadsPublication() async throws {
        let spy = ContentTransportSpy(responseJSON: Self.detailJSON)
        let repository = MobilePublishedContentRepository(transport: spy)

        let detail = try await repository.contentDetail(publicationID: Self.publicationID)

        let request = try #require(await spy.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/content/\(Self.publicationID)")
        #expect(detail.data.bodyMarkdown.hasPrefix("# Hidratação"))
        #expect(detail.data.summary.version == 3)
        #expect(detail.data.summary.cover == nil)

        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.contentDetail(publicationID: "../covers/x")
        }
        #expect(await spy.requests.count == 1)
    }

    @Test("read and save post the documented bodies with the attempt's key")
    func readAndSavePost() async throws {
        let spy = ContentTransportSpy(responseJSON: Self.stateJSON)
        let repository = MobilePublishedContentRepository(transport: spy)

        let read = try await repository.recordRead(MutationAttempt(
            operation: .contentRead, key: try key("mobile-test-read-1"),
            payload: ContentReadCommand(
                publicationID: Self.publicationID,
                body: ContentReadBody(event: .opened, origin: .library, version: 3)
            ),
            createdAt: Date()
        ))
        _ = try await repository.setSaved(MutationAttempt(
            operation: .contentSave, key: try key("mobile-test-save-1"),
            payload: ContentSaveCommand(
                publicationID: Self.publicationID,
                body: ContentSaveBody(saved: true, version: 3)
            ),
            createdAt: Date()
        ))

        let requests = await spy.requests
        #expect(requests.map(\.method) == [.post, .post])
        #expect(requests.map(\.path) == [
            "/api/mobile/v1/content/\(Self.publicationID)/read",
            "/api/mobile/v1/content/\(Self.publicationID)/save",
        ])
        #expect(requests[0].idempotency == .required(try key("mobile-test-read-1")))
        #expect(requests[1].idempotency == .required(try key("mobile-test-save-1")))
        let readBody = try #require(requests[0].body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(readBody["event"] as? String == "opened")
        #expect(readBody["origin"] as? String == "library")
        #expect(readBody["version"] as? Int == 3)
        #expect(readBody.count == 3)
        let saveBody = try #require(requests[1].body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(saveBody["saved"] as? Bool == true)
        #expect(saveBody["version"] as? Int == 3)
        #expect(saveBody.count == 2)
        #expect(read.data.saved == true)
        #expect(read.data.changed == true)
        #expect(read.data.replayed == false)
    }

    @Test("transport failures land on the content capability states")
    func transportFailuresMap() async throws {
        let cases: [(MobileAPITransportError, BodyFlowCapabilityError)] = [
            (.http(status: 404, code: "content_not_found", requestID: nil), .contentNotFound),
            (.conflict(code: "content_version_changed", requestID: nil), .contentVersionChanged),
            (.conflict(code: "idempotency_key_conflict", requestID: nil), .idempotencyConflict),
            (.conflict(code: "idempotency_request_in_progress", requestID: nil), .idempotencyRequestInProgress),
            (.http(status: 402, code: "subscription_required", requestID: nil), .subscriptionRequired),
            (.timeout, .offline),
            (.server(status: 500, code: "internal_error", requestID: nil), .serviceUnavailable),
        ]
        for (failure, expected) in cases {
            let spy = ContentTransportSpy(responseJSON: Self.detailJSON, failure: failure)
            let repository = MobilePublishedContentRepository(transport: spy)
            await #expect(throws: expected) {
                try await repository.contentDetail(publicationID: Self.publicationID)
            }
        }
    }

    @Test("the session factory serves every role from the transport-backed repository")
    func factoryBuildsSession() async {
        let spy = ContentTransportSpy(responseJSON: Self.feedJSON)
        let session = MobilePublishedContentSessionFactory(transport: spy).makeSession(userID: "user-a")
        #expect(session.listing is MobilePublishedContentRepository)
        #expect(session.detail is MobilePublishedContentRepository)
        #expect(session.state is MobilePublishedContentRepository)
        #expect(session.lifetime is MobilePublishedContentRepository)
        await session.lifetime.endSession()
        #expect(await spy.requests.isEmpty)
    }
}

private actor ContentTransportSpy: MobileAPIEnvelopeExecuting {
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let queryItems: [URLQueryItem]
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }

    private(set) var requests: [Recorded] = []
    private let responseJSON: Data
    private let failure: MobileAPITransportError?

    init(responseJSON: Data, failure: MobileAPITransportError? = nil) {
        self.responseJSON = responseJSON
        self.failure = failure
    }

    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        requests.append(Recorded(
            method: request.method, path: request.path, queryItems: request.queryItems,
            body: request.body, idempotency: request.idempotency
        ))
        if let failure { throw failure }
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: responseJSON)
    }
}
