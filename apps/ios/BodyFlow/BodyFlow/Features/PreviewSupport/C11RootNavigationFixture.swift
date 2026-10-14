#if DEBUG
import Foundation
import Observation
import SwiftUI

/// Requires an explicit DEBUG UI-test choice. Normal launches never select this fixture.
enum C11RootNavigationSelection: String, Sendable {
    case sourceOn = "on"
    case sourceOff = "off"
    case logoutMarkerFailure = "h05-marker-failure"
    case sameRecordForeground = "same-record-foreground"
    case getUnauthorizedThenSuccess = "get-401-200"
    case getUnauthorizedTwice = "get-401-401"
    case getUnauthorizedTwiceThenRetrySuccess = "get-401-401-retry-200"
    case patchUnauthorizedThenSuccess = "patch-401-200"
    case deleteUnauthorizedThenSuccess = "delete-401-200"
    case observeCompleted401 = "observe-completed401"
    case observeDeliveryFailure = "observe-delivery-failure"
    case observeDeliveryCancellation = "observe-delivery-cancellation"
    case completed401Foreground = "held401-foreground"
    case newCredentialRefresh = "new-credential-refresh"

    var observesDelivery: Bool {
        self == .observeCompleted401 || self == .observeDeliveryFailure || self == .observeDeliveryCancellation
    }

    static func resolve(arguments: [String]) -> Self? {
        guard arguments.contains("--ui-testing") else { return nil }
        let choices: [(Self, String)] = [
            (.sourceOn, "--ui-testing-c11-root-source-on"),
            (.sourceOff, "--ui-testing-c11-root-source-off"),
            (.logoutMarkerFailure, "--ui-testing-c11-root-h05-marker-failure"),
            (.sameRecordForeground, "--ui-testing-c11-root-same-record-foreground-restore"),
            (.getUnauthorizedThenSuccess, "--ui-testing-c11-root-get-401-200"),
            (.getUnauthorizedTwice, "--ui-testing-c11-root-get-401-401"),
            (.getUnauthorizedTwiceThenRetrySuccess, "--ui-testing-c11-root-get-401-401-retry-200"),
            (.patchUnauthorizedThenSuccess, "--ui-testing-c11-root-patch-401-200"),
            (.deleteUnauthorizedThenSuccess, "--ui-testing-c11-root-delete-401-200"),
            (.observeCompleted401, "--ui-testing-c11-root-observe-completed401"),
            (.observeDeliveryFailure, "--ui-testing-c11-root-observe-delivery-failure"),
            (.observeDeliveryCancellation, "--ui-testing-c11-root-observe-delivery-cancellation"),
            (.completed401Foreground, "--ui-testing-c11-root-held401-foreground"),
            (.newCredentialRefresh, "--ui-testing-c11-root-new-credential-refresh")
        ]
        let selected = choices.filter { arguments.contains($0.1) }
        guard selected.count == 1 else { return nil }
        return selected[0].0
    }

    var suppliesMealRecordSource: Bool {
        switch self {
        case .sourceOn, .logoutMarkerFailure, .sameRecordForeground, .getUnauthorizedThenSuccess, .getUnauthorizedTwice, .getUnauthorizedTwiceThenRetrySuccess, .patchUnauthorizedThenSuccess, .deleteUnauthorizedThenSuccess: true
        case .observeCompleted401, .observeDeliveryFailure, .observeDeliveryCancellation, .completed401Foreground, .newCredentialRefresh: true
        case .sourceOff: false
        }
    }
}

/// Synthetic app-process dependencies; Root executes the only initial auth restore.
/// This is a harness bootstrap, not a new authentication implementation.
@MainActor
struct C11RootNavigationFixture {
    let selection: C11RootNavigationSelection
    let configuration: AppLaunchConfiguration
    let dependencies: AppDependencies
    let probe: C11RootNavigationProbe
    fileprivate let held401Checkpoint: C11RootHeld401Checkpoint?
    fileprivate let newCredentialDriver: C11RootI4Driver?

    static func make(selection: C11RootNavigationSelection) throws -> Self {
        let configuration = AppLaunchConfiguration(mode: .releaseUnavailable,
            shouldResetDemoState: false, startsWithCompletedFixture: true,
            preloadsSyntheticOnboardingValues: false, authBehavior: .succeed(after: nil))
        let held401State = selection == .completed401Foreground ? C11RootHeld401State() : nil
        let held401Checkpoint = held401State.map { _ in C11RootHeld401Checkpoint() }
        let newCredentialState = selection == .newCredentialRefresh ? C11RootI4State() : nil
        let newCredentialHold = newCredentialState.map { _ in C11RootI4RefreshHold() }
        let probe = C11RootNavigationProbe(held401: held401State, newCredential: newCredentialState)
        let record: AuthenticationSessionRecord
        if selection == .newCredentialRefresh { record = C11RootI4Facts.old }
        else { record = try C11RootNavigationFacts.record() }
        let secure = try C11RootNavigationSecureStore(record: record,
            markerFailureProbe: selection == .logoutMarkerFailure ? probe : nil)
        let store = AuthenticationSessionStore(secureStore: secure,
            now: { Date(timeIntervalSince1970: 1000) })
        let heldRemote = newCredentialState.flatMap { state in
            newCredentialHold.map { C11RootI4Remote(probe: probe, state: state, hold: $0) }
        }
        let remote = C11RootNavigationRemote(probe: probe, selection: selection, newCredentialRemote: heldRemote)
        let lifecycle = SessionLifecycleCoordinator(store: store, remote: remote,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        let newCredentialDriver = newCredentialState.flatMap { state in
            newCredentialHold.map { C11RootI4Driver(lifecycle: lifecycle, store: store, state: state, hold: $0) }
        }
        let bindingProbe = C11RootNavigationLifecycleProbe(base: lifecycle, probe: probe,
            capturesForegroundGrants: selection == .sameRecordForeground || selection == .completed401Foreground
                || selection == .newCredentialRefresh)
        let patchState = selection == .patchUnauthorizedThenSuccess ? C11RootNavigationPatchState(probe: probe) : nil
        let deleteState = selection == .deleteUnauthorizedThenSuccess ? C11RootNavigationDeleteState(probe: probe) : nil
        let observation = selection.observesDelivery || selection == .completed401Foreground
            ? C11RootNavigationDeliveryObservation(probe: probe, held401Checkpoint: held401Checkpoint) : nil
        let server = C11RootNavigationServer(probe: probe, selection: selection,
            patchState: patchState, deleteState: deleteState, deliveryObservation: observation)
        C11RootNavigationURLProtocol.install(server)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [C11RootNavigationURLProtocol.self]
        let transportLifecycle: any SessionLifecycleProviding
        if let newCredentialDriver {
            transportLifecycle = C11RootI4Lifecycle(driver: newCredentialDriver, probe: probe)
        } else if let held401State, let held401Checkpoint {
            transportLifecycle = C11RootHeld401Lifecycle(base: lifecycle, probe: probe,
                state: held401State, checkpoint: held401Checkpoint)
        } else if selection == .observeDeliveryCancellation {
            transportLifecycle = C11RootNavigationCancelledCallerObservation(base: lifecycle, probe: probe)
        } else { transportLifecycle = lifecycle }
        let transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://c11-ui.fixture.invalid"),
            sessionLifecycle: transportLifecycle, session: URLSession(configuration: sessionConfiguration),
            clock: ContinuousClock(), timeout: .seconds(5))
        // Only this explicitly selected synthetic harness can supply a source.
        let source = AppDependencies.makeMealRecordBindingSource(enabled: selection.suppliesMealRecordSource,
            mode: configuration.mode, client: transport, lifecycle: bindingProbe)
        let scaffold = AppDependencies.scaffold()
        let unavailable = UnavailableBodyFlowCapabilities()
        let reads = C11RootNavigationReads()
        let plan: any PlanProviding
        if selection == .sameRecordForeground || selection == .newCredentialRefresh {
            // Existing loaded DEBUG provider; scaffold().plan is unavailable.
            plan = DemoBodyFlowRepository(scenario: .loaded)
        } else { plan = unavailable }
        let today: any TodayProviding
        let history: any HistoryProviding
        if let patchState {
            let tracked = C11RootNavigationPatchReads(state: patchState, probe: probe)
            today = tracked
            history = tracked
        } else if let deleteState {
            let tracked = C11RootNavigationDeleteReads(state: deleteState, probe: probe)
            today = tracked
            history = tracked
        } else {
            today = reads
            history = reads
        }
        let authentication = SupabaseAuthenticationService(remote: remote, lifecycle: lifecycle)
        let dependencies = AppDependencies(apiClient: transport, authentication: authentication,
            onboarding: C11RootNavigationOnboarding(), coachPersona: scaffold.coachPersona,
            secureStore: secure, telemetry: DisabledTelemetryClient(), today: today, history: history,
            plan: plan, progress: unavailable, mealDetection: unavailable,
            registration: unavailable, hydration: unavailable, weight: unavailable,
            routine: unavailable, me: unavailable,
            publishedContentSessions: UnavailablePublishedContentSessionFactory(),
            coachExperienceSessions: UnavailableCoachExperienceSessionFactory(),
            contentCoverSessions: UnavailableContentCoverSessionFactory(),
            timeProvider: C11RootNavigationTime(), idempotencyKeyProvider: RandomIdempotencyKeyProvider(),
            patientTimeZoneStore: PatientTimeZoneStore(seed: PatientTimeZoneContext(documentedIANAIdentifier: nil)),
            flowChat: scaffold.flowChat, mealRecordBindingSource: source)
        return Self(selection: selection, configuration: configuration, dependencies: dependencies, probe: probe,
            held401Checkpoint: held401Checkpoint, newCredentialDriver: newCredentialDriver)
    }
}

/// Read-only diagnostic values from actual source/transport/remote calls, never tokens.
@MainActor
@Observable
final class C11RootNavigationProbe {
    fileprivate let held401: C11RootHeld401State?
    fileprivate let newCredential: C11RootI4State?
    fileprivate init(held401: C11RootHeld401State? = nil, newCredential: C11RootI4State? = nil) {
        self.held401 = held401; self.newCredential = newCredential
    }
    fileprivate func matchesFirstForegroundOwner(userID: String, generation: UInt64) -> Bool {
        foregroundFirst?.userID == userID && foregroundFirst?.generation == generation
    }
    fileprivate var firstForegroundCapabilityIsRetained: Bool {
        foregroundFirst?.capability.hasRetainedCapability == true
    }
    private(set) var gets = 0
    private(set) var binds = 0
    private(set) var refreshes = 0
    private(set) var blocked = 0
    private(set) var delivery = C11RootNavigationDeliverySnapshot()
    private(set) var deliveryWaiting = 0
    private(set) var deliveryCallerFinishes = 0
    private(set) var deliveryFirstCallerCancelled = false
    func recordDeliveryCallerFinish(cancelledAtEntry: Bool) {
        deliveryCallerFinishes += 1
        if deliveryCallerFinishes == 1 { deliveryFirstCallerCancelled = cancelledAtEntry }
    }
    func recordDelivery(_ snapshot: C11RootNavigationDeliverySnapshot) {
        // Concurrent real loading tasks may publish snapshots in reverse
        // MainActor order. Aggregated facts only increase; never lose one.
        delivery.completed401 = max(delivery.completed401, snapshot.completed401)
        delivery.success = max(delivery.success, snapshot.success)
        delivery.error = max(delivery.error, snapshot.error)
        delivery.callbackCancel = max(delivery.callbackCancel, snapshot.callbackCancel)
        delivery.stopBefore = max(delivery.stopBefore, snapshot.stopBefore)
        delivery.stopAfter = max(delivery.stopAfter, snapshot.stopAfter)
    }
    func recordDeliveryWaiting() { deliveryWaiting += 1 }
    private(set) var sameLogicalRequest = false
    private(set) var bearerChanged = false
    private(set) var patches = 0
    private(set) var deletes = 0
    private(set) var uniqueKeys = 0
    private(set) var todayReads = 0
    private(set) var historyReads = 0
    private(set) var fixtureCommits = 0
    private(set) var recoveryMarkerFailures = 0
    private(set) var recoveryRemoteRevokes = 0
    private(set) var recoveryCommands = 0
    private(set) var recoveryReadBodyAbsent = false
    private(set) var recoveryReadKeyAbsent = false
    func recordRecoveryMarkerFailure() { recoveryMarkerFailures += 1 }
    func recordRecoveryRemoteRevoke() { recoveryRemoteRevokes += 1 }
    func recordRecoveryCommand() { recoveryCommands += 1 }
    func recordRecoveryReadMetadata(bodyAbsent: Bool, keyAbsent: Bool) {
        recoveryReadBodyAbsent = bodyAbsent
        recoveryReadKeyAbsent = keyAbsent
    }
    // Harness admission of a canned response only; no Model/lease/ticket authority.
    var canServeRecoveryRead: Bool {
        recoveryMarkerFailures == 1 && binds == 2 && refreshes == 0
            && recoveryRemoteRevokes == 0 && recoveryCommands == 0
    }
    private struct ForegroundGrant {
        let capability: MealRecordSessionCapability
        let userID: String
        let generation: UInt64
    }
    @ObservationIgnored private var foregroundFirst: ForegroundGrant?
    @ObservationIgnored private var foregroundSecond: ForegroundGrant?
    private(set) var foregroundCaptures = 0
    private(set) var foregroundBackgrounds = 0
    private(set) var foregroundRestores = 0
    private(set) var foregroundFinished = 0
    private(set) var foregroundCancelled = 0
    private(set) var foregroundDisappeared = 0
    private(set) var foregroundPreRetained = false
    private(set) var foregroundPreclosed = false
    private(set) var foregroundOldClosed = false
    private(set) var foregroundDistinct = false
    private(set) var foregroundSameUser = false
    private(set) var foregroundSameGeneration = false
    private(set) var foregroundTicketChanged = false
    private(set) var foregroundSamePublic = false
    private(set) var foregroundBodyAbsent = false
    private(set) var foregroundKeyAbsent = false
    private(set) var foregroundCommands = 0

    /// Original real result only; at most two caps, never SessionLease/bearer.
    func recordForegroundGrant(_ capability: MealRecordSessionCapability, userID: String, generation: UInt64) {
        foregroundCaptures += 1
        let capture = ForegroundGrant(capability: capability, userID: userID, generation: generation)
        if foregroundCaptures == 1 { foregroundFirst = capture }
        else if foregroundCaptures == 2, let first = foregroundFirst {
            foregroundSecond = capture
            foregroundDistinct = first.capability !== capability
            foregroundSameUser = first.userID == userID
            foregroundSameGeneration = first.generation == generation
        }
        // Unexpected third results are counted but not retained.
    }
    func armForegroundAfterRealBackground() -> Bool {
        guard foregroundBackgrounds == 0, foregroundRestores == 0, foregroundDisappeared == 0,
              gets == 1, binds == 1, foregroundCaptures == 1, foregroundFirst != nil,
              refreshes == 0, blocked == 0, foregroundCommands == 0 else { return false }
        foregroundBackgrounds = 1
        return true
    }
    func observeForegroundPreStartRetained() -> Bool {
        let retained = foregroundDisappeared == 0 && foregroundFirst?.capability.hasRetainedCapability == true
        foregroundPreRetained = retained
        foregroundPreclosed = !retained
        return retained
    }
    func recordForegroundRestoreStarted() { foregroundRestores += 1 }
    func recordForegroundRestoreFinished(cancelled: Bool, samePublicSession: Bool, ticketChanged: Bool) {
        foregroundFinished += 1
        if cancelled { foregroundCancelled += 1 }
        foregroundSamePublic = samePublicSession
        foregroundTicketChanged = ticketChanged
        if let first = foregroundFirst { foregroundOldClosed = !first.capability.hasRetainedCapability }
        clearForegroundReferencesIfDisappearedAndIdle()
    }
    func recordForegroundDisappearance() {
        foregroundDisappeared += 1
        clearForegroundReferencesIfDisappearedAndIdle()
    }
    private func clearForegroundReferencesIfDisappearedAndIdle() {
        guard foregroundDisappeared > 0, foregroundRestores == foregroundFinished else { return }
        // Drop observation, never close/reset actual authority.
        foregroundFirst = nil
        foregroundSecond = nil
    }
    func recordForegroundCommand() { foregroundCommands += 1 }
    func recordForegroundReadMetadata(bodyAbsent: Bool, keyAbsent: Bool) {
        foregroundBodyAbsent = bodyAbsent
        foregroundKeyAbsent = keyAbsent
    }
    func canServeForegroundRead(attempt: Int) -> Bool {
        guard refreshes == 0, foregroundCommands == 0, foregroundDisappeared == 0 else { return false }
        if attempt == 1 { return foregroundCaptures == 1 && foregroundRestores == 0 }
        return attempt == 2 && foregroundRestores == 1 && foregroundPreRetained
            && foregroundCaptures == 2 && foregroundDistinct && foregroundSameUser && foregroundSameGeneration
    }
    fileprivate func armNewCredentialAfterRealBackground() -> Bool {
        guard let current = newCredential, current.remoteStarted == 1, current.remoteCompleted == 0,
              current.remoteHeld, foregroundBackgrounds == 0, foregroundRestores == 0,
              foregroundDisappeared == 0, gets == 1, binds == 1, foregroundCaptures == 1,
              foregroundFirst?.capability.hasRetainedCapability == true, refreshes == 1,
              blocked == 0, foregroundCommands == 0 else { return false }
        foregroundBackgrounds = 1
        return true
    }
    fileprivate func canServeNewCredentialRead(attempt: Int) -> Bool {
        guard let current = newCredential, blocked == 0, foregroundCommands == 0,
              foregroundDisappeared == 0 else { return false }
        if attempt == 1 {
            return refreshes == 0 && foregroundCaptures == 1 && foregroundRestores == 0
        }
        return attempt == 2 && refreshes == 1 && foregroundRestores == 1
            && foregroundFinished == 1 && current.normalRelease == 1
            && current.storedNewAfterSwitch && foregroundPreRetained
            && foregroundCaptures == 2 && foregroundDistinct && foregroundSameUser && foregroundSameGeneration
    }
    func recordPATCH(uniqueKeys: Int) { patches += 1; self.uniqueKeys = uniqueKeys }
    func recordDELETE(uniqueKeys: Int) { deletes += 1; self.uniqueKeys = uniqueKeys }
    func recordTodayRead() { todayReads += 1 }
    func recordHistoryRead() { historyReads += 1 }
    func recordFixtureCommit() { fixtureCommits += 1 }
    func recordGET() { gets += 1 }
    func recordBind() { binds += 1 }
    func recordRefresh() { refreshes += 1 }
    func recordBlocked() { blocked += 1 }
    private(set) var manualReadHasNewRequestID = false
    private(set) var manualReadHasSameCurrentBearer = false
    private(set) var manualReadBodyAbsent = false
    private(set) var manualReadKeyAbsent = false
    func recordManualReadComparison(newRequestID: Bool, sameCurrentBearer: Bool, bodyAbsent: Bool, keyAbsent: Bool) {
        manualReadHasNewRequestID = newRequestID
        manualReadHasSameCurrentBearer = sameCurrentBearer
        manualReadBodyAbsent = bodyAbsent
        manualReadKeyAbsent = keyAbsent
    }
    func recordReplayComparison(sameLogical: Bool, bearerChanged: Bool) {
        sameLogicalRequest = sameLogical
        self.bearerChanged = bearerChanged
    }
}

@MainActor
struct C11RootNavigationDiagnosticView: View {
    let selection: C11RootNavigationSelection
    let probe: C11RootNavigationProbe
    private var diagnostic: String {
        let counts = "C11 \(selection.rawValue): get=\(probe.gets) bind=\(probe.binds) refresh=\(probe.refreshes) blocked=\(probe.blocked)"
        if selection == .newCredentialRefresh, let current = probe.newCredential {
            return counts + " started=\(current.remoteStarted) completed=\(current.remoteCompleted) remoteCancelled=\(current.remoteCancelled ? 1 : 0) remoteHeld=\(current.remoteHeld ? 1 : 0)"
                + " fixturesDistinct=\(current.fixturesDistinct ? 1 : 0) oldInput=\(current.oldCredentialInputMatches ? 1 : 0) oldAccount=\(current.oldAccountMatches ? 1 : 0) rejected=\(current.rejected)"
                + " switches=\(current.switches) storedNewAfterSwitch=\(current.storedNewAfterSwitch ? 1 : 0) normalRelease=\(current.normalRelease) controllerError=\(current.controllerErrors)"
                + " consumer=\(current.consumerEntries) entryCancelled=\(current.consumerCancelledAtEntry ? 1 : 0) ownerGeneration=\(current.originalOwnerGeneration ? 1 : 0) oldOutcome=\(current.oldOutcomes) oldCancelled=\(current.oldCancelledAtOutcome ? 1 : 0) oldCancellationOutcome=\(current.oldCancellationOutcome ? 1 : 0) storedNewAfterOld=\(current.storedNewAfterOld ? 1 : 0)"
                + " firstUsesOld=\(current.firstReadUsesOld ? 1 : 0) secondUsesNew=\(current.secondReadUsesNew ? 1 : 0) newReadID=\(current.newReadID ? 1 : 0)"
                + " bg=\(probe.foregroundBackgrounds) restore=\(probe.foregroundRestores) finished=\(probe.foregroundFinished) controllerCancelled=\(probe.foregroundCancelled) disappeared=\(probe.foregroundDisappeared)"
                + " captures=\(probe.foregroundCaptures) preRetained=\(probe.foregroundPreRetained ? 1 : 0) originalLive=\(probe.firstForegroundCapabilityIsRetained ? 1 : 0) oldClosed=\(probe.foregroundOldClosed ? 1 : 0) distinct=\(probe.foregroundDistinct ? 1 : 0)"
                + " sameUser=\(probe.foregroundSameUser ? 1 : 0) sameGeneration=\(probe.foregroundSameGeneration ? 1 : 0) ticketChanged=\(probe.foregroundTicketChanged ? 1 : 0) samePublic=\(probe.foregroundSamePublic ? 1 : 0)"
                + " bodyAbsent=\(probe.foregroundBodyAbsent ? 1 : 0) keyAbsent=\(probe.foregroundKeyAbsent ? 1 : 0) commands=\(probe.foregroundCommands)"
        }
        if selection == .completed401Foreground, let held = probe.held401 {
            let delivery = probe.delivery
            return counts + " client401=\(delivery.completed401) deliverySuccess=\(delivery.success) deliveryError=\(delivery.error) stopBefore=\(delivery.stopBefore)"
                + " firstFinish=\(held.firstFinishEntries) matchedWork=\(held.matchedFirstWork ? 1 : 0) entryCancelled=\(held.cancelledAtFinishEntry ? 1 : 0) held=\(held.held ? 1 : 0) rejected=\(held.rejected)"
                + " normalRelease=\(held.normalRelease) releaseSeen=\(held.releaseSeen) releasedCancelled=\(held.cancelledAtRelease ? 1 : 0) baseFinishReturned=\(held.baseFinishReturned)"
                + " consumer=\(held.consumerEntries) consumerCancelled=\(held.cancelledAtConsumerEntry ? 1 : 0) ownerGeneration=\(held.sameOwnerGeneration ? 1 : 0) newReadID=\(held.newReadID ? 1 : 0)"
                + " bg=\(probe.foregroundBackgrounds) restore=\(probe.foregroundRestores) finished=\(probe.foregroundFinished) controllerCancelled=\(probe.foregroundCancelled) disappeared=\(probe.foregroundDisappeared)"
                + " captures=\(probe.foregroundCaptures) preRetained=\(probe.foregroundPreRetained ? 1 : 0) originalLive=\(probe.firstForegroundCapabilityIsRetained ? 1 : 0) oldClosed=\(probe.foregroundOldClosed ? 1 : 0) distinct=\(probe.foregroundDistinct ? 1 : 0)"
                + " sameUser=\(probe.foregroundSameUser ? 1 : 0) sameGeneration=\(probe.foregroundSameGeneration ? 1 : 0) ticketChanged=\(probe.foregroundTicketChanged ? 1 : 0) samePublic=\(probe.foregroundSamePublic ? 1 : 0)"
                + " bodyAbsent=\(probe.foregroundBodyAbsent ? 1 : 0) keyAbsent=\(probe.foregroundKeyAbsent ? 1 : 0) commands=\(probe.foregroundCommands)"
        }
        if selection.observesDelivery {
            let delivery = probe.delivery
            return counts + " completed401=\(delivery.completed401) success=\(delivery.success) error=\(delivery.error) callbackCancel=\(delivery.callbackCancel)"
                + " stopBefore=\(delivery.stopBefore) stopAfter=\(delivery.stopAfter) waiting=\(probe.deliveryWaiting)"
                + " sameLogical=\(probe.sameLogicalRequest ? 1 : 0) bearerChanged=\(probe.bearerChanged ? 1 : 0)"
                + (selection == .observeDeliveryCancellation
                    ? " finish=\(probe.deliveryCallerFinishes) callerCancelled=\(probe.deliveryFirstCallerCancelled ? 1 : 0)" : "")
        }
        if selection == .sameRecordForeground {
            return counts + " bg=\(probe.foregroundBackgrounds) restore=\(probe.foregroundRestores) finished=\(probe.foregroundFinished) cancelled=\(probe.foregroundCancelled) disappeared=\(probe.foregroundDisappeared)"
                + " preRetained=\(probe.foregroundPreRetained ? 1 : 0) preclosed=\(probe.foregroundPreclosed ? 1 : 0) oldClosed=\(probe.foregroundOldClosed ? 1 : 0) captures=\(probe.foregroundCaptures) distinct=\(probe.foregroundDistinct ? 1 : 0)"
                + " sameUser=\(probe.foregroundSameUser ? 1 : 0) sameGeneration=\(probe.foregroundSameGeneration ? 1 : 0) ticketChanged=\(probe.foregroundTicketChanged ? 1 : 0) samePublic=\(probe.foregroundSamePublic ? 1 : 0)"
                + " bodyAbsent=\(probe.foregroundBodyAbsent ? 1 : 0) keyAbsent=\(probe.foregroundKeyAbsent ? 1 : 0) commands=\(probe.foregroundCommands)"
        }
        if selection == .logoutMarkerFailure {
            return counts + " markerFailures=\(probe.recoveryMarkerFailures) revokes=\(probe.recoveryRemoteRevokes) commands=\(probe.recoveryCommands)"
                + " bodyAbsent=\(probe.recoveryReadBodyAbsent ? 1 : 0) keyAbsent=\(probe.recoveryReadKeyAbsent ? 1 : 0)"
        }
        if selection == .deleteUnauthorizedThenSuccess {
            return counts + " delete=\(probe.deletes) sameLogical=\(probe.sameLogicalRequest ? 1 : 0) bearerChanged=\(probe.bearerChanged ? 1 : 0)"
                + " keys=\(probe.uniqueKeys) today=\(probe.todayReads) history=\(probe.historyReads) commits=\(probe.fixtureCommits)"
        }
        if selection == .patchUnauthorizedThenSuccess {
            return counts + " patch=\(probe.patches) sameLogical=\(probe.sameLogicalRequest ? 1 : 0) bearerChanged=\(probe.bearerChanged ? 1 : 0)"
                + " keys=\(probe.uniqueKeys) today=\(probe.todayReads) history=\(probe.historyReads) commits=\(probe.fixtureCommits)"
        }
        if selection == .getUnauthorizedTwiceThenRetrySuccess {
            return counts + " sameLogical=\(probe.sameLogicalRequest ? 1 : 0) bearerChanged=\(probe.bearerChanged ? 1 : 0)"
                + " newReadID=\(probe.manualReadHasNewRequestID ? 1 : 0) currentBearerSame=\(probe.manualReadHasSameCurrentBearer ? 1 : 0)"
                + " bodyAbsent=\(probe.manualReadBodyAbsent ? 1 : 0) keyAbsent=\(probe.manualReadKeyAbsent ? 1 : 0)"
        }
        guard selection == .getUnauthorizedThenSuccess || selection == .getUnauthorizedTwice else { return counts }
        return counts + " sameLogical=\(probe.sameLogicalRequest ? 1 : 0) bearerChanged=\(probe.bearerChanged ? 1 : 0)"
    }
    var body: some View {
        Text(diagnostic)
            .lineLimit(selection == .newCredentialRefresh ? 1 : nil)
            .accessibilityLabel(diagnostic)
            .font(.system(size: 9, design: .monospaced))
            .padding(2)
            .background(.black.opacity(0.85))
            .foregroundStyle(.white)
            .accessibilityIdentifier("c11.fixture.status")
            .allowsHitTesting(false)
    }
}

/// DEBUG-only and one-shot. Normal/other fixtures install no effects.
@MainActor
struct C11ForegroundRestoreModifier: ViewModifier {
    private let originalModel: AppFlowModel
    private let probe: C11RootNavigationProbe?
    private let held401Probe: C11RootNavigationProbe?
    private let held401Checkpoint: C11RootHeld401Checkpoint?
    private let newCredentialDriver: C11RootI4Driver?
    private let newCredentialProbe: C11RootNavigationProbe?
    @Environment(\.scenePhase) private var phase
    @State private var armed = false
    @State private var consumed = false

    init(originalModel: AppFlowModel, fixture: C11RootNavigationFixture?) {
        self.originalModel = originalModel
        probe = fixture?.selection == .sameRecordForeground ? fixture?.probe : nil
        held401Probe = fixture?.selection == .completed401Foreground ? fixture?.probe : nil
        held401Checkpoint = fixture?.held401Checkpoint
        newCredentialDriver = fixture?.newCredentialDriver
        newCredentialProbe = fixture?.selection == .newCredentialRefresh ? fixture?.probe : nil
    }
    @ViewBuilder
    func body(content: Content) -> some View {
        if let probe {
            content
                .onChange(of: phase) { _, current in
                    if current == .background, !consumed { armed = probe.armForegroundAfterRealBackground() }
                }
                .task(id: phase) {
                    guard phase == .active, armed, !consumed, !Task.isCancelled else { return }
                    consumed = true
                    armed = false
                    // No await before this original grant observation.
                    guard probe.observeForegroundPreStartRetained() else { return }
                    let originalSession = originalModel.currentSession
                    let originalActivation = originalModel.mealRecordActivation
                    probe.recordForegroundRestoreStarted()
                    defer {
                        let current = originalModel.mealRecordActivation
                        probe.recordForegroundRestoreFinished(cancelled: Task.isCancelled,
                            samePublicSession: originalSession != nil && originalModel.currentSession == originalSession,
                            ticketChanged: originalActivation != nil && current != nil
                                && originalActivation?.ticket != current?.ticket)
                    }
                    // Existing restore creates its own ticket/grant.
                    await originalModel.start()
                }
                .onDisappear {
                    armed = false
                    probe.recordForegroundDisappearance()
                    // SwiftUI owns/cancels task. Do not close/reset authority.
                }
        } else if let held401Probe, let held401Checkpoint {
            content.modifier(C11RootHeld401ForegroundModifier(originalModel: originalModel,
                probe: held401Probe, checkpoint: held401Checkpoint))
        } else if let newCredentialDriver, let newCredentialProbe {
            content.modifier(C11RootI4ForegroundModifier(originalModel: originalModel,
                probe: newCredentialProbe, driver: newCredentialDriver))
        } else { content }
    }
}

/// New selection only. No identifiers, body, bearer or lease enter these facts.
@MainActor
@Observable
fileprivate final class C11RootHeld401State {
    var firstFinishEntries = 0
    var matchedFirstWork = false
    var cancelledAtFinishEntry = false
    var held = false
    var rejected = 0
    var normalRelease = 0
    var releaseSeen = 0
    var cancelledAtRelease = false
    var baseFinishReturned = 0
    var consumerEntries = 0
    var cancelledAtConsumerEntry = false
    var sameOwnerGeneration = false
    var newReadID = false
}

/// Post-publish event + controller-owned release, both one-shot. The old caller's
/// EXPECTED cancellation does not release its hold. Every resume is outside the
/// private lock; no callback, scheduling, I/O or authority is created here.
fileprivate final class C11RootHeld401Checkpoint: @unchecked Sendable {
    private let lock = NSLock()
    private var terminalResult: Bool?
    private var terminalWaiter: CheckedContinuation<Bool, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var held = false
    private var released = false
    private var aborted = false

    var isHeld: Bool { lock.withLock { held && !released && !aborted } }
    func recordPublishedTerminal(_ snapshot: C11RootNavigationDeliverySnapshot) {
        let valid = snapshot.completed401 == 1 && snapshot.success == 1
            && snapshot.error == 0 && snapshot.callbackCancel == 0 && snapshot.stopBefore == 0
        let signal: (CheckedContinuation<Bool, Never>?, Bool) = lock.withLock {
            guard terminalResult == nil else { return (nil, false) }
            let result = valid && !aborted
            terminalResult = result
            let waiting = terminalWaiter
            terminalWaiter = nil
            return (waiting, result)
        }
        signal.0?.resume(returning: signal.1)
    }
    func waitForPublishedTerminal() async -> Bool {
        await withCheckedContinuation { continuation in
            let result: Bool? = lock.withLock {
                if let terminalResult { return terminalResult }
                terminalWaiter = continuation
                return nil
            }
            if let result { continuation.resume(returning: result) }
        }
    }
    func admitHold() -> Bool {
        lock.withLock {
            guard terminalResult == true, !held, !released, !aborted else { return false }
            held = true
            return true
        }
    }
    func waitForControllerRelease() async {
        await withCheckedContinuation { continuation in
            let releaseNow = lock.withLock {
                if released { return true }
                releaseWaiter = continuation
                return false
            }
            if releaseNow { continuation.resume() }
        }
    }
    func release() {
        let waiting = lock.withLock {
            released = true
            let waiting = releaseWaiter
            releaseWaiter = nil
            return waiting
        }
        waiting?.resume()
    }
    func abort() {
        let waiting: (CheckedContinuation<Bool, Never>?, CheckedContinuation<Void, Never>?) = lock.withLock {
            aborted = true
            released = true
            if terminalResult == nil { terminalResult = false }
            let pending = (terminalWaiter, releaseWaiter)
            terminalWaiter = nil
            releaseWaiter = nil
            return pending
        }
        waiting.0?.resume(returning: false)
        waiting.1?.resume()
    }
}

/// Injected into transport only for held401-foreground. All authority stays in
/// the same real coordinator. One private workID is retained only to identify
/// the first real finish; no prepared work/grant/lease/ticket is manufactured.
private actor C11RootHeld401Lifecycle: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    let probe: C11RootNavigationProbe
    let state: C11RootHeld401State
    let checkpoint: C11RootHeld401Checkpoint
    private var firstWorkID: UUID?
    private var firstFinishTaken = false
    init(base: SessionLifecycleCoordinator, probe: C11RootNavigationProbe,
        state: C11RootHeld401State, checkpoint: C11RootHeld401Checkpoint) {
        self.base = base; self.probe = probe; self.state = state; self.checkpoint = checkpoint
    }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease { try await base.leaseForRequest() }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        let realID = try await base.beginPatientWork(lease: lease, cancel: cancel)
        if firstWorkID == nil, !firstFinishTaken { firstWorkID = realID }
        return realID
    }
    func finishPatientWork(_ id: UUID) async {
        let cancelledAtEntry = Task.isCancelled // Actual caller; before first await.
        guard !firstFinishTaken, let firstWorkID, firstWorkID == id else {
            await base.finishPatientWork(id)
            return
        }
        firstFinishTaken = true
        await MainActor.run {
            state.firstFinishEntries += 1
            state.matchedFirstWork = true
            state.cancelledAtFinishEntry = cancelledAtEntry
        }
        let terminalWasPublished = await checkpoint.waitForPublishedTerminal()
        if terminalWasPublished, !cancelledAtEntry, checkpoint.admitHold() {
            await MainActor.run { state.held = true }
            // Deliberately no caller cancellation handler: only the foreground
            // controller releases, after its real Model.start return or cleanup.
            await checkpoint.waitForControllerRelease()
            let cancelledAtRelease = Task.isCancelled
            await MainActor.run {
                state.releaseSeen += 1
                state.cancelledAtRelease = cancelledAtRelease
            }
        } else { await MainActor.run { state.rejected += 1 } }
        await base.finishPatientWork(id)
        self.firstWorkID = nil
        await MainActor.run { state.baseFinishReturned += 1 }
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
        let cancelledAtEntry = Task.isCancelled // Before first await; never a getter/re-lease.
        let userID = lease.userID, generation = lease.generation
        await MainActor.run {
            state.consumerEntries += 1
            if state.consumerEntries == 1 {
                state.cancelledAtConsumerEntry = cancelledAtEntry
                state.sameOwnerGeneration = probe.matchesFirstForegroundOwner(userID: userID, generation: generation)
            }
        }
        // Exact original argument. Integral forwarding is proved by pinned
        // transport/callsite source, NOT a fabricated runtime fullLeaseEqual.
        return try await base.refreshAfterUnauthorized(lease: lease)
    }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

/// Separate new-mode branch. This structured scene task owns release; it never
/// waits for A2/grant2/GET2/Form or old-task join before releasing first finish.
@MainActor
private struct C11RootHeld401ForegroundModifier: ViewModifier {
    let originalModel: AppFlowModel
    let probe: C11RootNavigationProbe
    let checkpoint: C11RootHeld401Checkpoint
    @Environment(\.scenePhase) private var phase
    @State private var armed = false
    @State private var consumed = false
    func body(content: Content) -> some View {
        content
            .onChange(of: phase) { _, current in
                if current == .background, !consumed, checkpoint.isHeld {
                    armed = probe.armForegroundAfterRealBackground()
                }
            }
            .task(id: phase) {
                guard phase == .active, armed, !consumed, !Task.isCancelled else { return }
                consumed = true
                armed = false
                await withTaskCancellationHandler {
                    defer { checkpoint.release() } // All returns release before any join.
                    guard checkpoint.isHeld, let held = probe.held401,
                          probe.observeForegroundPreStartRetained() else { return }
                    let originalSession = originalModel.currentSession
                    let originalActivation = originalModel.mealRecordActivation
                    probe.recordForegroundRestoreStarted()
                    await originalModel.start() // The existing actual Model, not a copy.
                    let current = originalModel.mealRecordActivation
                    let samePublic = originalSession != nil && originalModel.currentSession == originalSession
                    let changedTicket = originalActivation != nil && current != nil
                        && originalActivation?.ticket != current?.ticket
                    probe.recordForegroundRestoreFinished(cancelled: Task.isCancelled,
                        samePublicSession: samePublic, ticketChanged: changedTicket)
                    if !Task.isCancelled, samePublic, changedTicket { held.normalRelease += 1 }
                    checkpoint.release() // Immediately after start return + synchronous facts.
                } onCancel: {
                    checkpoint.abort() // Synchronous/idempotent; no orphan cleanup Task.
                }
            }
            .onDisappear {
                armed = false
                checkpoint.abort()
                probe.recordForegroundDisappearance()
            }
    }
}

/// No actual credential/record/hash is retained in observations. Expected
/// fixture records below are immutable synthetic operation inputs, not probes.
@MainActor
@Observable
fileprivate final class C11RootI4State {
    var fixturesDistinct = C11RootI4Facts.credentialsAreDistinct
    var remoteStarted = 0
    var remoteCompleted = 0
    var remoteHeld = false // Historical fact: the actual remote entered its hold.
    var remoteCancelled = false
    var oldCredentialInputMatches = false
    var oldAccountMatches = false
    var rejected = 0
    var switches = 0
    var storedNewAfterSwitch = false
    var normalRelease = 0
    var controllerErrors = 0
    var consumerEntries = 0
    var consumerCancelledAtEntry = false
    var originalOwnerGeneration = false
    var oldOutcomes = 0
    var oldCancelledAtOutcome = false
    var oldCancellationOutcome = false
    var storedNewAfterOld = false
    var firstReadUsesOld = false
    var secondReadUsesNew = false
    var newReadID = false
}

/// One actual remote await. Release is owned by the structured foreground
/// controller; old caller cancellation cannot release/erase this schedule.
fileprivate final class C11RootI4RefreshHold: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    var isHeld: Bool { lock.withLock { entered && !released } }
    func enter() -> Bool {
        lock.withLock {
            guard !entered, !released else { return false }
            entered = true
            return true
        }
    }
    func waitForRelease() async {
        await withCheckedContinuation { continuation in
            let releaseNow = lock.withLock {
                if released { return true }
                waiter = continuation
                return false
            }
            if releaseNow { continuation.resume() }
        }
    }
    func release() {
        let pending = lock.withLock {
            released = true
            let pending = waiter
            waiter = nil
            return pending
        }
        pending?.resume() // Never under the hold lock or a client callback lock.
    }
}

fileprivate struct C11RootI4Driver: Sendable {
    let lifecycle: SessionLifecycleCoordinator
    let store: AuthenticationSessionStore
    let state: C11RootI4State
    let hold: C11RootI4RefreshHold
}

/// The real coordinator-owned shared task calls this through its actual remote.
/// It receives its real operation record as required by the protocol. Only
/// transient comparisons over that argument are copied into boolean probes.
private actor C11RootI4Remote {
    let probe: C11RootNavigationProbe
    let state: C11RootI4State
    let hold: C11RootI4RefreshHold
    init(probe: C11RootNavigationProbe, state: C11RootI4State, hold: C11RootI4RefreshHold) {
        self.probe = probe; self.state = state; self.hold = hold
    }
    func refresh(record: AuthenticationSessionRecord) async throws -> AuthenticationSessionRecord {
        await probe.recordRefresh() // Count every actual call before any guard/response.
        let oldMatches = record == C11RootI4Facts.old
        let accountMatches = record.publicSession == C11RootI4Facts.old.publicSession
        await MainActor.run {
            state.remoteStarted += 1
            if state.remoteStarted == 1 {
                state.oldCredentialInputMatches = oldMatches
                state.oldAccountMatches = accountMatches
            }
        }
        guard oldMatches, accountMatches, hold.enter() else {
            await MainActor.run { state.rejected += 1 }
            throw SupabaseAuthRemoteError.requestFailed
        }
        await MainActor.run { state.remoteHeld = true }
        await hold.waitForRelease() // The operation's own record is not copied into observation.
        let cancelled = Task.isCancelled
        await MainActor.run {
            state.remoteCompleted += 1
            state.remoteCancelled = cancelled
        }
        // Valid STALE R, intentionally different from installed N. Its actual
        // outcome must traverse the real coordinator's revision/operation guard.
        return C11RootI4Facts.stale
    }
}

/// Real transport call-through only. The post-base observation occurs after
/// its real shared refresh task completed, including commitRefresh resolution.
/// No extra auth getter, fresh lease or credential copy is used for observation.
private actor C11RootI4Lifecycle: SessionLifecycleProviding {
    let driver: C11RootI4Driver
    let probe: C11RootNavigationProbe
    init(driver: C11RootI4Driver, probe: C11RootNavigationProbe) {
        self.driver = driver; self.probe = probe
    }
    func currentBearerToken() async -> String? { await driver.lifecycle.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await driver.lifecycle.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await driver.lifecycle.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease { try await driver.lifecycle.leaseForRequest() }
    func validate(_ lease: SessionLease) async throws { try await driver.lifecycle.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await driver.lifecycle.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        try await driver.lifecycle.beginPatientWork(lease: lease, cancel: cancel)
    }
    func finishPatientWork(_ id: UUID) async { await driver.lifecycle.finishPatientWork(id) }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
        let cancelledAtEntry = Task.isCancelled // Before the first await.
        let userID = lease.userID, generation = lease.generation
        await MainActor.run {
            driver.state.consumerEntries += 1
            if driver.state.consumerEntries == 1 {
                driver.state.consumerCancelledAtEntry = cancelledAtEntry
                driver.state.originalOwnerGeneration = probe.matchesFirstForegroundOwner(userID: userID, generation: generation)
            }
        }
        do {
            let result = try await driver.lifecycle.refreshAfterUnauthorized(lease: lease)
            await recordOldOutcome(cancellationOutcome: false)
            return result // Actual protocol result, unchanged; never placed in a probe.
        } catch let error as CancellationError {
            await recordOldOutcome(cancellationOutcome: true)
            throw error
        } catch {
            await recordOldOutcome(cancellationOutcome: false)
            throw error
        }
    }
    private func recordOldOutcome(cancellationOutcome: Bool) async {
        let cancelled = Task.isCancelled
        // Compare within this expression. No observed record/bearer/hash
        // crosses the next await; only the boolean survives.
        let newestStillStored = (await driver.store.currentRecord()) == C11RootI4Facts.newest
        await MainActor.run {
            driver.state.oldOutcomes += 1
            if driver.state.oldOutcomes == 1 {
                driver.state.oldCancelledAtOutcome = cancelled
                driver.state.oldCancellationOutcome = cancellationOutcome
                driver.state.storedNewAfterOld = newestStillStored
            }
        }
    }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await driver.lifecycle.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await driver.lifecycle.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

/// Existing public same-user replacement, followed by the original Root Model.
/// Release happens immediately after start returns and before any A2/join wait.
@MainActor
private struct C11RootI4ForegroundModifier: ViewModifier {
    let originalModel: AppFlowModel
    let probe: C11RootNavigationProbe
    let driver: C11RootI4Driver
    @Environment(\.scenePhase) private var phase
    @State private var armed = false
    @State private var consumed = false
    func body(content: Content) -> some View {
        content
            .onChange(of: phase) { _, current in
                if current == .background, !consumed, driver.hold.isHeld {
                    armed = probe.armNewCredentialAfterRealBackground()
                }
            }
            .task(id: phase) {
                guard phase == .active, armed, !consumed, !Task.isCancelled else { return }
                consumed = true
                armed = false
                await withTaskCancellationHandler {
                    defer { driver.hold.release() }
                    guard driver.hold.isHeld, probe.observeForegroundPreStartRetained() else { return }
                    let originalSession = originalModel.currentSession
                    let originalActivation = originalModel.mealRecordActivation
                    do {
                        try await driver.lifecycle.switch(to: C11RootI4Facts.newest)
                        let storedNew = (await driver.store.currentRecord()) == C11RootI4Facts.newest
                        driver.state.switches += 1
                        driver.state.storedNewAfterSwitch = storedNew
                        guard storedNew, !Task.isCancelled else { return }
                        probe.recordForegroundRestoreStarted()
                        await originalModel.start()
                        let current = originalModel.mealRecordActivation
                        let samePublic = originalSession != nil && originalModel.currentSession == originalSession
                        let changedTicket = originalActivation != nil && current != nil
                            && originalActivation?.ticket != current?.ticket
                        probe.recordForegroundRestoreFinished(cancelled: Task.isCancelled,
                            samePublicSession: samePublic, ticketChanged: changedTicket)
                        if !Task.isCancelled, samePublic, changedTicket { driver.state.normalRelease += 1 }
                        driver.hold.release() // No await/A2/grant2/Form/join before release.
                    } catch { driver.state.controllerErrors += 1 }
                } onCancel: {
                    driver.hold.release() // Synchronous/idempotent; no orphan cleanup Task.
                }
            }
            .onDisappear {
                armed = false
                driver.hold.release()
                probe.recordForegroundDisappearance()
            }
    }
}

/// Exact precomputed synthetic JWT bytes; never regenerated from an unordered
/// JSON dictionary. A/N/R all have the same public account and future expiry.
private enum C11RootI4Facts {
    static let old = record(access: "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhYWFhYWFhYS1hYWFhLTRhYWEtOGFhYS1hYWFhYWFhYWFhYWEiLCJmaXh0dXJlIjoiYzExLWk0LUEifQ.synthetic-signature", refresh: "synthetic-i4-old", expiry: 2000)
    static let newest = record(access: "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhYWFhYWFhYS1hYWFhLTRhYWEtOGFhYS1hYWFhYWFhYWFhYWEiLCJmaXh0dXJlIjoiYzExLWk0LU4ifQ.synthetic-signature", refresh: "synthetic-i4-newest", expiry: 4000)
    static let stale = record(access: "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhYWFhYWFhYS1hYWFhLTRhYWEtOGFhYS1hYWFhYWFhYWFhYWEiLCJmaXh0dXJlIjoiYzExLWk0LVIifQ.synthetic-signature", refresh: "synthetic-i4-stale", expiry: 3000)
    static var credentialsAreDistinct: Bool {
        old.publicSession == newest.publicSession && newest.publicSession == stale.publicSession
            && old.accessToken != newest.accessToken && old.accessToken != stale.accessToken
            && newest.accessToken != stale.accessToken && old.refreshToken != newest.refreshToken
            && old.refreshToken != stale.refreshToken && newest.refreshToken != stale.refreshToken
    }
    private static func record(access: String, refresh: String, expiry: TimeInterval) -> AuthenticationSessionRecord {
        AuthenticationSessionRecord(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", email: "c11-root@example.invalid",
            isEmailConfirmed: true, isOnboardingCompleted: true, accessToken: access,
            refreshToken: refresh, expiresAt: Date(timeIntervalSince1970: expiry))
    }
}

private enum C11RootNavigationFacts {
    static let userID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let recordID = "11111111-1111-4111-8111-111111111111"
    static let date = Date(timeIntervalSince1970: 1791903600)
    static let meta = MobileResponseMetadata(apiVersion: "v1", requestID: "c11-ui-get-200")
    static func record() throws -> AuthenticationSessionRecord {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: ["sub": userID, "fixture": "c11-root-navigation"])
        func part(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let synthetic = "\(part(header)).\(part(payload)).synthetic-signature"
        return AuthenticationSessionRecord(userID: userID, email: "c11-root@example.invalid",
            isEmailConfirmed: true, isOnboardingCompleted: true, accessToken: synthetic,
            refreshToken: "synthetic-c11-root-refresh", expiresAt: Date(timeIntervalSince1970: 2000))
    }
    /// This valid synthetic replacement is returned ONLY by the new refresh scenario.
    /// Public session facts stay identical; token values never enter diagnostics.
    static func refreshedRecord(from original: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord {
        guard original.userID == userID else { throw SupabaseAuthRemoteError.requestFailed }
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: ["sub": userID, "fixture": "c11-root-navigation-refreshed"])
        func part(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let synthetic = "\(part(header)).\(part(payload)).synthetic-signature"
        return AuthenticationSessionRecord(userID: original.userID, email: original.email,
            isEmailConfirmed: original.isEmailConfirmed, isOnboardingCompleted: original.isOnboardingCompleted,
            accessToken: synthetic, refreshToken: "synthetic-c11-root-refreshed", expiresAt: Date(timeIntervalSince1970: 3000))
    }
    static var row: HistoryMealLogRow {
        HistoryMealLogRow(id: recordID, mealType: "almoco", foodName: "Synthetic C11 confirmed food",
            quantityG: 50, kcal: 100, proteinG: 1, carbsG: 2, fatG: 3, consumedAt: APITimestamp(value: date))
    }
    static func detail() -> MealRecordResponse {
        let item = MealRecordItemSnapshot(id: recordID, foodName: "Synthetic C11 confirmed food",
            quantityG: 50, kcal: 100, proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact",
            consumedAt: APITimestamp(value: date), mealType: "almoco")
        return MealRecordResponse(data: MealRecordSnapshot(recordID: recordID, scope: .item,
            expectedVersion: "opaque-c11-ui-version", itemIDs: [recordID], items: [item], editable: true,
            dayClosed: false, localDate: "2026-10-13", timezone: "America/Sao_Paulo", editBlockReason: nil), meta: meta)
    }
    static func foregroundDetail() -> MealRecordResponse {
        let item = MealRecordItemSnapshot(id: recordID, foodName: "Synthetic C11 foreground restored official food",
            quantityG: 50, kcal: 100, proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact",
            consumedAt: APITimestamp(value: date), mealType: "almoco")
        return MealRecordResponse(data: MealRecordSnapshot(recordID: recordID, scope: .item,
            expectedVersion: "opaque-c11-ui-version", itemIDs: [recordID], items: [item], editable: true,
            dayClosed: false, localDate: "2026-10-13", timezone: "America/Sao_Paulo", editBlockReason: nil),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "c11-ui-foreground-get-200"))
    }
    /// Distinct canned official read after explicit recovery; History's local row stays unchanged.
    static func recoveredDetail() -> MealRecordResponse {
        let item = MealRecordItemSnapshot(id: recordID, foodName: "Synthetic C11 recovered official food",
            quantityG: 50, kcal: 100, proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact",
            consumedAt: APITimestamp(value: date), mealType: "almoco")
        return MealRecordResponse(data: MealRecordSnapshot(recordID: recordID, scope: .item,
            expectedVersion: "opaque-c11-ui-version", itemIDs: [recordID], items: [item], editable: true,
            dayClosed: false, localDate: "2026-10-13", timezone: "America/Sao_Paulo", editBlockReason: nil),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "c11-ui-recovery-get-200"))
    }
}

/// Same JSONEncoder/schema/storageKey as AuthenticationSessionStore.replace; no async init race.
private final class C11RootNavigationSecureStore: SecureStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    private let markerFailureProbe: C11RootNavigationProbe?
    init(record: AuthenticationSessionRecord, markerFailureProbe: C11RootNavigationProbe? = nil) throws {
        values = [AuthenticationSessionStore.storageKey: try JSONEncoder().encode(record)]
        self.markerFailureProbe = markerFailureProbe
    }
    func data(forKey key: String) -> Data? { lock.withLock { values[key] } }
    func store(_ data: Data, forKey key: String) async throws {
        if key == AuthenticationSessionStore.invalidationMarkerKey, let markerFailureProbe {
            // Await the real attempt's safe counter before failing; no detached Task.
            // The actual AuthStore catches this before record/generation invalidation.
            await markerFailureProbe.recordRecoveryMarkerFailure()
            throw AuthenticationSessionStoreError.localInvalidationFailed
        }
        lock.withLock { values[key] = data }
    }
    func removeData(forKey key: String) { lock.withLock { _ = values.removeValue(forKey: key) } }
}

private actor C11RootNavigationRemote: SupabaseAuthRemoteOperating {
    let probe: C11RootNavigationProbe
    let selection: C11RootNavigationSelection
    private let newCredentialRemote: C11RootI4Remote?
    init(probe: C11RootNavigationProbe, selection: C11RootNavigationSelection,
        newCredentialRemote: C11RootI4Remote? = nil) {
        self.probe = probe
        self.selection = selection
        self.newCredentialRemote = newCredentialRemote
    }
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws { throw SupabaseAuthRemoteError.requestFailed }
    func refresh(record: AuthenticationSessionRecord) async throws -> AuthenticationSessionRecord {
        if let newCredentialRemote { return try await newCredentialRemote.refresh(record: record) }
        await probe.recordRefresh()
        guard selection == .getUnauthorizedThenSuccess || selection == .getUnauthorizedTwice
            || selection == .getUnauthorizedTwiceThenRetrySuccess || selection == .patchUnauthorizedThenSuccess
            || selection == .deleteUnauthorizedThenSuccess || selection == .observeCompleted401
            || selection == .completed401Foreground else {
            throw SupabaseAuthRemoteError.requestFailed
        }
        return try C11RootNavigationFacts.refreshedRecord(from: record)
    }
    func revokeCurrentSession(accessToken: String) async -> RemoteRevocationOutcome {
        if selection == .logoutMarkerFailure { await probe.recordRecoveryRemoteRevoke() }
        return .unconfirmed
    }
}

private struct C11RootNavigationReads: TodayProviding, HistoryProviding {
    func today() -> TodayResponse { DemoBodyFlowFixtures.loadedToday }
    func history(_ query: HistoryQuery) -> HistoryResponse {
        HistoryResponse(data: HistorySnapshot(meals: [C11RootNavigationFacts.row], workouts: [],
            pagination: HistoryPaginationMetadata(limit: 30, before: nil)), meta: C11RootNavigationFacts.meta)
    }
}
private actor C11RootNavigationOnboarding: OnboardingRepository {
    func loadDraft(for userID: String) -> OnboardingDraft? { nil }
    func loadState(for userID: String) -> OnboardingServerState {
        OnboardingServerState(locale: "pt-BR", completion: .init(completed: true,
            completedAt: "2026-10-13T00:00:00.000Z"), requirements: .unavailable,
            acceptedActions: [], draft: nil)
    }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) {}
    func complete(_ draft: OnboardingDraft, for userID: String) {}
    func clear(for userID: String) {}
}
private struct C11RootNavigationTime: TimeProviding { var now: Date { C11RootNavigationFacts.date } }

/// Canned server facts for the PATCH scenario. No quantity/energy calculation occurs here.
private enum C11RootNavigationPatchFacts {
    static let newRecordID = "22222222-2222-4222-8222-222222222222"
    static func row(committed: Bool) -> HistoryMealLogRow {
        guard committed else { return C11RootNavigationFacts.row }
        return HistoryMealLogRow(id: newRecordID, mealType: "almoco", foodName: "Synthetic C11 updated food",
            quantityG: 75, kcal: 123, proteinG: 2, carbsG: 3, fatG: 4,
            consumedAt: APITimestamp(value: C11RootNavigationFacts.date))
    }
    static func receipt() -> MealRecordMutationResponse {
        MealRecordMutationResponse(data: MealRecordMutationSnapshot(
            recordID: C11RootNavigationFacts.recordID, operation: .updated,
            newItemIDs: [newRecordID], removedItemIDs: [C11RootNavigationFacts.recordID],
            nextRecordID: newRecordID,
            snapshot: MealRecordPersistedSnapshot(id: "33333333-3333-4333-8333-333333333333",
                date: "2026-10-13", caloriesConsumed: 123, proteinG: 2, carbsG: 3, fatG: 4,
                dailyBalance: -1677)),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "c11-ui-patch-200"))
    }
    static var expectedBody: MealRecordPatchBody {
        MealRecordPatchBody(expectedVersion: "opaque-c11-ui-version",
            itemIDs: [C11RootNavigationFacts.recordID], items: [MealProposalItemRequest(
                foodName: "Synthetic C11 confirmed food", quantityG: 75, userKcal: nil)])
    }
    static func today(committed: Bool) -> TodayResponse {
        let base = DemoBodyFlowFixtures.loadedToday.data
        let row = row(committed: committed)
        let meal = TodayMeal(id: row.id, mealType: row.mealType, foodName: row.foodName,
            quantityG: row.quantityG, kcal: row.kcal, proteinG: row.proteinG, carbsG: row.carbsG,
            fatG: row.fatG, consumedAt: row.consumedAt, nutritionSource: "canonical_exact")
        let snapshot = TodaySnapshot(localDate: "2026-10-13", protocolName: base.protocolName,
            currentProtocol: base.currentProtocol,
            targets: TodayTargets(caloriesKcal: 1800, proteinG: 100, source: "synthetic-official",
                caloriesSource: "synthetic-official", proteinSource: "synthetic-official"),
            consumed: TodayConsumed(caloriesKcal: committed ? 123 : 100,
                proteinG: committed ? 2 : 1, carbsG: committed ? 3 : 2, fatG: committed ? 4 : 3,
                source: "synthetic-persisted"),
            remainingFoodKcal: committed ? 1677 : 1700, foodExcessKcal: nil, exerciseKcal: 0,
            dailyBalanceKcal: committed ? -1677 : -1700, dailyBalanceStatus: "deficit",
            dailyBalanceIncludesExercise: true, dailyBalanceReferenceKcal: 1800,
            proteinStatus: TodayProteinStatus(consumedG: committed ? 2 : 1, targetG: 100,
                remainingG: committed ? 98 : 99, percentage: committed ? 2 : 1, status: "below"),
            meals: [meal], workouts: [], hydration: base.hydration, supplements: base.supplements,
            medications: base.medications, pendingActions: base.pendingActions, block7700: base.block7700,
            completionStatus: base.completionStatus, sources: base.sources,
            calculationVersion: "synthetic-persisted", updatedAt: base.updatedAt, generatedAt: base.generatedAt)
        return TodayResponse(data: snapshot,
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: committed ? "c11-ui-today-after" : "c11-ui-today-before"))
    }
}

/// A synthetic persisted state: only the second valid PATCH may commit it once.
private actor C11RootNavigationPatchState {
    let probe: C11RootNavigationProbe
    private var committed = false
    init(probe: C11RootNavigationProbe) { self.probe = probe }
    func commit() async throws {
        guard !committed else { throw MobileAPITransportError.invalidResponse }
        committed = true
        await probe.recordFixtureCommit()
    }
    func today() -> TodayResponse { C11RootNavigationPatchFacts.today(committed: committed) }
    func history() -> HistoryResponse {
        HistoryResponse(data: HistorySnapshot(meals: [C11RootNavigationPatchFacts.row(committed: committed)],
            workouts: [], pagination: HistoryPaginationMetadata(limit: 30, before: nil)),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: committed ? "c11-ui-history-after" : "c11-ui-history-before"))
    }
}

/// Counts provider calls made by the real Today/History Models, not revisions of their private center.
/// This does not trigger invalidation or read from a getter; server facts are returned as received.
private struct C11RootNavigationPatchReads: TodayProviding, HistoryProviding {
    let state: C11RootNavigationPatchState
    let probe: C11RootNavigationProbe
    func today() async -> TodayResponse {
        let value = await state.today()
        await probe.recordTodayRead()
        return value
    }
    func history(_ query: HistoryQuery) async -> HistoryResponse {
        let value = await state.history()
        await probe.recordHistoryRead()
        return value
    }
}

/// Own DELETE receipt: no new row, explicit null nextRecordID, literal persisted zero.
private enum C11RootNavigationDeleteFacts {
    static var expectedBody: MealRecordDeleteBody {
        MealRecordDeleteBody(expectedVersion: "opaque-c11-ui-version", itemIDs: [C11RootNavigationFacts.recordID])
    }
    static func receipt() -> MealRecordMutationResponse {
        MealRecordMutationResponse(data: MealRecordMutationSnapshot(
            recordID: C11RootNavigationFacts.recordID, operation: .deleted,
            newItemIDs: [], removedItemIDs: [C11RootNavigationFacts.recordID], nextRecordID: nil,
            snapshot: MealRecordPersistedSnapshot(id: "33333333-3333-4333-8333-333333333333",
                date: "2026-10-13", caloriesConsumed: 0, proteinG: 0, carbsG: 0, fatG: 0,
                dailyBalance: -1800)),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "c11-ui-delete-200"))
    }
    static func today(committed: Bool) -> TodayResponse {
        let before = C11RootNavigationPatchFacts.today(committed: false)
        guard committed else { return before }
        let base = before.data
        let snapshot = TodaySnapshot(localDate: base.localDate, protocolName: base.protocolName,
            currentProtocol: base.currentProtocol, targets: base.targets,
            consumed: TodayConsumed(caloriesKcal: 0, proteinG: 0, carbsG: 0, fatG: 0,
                source: "synthetic-persisted"),
            remainingFoodKcal: 1800, foodExcessKcal: nil, exerciseKcal: 0,
            dailyBalanceKcal: -1800, dailyBalanceStatus: "deficit", dailyBalanceIncludesExercise: true,
            dailyBalanceReferenceKcal: 1800,
            proteinStatus: TodayProteinStatus(consumedG: 0, targetG: 100, remainingG: 100, percentage: 0, status: "below"),
            meals: [], workouts: [], hydration: base.hydration, supplements: base.supplements,
            medications: base.medications, pendingActions: base.pendingActions, block7700: base.block7700,
            completionStatus: base.completionStatus, sources: base.sources,
            calculationVersion: "synthetic-persisted", updatedAt: base.updatedAt, generatedAt: base.generatedAt)
        return TodayResponse(data: snapshot,
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "c11-ui-delete-today-after"))
    }
}

/// Only the second admitted DELETE commits this isolated synthetic state.
private actor C11RootNavigationDeleteState {
    let probe: C11RootNavigationProbe
    private var committed = false
    init(probe: C11RootNavigationProbe) { self.probe = probe }
    func commit() async throws {
        guard !committed else { throw MobileAPITransportError.invalidResponse }
        committed = true
        await probe.recordFixtureCommit()
    }
    func today() -> TodayResponse { C11RootNavigationDeleteFacts.today(committed: committed) }
    func history() -> HistoryResponse {
        HistoryResponse(data: HistorySnapshot(meals: committed ? [] : [C11RootNavigationFacts.row],
            workouts: [], pagination: HistoryPaginationMetadata(limit: 30, before: nil)),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: committed ? "c11-ui-delete-history-after" : "c11-ui-delete-history-before"))
    }
}

private struct C11RootNavigationDeleteReads: TodayProviding, HistoryProviding {
    let state: C11RootNavigationDeleteState
    let probe: C11RootNavigationProbe
    func today() async -> TodayResponse {
        let value = await state.today()
        await probe.recordTodayRead()
        return value
    }
    func history(_ query: HistoryQuery) async -> HistoryResponse {
        let value = await state.history()
        await probe.recordHistoryRead()
        return value
    }
}

/// A status-bearing HTTP response from the strictly synthetic protocol, never a real endpoint.
private struct C11RootNavigationHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

/// Only an exact synthetic GET is allowed. Unknown requests never reach internet.
private actor C11RootNavigationServer {
    let probe: C11RootNavigationProbe
    let selection: C11RootNavigationSelection
    nonisolated let deliveryObservation: C11RootNavigationDeliveryObservation?
    private var attemptedGETs = 0
    private var firstLogicalRequest: LogicalRequest?
    private var firstAuthorization: String?
    // Private comparisons for the new explicit manual-read scenario only.
    // Neither metadata IDs nor authorization values enter diagnostics.
    private var manualRetrySecondLogical: LogicalRequest?
    private var manualRetrySecondAuthorization: String?
    let patchState: C11RootNavigationPatchState?
    let deleteState: C11RootNavigationDeleteState?
    private var attemptedDELETEs = 0
    private var firstDELETE: PatchLogicalRequest?
    private var firstDELETEAuthorization: String?
    private var deleteKeys: Set<String> = []
    private var attemptedPATCHes = 0
    private var firstPATCH: PatchLogicalRequest?
    private var firstPATCHAuthorization: String?
    private var patchKeys: Set<String> = []

    private struct PatchLogicalRequest: Equatable {
        let method: String?
        let url: URL?
        let body: Data
        let requestID: String?
        let key: String
        init(_ request: URLRequest, body: Data, key: String) {
            method = request.httpMethod; url = request.url; self.body = body
            requestID = request.value(forHTTPHeaderField: "X-Request-Id"); self.key = key
        }
    }

    /// Contains safe request metadata only. Authorization is NEVER placed here.
    private struct LogicalRequest: Equatable {
        let method: String?
        let url: URL?
        let bodyIsAbsent: Bool
        let requestID: String?
        let idempotencyKey: String?
        init(_ request: URLRequest) {
            method = request.httpMethod
            url = request.url
            bodyIsAbsent = request.httpBody == nil && request.httpBodyStream == nil
            requestID = request.value(forHTTPHeaderField: "X-Request-Id")
            idempotencyKey = request.value(forHTTPHeaderField: "Idempotency-Key")
        }
        var isValidRead: Bool {
            bodyIsAbsent && requestID?.isEmpty == false && idempotencyKey == nil
        }
    }

    init(probe: C11RootNavigationProbe, selection: C11RootNavigationSelection,
         patchState: C11RootNavigationPatchState?, deleteState: C11RootNavigationDeleteState?,
         deliveryObservation: C11RootNavigationDeliveryObservation? = nil) {
        self.probe = probe
        self.selection = selection
        self.patchState = patchState
        self.deleteState = deleteState
        self.deliveryObservation = deliveryObservation
    }

    func respond(to request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
        if selection == .newCredentialRefresh { return try await respondToNewCredentialRefresh(request) }
        if selection == .completed401Foreground { return try await respondToHeld401Foreground(request) }
        if selection.observesDelivery { return try await respondToDeliveryControl(request) }
        if selection == .sameRecordForeground { return try await respondToForegroundRead(request) }
        if selection == .logoutMarkerFailure { return try await respondToRecoveryRead(request) }
        guard request.url?.absoluteString == "https://c11-ui.fixture.invalid/api/mobile/v1/meal-records/11111111-1111-4111-8111-111111111111" else {
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
        if request.httpMethod == "PATCH" {
            return try await respondToPATCH(request)
        }
        if request.httpMethod == "DELETE" {
            return try await respondToDELETE(request)
        }
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil else {
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
        attemptedGETs += 1
        await probe.recordGET()
        guard selection == .getUnauthorizedThenSuccess || selection == .getUnauthorizedTwice
            || selection == .getUnauthorizedTwiceThenRetrySuccess else {
            return C11RootNavigationHTTPResponse(statusCode: 200,
                data: try JSONEncoder().encode(C11RootNavigationFacts.detail()))
        }
        switch attemptedGETs {
        case 1:
            firstLogicalRequest = LogicalRequest(request)
            firstAuthorization = request.value(forHTTPHeaderField: "Authorization")
            let error = ["error": ["code": "expired_token", "message": "Synthetic fixture unauthorized",
                                     "request_id": "c11-ui-unauthorized"]]
            return C11RootNavigationHTTPResponse(statusCode: 401,
                data: try JSONSerialization.data(withJSONObject: error))
        case 2:
            let second = LogicalRequest(request)
            let currentAuthorization = request.value(forHTTPHeaderField: "Authorization")
            let sameLogical = firstLogicalRequest == second && second.isValidRead
            let changed = firstAuthorization?.hasPrefix("Bearer ") == true
                && currentAuthorization?.hasPrefix("Bearer ") == true
                && firstAuthorization != currentAuthorization
            firstAuthorization = nil
            await probe.recordReplayComparison(sameLogical: sameLogical, bearerChanged: changed)
            if selection == .getUnauthorizedTwiceThenRetrySuccess {
                manualRetrySecondLogical = second
                manualRetrySecondAuthorization = currentAuthorization
            }
            if selection == .getUnauthorizedTwice || selection == .getUnauthorizedTwiceThenRetrySuccess {
                let error = ["error": ["code": "invalid_access_token", "message": "Synthetic fixture second unauthorized",
                                         "request_id": "c11-ui-second-unauthorized"]]
                return C11RootNavigationHTTPResponse(statusCode: 401,
                    data: try JSONSerialization.data(withJSONObject: error))
            }
            return C11RootNavigationHTTPResponse(statusCode: 200,
                data: try JSONEncoder().encode(C11RootNavigationFacts.detail()))
        case 3:
            guard selection == .getUnauthorizedTwiceThenRetrySuccess,
                  let first = firstLogicalRequest, let second = manualRetrySecondLogical else {
                await probe.recordBlocked()
                throw MobileAPITransportError.invalidResponse
            }
            let third = LogicalRequest(request)
            let thirdAuthorization = request.value(forHTTPHeaderField: "Authorization")
            let newID = third.requestID?.isEmpty == false
                && third.requestID != first.requestID && third.requestID != second.requestID
            let sameCurrentBearer = manualRetrySecondAuthorization?.hasPrefix("Bearer ") == true
                && thirdAuthorization?.hasPrefix("Bearer ") == true
                && manualRetrySecondAuthorization == thirdAuthorization
            let noBody = third.bodyIsAbsent
            let noKey = third.idempotencyKey == nil
            manualRetrySecondAuthorization = nil
            await probe.recordManualReadComparison(newRequestID: newID, sameCurrentBearer: sameCurrentBearer,
                bodyAbsent: noBody, keyAbsent: noKey)
            guard first == second, second.isValidRead, third.method == second.method,
                  third.url == second.url, third.isValidRead, newID, sameCurrentBearer, noBody, noKey else {
                await probe.recordBlocked()
                throw MobileAPITransportError.invalidResponse
            }
            return C11RootNavigationHTTPResponse(statusCode: 200,
                data: try JSONEncoder().encode(C11RootNavigationFacts.detail()))
        default:
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
    }


    /// A1=401 over A; separate A2=200 over N. Never admit old A1 replay as A2.
    private func respondToNewCredentialRefresh(_ request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
        if request.httpMethod == "GET" {
            attemptedGETs += 1
            await probe.recordGET()
        } else { await probe.recordForegroundCommand() }
        let logical = LogicalRequest(request)
        let allowed = await probe.canServeNewCredentialRead(attempt: attemptedGETs)
        guard allowed, logical.method == "GET", logical.isValidRead,
              request.url?.absoluteString == "https://c11-ui.fixture.invalid/api/mobile/v1/meal-records/11111111-1111-4111-8111-111111111111" else {
            await probe.recordBlocked(); throw MobileAPITransportError.invalidResponse
        }
        await probe.recordForegroundReadMetadata(bodyAbsent: logical.bodyIsAbsent,
            keyAbsent: logical.idempotencyKey == nil)
        if attemptedGETs == 1 {
            let usesOld = request.value(forHTTPHeaderField: "Authorization") == "Bearer " + C11RootI4Facts.old.accessToken
            await MainActor.run { probe.newCredential?.firstReadUsesOld = usesOld }
            guard usesOld else { await probe.recordBlocked(); throw MobileAPITransportError.invalidResponse }
            firstLogicalRequest = logical // Safe metadata only; no authorization copy.
            let error = ["error": ["code": "expired_token", "message": "Synthetic I4 unauthorized",
                                     "request_id": "c11-ui-i4-401"]]
            return C11RootNavigationHTTPResponse(statusCode: 401,
                data: try JSONSerialization.data(withJSONObject: error))
        }
        let distinct = attemptedGETs == 2 && logical.requestID != firstLogicalRequest?.requestID
        let usesNewest = request.value(forHTTPHeaderField: "Authorization") == "Bearer " + C11RootI4Facts.newest.accessToken
        await MainActor.run {
            probe.newCredential?.newReadID = distinct
            probe.newCredential?.secondReadUsesNew = usesNewest
        }
        guard distinct, usesNewest else { await probe.recordBlocked(); throw MobileAPITransportError.invalidResponse }
        // This admission intentionally does not wait for an old-outcome counter.
        // Final UI separately requires the real old post-base outcome and storeN.
        return C11RootNavigationHTTPResponse(statusCode: 200,
            data: try JSONEncoder().encode(C11RootNavigationFacts.foregroundDetail()))
    }

    /// A1 is an actual completed401; A2 is a separate current read, never replay.
    private func respondToHeld401Foreground(_ request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
        if request.httpMethod == "GET" {
            attemptedGETs += 1
            await probe.recordGET()
        } else { await probe.recordForegroundCommand() }
        let logical = LogicalRequest(request)
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let allowed = await probe.canServeForegroundRead(attempt: attemptedGETs)
        guard allowed, logical.method == "GET", logical.isValidRead,
              request.url?.absoluteString == "https://c11-ui.fixture.invalid/api/mobile/v1/meal-records/11111111-1111-4111-8111-111111111111",
              authorization?.hasPrefix("Bearer ") == true, (authorization?.count ?? 0) > 7 else {
            await probe.recordBlocked(); throw MobileAPITransportError.invalidResponse
        }
        await probe.recordForegroundReadMetadata(bodyAbsent: logical.bodyIsAbsent,
            keyAbsent: logical.idempotencyKey == nil)
        if attemptedGETs == 1 {
            firstLogicalRequest = logical // No bearer/lease is retained by this mode.
            let error = ["error": ["code": "expired_token", "message": "Synthetic held401 unauthorized",
                                     "request_id": "c11-ui-held401"]]
            return C11RootNavigationHTTPResponse(statusCode: 401,
                data: try JSONSerialization.data(withJSONObject: error))
        }
        let distinct = attemptedGETs == 2 && firstLogicalRequest?.requestID != logical.requestID
        let releasedAfterStart = await MainActor.run {
            probe.foregroundFinished == 1 && probe.held401?.normalRelease == 1
        }
        await MainActor.run { probe.held401?.newReadID = distinct }
        guard distinct, releasedAfterStart else {
            await probe.recordBlocked(); throw MobileAPITransportError.invalidResponse
        }
        // No consumer-entry gate: A2 admission must not manufacture the ordering.
        return C11RootNavigationHTTPResponse(statusCode: 200,
            data: try JSONEncoder().encode(C11RootNavigationFacts.foregroundDetail()))
    }

    /// Separate harness controls; these never claim the held-finish I3 journey.
    private func respondToDeliveryControl(_ request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
        let logical = LogicalRequest(request)
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        guard logical.method == "GET", logical.isValidRead,
              request.url?.absoluteString == "https://c11-ui.fixture.invalid/api/mobile/v1/meal-records/11111111-1111-4111-8111-111111111111",
              authorization?.hasPrefix("Bearer ") == true, (authorization?.count ?? 0) > 7 else {
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
        attemptedGETs += 1
        await probe.recordGET()
        if selection == .observeDeliveryFailure {
            guard attemptedGETs == 1 else { await probe.recordBlocked(); throw MobileAPITransportError.invalidResponse }
            throw URLError(.cannotDecodeContentData)
        }
        if selection == .observeDeliveryCancellation {
            guard attemptedGETs == 1, let deliveryObservation else {
                await probe.recordBlocked(); throw MobileAPITransportError.invalidResponse
            }
            await probe.recordDeliveryWaiting()
            // Only this cancellation CONTROL waits before delivery. The later
            // I3 journey must instead hold lifecycle.finish after completed401.
            // The existing LoadingContext task owns this child await; actual
            // stopLoading cancels it and the cancellation handler releases it.
            try await deliveryObservation.waitForActualCancellation()
            throw MobileAPITransportError.invalidResponse
        }
        guard selection == .observeCompleted401 else {
            await probe.recordBlocked(); throw MobileAPITransportError.invalidResponse
        }
        if attemptedGETs == 1 {
            firstLogicalRequest = logical
            firstAuthorization = authorization
            let error = ["error": ["code": "expired_token", "message": "Synthetic observation unauthorized",
                                     "request_id": "c11-ui-observation-401"]]
            return C11RootNavigationHTTPResponse(statusCode: 401,
                data: try JSONSerialization.data(withJSONObject: error))
        }
        let sameLogical = attemptedGETs == 2 && logical == firstLogicalRequest
        let changed = firstAuthorization?.hasPrefix("Bearer ") == true && firstAuthorization != authorization
        firstAuthorization = nil
        guard sameLogical, changed else {
            await probe.recordBlocked(); throw MobileAPITransportError.invalidResponse
        }
        await probe.recordReplayComparison(sameLogical: sameLogical, bearerChanged: changed)
        return C11RootNavigationHTTPResponse(statusCode: 200,
            data: try JSONEncoder().encode(C11RootNavigationFacts.detail()))
    }

    private func respondToForegroundRead(_ request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
        if request.httpMethod == "GET" {
            attemptedGETs += 1
            await probe.recordGET()
        } else { await probe.recordForegroundCommand() }
        let logical = LogicalRequest(request)
        let bearer = request.value(forHTTPHeaderField: "Authorization")
        let allowed = await probe.canServeForegroundRead(attempt: attemptedGETs)
        guard allowed, logical.method == "GET", logical.isValidRead,
              request.url?.absoluteString == "https://c11-ui.fixture.invalid/api/mobile/v1/meal-records/11111111-1111-4111-8111-111111111111",
              bearer?.hasPrefix("Bearer ") == true, (bearer?.count ?? 0) > 7 else {
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
        await probe.recordForegroundReadMetadata(bodyAbsent: logical.bodyIsAbsent,
            keyAbsent: logical.idempotencyKey == nil)
        return C11RootNavigationHTTPResponse(statusCode: 200,
            data: try JSONEncoder().encode(attemptedGETs == 1
                ? C11RootNavigationFacts.detail() : C11RootNavigationFacts.foregroundDetail()))
    }

    /// One fresh official read, only after actual failed logout and explicit new binding.
    /// Unknown methods/routes/extra reads are intercepted and fail closed here.
    private func respondToRecoveryRead(_ request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
        if request.httpMethod == "GET" {
            attemptedGETs += 1
            await probe.recordGET()
        } else {
            await probe.recordRecoveryCommand()
        }
        let logical = LogicalRequest(request)
        let bearer = request.value(forHTTPHeaderField: "Authorization")
        let allowed = await probe.canServeRecoveryRead
        guard allowed, attemptedGETs == 1, logical.method == "GET", logical.isValidRead,
              request.url?.absoluteString == "https://c11-ui.fixture.invalid/api/mobile/v1/meal-records/11111111-1111-4111-8111-111111111111",
              bearer?.hasPrefix("Bearer ") == true, (bearer?.count ?? 0) > 7 else {
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
        await probe.recordRecoveryReadMetadata(bodyAbsent: logical.bodyIsAbsent,
            keyAbsent: logical.idempotencyKey == nil)
        return C11RootNavigationHTTPResponse(statusCode: 200,
            data: try JSONEncoder().encode(C11RootNavigationFacts.recoveredDetail()))
    }

    private func respondToPATCH(_ request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
        guard selection == .patchUnauthorizedThenSuccess, let patchState,
              let body = try? Self.bodyData(request),
              let decoded = try? JSONDecoder().decode(MealRecordPatchBody.self, from: body),
              decoded == C11RootNavigationPatchFacts.expectedBody,
              let key = request.value(forHTTPHeaderField: "Idempotency-Key"), !key.isEmpty,
              let requestID = request.value(forHTTPHeaderField: "X-Request-Id"), !requestID.isEmpty else {
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
        attemptedPATCHes += 1
        patchKeys.insert(key)
        await probe.recordPATCH(uniqueKeys: patchKeys.count)
        let logical = PatchLogicalRequest(request, body: body, key: key)
        switch attemptedPATCHes {
        case 1:
            firstPATCH = logical
            firstPATCHAuthorization = request.value(forHTTPHeaderField: "Authorization")
            let error = ["error": ["code": "expired_token", "message": "Synthetic PATCH unauthorized",
                                     "request_id": "c11-ui-patch-401"]]
            return C11RootNavigationHTTPResponse(statusCode: 401,
                data: try JSONSerialization.data(withJSONObject: error))
        case 2:
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            let same = firstPATCH == logical
            let changed = firstPATCHAuthorization?.hasPrefix("Bearer ") == true
                && authorization?.hasPrefix("Bearer ") == true && firstPATCHAuthorization != authorization
            firstPATCHAuthorization = nil
            guard same && changed else {
                await probe.recordBlocked()
                throw MobileAPITransportError.invalidResponse
            }
            try await patchState.commit()
            await probe.recordReplayComparison(sameLogical: same, bearerChanged: changed)
            return C11RootNavigationHTTPResponse(statusCode: 200,
                data: try JSONEncoder().encode(C11RootNavigationPatchFacts.receipt()))
        default:
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
    }

    private func respondToDELETE(_ request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
        guard selection == .deleteUnauthorizedThenSuccess, let deleteState,
              let body = try? Self.bodyData(request),
              let object = try? JSONSerialization.jsonObject(with: body),
              let json = object as? [String: Any],
              Set(json.keys) == Set(["expected_version", "item_ids"]),
              let decoded = try? JSONDecoder().decode(MealRecordDeleteBody.self, from: body),
              decoded == C11RootNavigationDeleteFacts.expectedBody,
              let key = request.value(forHTTPHeaderField: "Idempotency-Key"), !key.isEmpty,
              let requestID = request.value(forHTTPHeaderField: "X-Request-Id"), !requestID.isEmpty else {
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
        attemptedDELETEs += 1
        deleteKeys.insert(key)
        await probe.recordDELETE(uniqueKeys: deleteKeys.count)
        let logical = PatchLogicalRequest(request, body: body, key: key)
        switch attemptedDELETEs {
        case 1:
            firstDELETE = logical
            firstDELETEAuthorization = request.value(forHTTPHeaderField: "Authorization")
            let error = ["error": ["code": "expired_token", "message": "Synthetic DELETE unauthorized",
                                     "request_id": "c11-ui-delete-401"]]
            return C11RootNavigationHTTPResponse(statusCode: 401,
                data: try JSONSerialization.data(withJSONObject: error))
        case 2:
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            let same = firstDELETE == logical
            let changed = firstDELETEAuthorization?.hasPrefix("Bearer ") == true
                && authorization?.hasPrefix("Bearer ") == true && firstDELETEAuthorization != authorization
            firstDELETEAuthorization = nil
            guard same && changed else {
                await probe.recordBlocked()
                throw MobileAPITransportError.invalidResponse
            }
            try await deleteState.commit()
            await probe.recordReplayComparison(sameLogical: same, bearerChanged: changed)
            return C11RootNavigationHTTPResponse(statusCode: 200,
                data: try JSONEncoder().encode(C11RootNavigationDeleteFacts.receipt()))
        default:
            await probe.recordBlocked()
            throw MobileAPITransportError.invalidResponse
        }
    }

    /// URLSession may hand URLProtocol a body stream. Materialize only this
    /// bounded synthetic command; never log it or allow an unbounded read.
    private static func bodyData(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody {
            guard data.count <= 16_384 else { throw MobileAPITransportError.invalidResponse }
            return data
        }
        guard let stream = request.httpBodyStream else { throw MobileAPITransportError.invalidResponse }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let capacity = buffer.count
            let count = stream.read(&buffer, maxLength: capacity)
            guard count >= 0 else { throw MobileAPITransportError.invalidResponse }
            if count == 0 { break }
            guard data.count + count <= 16_384 else { throw MobileAPITransportError.invalidResponse }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

/// Counts only source.bind captures; all authority/visible state operations delegate to the REAL base.
private actor C11RootNavigationLifecycleProbe: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    let probe: C11RootNavigationProbe
    private let capturesForegroundGrants: Bool
    init(base: SessionLifecycleCoordinator, probe: C11RootNavigationProbe, capturesForegroundGrants: Bool = false) {
        self.base = base; self.probe = probe
        self.capturesForegroundGrants = capturesForegroundGrants
    }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease {
        await probe.recordBind()
        return try await base.leaseForRequest()
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
        try await base.refreshAfterUnauthorized(lease: lease)
    }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        try await base.beginPatientWork(lease: lease, cancel: cancel)
    }
    func finishPatientWork(_ id: UUID) async { await base.finishPatientWork(id) }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        guard capturesForegroundGrants else {
            return try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
        }
        let probe = probe
        // Copy only non-secret fields; never retain SessionLease/bearer.
        let userID = lease.userID, generation = lease.generation
        return try await base.performVisiblePatientStateOperation(lease: lease) {
            let original = try operation()
            if let capability = original as? MealRecordSessionCapability {
                probe.recordForegroundGrant(capability, userID: userID, generation: generation)
            }
            return original
        }
    }
}


/// Only the Back cancellation control uses this forwarding lifecycle.
/// The source binding still uses its unchanged bindingProbe and the same
/// real coordinator. This adapter grants no authority and retains no lease,
/// work identifier, token or request. Count/boolean are its only observation.
private actor C11RootNavigationCancelledCallerObservation: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    let probe: C11RootNavigationProbe
    init(base: SessionLifecycleCoordinator, probe: C11RootNavigationProbe) {
        self.base = base
        self.probe = probe
    }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease { try await base.leaseForRequest() }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
        try await base.refreshAfterUnauthorized(lease: lease)
    }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        try await base.beginPatientWork(lease: lease, cancel: cancel)
    }
    func finishPatientWork(_ id: UUID) async {
        let cancelledAtEntry = Task.isCancelled // Before the first await.
        await probe.recordDeliveryCallerFinish(cancelledAtEntry: cancelledAtEntry)
        await base.finishPatientWork(id)
    }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

// URLProtocol itself is not transferred into an async closure. Only the narrow
// immutable-handle loading context below crosses that boundary.
private final class C11RootNavigationURLProtocol: URLProtocol {
    private static let registry = C11RootNavigationProtocolRegistry()
    private let lock = NSLock()
    private var loadingContext: C11RootNavigationLoadingContext?
    private var stopped = false

    static func install(_ server: C11RootNavigationServer) { registry.install(server) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let server = Self.registry.current
        let context: C11RootNavigationLoadingContext
        if let observation = server?.deliveryObservation {
            context = C11RootNavigationLoadingContext(protocolInstance: self, request: request,
                server: server, client: client, observation: observation)
        } else {
            // Keep the old call without an observer for every old selection.
            context = C11RootNavigationLoadingContext(protocolInstance: self, request: request,
                server: server, client: client)
        }
        start(context)
    }

    @discardableResult
    private func start(_ context: C11RootNavigationLoadingContext) -> Task<Void, Never>? {
        let admission: (accepted: Bool, cancelImmediately: Bool) = lock.withLock {
            guard loadingContext == nil else { return (false, false) }
            loadingContext = context
            return (true, stopped)
        }
        guard admission.accepted else { return nil }
        if admission.cancelImmediately { context.cancel() }
        return context.start()
    }

    /// Dedicated instance only: never reads or installs the shared registry.
    fileprivate func startReentryControl(server: C11RootNavigationServer,
        observation: C11RootNavigationDeliveryObservation) -> C11RootNavigationReentryWork? {
        let context = C11RootNavigationLoadingContext(protocolInstance: self, request: request,
            server: server, client: client, observation: observation)
        guard let work = start(context) else { return nil }
        return C11RootNavigationReentryWork(context: context, task: work)
    }
    fileprivate var hasReleasedReentryContext: Bool { lock.withLock { loadingContext == nil } }

    override func stopLoading() {
        let current = lock.withLock {
            stopped = true
            return loadingContext
        }
        current?.observeActualStopLoading()
        current?.cancel()
    }

    fileprivate func release(_ context: C11RootNavigationLoadingContext) {
        lock.withLock {
            if loadingContext === context { loadingContext = nil }
        }
    }
}

/// The known loading-context pattern, with one immutable request/server/client
/// and serialized terminal delivery. No mutable URLProtocol properties are read
/// by the task. Its own start/cancel/finish state is protected by this lock.
private final class C11RootNavigationLoadingContext: @unchecked Sendable {
    private let protocolInstance: C11RootNavigationURLProtocol
    private let request: URLRequest
    private let server: C11RootNavigationServer?
    private let client: (any URLProtocolClient)?
    private let observation: C11RootNavigationDeliveryObservation?
    // Client delivery may synchronously call stopLoading: allow that reentry.
    private let lock = NSRecursiveLock()
    private var started = false
    private var cancelled = false
    private var terminalDelivered = false
    private var finished = false
    private var task: Task<Void, Never>?

    init(protocolInstance: C11RootNavigationURLProtocol, request: URLRequest,
         server: C11RootNavigationServer?, client: (any URLProtocolClient)?,
         observation: C11RootNavigationDeliveryObservation? = nil) {
        self.protocolInstance = protocolInstance
        self.request = request
        self.server = server
        self.client = client
        self.observation = observation
    }

    /// Pure observation under the existing context lock, before the unchanged
    /// cancellation call. A stop after terminal admission (including callback
    /// reentry) is cleanup; it does not erase a completed terminal response.
    func observeActualStopLoading() {
        guard let observation else { return }
        // terminalDelivered is the existing admission flag, set before the
        // callback. Reentry inside it is post-admission, not pre-terminal.
        lock.withLock { observation.recordStop(beforeTerminalAdmission: !terminalDelivered) }
    }

    @discardableResult
    func start() -> Task<Void, Never>? {
        let admitted = lock.withLock {
            guard !started, !cancelled, !finished else { return false }
            started = true
            return true
        }
        guard admitted else {
            finish()
            return nil
        }
        // The sendable context is the sole async capture; not the URLProtocol.
        let work = Task { await run() }
        let cancelNow = lock.withLock {
            guard !cancelled, !finished else { return true }
            task = work
            return false
        }
        if cancelNow { work.cancel() }
        return work
    }

    fileprivate var hasFinishedForReentryControl: Bool { lock.withLock { finished && task == nil } }

    func cancel() {
        let pending = lock.withLock {
            cancelled = true
            return task
        }
        pending?.cancel()
    }

    private func run() async {
        defer { finish() }
        do {
            try Task.checkCancellation()
            guard !isCancelled, let server else {
                if isCancelled { return }
                throw MobileAPITransportError.invalidResponse
            }
            let reply = try await server.respond(to: request)
            try Task.checkCancellation()
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: reply.statusCode, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]) else {
                throw MobileAPITransportError.invalidResponse
            }
            deliver(response: response, data: reply.data)
        } catch is CancellationError {
            // URLSession already owns cancellation; no callback after stopLoading.
        } catch {
            deliver(error: error)
        }
        // Existing owned task publishes only AFTER callback/lock return.
        // No Task, await or executor hop is introduced inside client callbacks.
        if let observation { await observation.publish() }
    }

    private func deliver(response: HTTPURLResponse, data: Data) {
        lock.withLock {
            guard !cancelled, !terminalDelivered, !finished, let client else { return }
            client.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
            guard !cancelled else { return }
            client.urlProtocol(protocolInstance, didLoad: data)
            guard !cancelled else { return }
            terminalDelivered = true
            client.urlProtocolDidFinishLoading(protocolInstance)
            if let observation {
                observation.recordSuccess(statusCode: response.statusCode)
            }
        }
    }

    private func deliver(error: any Error) {
        lock.withLock {
            guard !cancelled, !terminalDelivered, !finished, let client else { return }
            terminalDelivered = true
            client.urlProtocol(protocolInstance, didFailWithError: error)
            if let observation {
                observation.recordFailure(cancelled: error is CancellationError
                    || (error as? URLError)?.code == .cancelled)
            }
        }
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    private func finish() {
        lock.withLock {
            finished = true
            task = nil
        }
        // Break URLProtocol -> context -> URLProtocol after the task returns.
        protocolInstance.release(self)
    }
}

private final class C11RootNavigationProtocolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var server: C11RootNavigationServer?
    var current: C11RootNavigationServer? { lock.withLock { server } }
    func install(_ value: C11RootNavigationServer) { lock.withLock { server = value } }
}

/// Aggregated synthetic observations only; not request/session authority.
struct C11RootNavigationDeliverySnapshot: Equatable, Sendable {
    var completed401 = 0
    var success = 0
    var error = 0
    var callbackCancel = 0
    var stopBefore = 0
    var stopAfter = 0
}

/// Called synchronously inside the existing recursive callback lock. It does
/// no scheduling, callback, await or I/O there. The already-owned run() task
/// publishes an immutable snapshot only after leaving that lock/callback.
private final class C11RootNavigationDeliveryObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = C11RootNavigationDeliverySnapshot()
    private let probe: C11RootNavigationProbe
    private var cancellationReleased = false
    private var cancellationWaiter: CheckedContinuation<Void, Never>?
    private let held401Checkpoint: C11RootHeld401Checkpoint?
    init(probe: C11RootNavigationProbe, held401Checkpoint: C11RootHeld401Checkpoint? = nil) {
        self.probe = probe
        self.held401Checkpoint = held401Checkpoint
    }

    func recordSuccess(statusCode: Int) {
        lock.withLock {
            snapshot.success += 1
            if statusCode == 401 { snapshot.completed401 += 1 }
        }
    }
    func recordFailure(cancelled: Bool) {
        lock.withLock {
            snapshot.error += 1
            if cancelled { snapshot.callbackCancel += 1 }
        }
    }
    func recordStop(beforeTerminalAdmission: Bool) {
        lock.withLock {
            if beforeTerminalAdmission { snapshot.stopBefore += 1 }
            else { snapshot.stopAfter += 1 }
        }
    }
    fileprivate var snapshotForReentryControl: C11RootNavigationDeliverySnapshot { lock.withLock { snapshot } }
    func publish() async {
        let current = lock.withLock { snapshot }
        await probe.recordDelivery(current)
        // Existing owned task, strictly after callback/observer/context locks
        // and after the snapshot is published. Nil in every old selection.
        held401Checkpoint?.recordPublishedTerminal(current)
    }
    func waitForActualCancellation() async throws {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let releaseNow = lock.withLock {
                    if cancellationReleased { return true }
                    cancellationWaiter = continuation
                    return false
                }
                if releaseNow { continuation.resume() }
            }
        } onCancel: {
            self.releaseCancellationWaiter()
        }
        try Task.checkCancellation()
        throw MobileAPITransportError.invalidResponse
    }
    private func releaseCancellationWaiter() {
        let waiting = lock.withLock {
            cancellationReleased = true
            let pending = cancellationWaiter
            cancellationWaiter = nil
            return pending
        }
        waiting?.resume()
    }
}

/// Returned only to native DEBUG tests. Contains no protocol, server, payload,
/// credential or request identifier; every field is an aggregate/boolean.
struct C11RootNavigationReentryResult: Sendable {
    let beforeStop: C11RootNavigationDeliverySnapshot
    let insideCallbackAfterStop: C11RootNavigationDeliverySnapshot
    let afterOwnedTask: C11RootNavigationDeliverySnapshot
    let receivedCallbacks: Int
    let dataCallbacks: Int
    let finishedCallbacks: Int
    let failedCallbacks: Int
    let unexpectedCallbacks: Int
    let contextFinished: Bool
    let protocolReleasedContext: Bool
}

/// No registry, URLSession, auth, grant or lease is installed by this driver.
/// It runs the same actual context.start/run/deliver and actual stopLoading.
@MainActor
enum C11RootNavigationReentryControl {
    enum Mode: Equatable, Sendable { case success401, failure }
    static func run(_ mode: Mode) async throws -> C11RootNavigationReentryResult {
        try Task.checkCancellation()
        let probe = C11RootNavigationProbe()
        let observation = C11RootNavigationDeliveryObservation(probe: probe)
        let selection: C11RootNavigationSelection = mode == .success401 ? .observeCompleted401 : .observeDeliveryFailure
        let server = C11RootNavigationServer(probe: probe, selection: selection,
            patchState: nil, deleteState: nil, deliveryObservation: observation)
        var request = URLRequest(url: URL(string: "https://c11-ui.fixture.invalid/api/mobile/v1/meal-records/11111111-1111-4111-8111-111111111111")!)
        request.httpMethod = "GET"
        request.setValue("Bearer synthetic-reentry-control", forHTTPHeaderField: "Authorization")
        request.setValue("synthetic-reentry-control", forHTTPHeaderField: "X-Request-Id")
        let client = C11RootNavigationReentrantClient(observation: observation)
        let instance = C11RootNavigationURLProtocol(request: request, cachedResponse: nil, client: client)
        guard let owned = instance.startReentryControl(server: server, observation: observation) else {
            throw C11RootNavigationReentrySetupError.taskNotAdmitted
        }
        defer { owned.context.cancel() } // Synchronous/idempotent, never creates a Task.
        await withTaskCancellationHandler {
            await owned.task.value // Join the real existing loading task through defer finish.
        } onCancel: {
            owned.context.cancel()
        }
        try Task.checkCancellation()
        let callbacks = client.result
        guard let before = callbacks.before, let inside = callbacks.inside else {
            throw C11RootNavigationReentrySetupError.terminalCallbackMissing
        }
        return C11RootNavigationReentryResult(beforeStop: before,
            insideCallbackAfterStop: inside, afterOwnedTask: observation.snapshotForReentryControl,
            receivedCallbacks: callbacks.received, dataCallbacks: callbacks.data,
            finishedCallbacks: callbacks.finished, failedCallbacks: callbacks.failed,
            unexpectedCallbacks: callbacks.unexpected,
            contextFinished: owned.context.hasFinishedForReentryControl,
            protocolReleasedContext: instance.hasReleasedReentryContext)
    }
}

private enum C11RootNavigationReentrySetupError: Error { case taskNotAdmitted, terminalCallbackMissing }
private struct C11RootNavigationReentryWork: Sendable {
    let context: C11RootNavigationLoadingContext
    let task: Task<Void, Never>
}

/// Synthetic boundary client; no prepared phase boolean is passed to the
/// observer. Real stopLoading reads the real context's admission flag.
/// No client lock is held during reentry, and no continuation is resumed here.
private final class C11RootNavigationReentrantClient: NSObject, URLProtocolClient, @unchecked Sendable {
    struct Result {
        var before: C11RootNavigationDeliverySnapshot?
        var inside: C11RootNavigationDeliverySnapshot?
        var received = 0, data = 0, finished = 0, failed = 0, unexpected = 0
    }
    private let lock = NSLock()
    private var stored = Result()
    private let observation: C11RootNavigationDeliveryObservation
    init(observation: C11RootNavigationDeliveryObservation) {
        self.observation = observation
        super.init()
    }
    var result: Result { lock.withLock { stored } }
    private func reenter(_ instance: URLProtocol, finished: Bool) {
        let before = observation.snapshotForReentryControl
        instance.stopLoading() // Real override, synchronously inside real terminal callback.
        let inside = observation.snapshotForReentryControl
        lock.withLock {
            if stored.before == nil { stored.before = before; stored.inside = inside }
            if finished { stored.finished += 1 } else { stored.failed += 1 }
        }
    }
    func urlProtocolDidFinishLoading(_ instance: URLProtocol) { reenter(instance, finished: true) }
    func urlProtocol(_ instance: URLProtocol, didFailWithError error: Error) { reenter(instance, finished: false) }
    func urlProtocol(_ instance: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {
        lock.withLock { stored.received += 1 }
    }
    func urlProtocol(_ instance: URLProtocol, didLoad data: Data) { lock.withLock { stored.data += 1 } }
    func urlProtocol(_ instance: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {
        lock.withLock { stored.unexpected += 1 }
    }
    func urlProtocol(_ instance: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) {
        lock.withLock { stored.unexpected += 1 }
    }
    func urlProtocol(_ instance: URLProtocol, didReceive challenge: URLAuthenticationChallenge) {
        lock.withLock { stored.unexpected += 1 }
    }
    func urlProtocol(_ instance: URLProtocol, didCancel challenge: URLAuthenticationChallenge) {
        lock.withLock { stored.unexpected += 1 }
    }
}

#endif
