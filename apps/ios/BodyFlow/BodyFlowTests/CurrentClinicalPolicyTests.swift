import Foundation
import Testing

@testable import BodyFlow

@Suite("Current clinical read contracts — dormant opt-in")
struct CurrentClinicalPolicyTests {
    static let policy = #"{"version":1,"observed_at":"2026-10-26T12:00:00.123456Z","assessment":"complete","recording_allowed":true,"pause_weight_loss_guidance":false,"professional_assessment_recommended":false,"phase_selection_pending":true,"target_source":"unavailable","hide":{"objective":true,"calories":true,"protein":true,"balance":true,"block":true}}"#

    private func payload<T: Encodable>(_ value: T) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object["clinical_policy"] = try JSONSerialization.jsonObject(with: Data(Self.policy.utf8))
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test("all five current read contracts retain the same policy without inventing a first phase")
    func fiveContracts() throws {
        let today = try JSONDecoder().decode(TodaySnapshot.self,
            from: payload(BodyFlowTestFixtures.decodeInconsistentToday().data))
        let progress = try JSONDecoder().decode(ProgressSnapshot.self,
            from: payload(BodyFlowTestFixtures.progressSnapshot))
        let plan = try JSONDecoder().decode(PlanSnapshot.self,
            from: payload(PlanSnapshot(training: nil, nutrition: [])))
        let trends = try JSONDecoder().decode(TrendsSnapshot.self, from: payload(TrendsSnapshot.empty(days: 7)))
        let objective = try JSONDecoder().decode(CurrentObjectiveSnapshot.self,
            from: payload(CurrentObjectiveSnapshot(currentProtocol: nil, targets: nil, welcome: nil)))
        for policy in [today.clinicalPolicy, progress.clinicalPolicy, plan.clinicalPolicy,
                       trends.clinicalPolicy, objective.clinicalPolicy] {
            let value = try #require(policy)
            #expect(value.version == 1)
            #expect(value.recordingAllowed)
            #expect(!value.pauseWeightLossGuidance)
            #expect(value.phaseSelectionPending)
            #expect(value.targetSource == .unavailable)
            #expect(value.hide.objective && value.hide.block)
        }
        #expect(objective.currentProtocol == nil && objective.welcome == nil)
        #expect(progress.xpTotal == 12_345)
        #expect(!progress.blockPresentationPolicy.showsBlock)
        #expect(!today.blockPresentationPolicy.showsBlock)
        let presentation = ProgressPresentation(snapshot: progress, language: .portugueseBrazil)
        #expect(presentation.completedBlocksText == "Não disponível")
        #expect(presentation.deficitBlockText == "Não disponível")
    }

    @Test("absent policy remains compatible with the existing response")
    func absentPolicy() throws {
        #expect(try BodyFlowTestFixtures.decodeInconsistentToday().data.clinicalPolicy == nil)
        #expect(BodyFlowTestFixtures.progressSnapshot.clinicalPolicy == nil)
        #expect(PlanSnapshot(training: nil, nutrition: []).clinicalPolicy == nil)
        #expect(TrendsSnapshot.empty(days: 7).clinicalPolicy == nil)
        #expect(CurrentObjectiveSnapshot(currentProtocol: nil, targets: nil, welcome: nil).clinicalPolicy == nil)
    }

    @Test("unsupported or malformed policy fails decoding", arguments: [
        ("\"version\":1", "\"version\":2"),
        ("\"assessment\":\"complete\"", "\"assessment\":\"future\""),
        ("\"target_source\":\"unavailable\"", "\"target_source\":\"guessed\""),
        ("\"recording_allowed\":true", "\"recording_allowed\":1"),
        ("\"block\":true", "\"block\":\"true\""),
    ])
    func malformedPolicy(_ mutation: (String, String)) {
        let json = Self.policy.replacingOccurrences(of: mutation.0, with: mutation.1)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CurrentClinicalPolicy.self, from: Data(json.utf8))
        }
    }

    @Test("public policy does not retain private additive risk fields")
    func privateFieldsNotRetained() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: Data(Self.policy.utf8)) as? [String: Any])
        object["private_health_answers"] = ["synthetic": true]
        let value = try JSONDecoder().decode(CurrentClinicalPolicy.self,
            from: JSONSerialization.data(withJSONObject: object))
        let encoded = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        #expect(encoded["private_health_answers"] == nil)
        #expect(Set(encoded.keys) == ["version", "observed_at", "assessment", "recording_allowed",
            "pause_weight_loss_guidance", "professional_assessment_recommended", "phase_selection_pending", "target_source", "hide"])
    }

    @Test("only the five explicit read surfaces negotiate; History Me and Profile keep their existing query")
    func explicitQueryScope() async throws {
        let transport = ClinicalQueryTransport()
        let repository = MobileBodyFlowRepository(transport: transport, clinicalRepresentation: .currentV1)
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await repository.today() }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await repository.progress() }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await repository.plan() }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await repository.trends(days: 7) }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await repository.me() }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await repository.profileWeight() }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await repository.history(.firstPage) }
        let objective = MobileCurrentObjectiveRepository(transport: transport, clinicalRepresentation: .currentV1)
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await objective.currentObjective() }
        let requests = await transport.requests
        #expect(requests.count == 8)
        for endpoint in ["today", "progress", "plan", "trends", "protocol"] {
            let read = try #require(requests.first { $0.path == "/api/mobile/v1/\(endpoint)" })
            #expect(read.query.filter { $0.name == "clinical_policy" }.map(\.value) == ["current_clinical_v1"])
        }
        for endpoint in ["me", "history", "profile"] {
            let read = try #require(requests.first { $0.path == "/api/mobile/v1/\(endpoint)" })
            #expect(!read.query.contains { $0.name == "clinical_policy" })
        }
        #expect(requests.allSatisfy { $0.isGetWithoutBody })
        #expect(requests.first { $0.path.hasSuffix("trends") }?.query.first?.value == "7")
        #expect(requests.first { $0.path.hasSuffix("history") }?.query.first?.value == "30")
    }

    @Test("existing repository constructors do not enable clinical representation")
    func defaultRemainsDormant() async {
        let transport = ClinicalQueryTransport()
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await MobileBodyFlowRepository(transport: transport).today()
        }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await MobileCurrentObjectiveRepository(transport: transport).currentObjective()
        }
        #expect(await transport.requests.allSatisfy { $0.query.isEmpty })
    }
}

private actor ClinicalQueryTransport: MobileAPIEnvelopeExecuting, MobileAPIExecuting, CurrentClinicalSessionAuthorizing {
    // Positive scoped test transport: this fixture checks query negotiation,
    // while real Auth generation behavior has its own transport tests.
    func validateCurrentClinicalSession() async throws {}
    struct Read: Sendable {
        let path: String
        let query: [URLQueryItem]
        let isGetWithoutBody: Bool
    }
    private(set) var requests: [Read] = []

    func executeEnvelope<Response: Codable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> MobileResponse<Response> {
        requests.append(Read(path: request.path, query: request.queryItems,
            isGetWithoutBody: request.method == .get && request.body == nil))
        throw BodyFlowCapabilityError.serviceUnavailable
    }
    func execute<Response: Decodable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> Response {
        requests.append(Read(path: request.path, query: request.queryItems,
            isGetWithoutBody: request.method == .get && request.body == nil))
        throw BodyFlowCapabilityError.serviceUnavailable
    }
}
