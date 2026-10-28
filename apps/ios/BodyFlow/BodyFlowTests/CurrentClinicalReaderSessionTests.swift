import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Clinical shell reader session composition", .serialized)
struct CurrentClinicalReaderSessionTests {
    @Test("Requested current mode binds before a shell can render; failure never falls back")
    func failedBindingDoesNotRenderLegacyOwner() async throws {
        var dependencies = AppDependencies.scaffold()
        let counter = ClinicalReaderBindCounter()
        dependencies.currentClinicalReadSessions = CurrentClinicalReaderSessionFactory { userID in
            await counter.record(userID)
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        let coordinator = Prompt14AuthenticatedShellCoordinator(dependencies: dependencies)
        await coordinator.transition(to: "auth-A")
        #expect(await counter.users == ["auth-A"])
        #expect(coordinator.renderableOwner == nil)
        #expect(coordinator.hasReaderBindingFailure(for: "auth-A"))
        #expect(!coordinator.hasReaderBindingFailure(for: "auth-B"))
        await coordinator.transition(to: nil)
        #expect(!coordinator.readerBindingFailed)
    }
    @Test("A suspended old bind cannot replace the latest shell or publish its error", arguments: [false, true])
    func oldBindingCannotPublish(_ failure: Bool) async throws {
        var dependencies = AppDependencies.scaffold()
        let hold = ClinicalReaderBindHold()
        let counter = ClinicalReaderBindCounter()
        let probe = ClinicalShellReadProbe()
        dependencies.currentClinicalReadSessions = CurrentClinicalReaderSessionFactory { userID in
            await counter.record(userID)
            if userID == "auth-A" {
                await hold.pause()
                if failure { throw BodyFlowCapabilityError.serviceUnavailable }
            }
            return Self.bundle(userID: userID, probe: probe)
        }
        let coordinator = Prompt14AuthenticatedShellCoordinator(dependencies: dependencies)
        let old = Task { await coordinator.transition(to: "auth-A") }
        await hold.waitUntilStarted()
        #expect(coordinator.renderableOwner == nil)
        await coordinator.transition(to: "auth-C")
        let ownerC = try #require(coordinator.renderableOwner)
        await hold.release()
        await old.value
        #expect(coordinator.renderableOwner === ownerC)
        #expect(!coordinator.readerBindingFailed)
        #expect(await counter.users == ["auth-A", "auth-C"])
        await coordinator.transition(to: nil)
    }

    @Test("Each new activation gets fresh readers; repeated rendering never rebinds")
    func sameUserNewActivationBindsAgain() async throws {
        var dependencies = AppDependencies.scaffold()
        let counter = ClinicalReaderBindCounter(), probe = ClinicalShellReadProbe()
        dependencies.currentClinicalReadSessions = CurrentClinicalReaderSessionFactory { userID in
            await counter.record(userID)
            return Self.bundle(userID: userID, probe: probe)
        }
        let coordinator = Prompt14AuthenticatedShellCoordinator(dependencies: dependencies)
        await coordinator.transition(to: "auth-A")
        let old = try #require(coordinator.renderableOwner)
        await coordinator.transition(to: "auth-A")
        #expect(coordinator.renderableOwner === old)
        #expect(await counter.users == ["auth-A"])
        await coordinator.transition(to: nil)
        await coordinator.transition(to: "auth-A")
        let new = try #require(coordinator.renderableOwner)
        #expect(new !== old)
        #expect(old.isInvalidated && !old.hasRetainedCapabilities)
        #expect(await counter.users == ["auth-A", "auth-A"])
        await #expect(throws: CancellationError.self) { _ = try await old.today.today() }
        await coordinator.transition(to: nil)
    }

    @Test("All clinical shell read surfaces use the bound bundle and the owner publication gate")
    func allReadersUseOwnerGate() async throws {
        var dependencies = AppDependencies.scaffold()
        let probe = ClinicalShellReadProbe()
        dependencies.currentClinicalReadSessions = CurrentClinicalReaderSessionFactory {
            Self.bundle(userID: $0, probe: probe)
        }
        let coordinator = Prompt14AuthenticatedShellCoordinator(dependencies: dependencies)
        await coordinator.transition(to: "auth-A")
        let owner = try #require(coordinator.renderableOwner)
        await owner.awaitPatientTimeZoneResolution()
        let objective = try #require(owner.currentObjective)
        await #expect(throws: ClinicalReaderProbeFailure.called) { _ = try await owner.today.today() }
        await #expect(throws: ClinicalReaderProbeFailure.called) { _ = try await owner.plan.plan() }
        await #expect(throws: ClinicalReaderProbeFailure.called) { _ = try await owner.history.history(.firstPage) }
        await #expect(throws: ClinicalReaderProbeFailure.called) { _ = try await owner.progress.progress() }
        await #expect(throws: ClinicalReaderProbeFailure.called) { _ = try await owner.progress.profileWeight() }
        await #expect(throws: ClinicalReaderProbeFailure.called) { _ = try await owner.progress.trends(days: 7) }
        await #expect(throws: ClinicalReaderProbeFailure.called) { _ = try await objective.currentObjective() }
        #expect(Set(await probe.calls) == ["me", "today", "plan", "history", "progress", "profile", "trends", "objective"])
        let before = await probe.calls
        await coordinator.transition(to: nil)
        await #expect(throws: CancellationError.self) { _ = try await owner.today.today() }
        await #expect(throws: CancellationError.self) { _ = try await owner.plan.plan() }
        await #expect(throws: CancellationError.self) { _ = try await owner.history.history(.firstPage) }
        await #expect(throws: CancellationError.self) { _ = try await owner.progress.progress() }
        await #expect(throws: CancellationError.self) { _ = try await objective.currentObjective() }
        #expect(await probe.calls == before)
        #expect(!owner.hasRetainedCapabilities)
    }

    @Test("A current bind failure can retry, and a mismatched owner never renders")
    func failureRetryAndOwnerMismatch() async throws {
        var dependencies = AppDependencies.scaffold()
        let counter = ClinicalReaderBindCounter(), probe = ClinicalShellReadProbe()
        dependencies.currentClinicalReadSessions = CurrentClinicalReaderSessionFactory { userID in
            await counter.record(userID)
            let first = await counter.users.count == 1
            return Self.bundle(userID: first ? "auth-B" : userID, probe: probe)
        }
        let coordinator = Prompt14AuthenticatedShellCoordinator(dependencies: dependencies)
        await coordinator.transition(to: "auth-A")
        #expect(coordinator.readerBindingFailed && coordinator.renderableOwner == nil)
        await coordinator.transition(to: "auth-A")
        #expect(coordinator.renderableOwner?.userID == "auth-A")
        #expect(!coordinator.readerBindingFailed)
        await coordinator.transition(to: nil)
    }

    @Test("Cancelled bind never creates a shell or a retry error")
    func cancelledBindingDoesNotPublish() async throws {
        var dependencies = AppDependencies.scaffold()
        let hold = ClinicalReaderBindHold(), probe = ClinicalShellReadProbe()
        dependencies.currentClinicalReadSessions = CurrentClinicalReaderSessionFactory { userID in
            await hold.pause()
            return Self.bundle(userID: userID, probe: probe)
        }
        let coordinator = Prompt14AuthenticatedShellCoordinator(dependencies: dependencies)
        let task = Task { await coordinator.transition(to: "auth-A") }
        await hold.waitUntilStarted()
        task.cancel()
        await hold.release()
        await task.value
        #expect(coordinator.renderableOwner == nil && !coordinator.readerBindingFailed)
        await coordinator.transition(to: nil)
    }

    nonisolated private static func bundle(userID: String, probe: ClinicalShellReadProbe) -> CurrentClinicalReaderSession {
        .init(userID: userID, today: probe, history: probe, plan: probe,
              progress: probe, me: probe, currentObjective: probe)
    }
}

private actor ClinicalReaderBindHold {
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        started = true
        await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
private enum ClinicalReaderProbeFailure: Error { case called }
private actor ClinicalShellReadProbe: TodayProviding, HistoryProviding, PlanProviding,
    ProgressProviding, MeProviding, CurrentObjectiveProviding {
    private(set) var calls: [String] = []
    func today() async throws -> TodayResponse { calls.append("today"); throw ClinicalReaderProbeFailure.called }
    func history(_ query: HistoryQuery) async throws -> HistoryResponse { calls.append("history"); throw ClinicalReaderProbeFailure.called }
    func plan() async throws -> PlanResponse { calls.append("plan"); throw ClinicalReaderProbeFailure.called }
    func progress() async throws -> ProgressResponse { calls.append("progress"); throw ClinicalReaderProbeFailure.called }
    func profileWeight() async throws -> ProfileWeightResponse? { calls.append("profile"); throw ClinicalReaderProbeFailure.called }
    func trends(days: Int) async throws -> TrendsResponse { calls.append("trends"); throw ClinicalReaderProbeFailure.called }
    func me() async throws -> MeResponse { calls.append("me"); throw ClinicalReaderProbeFailure.called }
    func currentObjective() async throws -> CurrentObjectiveSnapshot { calls.append("objective"); throw ClinicalReaderProbeFailure.called }
}

private actor ClinicalReaderBindCounter {
    private(set) var users: [String] = []
    func record(_ userID: String) { users.append(userID) }
}
