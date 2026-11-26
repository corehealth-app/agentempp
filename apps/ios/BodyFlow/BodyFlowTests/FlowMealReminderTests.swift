import Foundation
import Testing
@testable import BodyFlow

@Suite("Flow meal reminders")
struct FlowMealReminderTests {
    private actor Fixture: FlowMealReminderProviding {
        private(set) var skipped: [UUID] = []
        private var result: FlowMealReminder.State = .pending

        func reminder(id: UUID, skip: Bool) -> FlowMealReminder {
            if skip && result == .pending {
                skipped.append(id)
                result = .resolved
            }
            return FlowMealReminder(id: id, localDate: "2026-11-26", mealType: .dinner, state: result)
        }
    }

    @MainActor
    @Test("A reminder uses the actual diary state before preparing a response")
    func respondsOnlyToPendingReminder() async {
        let fixture = Fixture()
        let model = FlowMealReminderModel { fixture }
        let id = UUID()
        model.open(id)
        model.beginAnswer()
        #expect(model.answerMeal == nil)
        await model.refresh(alreadyLogged: true)
        #expect(model.hasNoMatchingMeal)
        model.beginAnswer()
        #expect(model.answerMeal == .jantar)
        await model.refresh(skip: true)
        #expect(model.reminder?.state == .resolved)
        #expect(model.answerMeal == nil)
        #expect(await fixture.skipped == [id])
        model.dismiss()
        #expect(model.reminder == nil)
        #expect(model.id == nil)
    }

    private actor Transport: MobileAPIEnvelopeExecuting {
        private(set) var method: HTTPMethod?
        private(set) var replay: MobileAPIUnauthorizedReplay?
        private(set) var path: String?
        private(set) var body: Data?
        let data: Data

        init(_ id: UUID) {
            data = Data("""
            {"data":{"id":"\(id.uuidString.lowercased())","local_date":"2026-11-26","meal_type":"jantar","state":"resolved"},
            "meta":{"api_version":"v1","request_id":"reminder-qa"}}
            """.utf8)
        }

        func executeEnvelope<Response: Codable & Sendable>(
            _ request: MobileAPIRequest<Response>
        ) throws -> MobileResponse<Response> {
            method = request.method
            replay = request.unauthorizedReplay
            path = request.path
            body = request.body
            return try JSONDecoder().decode(MobileResponse<Response>.self, from: data)
        }
    }

    @Test("Skipping uses the original notice and does not replay after a session failure")
    func skipTransport() async throws {
        let id = UUID()
        let transport = Transport(id)
        let reply = try await MobileFlowMealReminderRepository(transport: transport).reminder(id: id, skip: true)
        #expect(reply.id == id)
        #expect(reply.mealType == .dinner)
        #expect(await transport.method == .post)
        #expect(await transport.replay == .never)
        #expect(await transport.path == "/api/mobile/v1/conversation/meal-reminders/\(id.uuidString.lowercased())")
        #expect(await transport.body == Data(#"{"action":"skipped"}"#.utf8))
    }
}
