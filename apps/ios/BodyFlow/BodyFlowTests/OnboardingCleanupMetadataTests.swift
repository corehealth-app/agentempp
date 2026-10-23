#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

// PRIVATE TEST DRAFT. Not compiled or executed by the author.
@MainActor
@Suite("Official onboarding cleanup metadata", .serialized)
struct OnboardingCleanupMetadataTests {
    @Test("M01 old GET/ACK remain authoritative without metadata")
    func oldGETAndACKCompatibility() throws {
        let state = try JSONDecoder().decode(OnboardingServerState.self, from: F.get())
        #expect(state.locale == "en-US")
        #expect(state.completion == OnboardingCompletionState(completed: false, completedAt: nil))
        #expect(state.requirements == .unavailable)
        #expect(state.acceptedActions.isEmpty)
        #expect(state.draft == nil)
        #expect(state.bodyPhotoCleanup == nil)
        let acknowledgement = try JSONDecoder().decode(OnboardingCompletionAcknowledgement.self, from: F.ack())
        #expect(acknowledgement.completedAt == F.oldG)
        #expect(acknowledgement.matches(F.draft()))
        #expect(acknowledgement.bodyPhotoCleanup == nil)
        let encodedState = try F.object(JSONEncoder().encode(state))
        let encodedACK = try F.object(JSONEncoder().encode(acknowledgement))
        #expect(encodedState["body_photo_cleanup"] == nil)
        #expect(encodedACK["body_photo_cleanup"] == nil)
    }

    @Test("M02 the three states preserve literal micros/offset and valid leap date")
    func validMetadataRetainsLiteralGeneration() throws {
        let states: [OnboardingBodyPhotoCleanupState] = [.notRequired, .pending, .unknown]
        let generations = [F.g1, "2026-10-12T15:00:00.123456-03:00", "2024-02-29T11:22:33.123456Z"]
        for state in states {
            for generation in generations {
                let metadata = F.scope(generation, state.rawValue)
                let decoded = try JSONDecoder().decode(OnboardingServerState.self,
                    from: F.get(completedAt: F.g2, metadata: metadata))
                let expected = OnboardingBodyPhotoCleanupScope(generation: generation, state: state)
                #expect(decoded.bodyPhotoCleanup == expected)
                let encoded = try F.object(JSONEncoder().encode(decoded))
                let roundtrip = encoded["body_photo_cleanup"] as? [String: Any]
                #expect(roundtrip?["generation"] as? String == generation)
                #expect(roundtrip?["state"] as? String == state.rawValue)
                let acknowledgement = try JSONDecoder().decode(OnboardingCompletionAcknowledgement.self,
                    from: F.ack(completedAt: generation, metadata: metadata))
                #expect(acknowledgement.bodyPhotoCleanup == expected)
                #expect(acknowledgement.completedAt == generation)
                #expect(acknowledgement.matches(F.draft()))
            }
        }
    }

    @Test("M03 malformed optional metadata never invalidates an otherwise valid base")
    func malformedMetadataIsUnavailableOnly() throws {
        let malformed: [Any] = [NSNull(), "pending", [], [:], ["state": "pending"],
            ["generation": F.g1], F.scope(F.g1, "none"), ["generation": 12, "state": "pending"],
            F.scope("not-a-time", "pending"), F.scope("2026-10-12T15:00:00.1234567Z", "pending"),
            F.scope("2026-02-30T11:22:33.123456Z", "pending"),
            F.scope("2025-02-29T11:22:33.123456Z", "pending"),
            ["generation": F.g1, "state": "pending", "asset_id": MetadataHTTPHarness.a]]
        for metadata in malformed {
            let state = try JSONDecoder().decode(OnboardingServerState.self, from: F.get(metadata: metadata))
            #expect(state.bodyPhotoCleanup == nil)
            #expect(state.locale == "en-US")
            #expect(state.requirements == .unavailable)
            let acknowledgement = try JSONDecoder().decode(OnboardingCompletionAcknowledgement.self,
                from: F.ack(metadata: metadata))
            #expect(acknowledgement.bodyPhotoCleanup == nil)
            #expect(acknowledgement.matches(F.draft()))
        }
    }

    @Test("M04 optional metadata cannot weaken required decoding or matches(draft)")
    func baseAuthorityRemainsStrict() throws {
        let metadata = F.scope(F.oldG, "pending")
        for field in ["locale", "completion", "requirements", "accepted_actions"] {
            var object = try F.object(F.get(metadata: metadata)); object[field] = "wrong-type"
            if field == "locale" { object.removeValue(forKey: field) }
            let data = try F.data(object)
            var rejected = false
            do { _ = try JSONDecoder().decode(OnboardingServerState.self, from: data) }
            catch { rejected = true }
            #expect(rejected)
        }
        for field in ["onboarding_completed", "persona", "objective", "document_actions", "protocol_welcome"] {
            var object = try F.object(F.ack(metadata: metadata)); object[field] = "wrong-type"
            let data = try F.data(object)
            var rejected = false
            do { _ = try JSONDecoder().decode(OnboardingCompletionAcknowledgement.self, from: data) }
            catch { rejected = true }
            #expect(rejected)
        }
        let base = try F.object(F.ack(metadata: metadata))
        var wrongObjective = base; wrongObjective["objective"] = "ganho_massa"
        var badTime = base; badTime["completed_at"] = "not-a-server-timestamp"
        var absentAction = base; absentAction["document_actions"] = []
        var duplicatedAction = base
        let actions = try #require(base["document_actions"] as? [[String: Any]])
        duplicatedAction["document_actions"] = actions + actions
        for object in [wrongObjective, badTime, absentAction, duplicatedAction] {
            let acknowledgement = try JSONDecoder().decode(OnboardingCompletionAcknowledgement.self,
                from: F.data(object))
            #expect(!acknowledgement.matches(F.draft()))
        }
    }

    @Test("M05 ACK metadata echo uses textual identity and does not reject valid completion")
    func ACKGenerationMismatchOnlyDropsMetadata() throws {
        for generation in [F.g2, F.aliasOfG1] {
            let acknowledgement = try JSONDecoder().decode(OnboardingCompletionAcknowledgement.self,
                from: F.ack(completedAt: F.g1, metadata: F.scope(generation, "pending")))
            #expect(acknowledgement.completedAt == F.g1)
            #expect(acknowledgement.bodyPhotoCleanup == nil)
            #expect(acknowledgement.matches(F.draft()))
        }
    }

    @Test("M06 historical GET sends the schema and one encoded literal generation and never mutates a draft")
    func historicalGETPreservesPositiveOffsetOnTheWire() async throws {
        let h = try await MetadataHTTPHarness(payload: F.envelope(F.get(
            completedAt: F.g2, metadata: F.scope(F.g1, "pending"))))
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: MetadataHTTPHarness.a)
        let before = try h.seedDraft(userID: MetadataHTTPHarness.a)
        let outcome = await Self.read(repository, generation: F.g1)
        #expect(outcome == .value(OnboardingBodyPhotoCleanupScope(generation: F.g1, state: .pending)))
        let requests = await h.peer.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/mobile/v1/onboarding")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
        let raw = try #require(request.url?.absoluteString)
        #expect(raw.contains("%2B"))
        #expect(!raw.contains("%252B"))
        let query = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery })
        #expect(query.split(separator: "&").count == 2)
        #expect(F.formValue(query, name: "onboarding_profile_schema") == "habitual_water_optional_v1")
        #expect(F.formValue(query, name: "body_photo_cleanup_generation") == F.g1)
        #expect(!query.contains("user_id"))
        #expect(!query.contains("locale"))
        #expect(try Data(contentsOf: h.draftStore.fileURL) == before)
    }

    @Test("M07 current absent-generation query and historical echo do not confuse profile G2 with G1")
    func currentAndHistoricalReadsUseTheirOwnEcho() async throws {
        let cases: [(requested: String?, current: String?, echoed: String, expected: OnboardingBodyPhotoCleanupScope?)] = [
            (F.g1, F.g2, F.g1, .init(generation: F.g1, state: .pending)),
            (F.g1, nil, F.g1, .init(generation: F.g1, state: .pending)),
            (F.g1, F.g2, F.g2, nil), (F.g1, F.g2, F.aliasOfG1, nil),
            (nil, F.g1, F.g1, .init(generation: F.g1, state: .pending)),
            (nil, F.g1, F.aliasOfG1, nil), (nil, nil, F.g1, nil)]
        for item in cases {
            let h = try await MetadataHTTPHarness(payload: F.envelope(F.get(
                completedAt: item.current, metadata: F.scope(item.echoed, "pending"))))
            defer { h.removeFolder() }
            let repository = try await h.repository.scoped(for: MetadataHTTPHarness.a)
            let before = try h.seedDraft(userID: MetadataHTTPHarness.a)
            let outcome = await Self.read(repository, generation: item.requested)
            #expect(outcome == .value(item.expected))
            let requests = await h.peer.requests
            #expect(requests.count == 1)
            let request = try #require(requests.first)
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
            if let generation = item.requested {
                #expect(F.formValue(query ?? "", name: "body_photo_cleanup_generation") == generation)
            } else {
                #expect(F.formValue(query ?? "", name: "body_photo_cleanup_generation") == nil)
            }
            let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(items.filter { $0.name == "onboarding_profile_schema" }.count == 1)
            #expect(F.formValue(query ?? "", name: "onboarding_profile_schema") == "habitual_water_optional_v1")
            #expect(items.count == (item.requested == nil ? 1 : 2))
            #expect(request.httpBody == nil)
            #expect(try Data(contentsOf: h.draftStore.fileURL) == before)
        }
    }

    @Test("M08 retained A lease cannot send or publish after B and a later A")
    func retainedLeaseAndHeldResponseCannotAuthorizeANewerSession() async throws {
        for returnToA in [false, true] {
            let payload = try F.envelope(F.get(completedAt: F.g2, metadata: F.scope(F.g1, "pending")))
            let h = try await MetadataHTTPHarness(payload: payload)
            defer { h.removeFolder() }
            let repository = try await h.repository.scoped(for: MetadataHTTPHarness.a)
            try await h.lifecycle.switch(to: MetadataHTTPHarness.record(MetadataHTTPHarness.b, marker: "B"))
            if returnToA { try await h.lifecycle.switch(to: MetadataHTTPHarness.record(MetadataHTTPHarness.a, marker: "New A")) }
            let later = returnToA ? MetadataHTTPHarness.a : MetadataHTTPHarness.b
            let before = try h.seedDraft(userID: later)
            let outcome = await Self.read(repository, generation: F.g1)
            #expect(outcome.isRejected)
            let requests = await h.peer.requests
            #expect(requests.isEmpty)
            #expect(try Data(contentsOf: h.draftStore.fileURL) == before)

            let held = try await MetadataHTTPHarness(payload: payload, held: true)
            defer { held.removeFolder() }
            let old = try await held.repository.scoped(for: MetadataHTTPHarness.a)
            let task = Task {
                let answer = await Self.read(old, generation: F.g1)
                await held.peer.markOperationEnded()
                return answer
            }
            let entered = await held.peer.waitForEntryOrOperationEnd()
            if !entered {
                await held.peer.releaseHeld()
                _ = await task.value
                try #require(entered) // Missing dispatch is a semantic RED, not a hang.
            }
            do {
                try await held.lifecycle.switch(to: MetadataHTTPHarness.record(MetadataHTTPHarness.b, marker: "B"))
                if returnToA { try await held.lifecycle.switch(to: MetadataHTTPHarness.record(MetadataHTTPHarness.a, marker: "New A")) }
                let laterBytes = try held.seedDraft(userID: later)
                await held.peer.releaseHeld()
                let answer = await task.value
                #expect(answer.isRejected)
                let heldRequests = await held.peer.requests
                #expect(heldRequests.count == 1)
                #expect(try Data(contentsOf: held.draftStore.fileURL) == laterBytes)
            } catch {
                await held.peer.releaseHeld()
                _ = await task.value
                throw error
            }
        }
    }

    @Test("a noncooperative decoded reply cannot escape the repository under B or a later A", arguments: [false, true])
    func repositoryRejectsLateDecodedReplies(_ returnToA: Bool) async throws {
        let h = try await MetadataHTTPHarness(payload: F.envelope(F.get()))
        defer { h.removeFolder() }
        let late = MetadataDeferredTransport(data: try F.get(completedAt: F.g2, metadata: F.scope(F.g1, "pending")))
        let raw = MobileOnboardingRepository(transport: late, deviceDraft: h.draftStore, sessionLifecycle: h.lifecycle)
        let repository = try await raw.scoped(for: MetadataHTTPHarness.a)
        let task = Task {
            let answer = await Self.read(repository, generation: F.g1)
            await late.markOperationEnded()
            return answer
        }
        let entered = await late.waitForEntryOrOperationEnd()
        if !entered {
            await late.releaseHeld()
            _ = await task.value
            try #require(entered)
        }
        do {
            try await h.lifecycle.switch(to: MetadataHTTPHarness.record(MetadataHTTPHarness.b, marker: "B"))
            if returnToA { try await h.lifecycle.switch(to: MetadataHTTPHarness.record(MetadataHTTPHarness.a, marker: "New A")) }
            let later = returnToA ? MetadataHTTPHarness.a : MetadataHTTPHarness.b
            let bytes = try h.seedDraft(userID: later)
            await late.releaseHeld()
            let answer = await task.value
            #expect(answer == .superseded)
            #expect(await late.calls == 1)
            #expect(try Data(contentsOf: h.draftStore.fileURL) == bytes)
        } catch {
            await late.releaseHeld()
            _ = await task.value
            throw error
        }
    }

    @Test("late network errors retain cancellation and session identity", arguments: MetadataLateErrorCase.allCases)
    func rejectsLateErrorsUnderTheirOriginalSession(_ scenario: MetadataLateErrorCase) async throws {
        let h = try await MetadataHTTPHarness(payload: F.envelope(F.get()))
        defer { h.removeFolder() }
        let late = MetadataDeferredTransport(data: try F.get(), fails: true)
        let raw = MobileOnboardingRepository(transport: late, deviceDraft: h.draftStore, sessionLifecycle: h.lifecycle)
        let repository = try await raw.scoped(for: MetadataHTTPHarness.a)
        let task = Task {
            let answer = await Self.read(repository, generation: F.g1)
            await late.markOperationEnded()
            return answer
        }
        let entered = await late.waitForEntryOrOperationEnd()
        if !entered {
            await late.releaseHeld()
            _ = await task.value
            try #require(entered)
        }
        do {
            if scenario == .switchToB || scenario == .returnToA {
                try await h.lifecycle.switch(to: MetadataHTTPHarness.record(MetadataHTTPHarness.b, marker: "B"))
            }
            if scenario == .returnToA {
                try await h.lifecycle.switch(to: MetadataHTTPHarness.record(MetadataHTTPHarness.a, marker: "New A"))
            }
            if scenario == .cancel { task.cancel() }
            let later = scenario == .switchToB ? MetadataHTTPHarness.b : MetadataHTTPHarness.a
            let bytes = try h.seedDraft(userID: later)
            await late.releaseHeld()
            let answer = await task.value
            let expected: MetadataReadOutcome = scenario == .cancel ? .cancelled
                : scenario == .current ? .unavailable : .superseded
            #expect(answer == expected)
            #expect(await late.calls == 1)
            #expect(try Data(contentsOf: h.draftStore.fileURL) == bytes)
        } catch {
            await late.releaseHeld()
            _ = await task.value
            throw error
        }
    }

    @Test("M09 unbound/default/invalid/cancelled calls cannot fabricate official authority")
    func failClosedDefaultsAndZeroDispatch() async throws {
        let payload = try F.envelope(F.get(metadata: F.scope(F.g1, "pending")))
        let unbound = try await MetadataHTTPHarness(payload: payload)
        defer { unbound.removeFolder() }
        let unboundOutcome = await Self.read(unbound.repository, generation: F.g1)
        #expect(unboundOutcome.isRejected)
        let unboundRequests = await unbound.peer.requests
        #expect(unboundRequests.isEmpty)
        let defaultRepository = MetadataDefaultRepository()
        let defaultOutcome = await Self.read(defaultRepository, generation: nil)
        #expect(defaultOutcome == .unavailable)
        let calls = await defaultRepository.calls
        #expect(calls == 0)
        let unavailableOutcome = await Self.read(UnavailableOnboardingRepository(), generation: F.g1)
        #expect(unavailableOutcome == .unavailable)
        let h = try await MetadataHTTPHarness(payload: payload)
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: MetadataHTTPHarness.a)
        let invalid = await Self.read(repository, generation: "2026-02-30T11:22:33.123456Z")
        #expect(invalid.isRejected)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await Self.read(repository, generation: F.g1)
        }
        let cancelledOutcome = await cancelled.value
        #expect(cancelledOutcome == .cancelled)
        let requests = await h.peer.requests
        #expect(requests.isEmpty)
    }

    @Test("M10 omission and server/base failures never become notRequired or clear local state")
    func oldServerAndUnavailableMetadataPreserveLocalState() async throws {
        var badBase = try F.object(F.get(metadata: F.scope(F.g1, "not_required")))
        badBase.removeValue(forKey: "requirements")
        let error = Data(#"{"error":{"code":"onboarding_locale_unsupported","message":"Synthetic refusal","request_id":"metadata-locale-409"}}"#.utf8)
        let cases: [(Data, Int, MetadataReadOutcome)] = [
            (try F.envelope(F.get(completedAt: F.g1)), 200, .value(nil)),
            (try F.envelope(F.data(badBase)), 200, .unavailable),
            (error, 409, .unavailable)]
        for (payload, status, expected) in cases {
            let h = try await MetadataHTTPHarness(payload: payload, status: status)
            defer { h.removeFolder() }
            let repository = try await h.repository.scoped(for: MetadataHTTPHarness.a)
            let before = try h.seedDraft(userID: MetadataHTTPHarness.a)
            let outcome = await Self.read(repository, generation: nil)
            #expect(outcome == expected)
            let requests = await h.peer.requests
            #expect(requests.count == 1)
            #expect(try Data(contentsOf: h.draftStore.fileURL) == before)
        }
    }

    private typealias F = MetadataFixtures
    private static func read(_ repository: any OnboardingRepository, generation: String?) async -> MetadataReadOutcome {
        do { return .value(try await repository.loadBodyPhotoCleanupScope(generation: generation)) }
        catch is CancellationError { return .cancelled }
        catch let error as SessionLifecycleError where error == .sessionSuperseded { return .superseded }
        catch let error as MobileAPITransportError where error == .sessionSuperseded { return .superseded }
        catch let error as OnboardingRepositoryError where error == .serviceUnavailable { return .unavailable }
        catch { return .otherFailure }
    }
}

private enum MetadataReadOutcome: Equatable, Sendable {
    case value(OnboardingBodyPhotoCleanupScope?)
    case cancelled, superseded, unavailable, otherFailure
    var isRejected: Bool { if case .value = self { false } else { true } }
}

enum MetadataLateErrorCase: CaseIterable, Sendable {
    case switchToB, returnToA, cancel, current
}

private actor MetadataDefaultRepository: OnboardingRepository {
    private(set) var calls = 0
    func loadDraft(for userID: String) -> OnboardingDraft? { calls += 1; return nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) { calls += 1 }
    func complete(_ draft: OnboardingDraft, for userID: String) { calls += 1 }
    func clear(for userID: String) { calls += 1 }
}

private enum MetadataFixtures {
    static let g1 = "2026-10-12T15:00:00.123456+00:00"
    static let g2 = "2026-10-12T15:01:00.654321Z"
    static let aliasOfG1 = "2026-10-12T15:00:00.123456Z"
    static let oldG = "2026-09-15T15:00:00.000Z"
    static func scope(_ generation: String, _ state: String) -> [String: Any] {
        ["generation": generation, "state": state]
    }
    static func get(completedAt: String? = nil, metadata: Any? = nil) throws -> Data {
        var object: [String: Any] = ["locale": "en-US",
            "completion": ["completed": completedAt != nil, "completed_at": completedAt as Any? ?? NSNull()],
            "requirements": ["available": false, "blocking_reason": "documents_unavailable", "documents": []],
            "accepted_actions": []]
        if let metadata { object["body_photo_cleanup"] = metadata }
        return try data(object)
    }
    static func ack(completedAt: String = oldG, metadata: Any? = nil) throws -> Data {
        var object: [String: Any] = ["onboarding_completed": true, "completed_at": completedAt,
            "objective": "recomposicao", "persona": "focus", "document_actions": [[
                "document_key": "terms_of_service", "version": "2026-09-15.1", "locale": "pt-BR",
                "content_hash": String(repeating: "a", count: 64), "purpose": "synthetic_terms_test",
                "action": "acceptance", "acted_at": oldG]]]
        if let metadata { object["body_photo_cleanup"] = metadata }
        return try data(object)
    }
    static func draft() -> OnboardingDraft {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.objective = .bodyRecomposition; draft.persona = .focus
        draft.documentActions = [OnboardingDocumentAction(documentKey: "terms_of_service",
            version: "2026-09-15.1", locale: "pt-BR", contentHash: String(repeating: "a", count: 64), action: .acceptance)]
        return draft
    }
    static func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    static func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    static func envelope(_ data: Data) throws -> Data {
        let value = try JSONSerialization.jsonObject(with: data)
        return try Self.data(["data": value, "meta": ["api_version": "v1", "request_id": "metadata-native-ok"]])
    }
    // Independent form-query decode matches URLSearchParams (+ means a space).
    static func formValue(_ query: String, name: String) -> String? {
        let pairs = query.split(separator: "&")
        let prefix = name + "="
        guard let pair = pairs.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let raw = String(pair.dropFirst(prefix.count))
        return raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}
#endif

#if DEBUG
import Foundation

@testable import BodyFlow

// PRIVATE DRAFT ONLY. Not compiled or executed by the author.
// Tests using this registry must be in one @MainActor, .serialized suite.
// `payload` is the entire raw mobile envelope, not merely its `data` value.
// No repository implementation is provided here.
@MainActor
struct MetadataHTTPHarness: Sendable {
    nonisolated static let a = "00000000-0000-4000-8000-0000000000a1"
    nonisolated static let b = "00000000-0000-4000-8000-0000000000b2"

    let folder: URL
    let draftStore: OnboardingDeviceDraftStore
    let authStore: AuthenticationSessionStore
    let lifecycle: SessionLifecycleCoordinator
    let peer: MetadataHTTPPeer
    let transport: MobileAPITransport
    let repository: MobileOnboardingRepository

    init(payload: Data, status: Int = 200, held: Bool = false) async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanup-metadata-http-\(UUID().uuidString)", isDirectory: true)
        draftStore = OnboardingDeviceDraftStore(directory: folder)
        authStore = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await authStore.replace(with: Self.record(Self.a, marker: "Initial"))
        lifecycle = SessionLifecycleCoordinator(
            store: authStore,
            remote: MetadataHTTPAuthRemote(),
            sensitiveStateClearer: OnboardingDeviceDraftSessionClearer(store: draftStore),
            refreshPolicy: SessionRefreshPolicy(
                now: { Date(timeIntervalSince1970: 1_000) }, leeway: 60
            )
        )
        peer = MetadataHTTPPeer(payload: payload, status: status, held: held)
        await MetadataHTTPURLProtocol.install(peer)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetadataHTTPURLProtocol.self]
        transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://mobile.example.test"),
            sessionLifecycle: lifecycle,
            session: URLSession(configuration: configuration),
            clock: ContinuousClock()
        )
        repository = MobileOnboardingRepository(
            transport: transport, deviceDraft: draftStore, sessionLifecycle: lifecycle
        )
    }

    nonisolated static func record(_ userID: String, marker: String) -> AuthenticationSessionRecord {
        AuthenticationSessionRecord(
            userID: userID,
            email: "synthetic@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false,
            accessToken: token(subject: userID, marker: marker),
            refreshToken: "synthetic-refresh-\(marker)",
            expiresAt: Date(timeIntervalSince1970: 1_500)
        )
    }

    // Fixture setup only; this intentionally does not call the method under test.
    // Call after the final switch to seed the later owner's byte baseline.
    func seedDraft(userID: String, marker: String = "Synthetic later draft") throws -> Data {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        draft.displayName = marker
        guard draftStore.save(draft, for: userID),
              draftStore.load(for: userID)?.displayName == marker else {
            throw MetadataHTTPHarnessError.fixtureDraftUnavailable
        }
        return try Data(contentsOf: draftStore.fileURL)
    }

    func removeFolder() {
        try? FileManager.default.removeItem(at: folder)
    }

    private nonisolated static func token(subject: String, marker: String) -> String {
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payload = base64URL(Data(#"{"sub":"\#(subject)","marker":"\#(marker)"}"#.utf8))
        return "\(header).\(payload).synthetic"
    }
}

private enum MetadataHTTPHarnessError: Error, Sendable {
    case fixtureDraftUnavailable
}

// The actor deliberately keeps a held response suspended when its loader task
// is cancelled. The test must always release after observing entry, including
// its error paths. Cancellation never supplies authority to the old request.
actor MetadataHTTPPeer {
    private let payload: Data
    private let status: Int
    private var entered = false
    private var released: Bool
    private var operationEnded = false
    private var entryWaiters: [CheckedContinuation<Bool, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requests: [URLRequest] = []

    init(payload: Data, status: Int, held: Bool) {
        self.payload = payload
        self.status = status
        released = !held
    }

    func respond(to request: URLRequest) async -> (Int, Data) {
        requests.append(request)
        entered = true
        let observers = entryWaiters
        entryWaiters.removeAll()
        observers.forEach { $0.resume(returning: true) }
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        // No Task.checkCancellation here: this is the adverse late peer.
        return (status, payload)
    }

    func waitForEntryOrOperationEnd() async -> Bool {
        if entered { return true }
        if operationEnded { return false }
        return await withCheckedContinuation { entryWaiters.append($0) }
    }

    // Caller must invoke this on BOTH success and throw from the repository
    // task. It only releases the no-request fallback, never a held response.
    func markOperationEnded() {
        operationEnded = true
        guard !entered else { return }
        let observers = entryWaiters
        entryWaiters.removeAll()
        observers.forEach { $0.resume(returning: false) }
    }

    func releaseHeld() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor MetadataHTTPAuthRemote: SupabaseAuthRemoteOperating {
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord {
        // A legitimate refresh keeps the real coordinator's generation.
        MetadataHTTPHarness.record(record.userID, marker: "Refreshed")
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}

private actor MetadataHTTPProtocolRegistry {
    var peer: MetadataHTTPPeer?
    func install(_ peer: MetadataHTTPPeer) { self.peer = peer }
}

private final class MetadataHTTPURLProtocol: URLProtocol {
    private static let registry = MetadataHTTPProtocolRegistry()
    private let lock = NSLock()
    private var operation: Task<Void, Never>?
    private var cancelled = false

    static func install(_ peer: MetadataHTTPPeer) async { await registry.install(peer) }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "mobile.example.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let box = MetadataHTTPURLProtocolBox(instance: self)
        let task = Task { await box.instance.load() }
        lock.withLock {
            if cancelled { task.cancel() }
            operation = task
        }
    }

    private func load() async {
        do {
            try Task.checkCancellation()
            guard let peer = await Self.registry.peer,
                  let url = request.url else { throw URLError(.badServerResponse) }
            let (status, body) = await peer.respond(to: request)
            // Deliberately attempt the late callback after cancellation.
            // URLSession may discard it. It must not become repository success.
            guard let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        lock.withLock {
            cancelled = true
            operation?.cancel()
        }
    }
}

// Foundation excludes URLProtocol from checked Sendable. One loader task
// receives this box; cancel/task state is protected by the instance lock.
private struct MetadataHTTPURLProtocolBox: @unchecked Sendable {
    let instance: MetadataHTTPURLProtocol
}
#endif

#if DEBUG
// A lower transport peer deliberately delivers decoded data despite cancellation.
// Real URLSession/wire and lifecycle coverage above is kept independently.
private actor MetadataDeferredTransport: MobileAPIExecuting {
    let data: Data
    let fails: Bool
    private var entered = false
    private var ended = false
    private var released = false
    private var observers: [CheckedContinuation<Bool, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0
    init(data: Data, fails: Bool = false) { self.data = data; self.fails = fails }
    func execute<Response: Decodable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> Response {
        calls += 1; entered = true
        let ready = observers; observers.removeAll(); ready.forEach { $0.resume(returning: true) }
        if !released { await withCheckedContinuation { waiters.append($0) } }
        if fails { throw URLError(.networkConnectionLost) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
    func waitForEntryOrOperationEnd() async -> Bool {
        if entered { return true }
        if ended { return false }
        return await withCheckedContinuation { observers.append($0) }
    }
    func markOperationEnded() {
        ended = true
        if !entered {
            let ready = observers; observers.removeAll(); ready.forEach { $0.resume(returning: false) }
        }
    }
    func releaseHeld() {
        released = true
        let ready = waiters; waiters.removeAll(); ready.forEach { $0.resume() }
    }
}
#endif
