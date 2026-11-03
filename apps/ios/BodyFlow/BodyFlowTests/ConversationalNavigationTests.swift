import Foundation
import SwiftUI
import Testing
@testable import BodyFlow

@MainActor
@Suite("Conversational navigation candidate preserves legacy identity")
struct ConversationalNavigationTests {
    @Test("four-tab preview requires Debug, demo, non-real identity and explicit argument")
    func previewGate() {
        let flag = [AppNavigationLayout.previewArgument]
        #expect(AppNavigationLayout.resolve(arguments: flag, buildFlavor: .debug, runtimeMode: .demo,
            presentsRealAccountIdentity: false) == .conversationalPreview)
        for flavor in [AppBuildFlavor.debug, .release] {
            for mode in [AppRuntimeMode.demo, .releaseUnavailable] {
                for real in [false, true] {
                    for arguments in [[], flag] {
                        let result = AppNavigationLayout.resolve(arguments: arguments, buildFlavor: flavor,
                            runtimeMode: mode, presentsRealAccountIdentity: real)
                        let admitted = flavor == .debug && mode == .demo && !real && !arguments.isEmpty
                        #expect((result == .conversationalPreview) == admitted)
                    }
                }
            }
        }
    }

    @Test("candidate changes only visible presentation while all persisted raw values remain valid")
    func labelsAndIdentity() {
        let layout = AppNavigationLayout.conversationalPreview
        #expect(AppNavigationLayout.legacy.visibleTabs == AppTab.displayOrder)
        #expect(layout.visibleTabs == [.today, .plan, .register, .progress])
        #expect(layout.visibleTabs.map { layout.title(for: $0, language: .portugueseBrazil) } == ["Flow", "Alimentação", "Treino", "Jornada"])
        #expect(layout.visibleTabs.map { layout.title(for: $0, language: .englishUnitedStates) } == ["Flow", "Nutrition", "Training", "Journey"])
        #expect(layout.visibleTabs.map { layout.systemImage(for: $0) } == ["bubble.left", "fork.knife", "dumbbell", "chart.bar"])
        #expect(AppTab.allCases.map(\.rawValue) == ["today", "register", "plan", "progress", "profile"])
        #expect(AppTab.allCases.allSatisfy { AppTab(rawValue: $0.rawValue) == $0 })
        #expect(layout.visibleTabs.map(\.accessibilityIdentifier) == ["tab.hoje", "tab.plano", "tab.registrar", "tab.progresso"])
    }

    @Test("known workout and food routes choose domain host and active origin is retained")
    func domainAndOriginHosts() {
        let layout = AppNavigationLayout.conversationalPreview
        let workout = AppRoute.historyWorkout(logID: "workout")
        let meal = AppRoute.historyMealLog(rowID: "meal")
        #expect(workout.tab == .today)
        #expect(meal.tab == .today)
        #expect(AppRoute.plan(.detail).tab == .plan)
        #expect(layout.presentationHost(for: workout) == .register)
        #expect(layout.presentationHost(for: meal) == .plan)
        #expect(layout.presentationHost(for: .plan(.detail), from: .register) == .register)
        #expect(layout.presentationHost(for: workout, from: .register) == .register)
        #expect(layout.presentationHost(for: meal, from: .today) == .today)
        #expect(layout.presentationHost(for: .legacyRoot(.register)) == .today)
        #expect(layout.presentationHost(for: .legacyRoot(.profile)) == .progress)
        #expect(AppNavigationLayout.legacy.presentationHost(for: workout, from: .register) == .today)
    }

    @Test("native path bindings retain secondary routes in active stack without rewriting route identity")
    func nativeBindingsAndProgrammaticRoutes() {
        let router = AppRouter(layout: .conversationalPreview)
        let workout = AppRoute.historyWorkout(logID: "saved")
        let plan = AppRoute.plan(.detail)
        let host = router.open(workout)
        #expect(host == .register)
        router.binding(for: host).wrappedValue.append(plan)
        #expect(router.path(for: .register) == [workout, plan])
        #expect(router.path(for: .plan).isEmpty)
        #expect(router.open(.legacyRoot(.profile), from: .today) == .today)
        router.binding(for: .today).wrappedValue.append(.localReminders)
        #expect(router.path(for: .today) == [.legacyRoot(.profile), .localReminders])
        #expect(router.path(for: .register) == [workout, plan])
        router.navigate(to: .localReminders, in: .today)
        #expect(router.path(for: .today) == [.legacyRoot(.profile), .localReminders])
        router.navigate(to: .currentObjective, in: .profile)
        #expect(router.path(for: .progress) == [.currentObjective])
        #expect(router.path(for: .profile) == [.currentObjective])
    }

    @Test("legacy entry opens real original roots and meal sheet does not select Training")
    func legacyEntriesAndRegistration() {
        let router = AppRouter(layout: .conversationalPreview)
        for tab in AppTab.allCases {
            let host = router.openLegacyTab(tab)
            #expect(router.path(for: host).last == .legacyRoot(tab))
        }
        let before = AppTab.allCases.map { router.path(for: $0) }
        router.presentedSheet = .registration(.meal)
        #expect(router.presentedSheet?.id == "sheet.registrar.refeicao")
        #expect(AppTab.allCases.map { router.path(for: $0) } == before)
    }

    @Test("new shell router starts empty and resetting old shell removes only its routes and sheet")
    func sessionRootState() {
        let old = AppRouter(layout: .conversationalPreview)
        _ = old.open(.historyMealLog(rowID: "account-a"))
        old.presentedSheet = .registration(.training)
        let new = AppRouter(layout: .conversationalPreview)
        #expect(AppTab.allCases.allSatisfy { new.path(for: $0).isEmpty })
        #expect(new.presentedSheet == nil)
        _ = new.open(.historyWorkout(logID: "account-b"))
        old.reset()
        #expect(AppTab.allCases.allSatisfy { old.path(for: $0).isEmpty })
        #expect(old.presentedSheet == nil)
        #expect(new.path(for: .register) == [.historyWorkout(logID: "account-b")])
    }

    @Test("domain plan reads preserve saved values and do not fabricate absent training or nutrition")
    func officialDomainAvailability() throws {
        let data = Data("""
        {"training":{"id":"synthetic-plan","plan_type":"full_body","days_per_week":3,
        "generated_at":"2026-11-03T12:00:00Z","weekly_schedule":[{"day":"Segunda","focus":"Força",
        "duration_min":40,"exercises":[{"name":"Agachamento","sets":3,"reps_range":"8–12","rest_seconds":60}]}]},"nutrition":[]}
        """.utf8)
        let snapshot = try JSONDecoder().decode(PlanSnapshot.self, from: data)
        let presentation = PlanPresentation(snapshot: snapshot)
        #expect(!presentation.isEmpty(in: .all))
        #expect(!presentation.isEmpty(in: .training))
        #expect(presentation.isEmpty(in: .nutrition))
        #expect(presentation.trainingDays.first?.exercises.first?.title == "Agachamento")
        #expect(presentation.trainingDays.first?.exercises.first?.value == "3 × 8–12 · descanso 60 s")
        let empty = PlanPresentation(snapshot: PlanSnapshot(training: nil, nutrition: []))
        #expect(empty.isEmpty(in: .training) && empty.isEmpty(in: .nutrition))
    }

    @Test("preview Flow scopes and reads but no direct or scoped send reaches old writer")
    func noLegacyFlowWriter() async throws {
        let source = NavigationFlowSpy()
        let candidate = ReadOnlyFlowChatRepository(source: source)
        _ = try await candidate.history(limit: 10)
        let scoped = try await candidate.scoped(for: "synthetic-owner")
        _ = try await scoped.history(limit: 3)
        let key = try IdempotencyKey(validating: "navigation-only")
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) { try await candidate.send(text: "Comi arroz", idempotencyKey: key) }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) { try await scoped.send(text: "Retry", idempotencyKey: key) }
        #expect(await source.readLimits == [10, 3])
        #expect(await source.owners == ["synthetic-owner"])
        #expect(await source.sends == 0)
    }
}

private actor NavigationFlowSpy: FlowChatProviding {
    private(set) var readLimits: [Int] = []
    private(set) var owners: [String] = []
    private(set) var sends = 0
    func scoped(for userID: String) -> any FlowChatProviding { owners.append(userID); return self }
    func history(limit: Int) -> FlowHistoryResponse { readLimits.append(limit); return .init(conversationID: "synthetic", messages: []) }
    func send(text: String, idempotencyKey: IdempotencyKey) throws -> FlowSendResponse {
        sends += 1; throw BodyFlowCapabilityError.invalidInput
    }
}
