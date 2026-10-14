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
            (.deleteUnauthorizedThenSuccess, "--ui-testing-c11-root-delete-401-200")
        ]
        let selected = choices.filter { arguments.contains($0.1) }
        guard selected.count == 1 else { return nil }
        return selected[0].0
    }

    var suppliesMealRecordSource: Bool {
        switch self {
        case .sourceOn, .logoutMarkerFailure, .sameRecordForeground, .getUnauthorizedThenSuccess, .getUnauthorizedTwice, .getUnauthorizedTwiceThenRetrySuccess, .patchUnauthorizedThenSuccess, .deleteUnauthorizedThenSuccess: true
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

    static func make(selection: C11RootNavigationSelection) throws -> Self {
        let configuration = AppLaunchConfiguration(mode: .releaseUnavailable,
            shouldResetDemoState: false, startsWithCompletedFixture: true,
            preloadsSyntheticOnboardingValues: false, authBehavior: .succeed(after: nil))
        let probe = C11RootNavigationProbe()
        let record = try C11RootNavigationFacts.record()
        let secure = try C11RootNavigationSecureStore(record: record,
            markerFailureProbe: selection == .logoutMarkerFailure ? probe : nil)
        let store = AuthenticationSessionStore(secureStore: secure,
            now: { Date(timeIntervalSince1970: 1000) })
        let remote = C11RootNavigationRemote(probe: probe, selection: selection)
        let lifecycle = SessionLifecycleCoordinator(store: store, remote: remote,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        let bindingProbe = C11RootNavigationLifecycleProbe(base: lifecycle, probe: probe,
            capturesForegroundGrants: selection == .sameRecordForeground)
        let patchState = selection == .patchUnauthorizedThenSuccess ? C11RootNavigationPatchState(probe: probe) : nil
        let deleteState = selection == .deleteUnauthorizedThenSuccess ? C11RootNavigationDeleteState(probe: probe) : nil
        let server = C11RootNavigationServer(probe: probe, selection: selection,
            patchState: patchState, deleteState: deleteState)
        C11RootNavigationURLProtocol.install(server)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [C11RootNavigationURLProtocol.self]
        let transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://c11-ui.fixture.invalid"),
            sessionLifecycle: lifecycle, session: URLSession(configuration: sessionConfiguration),
            clock: ContinuousClock(), timeout: .seconds(5))
        // Only this explicitly selected synthetic harness can supply a source.
        let source = AppDependencies.makeMealRecordBindingSource(enabled: selection.suppliesMealRecordSource,
            mode: configuration.mode, client: transport, lifecycle: bindingProbe)
        let scaffold = AppDependencies.scaffold()
        let unavailable = UnavailableBodyFlowCapabilities()
        let reads = C11RootNavigationReads()
        let plan: any PlanProviding
        if selection == .sameRecordForeground {
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
        return Self(selection: selection, configuration: configuration, dependencies: dependencies, probe: probe)
    }
}

/// Read-only diagnostic values from actual source/transport/remote calls, never tokens.
@MainActor
@Observable
final class C11RootNavigationProbe {
    private(set) var gets = 0
    private(set) var binds = 0
    private(set) var refreshes = 0
    private(set) var blocked = 0
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
    @Environment(\.scenePhase) private var phase
    @State private var armed = false
    @State private var consumed = false

    init(originalModel: AppFlowModel, fixture: C11RootNavigationFixture?) {
        self.originalModel = originalModel
        probe = fixture?.selection == .sameRecordForeground ? fixture?.probe : nil
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
        } else { content }
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
    init(probe: C11RootNavigationProbe, selection: C11RootNavigationSelection) {
        self.probe = probe
        self.selection = selection
    }
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws { throw SupabaseAuthRemoteError.requestFailed }
    func refresh(record: AuthenticationSessionRecord) async throws -> AuthenticationSessionRecord {
        await probe.recordRefresh()
        guard selection == .getUnauthorizedThenSuccess || selection == .getUnauthorizedTwice
            || selection == .getUnauthorizedTwiceThenRetrySuccess || selection == .patchUnauthorizedThenSuccess
            || selection == .deleteUnauthorizedThenSuccess else {
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
         patchState: C11RootNavigationPatchState?, deleteState: C11RootNavigationDeleteState?) {
        self.probe = probe
        self.selection = selection
        self.patchState = patchState
        self.deleteState = deleteState
    }

    func respond(to request: URLRequest) async throws -> C11RootNavigationHTTPResponse {
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
        let context = C11RootNavigationLoadingContext(protocolInstance: self, request: request,
            server: Self.registry.current, client: client)
        let admission: (accepted: Bool, cancelImmediately: Bool) = lock.withLock {
            guard loadingContext == nil else { return (false, false) }
            loadingContext = context
            return (true, stopped)
        }
        guard admission.accepted else { return }
        if admission.cancelImmediately { context.cancel() }
        context.start()
    }

    override func stopLoading() {
        let current = lock.withLock {
            stopped = true
            return loadingContext
        }
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
    // Client delivery may synchronously call stopLoading: allow that reentry.
    private let lock = NSRecursiveLock()
    private var started = false
    private var cancelled = false
    private var terminalDelivered = false
    private var finished = false
    private var task: Task<Void, Never>?

    init(protocolInstance: C11RootNavigationURLProtocol, request: URLRequest,
         server: C11RootNavigationServer?, client: (any URLProtocolClient)?) {
        self.protocolInstance = protocolInstance
        self.request = request
        self.server = server
        self.client = client
    }

    func start() {
        let admitted = lock.withLock {
            guard !started, !cancelled, !finished else { return false }
            started = true
            return true
        }
        guard admitted else {
            finish()
            return
        }
        // The sendable context is the sole async capture; not the URLProtocol.
        let work = Task { await run() }
        let cancelNow = lock.withLock {
            guard !cancelled, !finished else { return true }
            task = work
            return false
        }
        if cancelNow { work.cancel() }
    }

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
        }
    }

    private func deliver(error: any Error) {
        lock.withLock {
            guard !cancelled, !terminalDelivered, !finished, let client else { return }
            terminalDelivered = true
            client.urlProtocol(protocolInstance, didFailWithError: error)
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

#endif
