import Foundation
import Testing

@testable import BodyFlow

@Suite("Authentication Session Store")
struct AuthenticationSessionStoreTests {
    @Test("starts unhydrated and missing storage hydrates signed out")
    func initialAndMissingState() async throws {
        let store = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        #expect(await store.state == .notHydrated)
        #expect(try await store.hydrate() == nil)
        #expect(await store.state == .signedOut)
    }

    @Test("valid record hydrates and provides a bearer")
    func validRecordHydrates() async throws {
        let secureStore = InMemorySecureStore()
        let record = fixtureRecord(accessToken: "access-valid", expiresAt: 2_000)
        try await secureStore.store(try JSONEncoder().encode(record), forKey: AuthenticationSessionStore.storageKey)
        let store = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        #expect(try await store.hydrate() == record.publicSession)
        #expect(await store.currentBearerToken() == record.accessToken)
    }

    @Test("expired record hydrates signed out and provides no bearer")
    func expiredRecordFailsClosed() async throws {
        let secureStore = InMemorySecureStore()
        try await secureStore.store(
            try JSONEncoder().encode(fixtureRecord(expiresAt: 999)),
            forKey: AuthenticationSessionStore.storageKey
        )
        let store = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        #expect(try await store.hydrate() == nil)
        #expect(await store.currentBearerToken() == nil)
        #expect(await store.state == .signedOut)
    }

    @Test("expired replacement is rejected before persistence or publication")
    func expiredReplacementFailsClosed() async {
        let secureStore = RecordingSecureStore()
        let store = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        await #expect(throws: AuthenticationSessionStoreError.invalidRecord) {
            try await store.replace(with: fixtureRecord(expiresAt: 1_000))
        }
        #expect(await secureStore.storeCount == 0)
        #expect(await store.state == .notHydrated)
        #expect(await store.currentBearerToken() == nil)
    }

    @Test("unconfirmed or identity-mismatched records fail closed during hydration", arguments: [
        fixtureRecord(isEmailConfirmed: false),
        fixtureRecord(tokenSubject: "00000000-0000-4000-8000-000000000099"),
    ])
    func semanticallyInvalidRecordsFailClosed(_ record: AuthenticationSessionRecord) async throws {
        let secureStore = InMemorySecureStore()
        try await secureStore.store(
            try JSONEncoder().encode(record),
            forKey: AuthenticationSessionStore.storageKey
        )
        let store = AuthenticationSessionStore(secureStore: secureStore)

        await #expect(throws: AuthenticationSessionStoreError.invalidRecord) {
            _ = try await store.hydrate()
        }
        #expect(await store.state == .notHydrated)
        #expect(await store.currentBearerToken() == nil)
    }

    @Test("failed rehydration clears a previously published bearer")
    func failedRehydrationClearsPublishedBearer() async throws {
        let secureStore = InMemorySecureStore()
        let valid = fixtureRecord()
        try await secureStore.store(
            try JSONEncoder().encode(valid),
            forKey: AuthenticationSessionStore.storageKey
        )
        let store = AuthenticationSessionStore(secureStore: secureStore)
        #expect(try await store.hydrate() == valid.publicSession)

        try await secureStore.store(
            Data("not-json".utf8),
            forKey: AuthenticationSessionStore.storageKey
        )
        await #expect(throws: AuthenticationSessionStoreError.invalidRecord) {
            _ = try await store.hydrate()
        }

        #expect(await store.state == .notHydrated)
        #expect(await store.currentBearerToken() == nil)
    }

    @Test("pre-cancelled hydration preserves an authenticated session")
    func preCancelledHydrationPreservesSession() async throws {
        let secureStore = RecordingSecureStore()
        let store = AuthenticationSessionStore(secureStore: secureStore)
        let record = fixtureRecord()
        try await store.replace(with: record)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.hydrate()
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await store.state == .authenticated(record.publicSession))
        #expect(await store.currentBearerToken() == record.accessToken)
    }

    @Test("cancellation during persisted read preserves an authenticated session")
    func readCancellationPreservesSession() async throws {
        let secureStore = RecordingSecureStore()
        let store = AuthenticationSessionStore(secureStore: secureStore)
        let record = fixtureRecord()
        try await store.replace(with: record)
        await secureStore.cancelReads()
        let task = Task { try await store.hydrate() }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await store.state == .authenticated(record.publicSession))
        #expect(await store.currentBearerToken() == record.accessToken)
    }

    @Test("corrupt and unknown-version records fail closed", arguments: [
        Data("not-json".utf8),
        Data(#"{"schemaVersion":2}"#.utf8),
    ])
    func invalidRecordsFailClosed(_ data: Data) async throws {
        let secureStore = InMemorySecureStore()
        try await secureStore.store(data, forKey: AuthenticationSessionStore.storageKey)
        let store = AuthenticationSessionStore(secureStore: secureStore)

        await #expect(throws: AuthenticationSessionStoreError.invalidRecord) {
            _ = try await store.hydrate()
        }
        #expect(await store.state == .notHydrated)
        #expect(await store.currentBearerToken() == nil)
    }

    @Test("replace persists before publishing and next bearer read observes replacement")
    func replacePersistsBeforePublish() async throws {
        let secureStore = RecordingSecureStore()
        let store = AuthenticationSessionStore(
            secureStore: secureStore,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let first = fixtureRecord(accessToken: "access-one", expiresAt: 2_000)
        let second = fixtureRecord(accessToken: "access-two", expiresAt: 3_000)

        try await store.replace(with: first)
        #expect(await secureStore.storeCount == 1)
        #expect(await store.currentBearerToken() == first.accessToken)
        try await store.replace(with: second)
        #expect(await store.currentBearerToken() == second.accessToken)
        #expect(await store.state == .authenticated(second.publicSession))
    }

    @Test("persistence failure does not publish a replacement")
    func persistenceFailureDoesNotPublish() async throws {
        let secureStore = RecordingSecureStore()
        let store = AuthenticationSessionStore(secureStore: secureStore)
        let original = fixtureRecord(accessToken: "access-original")
        try await store.replace(with: original)
        await secureStore.failStores()

        await #expect(throws: AuthenticationSessionStoreError.storageUnavailable) {
            try await store.replace(with: fixtureRecord(accessToken: "access-new"))
        }
        #expect(await store.currentBearerToken() == original.accessToken)
        #expect(await store.state == .authenticated(original.publicSession))
    }

    @Test("clear publishes signed out only after successful deletion")
    func clearFailurePreservesSession() async throws {
        let secureStore = RecordingSecureStore()
        let store = AuthenticationSessionStore(secureStore: secureStore)
        let record = fixtureRecord()
        try await store.replace(with: record)
        await secureStore.failRemovals()

        await #expect(throws: AuthenticationSessionStoreError.storageUnavailable) {
            try await store.clear()
        }
        #expect(await store.state == .authenticated(record.publicSession))

        await secureStore.allowRemovals()
        try await store.clear()
        #expect(await store.state == .signedOut)
        #expect(await store.currentBearerToken() == nil)
    }

    @Test("concurrent replacements remain atomic and persisted state matches published state")
    func concurrentReplacementsRemainAtomic() async throws {
        let secureStore = RecordingSecureStore()
        let store = AuthenticationSessionStore(secureStore: secureStore)
        let first = fixtureRecord(userID: "00000000-0000-4000-8000-000000000001", accessToken: "access-one")
        let second = fixtureRecord(userID: "00000000-0000-4000-8000-000000000002", accessToken: "access-two")

        async let firstReplace: Void = store.replace(with: first)
        async let secondReplace: Void = store.replace(with: second)
        _ = try await (firstReplace, secondReplace)

        let persisted = try #require(await secureStore.value)
        let persistedRecord = try JSONDecoder().decode(AuthenticationSessionRecord.self, from: persisted)
        #expect(await store.state == .authenticated(persistedRecord.publicSession))
        #expect(await store.currentBearerToken() == persistedRecord.accessToken)
    }

    @Test("pre-cancelled replacement writes nothing")
    func cancellationWritesNothing() async {
        let secureStore = RecordingSecureStore()
        let store = AuthenticationSessionStore(secureStore: secureStore)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.replace(with: fixtureRecord())
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await secureStore.storeCount == 0)
        #expect(await store.state == .notHydrated)
    }

    @Test("successful persistence remains the replacement linearization boundary")
    func persistenceBoundaryCommitsCoherently() async throws {
        let secureStore = CancellingAfterWriteSecureStore()
        let store = AuthenticationSessionStore(secureStore: secureStore)
        let record = fixtureRecord()

        let session = Task { () throws -> AuthenticationSessionState in
            try await store.replace(with: record)
            return await store.state
        }

        #expect(try await session.value == .authenticated(record.publicSession))
        #expect(await secureStore.value != nil)
        #expect(await store.currentBearerToken() == record.accessToken)
    }

    @Test("record and errors never describe tokens")
    func descriptionsAreRedacted() {
        let record = fixtureRecord(accessToken: "access-do-not-print", refreshToken: "refresh-do-not-print")
        for description in [String(describing: record), String(reflecting: record)] {
            #expect(!description.contains(record.accessToken))
            #expect(!description.contains("refresh-do-not-print"))
        }
    }

    @Test("a new store restores the same record without a network dependency")
    func relaunchRestoresLocally() async throws {
        let secureStore = InMemorySecureStore()
        let firstStore = AuthenticationSessionStore(secureStore: secureStore)
        let record = fixtureRecord()
        try await firstStore.replace(with: record)

        let relaunched = AuthenticationSessionStore(secureStore: secureStore)
        #expect(try await relaunched.hydrate() == record.publicSession)
    }
}

private func fixtureRecord(
    userID: String = "00000000-0000-4000-8000-000000000001",
    accessToken: String = "access-synthetic",
    refreshToken: String = "refresh-synthetic",
    expiresAt: TimeInterval = 4_000_000_000,
    isEmailConfirmed: Bool = true,
    tokenSubject: String? = nil
) -> AuthenticationSessionRecord {
    AuthenticationSessionRecord(
        userID: userID,
        email: "member@fixture.invalid",
        isEmailConfirmed: isEmailConfirmed,
        isOnboardingCompleted: false,
        accessToken: sessionStoreAccessToken(
            subject: tokenSubject ?? userID,
            marker: accessToken
        ),
        refreshToken: refreshToken,
        expiresAt: Date(timeIntervalSince1970: expiresAt)
    )
}

private func sessionStoreAccessToken(subject: String, marker: String) -> String {
    let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8).base64URLEncoded
    let payload = Data(#"{"sub":"\#(subject)","marker":"\#(marker)"}"#.utf8)
        .base64URLEncoded
    return "\(header).\(payload).synthetic"
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private actor RecordingSecureStore: SecureStoring {
    private(set) var value: Data?
    private(set) var storeCount = 0
    private var storeFails = false
    private var removalFails = false
    private var readsCancel = false

    func data(forKey key: String) throws -> Data? {
        if readsCancel {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return value
    }

    func store(_ data: Data, forKey key: String) throws {
        guard !storeFails else { throw RecordingSecureStoreError.unavailable }
        value = data
        storeCount += 1
    }

    func removeData(forKey key: String) throws {
        guard !removalFails else { throw RecordingSecureStoreError.unavailable }
        value = nil
    }

    func failStores() { storeFails = true }
    func failRemovals() { removalFails = true }
    func allowRemovals() { removalFails = false }
    func cancelReads() { readsCancel = true }
}

private enum RecordingSecureStoreError: Error { case unavailable }

private actor CancellingAfterWriteSecureStore: SecureStoring {
    private(set) var value: Data?

    func data(forKey key: String) -> Data? { value }

    func store(_ data: Data, forKey key: String) {
        value = data
        withUnsafeCurrentTask { $0?.cancel() }
    }

    func removeData(forKey key: String) { value = nil }
}
