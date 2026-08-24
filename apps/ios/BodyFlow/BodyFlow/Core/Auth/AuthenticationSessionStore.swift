import Foundation

enum AuthenticationSessionState: Equatable, Sendable {
    case notHydrated
    case signedOut
    case authenticated(AuthSession)
}

enum AuthenticationSessionStoreError: Error, Equatable, Sendable {
    case invalidRecord
    case storageUnavailable
}

actor AuthenticationSessionStore: SessionTokenProviding {
    static let keychainService = "com.bodyflow.app.auth-session.v1"
    static let storageKey = "bodyflow.auth.session.v1"

    private let secureStore: any SecureStoring
    private let now: @Sendable () -> Date
    private var currentRecord: AuthenticationSessionRecord?
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
        try Task.checkCancellation()
        try await beginTransition()
        defer { endTransition() }
        try Task.checkCancellation()

        let data: Data?
        do {
            data = try await secureStore.data(forKey: Self.storageKey)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            currentRecord = nil
            state = .notHydrated
            throw AuthenticationSessionStoreError.storageUnavailable
        }
        try Task.checkCancellation()

        guard let data else {
            currentRecord = nil
            state = .signedOut
            return nil
        }
        guard let record = try? JSONDecoder().decode(
            AuthenticationSessionRecord.self,
            from: data
        ), record.schemaVersion == 1, Self.isStructurallyValid(record) else {
            currentRecord = nil
            state = .notHydrated
            throw AuthenticationSessionStoreError.invalidRecord
        }
        guard record.expiresAt > now() else {
            currentRecord = nil
            state = .signedOut
            return nil
        }

        currentRecord = record
        state = .authenticated(record.publicSession)
        return record.publicSession
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
            data = try JSONEncoder().encode(record)
            try await secureStore.store(data, forKey: Self.storageKey)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AuthenticationSessionStoreError.storageUnavailable
        }
        currentRecord = record
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
        currentRecord = nil
        state = .signedOut
    }

    func currentBearerToken() -> String? {
        guard let currentRecord,
              Self.isStructurallyValid(currentRecord),
              currentRecord.expiresAt > now()
        else {
            self.currentRecord = nil
            state = .signedOut
            return nil
        }
        return currentRecord.accessToken
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
