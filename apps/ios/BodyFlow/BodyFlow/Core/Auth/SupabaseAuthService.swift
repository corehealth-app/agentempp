import Auth
import Foundation

enum SupabaseAuthNetworkError: Error, Equatable, Sendable {
    case originNotAllowed
    case redirectNotAllowed
    case invalidResponse
    case timeout
    case network
}

struct SupabaseAuthFetch: Sendable {
    private let configuration: SupabaseAuthConfiguration
    private let session: URLSession
    private let timeout: TimeInterval

    init(
        configuration: SupabaseAuthConfiguration,
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        timeout: TimeInterval = 30
    ) {
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCredentialStorage = nil
        sessionConfiguration.timeoutIntervalForRequest = timeout
        sessionConfiguration.timeoutIntervalForResource = timeout
        self.configuration = configuration
        session = URLSession(configuration: sessionConfiguration)
        self.timeout = timeout
    }

    func callAsFunction(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard let url = request.url, configuration.approves(url) else {
            throw SupabaseAuthNetworkError.originNotAllowed
        }

        var safeRequest = request
        safeRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        safeRequest.timeoutInterval = timeout
        let delegate = SupabaseAuthRedirectDelegate(configuration: configuration)
        do {
            let result = try await session.data(for: safeRequest, delegate: delegate)
            try Task.checkCancellation()
            if delegate.wasRejected {
                throw SupabaseAuthNetworkError.redirectNotAllowed
            }
            guard result.1 is HTTPURLResponse else {
                throw SupabaseAuthNetworkError.invalidResponse
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SupabaseAuthNetworkError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            if delegate.wasRejected {
                throw SupabaseAuthNetworkError.redirectNotAllowed
            }
            try Task.checkCancellation()
            throw SupabaseAuthNetworkError.network
        } catch let error as URLError where error.code == .timedOut {
            throw SupabaseAuthNetworkError.timeout
        } catch {
            if delegate.wasRejected {
                throw SupabaseAuthNetworkError.redirectNotAllowed
            }
            throw SupabaseAuthNetworkError.network
        }
    }
}

private final class SupabaseAuthRedirectDelegate: NSObject,
    URLSessionTaskDelegate, @unchecked Sendable {
    private let configuration: SupabaseAuthConfiguration
    private let lock = NSLock()
    private var rejected = false

    init(configuration: SupabaseAuthConfiguration) {
        self.configuration = configuration
    }

    var wasRejected: Bool { lock.withLock { rejected } }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, configuration.approves(url) else {
            lock.withLock { rejected = true }
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }
}

enum SupabaseAuthRemoteError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidCredentials
    case emailNotConfirmed
    case requestFailed
}

enum SupabaseRemoteSignUpResult: Equatable, Sendable {
    case confirmationRequired(email: String)
    case authenticated(AuthenticationSessionRecord)
}

protocol SupabaseAuthRemoteOperating: Sendable {
    func signIn(email: String, password: String) async throws
        -> AuthenticationSessionRecord
    func signUp(email: String, password: String) async throws
        -> SupabaseRemoteSignUpResult
    func requestPasswordRecovery(email: String) async throws
}

struct SupabaseAuthRemoteClient: SupabaseAuthRemoteOperating, Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias ClientObserver = @Sendable (AuthClient) -> Void

    private let configuration: SupabaseAuthConfiguration
    private let fetch: Fetch
    private let clientObserver: ClientObserver

    init(
        configuration: SupabaseAuthConfiguration,
        fetch: @escaping Fetch,
        clientObserver: @escaping ClientObserver = { _ in }
    ) {
        self.configuration = configuration
        self.fetch = fetch
        self.clientObserver = clientObserver
    }

    func signIn(email: String, password: String) async throws
        -> AuthenticationSessionRecord {
        try Task.checkCancellation()
        do {
            let client = makeClient()
            let session = try await client.signIn(email: email, password: password)
            try Task.checkCancellation()
            return try Self.makeRecord(from: session)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SupabaseAuthRemoteError {
            throw error
        } catch let error as AuthError where error.errorCode == .invalidCredentials {
            throw SupabaseAuthRemoteError.invalidCredentials
        } catch let error as AuthError where error.errorCode == .emailNotConfirmed {
            throw SupabaseAuthRemoteError.emailNotConfirmed
        } catch {
            throw SupabaseAuthRemoteError.requestFailed
        }
    }

    func signUp(email: String, password: String) async throws
        -> SupabaseRemoteSignUpResult {
        try Task.checkCancellation()
        do {
            let client = makeClient()
            let response = try await client.signUp(email: email, password: password)
            try Task.checkCancellation()
            switch response {
            case .session(let session):
                return .authenticated(try Self.makeRecord(from: session))
            case .user(let user):
                guard let email = user.email, Self.isValid(email: email) else {
                    throw SupabaseAuthRemoteError.invalidResponse
                }
                return .confirmationRequired(email: email)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SupabaseAuthRemoteError {
            throw error
        } catch {
            throw SupabaseAuthRemoteError.requestFailed
        }
    }

    func requestPasswordRecovery(email: String) async throws {
        try Task.checkCancellation()
        do {
            let client = makeClient()
            try await client.resetPasswordForEmail(email)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SupabaseAuthRemoteError.requestFailed
        }
    }

    private func makeClient() -> AuthClient {
        let client = AuthClient(
            url: configuration.authURL,
            headers: [
                "apikey": configuration.key,
                "Authorization": "Bearer \(configuration.key)",
            ],
            localStorage: DiscardingSupabaseAuthStorage(),
            fetch: fetch,
            autoRefreshToken: false,
            emitLocalSessionAsInitialSession: true
        )
        clientObserver(client)
        return client
    }

    private static func makeRecord(from session: Session) throws
        -> AuthenticationSessionRecord {
        let userID = session.user.id.uuidString.lowercased()
        guard let email = session.user.email,
              isValid(email: email),
              session.user.emailConfirmedAt != nil,
              !session.accessToken.isEmpty,
              !session.refreshToken.isEmpty,
              session.expiresAt.isFinite,
              session.expiresAt > 0,
              accessTokenSubject(session.accessToken) == userID
        else {
            throw SupabaseAuthRemoteError.invalidResponse
        }
        return AuthenticationSessionRecord(
            userID: userID,
            email: email,
            isEmailConfirmed: true,
            isOnboardingCompleted: false,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        )
    }

    private static func isValid(email: String) -> Bool {
        let candidate = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !candidate.isEmpty && candidate.contains("@")
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

struct SupabaseAuthenticationService: AuthenticationService, Sendable,
    CustomStringConvertible, CustomReflectable {
    private let remote: any SupabaseAuthRemoteOperating
    private let sessionStore: AuthenticationSessionStore

    init(
        remote: any SupabaseAuthRemoteOperating,
        sessionStore: AuthenticationSessionStore
    ) {
        self.remote = remote
        self.sessionStore = sessionStore
    }

    var description: String { "SupabaseAuthenticationService(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    func restoreSession() async throws -> AuthSession? {
        do {
            return try await sessionStore.hydrate()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AuthenticationError.storageUnavailable
        }
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        guard Self.valid(email: email), Self.valid(password: password) else {
            throw AuthenticationError.invalidInput
        }
        do {
            let record = try await remote.signIn(email: email, password: password)
            try Task.checkCancellation()
            try await sessionStore.replace(with: record)
            return record.publicSession
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SupabaseAuthRemoteError {
            throw Self.map(error)
        } catch is AuthenticationSessionStoreError {
            throw AuthenticationError.storageUnavailable
        } catch {
            throw AuthenticationError.serviceUnavailable
        }
    }

    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        guard Self.valid(email: email), Self.valid(password: password) else {
            throw AuthenticationError.invalidInput
        }
        do {
            switch try await remote.signUp(email: email, password: password) {
            case .confirmationRequired(let confirmedEmail):
                return .confirmationRequired(email: confirmedEmail)
            case .authenticated(let record):
                try Task.checkCancellation()
                try await sessionStore.replace(with: record)
                return .authenticated(record.publicSession)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SupabaseAuthRemoteError {
            throw Self.map(error)
        } catch is AuthenticationSessionStoreError {
            throw AuthenticationError.storageUnavailable
        } catch {
            throw AuthenticationError.serviceUnavailable
        }
    }

    func confirmEmailForDevelopment() async throws -> AuthSession {
        throw AuthenticationError.operationUnavailable
    }

    func requestPasswordRecovery(email: String) async throws {
        guard Self.valid(email: email) else {
            throw AuthenticationError.invalidInput
        }
        do {
            try await remote.requestPasswordRecovery(email: email)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SupabaseAuthRemoteError {
            throw Self.map(error)
        } catch {
            throw AuthenticationError.serviceUnavailable
        }
    }

    func signOut() async throws {
        do {
            try await sessionStore.clear()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AuthenticationError.storageUnavailable
        }
    }

    private static func valid(email: String) -> Bool {
        let candidate = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !candidate.isEmpty && candidate.contains("@")
    }

    private static func valid(password: String) -> Bool {
        !password.isEmpty
    }

    private static func map(_ error: SupabaseAuthRemoteError) -> AuthenticationError {
        switch error {
        case .invalidCredentials:
            .invalidCredentials
        case .emailNotConfirmed:
            .confirmationRequired
        case .invalidResponse, .requestFailed:
            .serviceUnavailable
        }
    }
}
