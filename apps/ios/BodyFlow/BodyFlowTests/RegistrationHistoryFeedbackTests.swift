import Foundation
import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

@MainActor
@Suite("C13 saved History feedback", .serialized)
struct RegistrationHistoryFeedbackTests {
    @Test("the real History strength host shows original feedback outside a not-applicable question")
    func realNotApplicableHostRendersFeedback() async throws {
        try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).contains { $0.isKeyWindow }, "Native hosting window required")
        #expect(historyPending != historyLog)
        let transport = HistoryFeedbackTransport(data: try historyEnvelope([
            "clarification": historyClarification("not_applicable"), "feedback": historySaved("workout")]))
        let session = WorkoutStrengthQuestionSession(
            provider: MobileWorkoutStrengthClarificationRepository(transport: transport), isSessionActive: { true })
        let configuration = WorkoutStrengthQuestionConfiguration(workoutID: historyLog,
            identity: .init(context: ObjectIdentifier(session), workoutID: historyLog), session: session,
            timeProvider: SystemTimeProvider(), keyProvider: RandomIdempotencyKeyProvider(),
            invalidationCenter: FeatureInvalidationCenter())
        let host = SignUpRenderingProbe.host(WorkoutStrengthQuestionHost(configuration: configuration,
            showsRegistrationFeedback: true).environment(\.locale, Locale(identifier: "pt_BR")), width: 393)
        defer { host.detach(); session.close() }
        let deadline = Date().addingTimeInterval(5)
        var nodes: [SignUpRenderingProbe.Node] = []
        repeat {
            await Task.yield()
            nodes = host.nodes()
            if nodes.contains(where: { $0.identifier == "registration.feedback.incentive"
                && $0.isElement && $0.label == "Original saved text" }) { break }
        } while Date() < deadline
        // A missing question or an empty tree alone must never pass this test.
        let incentive = try #require(nodes.first { $0.identifier == "registration.feedback.incentive"
            && $0.isElement && $0.label == "Original saved text" }, "Saved feedback absent: \(nodes)")
        #expect(incentive.frame.width > 0 && incentive.frame.height > 0)
        #expect(nodes.contains { $0.identifier == "registration.feedback.original" })
        #expect(!nodes.contains { ["workout.strength.question", "workout.strength.yes", "workout.strength.no"]
            .contains($0.identifier) })
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/workouts/\(historyLog)/strength-clarification")
        #expect(request.queryItems == [URLQueryItem(name: "include", value: "registration_feedback")])
        #expect(request.body == nil)
        #expect(session.retainedCount == 1)
    }

    @Test("workout read accepts the new wrapper and the old shape without equating pending and log IDs")
    func workoutReadContracts() async throws {
        for wrapped in [true, false] {
            let transport = HistoryFeedbackTransport(data: try historyEnvelope(
                wrapped ? ["clarification": historyClarification(), "feedback": historySaved("workout")] : historyClarification()))
            let response = try await MobileWorkoutStrengthClarificationRepository(transport: transport)
                .loadWithFeedback(workoutID: historyLog)
            #expect(response.data.clarification.workoutID == historyLog)
            #expect(response.data.feedback?.registrationID == (wrapped ? historyPending : nil))
            let requests = await transport.requests
            #expect(requests.count == 1)
            #expect(requests[0].method == .get)
            #expect(requests[0].path == "/api/mobile/v1/workouts/\(historyLog)/strength-clarification")
            #expect(requests[0].queryItems == [URLQueryItem(name: "include", value: "registration_feedback")])
            #expect(requests[0].body == nil)
        }
    }

    @Test("a malformed principal wrapper cannot downgrade to the old shape", arguments: ["null", "invalid"])
    func principalCannotDowngrade(_ variant: String) throws {
        var wire = historyClarification()
        wire["clarification"] = variant == "null" ? NSNull() : ["status": "unknown"]
        wire["feedback"] = historySaved("workout")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WorkoutStrengthHistorySnapshot.self,
                from: JSONSerialization.data(withJSONObject: wire))
        }
    }

    @Test("invalid optional workout feedback preserves the strict clarification", arguments: ["meal", "number", "null"])
    func optionalWorkout(_ variant: String) throws {
        let extra: Any = variant == "meal" ? historySaved("meal") : variant == "number" ? 1 : NSNull()
        let snapshot = try JSONDecoder().decode(WorkoutStrengthHistorySnapshot.self,
            from: JSONSerialization.data(withJSONObject: ["clarification": historyClarification(), "feedback": extra]))
        #expect(snapshot.clarification.workoutID == historyLog)
        #expect(snapshot.feedback == nil)
    }

    @Test("the legacy provider default calls the old reader exactly once")
    func legacyProviderDefault() async throws {
        let provider = LegacyHistoryStrengthProvider()
        let response = try await provider.loadWithFeedback(workoutID: historyLog)
        #expect(response.data.clarification.workoutID == historyLog)
        #expect(response.data.feedback == nil)
        #expect(await provider.reads == 1)
    }

    @Test("the saved feedback survives the official strength answer without an extra GET", arguments: [WorkoutStrengthAnswer.yes, .no])
    func answerPreservesFeedback(_ answer: WorkoutStrengthAnswer) async throws {
        let provider = HistoryStrengthProvider()
        let model = try strengthModel(provider)
        await model.load()
        let saved = try #require(model.feedback)
        #expect(model.canAnswer)
        await model.answer(answer)
        #expect(model.feedback == saved)
        guard case let .answered(receipt) = model.snapshot else { Issue.record("Missing official answer"); return }
        #expect(receipt.answer == answer)
        #expect(await provider.reads == 1)
        #expect(await provider.answers == 1)
    }

    @Test("late workout feedback cannot replace the winning read", arguments: [false, true])
    func workoutPublication(_ retireSession: Bool) async throws {
        let provider = HistoryStrengthProvider(held: true)
        let active = HistoryFeedbackActive()
        let model = try strengthModel(provider, active: active)
        let old = Task { await model.reload() }
        await provider.waitForReads(1)
        if retireSession {
            active.value = false
            await provider.release(0, text: "Late old text")
            await old.value
            #expect(model.snapshot == nil)
            #expect(model.feedback == nil)
        } else {
            let current = Task { await model.reload() }
            await provider.waitForReads(2)
            await provider.release(1, text: "Winning saved text")
            await current.value
            await provider.release(0, text: "Late old text")
            await old.value
            #expect(model.feedback?.incentive == "Winning saved text")
            #expect(model.snapshot?.workoutID == historyLog)
            #expect(model.readPublicationSequence == 1)
        }
    }

    @Test("read-only meal uses the existing owned GET once and preserves original feedback")
    func readOnlyMeal() async throws {
        let transport = HistoryFeedbackTransport(data: try historyEnvelope(historyMeal()))
        let model = try ReadOnlyMealFeedbackModel(recordID: historyLog,
            provider: MobileMealRecordRepository(transport: transport), isSessionActive: { true })
        await model.load()
        await model.load()
        #expect(model.feedback?.registrationID == historyPending)
        #expect(model.feedback?.mealTotals?.kcal == 155)
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].method == .get)
        #expect(requests[0].path == "/api/mobile/v1/meal-records/\(historyLog)")
        #expect(requests[0].queryItems == [URLQueryItem(name: "include", value: "registration_feedback")])
        #expect(requests[0].body == nil)
    }

    @Test("invalid meal enrichment is optional while malformed principal remains an error")
    func mealContracts() async throws {
        var meal = historyMeal(); meal["feedback"] = historySaved("workout")
        let transport = HistoryFeedbackTransport(data: try historyEnvelope(meal))
        let response = try await MobileMealRecordRepository(transport: transport).mealRecord(id: historyLog)
        #expect(response.data.recordID == historyLog)
        #expect(response.data.feedback == nil)
        meal["expected_version"] = NSNull()
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MealRecordSnapshot.self, from: JSONSerialization.data(withJSONObject: meal))
        }
    }

    @Test("leaving the meal or retiring its original session withdraws late publication", arguments: [false, true])
    func mealPublication(_ retireSession: Bool) async throws {
        let provider = HeldHistoryMealProvider()
        let active = HistoryFeedbackActive()
        let model = try ReadOnlyMealFeedbackModel(recordID: historyLog, provider: provider,
            isSessionActive: { active.value })
        let task = Task { await model.load() }
        await provider.waitForRead()
        if retireSession { active.value = false } else { model.cancel() }
        await provider.release()
        await task.value
        #expect(model.feedback == nil)
        #expect(!model.isLoading)
        #expect(await provider.reads == [historyLog])
        #expect(await provider.writes == 0)
    }
}

private let historyLog = "b2800000-0000-4000-8000-000000000001"
private let historyPending = "a1700000-0000-4000-8000-000000000001"
private let historyLifecycle = "c3900000-0000-4000-8000-000000000001"
private let historyQuestion = "d4a00000-0000-4000-8000-000000000001"

private func historyClarification(_ status: String = "not_applicable") -> [String: Any] {
    var value: [String: Any] = ["status": status, "workout_id": historyLog,
        "lifecycle_key": historyLifecycle, "fact_revision": 0]
    if status == "unanswered" { value["question_key"] = historyQuestion }
    return value
}
private func historySaved(_ kind: String, text: String = "Original saved text") -> [String: Any] {
    ["schema": "registration.feedback.v1", "registration_id": historyPending, "kind": kind, "locale": "pt-BR",
     "meal_totals": kind == "meal" ? ["kcal": 155, "protein_g": 23, "carbs_g": 4.5, "fat_g": 4.75] : NSNull(),
     "day": NSNull(), "lines": (kind == "meal" ? [["key": "meal_totals", "text": "155 kcal"]] : []) +
        [["key": "day_unavailable", "text": "Os dados deste dia estão indisponíveis."]],
     "food_comment": NSNull(), "incentive": text]
}
private func historyMeal() -> [String: Any] {
    ["record_id": historyLog, "scope": "item", "expected_version": "v1:original", "item_ids": [historyLog],
     "items": [["id": historyLog, "food_name": "nome editado", "quantity_g": 170, "kcal": 900,
                "protein_g": 10, "carbs_g": 20, "fat_g": 30, "source": "canonical_exact",
                "consumed_at": "2026-10-24T12:00:00Z", "meal_type": "almoco"]],
     "editable": false, "day_closed": true, "local_date": "2026-10-24", "timezone": "America/Sao_Paulo",
     "edit_block_reason": "MEAL_DAY_NOT_EDITABLE", "feedback": historySaved("meal")]
}
private func historyEnvelope(_ data: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["data": data,
        "meta": ["api_version": "v1", "request_id": "synthetic-history"]])
}
@MainActor private final class HistoryFeedbackActive { var value = true }
@MainActor private func strengthModel(_ provider: any WorkoutStrengthClarificationProviding,
                                    active: HistoryFeedbackActive = HistoryFeedbackActive()) throws -> WorkoutStrengthClarificationModel {
    try WorkoutStrengthClarificationModel(workoutID: historyLog, provider: provider,
        timeProvider: SystemTimeProvider(), keyProvider: RandomIdempotencyKeyProvider(),
        invalidationCenter: FeatureInvalidationCenter(), isSessionActive: { active.value })
}
private actor HistoryFeedbackTransport: MobileAPIEnvelopeExecuting {
    struct Recorded: Sendable { let method: HTTPMethod; let path: String; let queryItems: [URLQueryItem]; let body: Data? }
    let data: Data
    private(set) var requests: [Recorded] = []
    init(data: Data) { self.data = data }
    func executeEnvelope<Response: Codable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> MobileResponse<Response> {
        requests.append(.init(method: request.method, path: request.path, queryItems: request.queryItems, body: request.body))
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: data)
    }
}
private actor LegacyHistoryStrengthProvider: WorkoutStrengthClarificationProviding {
    private(set) var reads = 0
    func load(workoutID: String) throws -> WorkoutStrengthClarificationResponse {
        reads += 1
        return try JSONDecoder().decode(WorkoutStrengthClarificationResponse.self, from: historyEnvelope(historyClarification()))
    }
    func answer(_ attempt: MutationAttempt<WorkoutStrengthAnswerCommand>) throws -> WorkoutStrengthClarificationResponse {
        throw BodyFlowCapabilityError.serviceUnavailable
    }
}
private actor HistoryStrengthProvider: WorkoutStrengthClarificationProviding {
    private(set) var reads = 0
    private(set) var answers = 0
    let held: Bool
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var continuations: [Int: CheckedContinuation<String, Never>] = [:]
    init(held: Bool = false) { self.held = held }
    func load(workoutID: String) throws -> WorkoutStrengthClarificationResponse {
        throw BodyFlowCapabilityError.serviceUnavailable
    }
    func loadWithFeedback(workoutID: String) async throws -> WorkoutStrengthHistoryResponse {
        let index = reads; reads += 1
        let text: String
        if held {
            text = await withCheckedContinuation { continuations[index] = $0; resumeWaiters() }
        } else { text = "Original saved text"; resumeWaiters() }
        return try JSONDecoder().decode(WorkoutStrengthHistoryResponse.self,
            from: historyEnvelope(["clarification": historyClarification("unanswered"), "feedback": historySaved("workout", text: text)]))
    }
    func answer(_ attempt: MutationAttempt<WorkoutStrengthAnswerCommand>) throws -> WorkoutStrengthClarificationResponse {
        answers += 1
        var value = historyClarification("answered"); value["fact_revision"] = 1
        value["question_key"] = historyQuestion
        value["receipt"] = ["answer": attempt.payload.answer.rawValue, "accepted_at": "2026-10-24T12:00:00.123456Z"]
        return try JSONDecoder().decode(WorkoutStrengthClarificationResponse.self, from: historyEnvelope(value))
    }
    func waitForReads(_ count: Int) async {
        if reads >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    private func resumeWaiters() {
        let ready = waiters.filter { reads >= $0.0 }; waiters.removeAll { reads >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
    func release(_ index: Int, text: String) { continuations.removeValue(forKey: index)?.resume(returning: text) }
}
private actor HeldHistoryMealProvider: MealRecordProviding {
    private(set) var reads: [String] = []
    private(set) var writes = 0
    private var started: CheckedContinuation<Void, Never>?
    private var held: CheckedContinuation<Void, Never>?
    func mealRecord(id: String) async throws -> MealRecordResponse {
        reads.append(id)
        await withCheckedContinuation { held = $0; started?.resume(); started = nil }
        return try JSONDecoder().decode(MealRecordResponse.self, from: historyEnvelope(historyMeal()))
    }
    func waitForRead() async { if !reads.isEmpty { return }; await withCheckedContinuation { started = $0 } }
    func release() { held?.resume(); held = nil }
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) throws -> MealRecordMutationResponse { writes += 1; throw BodyFlowCapabilityError.serviceUnavailable }
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) throws -> MealRecordMutationResponse { writes += 1; throw BodyFlowCapabilityError.serviceUnavailable }
}
