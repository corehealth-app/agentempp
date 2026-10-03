import Foundation

/// Envelope-preserving execution: read surfaces show the server's own
/// request ID, so they need the metadata `execute` discards.
protocol MobileAPIEnvelopeExecuting: Sendable {
    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response>
}

extension MobileAPITransport: MobileAPIEnvelopeExecuting {}

/// The read surfaces the mobile BFF already serves (`/today`, `/history`,
/// `/plan`, `/progress`, `/me`), over the same transport as onboarding and
/// Flow. Nothing is computed here: the response is the official state.
struct MobileBodyFlowRepository: TodayProviding, HistoryProviding,
    PlanProviding, ProgressProviding, MeProviding {
    let transport: any MobileAPIEnvelopeExecuting

    func today() async throws -> TodayResponse {
        try await read("/api/mobile/v1/today")
    }

    func me() async throws -> MeResponse {
        try await read("/api/mobile/v1/me")
    }

    func plan() async throws -> PlanResponse {
        try await read("/api/mobile/v1/plan")
    }

    func progress() async throws -> ProgressResponse {
        try await read("/api/mobile/v1/progress")
    }

    func profileWeight() async throws -> ProfileWeightResponse? {
        try await read("/api/mobile/v1/profile")
    }

    func trends(days: Int) async throws -> TrendsResponse {
        try await read(
            "/api/mobile/v1/trends",
            queryItems: [URLQueryItem(name: "days", value: String(days))]
        )
    }

    func history(_ query: HistoryQuery) async throws -> HistoryResponse {
        var items = [URLQueryItem(name: "limit", value: String(query.limit))]
        if let before = query.before {
            // ISO8601DateFormatter is not Sendable; one per call is cheap.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            items.append(URLQueryItem(
                name: "before",
                value: formatter.string(from: before.value)
            ))
        }
        return try await read("/api/mobile/v1/history", queryItems: items)
    }

    private func read<Payload: Codable & Sendable>(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> MobileResponse<Payload> {
        do {
            return try await transport.executeEnvelope(MobileAPIRequest(
                method: .get,
                path: path,
                queryItems: queryItems
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MobileAPITransportError {
            throw Self.capabilityError(for: error)
        } catch {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
    }

    /// Transport failures land on the same states the demo repositories
    /// use, so the screens keep their offline / retry / unavailable families.
    static func capabilityError(
        for error: MobileAPITransportError
    ) -> BodyFlowCapabilityError {
        error.capabilityError
    }
}
