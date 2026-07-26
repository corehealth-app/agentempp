import Foundation

protocol APIClient: Sendable {
    func send<Response: Decodable & Sendable>(
        _ request: APIRequest<Response>
    ) async throws -> Response
}

enum APIClientError: Error, Equatable, Sendable {
    case fixtureFailure
    case missingPayload(APIRequestKey)
    case decodingFailure
}

actor MockAPIClient: APIClient {
    private let payloads: [APIRequestKey: Data]
    private let failures: [APIRequestKey: APIClientError]
    private let delay: Duration?

    init(
        payloads: [APIRequestKey: Data] = [:],
        failures: [APIRequestKey: APIClientError] = [:],
        delay: Duration? = nil
    ) {
        self.payloads = payloads
        self.failures = failures
        self.delay = delay
    }

    func send<Response: Decodable & Sendable>(
        _ request: APIRequest<Response>
    ) async throws -> Response {
        if let delay {
            try await Task.sleep(for: delay)
        }

        if let failure = failures[request.key] {
            throw failure
        }

        guard let payload = payloads[request.key] else {
            throw APIClientError.missingPayload(request.key)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: payload)
        } catch {
            throw APIClientError.decodingFailure
        }
    }
}
