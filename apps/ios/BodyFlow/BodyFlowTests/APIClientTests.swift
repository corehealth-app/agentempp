import Foundation
import Testing

@testable import BodyFlow

@Suite("API Client")
struct APIClientTests {
    @Test("decodes a typed server-shaped fixture")
    func decodesTypedFixture() async throws {
        let payload = Data(
            """
            {
              "local_date": "2026-07-26",
              "energy": {
                "consumed_kcal": 1200,
                "target_kcal": 1935,
                "remaining_food_kcal": 735
              },
              "routine": {
                "status_label": "3 de 5 concluídos",
                "next_item_label": "Hidratação às 16:00"
              },
              "next_action": {
                "id": "register-lunch",
                "title": "Registrar almoço",
                "detail": "Adicione o que você consumiu."
              },
              "calculation_version": "bodyflow.daily-state.v2"
            }
            """.utf8
        )
        let request = APIRequest<TodaySummary>(method: .get, path: "/today")
        let client = MockAPIClient(payloads: [request.key: payload])

        let summary = try await client.send(request)

        #expect(summary.energy.remainingFoodKcal == 735)
        #expect(summary.calculationVersion == "bodyflow.daily-state.v2")
    }

    @Test("throws a controlled fixture failure for the matching request")
    func throwsControlledFixtureFailure() async {
        let request = APIRequest<TodaySummary>(method: .get, path: "/today")
        let client = MockAPIClient(failures: [request.key: .fixtureFailure])

        do {
            _ = try await client.send(request)
            Issue.record("Expected the configured fixture failure")
        } catch let error as APIClientError {
            #expect(error == .fixtureFailure)
        } catch {
            Issue.record("Expected APIClientError, received \(type(of: error))")
        }
    }

    @Test("propagates cancellation while a mock response is delayed")
    func propagatesCancellation() async {
        let request = APIRequest<TodaySummary>(method: .get, path: "/today")
        let client = MockAPIClient(delay: .seconds(60))
        let task = Task {
            try await client.send(request)
        }

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected delayed request cancellation")
        } catch is CancellationError {
            // Expected: Task.sleep(for:) preserves structured cancellation.
        } catch {
            Issue.record("Expected CancellationError, received \(type(of: error))")
        }
    }
}
