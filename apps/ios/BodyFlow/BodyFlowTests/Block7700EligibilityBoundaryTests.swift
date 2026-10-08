import Foundation
import Testing

@testable import BodyFlow

/// C3: official current objective is independent of the historical day.
/// Stored values survive even when their presentation is not eligible.
@Suite("Flow block eligibility boundary")
struct Block7700EligibilityBoundaryTests {
    struct Case: Sendable {
        let currentProtocol: String?
        let flag: Bool
        let showsBlock: Bool
    }

    static let cases = [
        Case(currentProtocol: "recomposicao", flag: true, showsBlock: true),
        Case(currentProtocol: "ganho_massa", flag: false, showsBlock: false),
        Case(currentProtocol: "manutencao", flag: false, showsBlock: false),
        Case(currentProtocol: nil, flag: false, showsBlock: false),
        Case(currentProtocol: "desconhecido", flag: true, showsBlock: false),
        Case(currentProtocol: "RECOMPOSICAO", flag: true, showsBlock: false),
        Case(currentProtocol: "ganho_massa", flag: true, showsBlock: false),
        Case(currentProtocol: "recomposicao", flag: false, showsBlock: false),
    ]

    @Test("current protocol round trips independently of historical recomposition", arguments: cases)
    func todayContract(_ value: Case) throws {
        let snapshot = try today(value)
        let encoded = try object(snapshot)
        #expect(encoded["current_protocol"] as? String == value.currentProtocol)
        #expect(snapshot.protocolName == "recomposicao")
        #expect(snapshot.targets.caloriesKcal == 1_843)
        #expect(snapshot.consumed.caloriesKcal == 2_076)
        #expect(snapshot.exerciseKcal == 565)
        #expect(snapshot.dailyBalanceKcal == -832)
        #expect(snapshot.dailyBalanceReferenceKcal == 2_343)
        #expect(snapshot.dailyBalanceIncludesExercise == true)
        #expect(snapshot.foodExcessKcal == 233)
        #expect(snapshot.block7700?.currentKcal == 3_850)
        #expect(snapshot.block7700?.completedBlocks == 2)
        #expect(snapshot.block7700?.percentage == 50)
        #expect(snapshot.block7700?.totalCreditedKcal == 19_250)
    }

    @Test("Today sections omit block unless current objective and flag agree", arguments: cases)
    func todayPresentation(_ value: Case) throws {
        let snapshot = try today(value)
        let before = snapshot
        let presentation = TodayPresentation(snapshot: snapshot)
        #expect(presentation.sectionOrder.contains(.block) == value.showsBlock)
        #expect(presentation.energy.targetKcal == 1_843)
        #expect(presentation.energy.consumedKcal == 2_076)
        #expect(presentation.energy.dailyBalanceKcal == -832)
        #expect(snapshot == before)
    }

    @Test("Progress round trips the additive fields and all saved values", arguments: cases)
    func progressContract(_ value: Case) throws {
        let snapshot = try progress(value)
        let encoded = try object(snapshot)
        #expect(encoded["current_protocol"] as? String == value.currentProtocol)
        #expect(encoded["block_7700_enabled"] as? Bool == value.flag)
        #expect(snapshot.xpTotal == 1_240)
        #expect(snapshot.level == 2)
        #expect(snapshot.currentStreak == 3)
        #expect(snapshot.longestStreak == 7)
        #expect(snapshot.currentWeight == 80)
        #expect(snapshot.currentBodyFatPercent == nil)
        #expect(snapshot.deficitBlock == 3_120)
        #expect(snapshot.blocksCompleted == 4)
        #expect(snapshot.lastActiveDate == "2026-10-04")
        #expect(snapshot.nextReevaluation == "2026-10-18")
        #expect(snapshot.badgesEarned == ["Primeiro Bloco", "Primeira Semana", "badge-z", "Primeira Semana"])
    }

    @Test("only the block medal is hidden, without changing positional identity", arguments: cases)
    func medalPresentation(_ value: Case) throws {
        let snapshot = try progress(value)
        let before = snapshot
        let presentation = ProgressPresentation(snapshot: snapshot)
        let expected = value.showsBlock
            ? ["Primeiro Bloco", "Primeira Semana", "badge-z", "Primeira Semana"]
            : ["Primeira Semana", "badge-z", "Primeira Semana"]
        #expect(presentation.badges == expected)
        #expect(presentation.medalRows.map(\.text) == expected)
        #expect(presentation.medalRows.map(\.id.offset) == (value.showsBlock ? [0, 1, 2, 3] : [1, 2, 3]))
        #expect(presentation.xpText == "1.240 XP")
        #expect(presentation.levelText == "Nível 2")
        #expect(presentation.currentStreakText == "3 dias")
        #expect(presentation.longestStreakText == "7 dias")
        #expect(presentation.weightText == "80 kg")
        #expect(snapshot == before)
    }

    @Test("a legacy payload does not prove block eligibility")
    func missingFieldsHideBlockAndKeepData() throws {
        let legacyToday = try BodyFlowTestFixtures.decodeInconsistentToday().data
        #expect(!TodayPresentation(snapshot: legacyToday).sectionOrder.contains(.block))
        var raw = try object(BodyFlowTestFixtures.progressSnapshot)
        raw["badges_earned"] = ["Primeiro Bloco", "Primeira Semana"]
        let snapshot = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
        #expect(ProgressPresentation(snapshot: snapshot).badges == ["Primeira Semana"])
        #expect(snapshot.deficitBlock == BodyFlowTestFixtures.progressSnapshot.deficitBlock)
        #expect(snapshot.badgesEarned == ["Primeiro Bloco", "Primeira Semana"])
    }

    @Test("historical muscle gain retains +142 after current recomposition enables the block")
    func historicalGainDoesNotChooseCurrentObjective() throws {
        var raw = try object(today(Self.cases[0]))
        raw["protocol"] = "ganho_massa"
        var targets = try #require(raw["targets"] as? [String: Any])
        targets["calories_kcal"] = 2_980
        raw["targets"] = targets
        var consumed = try #require(raw["consumed"] as? [String: Any])
        consumed["calories_kcal"] = 2_980
        raw["consumed"] = consumed
        raw["exercise_kcal"] = 322
        raw["daily_balance_kcal"] = 142
        raw["daily_balance_reference_kcal"] = 2_838
        raw["daily_balance_includes_exercise"] = false
        let snapshot = try JSONDecoder().decode(TodaySnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
        let presentation = TodayPresentation(snapshot: snapshot)
        #expect(presentation.sectionOrder.contains(.block))
        #expect(snapshot.protocolName == "ganho_massa")
        #expect(snapshot.dailyBalanceReferenceKcal == 2_838)
        #expect(presentation.energy.targetKcal == 2_980)
        #expect(presentation.energy.consumedKcal == 2_980)
        #expect(presentation.energy.exerciseKcal == 322)
        #expect(presentation.energy.dailyBalanceKcal == 142)
        #expect(!presentation.energy.dailyBalanceIncludesExercise)
    }

    @Test("direct block detail requires current objective and flag", arguments: cases)
    @MainActor
    func directDetail(_ value: Case) async throws {
        let snapshot = try today(value)
        let model = Block7700ViewModel(today: BoundaryTodayQueue([
            .success(TodayResponse(data: snapshot, meta: BodyFlowTestFixtures.todayResponseWithBlock.meta)),
        ]))
        await model.load()
        #expect((model.descriptor != nil) == value.showsBlock)
        if value.showsBlock {
            #expect(model.descriptor?.currentKcal == 3_850)
            #expect(model.descriptor?.totalCreditedKcal == 19_250)
        }
    }

    @Test("an ineligible read clears a previous block before offline or failed retry", arguments: [
        BodyFlowCapabilityError.offline, .serviceUnavailable,
    ])
    @MainActor
    func ineligibleThenError(_ error: BodyFlowCapabilityError) async throws {
        let enabled = TodayResponse(data: try today(Self.cases[0]), meta: BodyFlowTestFixtures.todayResponseWithBlock.meta)
        let gain = TodayResponse(data: try today(Self.cases[1]), meta: enabled.meta)
        let model = Block7700ViewModel(today: BoundaryTodayQueue([
            .success(enabled), .success(gain), .failure(error),
        ]))
        await model.load()
        #expect(model.descriptor?.currentKcal == 3_850)
        await model.retry()
        #expect(model.descriptor == nil)
        await model.retry()
        #expect(model.descriptor == nil)
        let presentation = Block7700DetailPresentation(state: model.state)
        #expect(presentation.descriptor == nil)
        #expect(presentation.policy == .ineligible)
        #expect(presentation.showsStaleBanner && presentation.showsRetry)
    }

    @Test("eligibility fails closed for absent, invalid and contradictory context")
    func policyMatrix() {
        let matrix: [(String?, Bool?, Block7700PresentationPolicy)] = [
            ("recomposicao", true, .enabled), ("recomposicao", false, .unknown), ("recomposicao", nil, .unknown),
            ("ganho_massa", true, .unknown), ("ganho_massa", false, .ineligible), ("ganho_massa", nil, .unknown),
            ("manutencao", true, .unknown), ("manutencao", false, .ineligible), ("manutencao", nil, .unknown),
            (nil, true, .unknown), (nil, false, .unknown), (nil, nil, .unknown),
            ("desconhecido", true, .unknown), ("desconhecido", false, .unknown), ("desconhecido", nil, .unknown),
            ("RECOMPOSICAO", true, .unknown), ("RECOMPOSICAO", false, .unknown), ("RECOMPOSICAO", nil, .unknown),
        ]
        for (currentProtocol, flag, expected) in matrix {
            let policy = Block7700PresentationPolicy(currentProtocol: currentProtocol, enabled: flag)
            #expect(policy == expected)
            #expect(policy.showsBlock == (expected == .enabled))
            #expect(policy.showsExplanation == (expected == .ineligible))
        }
    }

    @Test("malformed flags are rejected, never coerced or treated as absent")
    func malformedFlags() throws {
        var rawToday = try object(today(Self.cases[0]))
        var block = try #require(rawToday["block_7700"] as? [String: Any])
        block["enabled"] = "false"
        rawToday["block_7700"] = block
        let todayData = try JSONSerialization.data(withJSONObject: rawToday)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(TodaySnapshot.self, from: todayData) }
        var rawProgress = try object(progress(Self.cases[1]))
        rawProgress["block_7700_enabled"] = "false"
        let progressData = try JSONSerialization.data(withJSONObject: rawProgress)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ProgressSnapshot.self, from: progressData) }
        rawProgress["block_7700_enabled"] = NSNull()
        let missing = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONSerialization.data(withJSONObject: rawProgress))
        #expect(missing.blockPresentationPolicy == .unknown)
        #expect(missing.deficitBlock == 3_120)
    }

    @Test("an older recomposition result or error cannot overwrite a newer ineligible detail", arguments: [false, true])
    @MainActor
    func lateDetail(_ returnsError: Bool) async throws {
        let enabled = TodayResponse(data: try today(Self.cases[0]), meta: BodyFlowTestFixtures.todayResponseWithBlock.meta)
        let gain = TodayResponse(data: try today(Self.cases[1]), meta: enabled.meta)
        let provider = BoundaryControlledToday()
        let model = Block7700ViewModel(today: provider)
        let older = Task { await model.load() }
        await provider.waitForCall(1)
        let newer = Task { await model.load() }
        await provider.waitForCall(2)
        await provider.finish(2, with: .success(gain))
        await newer.value
        await provider.finish(1, with: returnsError ? .failure(.serviceUnavailable) : .success(enabled))
        await older.value
        #expect(model.blockPolicy == .ineligible)
        #expect(model.descriptor == nil)
        #expect(!Block7700DetailPresentation(state: model.state).showsStaleBanner)
    }

    @Test("the trail hides only the block node and keeps the other official facts", arguments: SupportedAppLanguage.allCases)
    func trailSelection(_ language: SupportedAppLanguage) throws {
        let enabled = TodayTrailDescriptor(recordCount: 3, remainingFood: "731 kcal", blockPercentage: 50,
            showsBlock7700: true, language: language)
        let hidden = TodayTrailDescriptor(recordCount: 3, remainingFood: "731 kcal", blockPercentage: 50,
            showsBlock7700: false, language: language)
        #expect(hidden.nodes.map(\.kind) == [.register, .today, .progress])
        #expect(hidden.nodes == enabled.nodes.filter { $0.kind != .block })
        #expect(!hidden.showsBlock7700)
        let detail = try AppLocalization.string("today.trail.detail.without-block", for: language)
        #expect(!detail.lowercased().contains("bloco") && !detail.lowercased().contains("block"))
        #expect(detail != "today.trail.detail.without-block")
    }

    private func today(_ value: Case) throws -> TodaySnapshot {
        var raw = try object(BodyFlowTestFixtures.decodeInconsistentToday().data)
        raw["current_protocol"] = value.currentProtocol.map { $0 as Any } ?? NSNull()
        raw["protocol"] = "recomposicao"
        var targets = try #require(raw["targets"] as? [String: Any])
        targets["calories_kcal"] = 1_843
        raw["targets"] = targets
        var consumed = try #require(raw["consumed"] as? [String: Any])
        consumed["calories_kcal"] = 2_076
        raw["consumed"] = consumed
        raw["exercise_kcal"] = 565
        raw["daily_balance_kcal"] = -832
        raw["daily_balance_reference_kcal"] = 2_343
        raw["daily_balance_includes_exercise"] = true
        raw["food_excess_kcal"] = 233
        raw["block_7700"] = ["enabled": value.flag, "availability": "available", "target_kcal": 7_700,
            "current_kcal": 3_850, "percentage": 50, "completed_blocks": 2, "total_credited_kcal": 19_250,
            "source": "user_progress"] as [String: Any]
        return try JSONDecoder().decode(TodaySnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    private func progress(_ value: Case) throws -> ProgressSnapshot {
        var raw = try object(BodyFlowTestFixtures.progressSnapshot)
        raw["current_protocol"] = value.currentProtocol.map { $0 as Any } ?? NSNull()
        raw["block_7700_enabled"] = value.flag
        raw["xp_total"] = 1_240
        raw["level"] = 2
        raw["current_streak"] = 3
        raw["longest_streak"] = 7
        raw["current_weight"] = 80
        raw["current_bf_percent"] = NSNull()
        raw["deficit_block"] = 3_120
        raw["blocks_completed"] = 4
        raw["last_active_date"] = "2026-10-04"
        raw["next_reevaluation"] = "2026-10-18"
        raw["badges_earned"] = ["Primeiro Bloco", "Primeira Semana", "badge-z", "Primeira Semana"]
        return try JSONDecoder().decode(ProgressSnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}

private actor BoundaryTodayQueue: TodayProviding {
    enum Outcome: Sendable {
        case success(TodayResponse)
        case failure(BodyFlowCapabilityError)
    }
    private var outcomes: [Outcome]
    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }
    func today() async throws -> TodayResponse {
        guard !outcomes.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
        switch outcomes.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }
}

private actor BoundaryControlledToday: TodayProviding {
    private var calls = 0
    private var continuations: [Int: CheckedContinuation<TodayResponse, any Error>] = [:]
    func today() async throws -> TodayResponse {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { continuations[call] = $0 }
    }
    func waitForCall(_ count: Int) async { while calls < count { await Task.yield() } }
    func finish(_ call: Int, with result: Result<TodayResponse, BodyFlowCapabilityError>) {
        guard let continuation = continuations.removeValue(forKey: call) else { return }
        switch result {
        case let .success(response): continuation.resume(returning: response)
        case let .failure(error): continuation.resume(throwing: error)
        }
    }
}
