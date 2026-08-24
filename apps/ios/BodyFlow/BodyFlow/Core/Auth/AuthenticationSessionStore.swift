import Foundation

enum AuthenticationSessionState: Equatable, Sendable {
    case notHydrated
    case signedOut
    case authenticated(AuthSession)
}

enum AuthenticationSessionStoreError: Error, Equatable, Sendable {
    case invalidRecord
    case storageUnavailable
    case localInvalidationFailed
    case cleanupIncomplete
}

actor AuthenticationSessionStore: SessionTokenProviding {
    static let keychainService = "com.bodyflow.app.auth-session.v1"
    static let storageKey = "bodyflow.auth.session.v1"
    static let invalidationMarkerKey = "bodyflow.auth.session.invalidated.v1"

    private let secureStore: any SecureStoring
    private let now: @Sendable () -> Date
    private var storedRecord: AuthenticationSessionRecord?
    private var transitionInProgress = false
    private var transitionWaiters: [TransitionWaiter] = []
    private(set) var state: AuthenticationSessionState = .notHydrated

    init(
        secureStore: any SecureStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.secureStore = secureStore
        self.now = now
    }

    func hydrate() async throws -> AuthSession? {
        guard let record = try await bootstrapRecord(),
              record.expiresAt > now()
        else { return nil }
        return record.publicSession
    }

    func bootstrapRecord() async throws -> AuthenticationSessionRecord? {
        try Task.checkCancellation()
        try await beginTransition()
        defer { endTransition() }
        try Task.checkCancellation()

        let marker: Data?
        do {
            marker = try await secureStore.data(forKey: Self.invalidationMarkerKey)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            storedRecord = nil
            state = .notHydrated
            throw AuthenticationSessionStoreError.storageUnavailable
        }
        try Task.checkCancellation()

        if marker != nil {
            storedRecord = nil
            state = .signedOut
            do {
                try await secureStore.removeData(forKey: Self.storageKey)
                try await secureStore.removeData(forKey: Self.invalidationMarkerKey)
            } catch {
                // The marker remains authoritative if cleanup cannot finish.
            }
            return nil
        }

        let data: Data?
        do {
            data = try await secureStore.data(forKey: Self.storageKey)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            storedRecord = nil
            state = .notHydrated
            throw AuthenticationSessionStoreError.storageUnavailable
        }
        try Task.checkCancellation()

        guard let data else {
            storedRecord = nil
            state = .signedOut
            return nil
        }
        guard let record = try? JSONDecoder().decode(
            AuthenticationSessionRecord.self,
            from: data
        ), record.schemaVersion == 1, Self.isStructurallyValid(record) else {
            storedRecord = nil
            state = .notHydrated
            throw AuthenticationSessionStoreError.invalidRecord
        }
        guard record.expiresAt > now() else {
            storedRecord = nil
            state = .signedOut
            return record
        }

        storedRecord = record
        state = .authenticated(record.publicSession)
        return record
    }

    func replace(with record: AuthenticationSessionRecord) async throws {
        try Task.checkCancellation()
        try await beginTransition()
        defer { endTransition() }
        try Task.checkCancellation()
        guard record.schemaVersion == 1,
              Self.isStructurallyValid(record),
              record.expiresAt > now()
        else {
            throw AuthenticationSessionStoreError.invalidRecord
        }

        let data: Data
        do {
            let marker = try await secureStore.data(
                forKey: Self.invalidationMarkerKey
            )
            data = try JSONEncoder().encode(record)
            try await secureStore.store(data, forKey: Self.storageKey)
            if marker != nil {
                try await secureStore.removeData(
                    forKey: Self.invalidationMarkerKey
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AuthenticationSessionStoreError.storageUnavailable
        }
        storedRecord = record
        state = .authenticated(record.publicSession)
    }

    func clear() async throws {
        try await beginTransition()
        defer { endTransition() }
        try Task.checkCancellation()
        do {
            try await secureStore.removeData(forKey: Self.storageKey)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AuthenticationSessionStoreError.storageUnavailable
        }
        storedRecord = nil
        state = .signedOut
    }

    func currentRecord() -> AuthenticationSessionRecord? {
        storedRecord
    }

    @discardableResult
    func invalidateLocally() async throws -> AuthenticationSessionRecord? {
        let retainedRecord = try await beginLocalInvalidation()
        try await finishLocalInvalidation()
        return retainedRecord
    }

    func beginLocalInvalidation() async throws -> AuthenticationSessionRecord? {
        try await beginTransition()
        defer { endTransition() }
        try Task.checkCancellation()
        let retainedRecord = storedRecord
        let marker = Data(#"{"schema_version":1,"invalidated":true}"#.utf8)
        do {
            try await secureStore.store(
                marker,
                forKey: Self.invalidationMarkerKey
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AuthenticationSessionStoreError.localInvalidationFailed
        }

        storedRecord = nil
        state = .signedOut
        return retainedRecord
    }

    func finishLocalInvalidation() async throws {
        try await beginTransition()
        defer { endTransition() }
        try Task.checkCancellation()
        do {
            try await secureStore.removeData(forKey: Self.storageKey)
        } catch {
            throw AuthenticationSessionStoreError.cleanupIncomplete
        }
        do {
            try await secureStore.removeData(
                forKey: Self.invalidationMarkerKey
            )
        } catch {
            throw AuthenticationSessionStoreError.cleanupIncomplete
        }
    }

    func currentBearerToken() -> String? {
        guard let storedRecord,
              Self.isStructurallyValid(storedRecord),
              storedRecord.expiresAt > now()
        else {
            self.storedRecord = nil
            state = .signedOut
            return nil
        }
        return storedRecord.accessToken
    }

    private func beginTransition() async throws {
        try Task.checkCancellation()
        guard transitionInProgress else {
            transitionInProgress = true
            return
        }

        let waiterID = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                transitionWaiters.append(TransitionWaiter(
                    id: waiterID,
                    continuation: continuation
                ))
            }
        } onCancel: {
            Task { await self.cancelTransitionWaiter(id: waiterID) }
        }

        guard acquired else { throw CancellationError() }
        do {
            try Task.checkCancellation()
        } catch {
            endTransition()
            throw error
        }
    }

    private func endTransition() {
        guard !transitionWaiters.isEmpty else {
            transitionInProgress = false
            return
        }
        transitionWaiters.removeFirst().continuation.resume(returning: true)
    }

    private func cancelTransitionWaiter(id: UUID) {
        guard let index = transitionWaiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        transitionWaiters.remove(at: index).continuation.resume(returning: false)
    }

    private static func isStructurallyValid(
        _ record: AuthenticationSessionRecord
    ) -> Bool {
        !record.userID.isEmpty
            && UUID(uuidString: record.userID) != nil
            && !record.email.isEmpty
            && record.email.contains("@")
            && record.isEmailConfirmed
            && !record.accessToken.isEmpty
            && !record.refreshToken.isEmpty
            && accessTokenSubject(record.accessToken) == record.userID.lowercased()
    }

    private static func accessTokenSubject(_ token: String) -> String? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data),
              let claims = object as? [String: Any]
        else { return nil }
        return (claims["sub"] as? String)?.lowercased()
    }
}

private struct TransitionWaiter {
    let id: UUID
    let continuation: CheckedContinuation<Bool, Never>
}
