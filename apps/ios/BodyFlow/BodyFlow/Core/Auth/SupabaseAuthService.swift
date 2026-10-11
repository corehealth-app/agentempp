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
    case invalidGrant
    case forbidden
    case rateLimited
    case server
    case timeout
    case requestFailed
    /// Sign-up only: the e-mail already has an account.
    case emailAlreadyRegistered
    /// Sign-up only: the auth server refused the password as too weak.
    case weakPassword
    /// Sign-up only: any other refusal of what was sent (another 4xx).
    case rejected
}

/// Why the auth server refused a sign-up, read from its answer.
///
/// The auth service's documented refusal carries a numeric `code` next to
/// the `error_code` (`{"code":422,"error_code":"user_already_exists",…}`),
/// which the SDK cannot decode: it then reports "unexpected failure" and
/// hands over the raw answer. So the code is taken from the SDK when it read
/// one, and from the body otherwise; the message is only a fallback. Nothing
/// of the answer — body, message, e-mail — is kept in what is returned.
///
/// > RC U1B-S1 — the body of the real 422 of 2026-10-10 was not read; these
/// > are the documented shapes.
enum SupabaseSignUpRefusal {
    static func classify(_ error: AuthError) -> SupabaseAuthRemoteError {
        switch error {
        case .weakPassword:
            return .weakPassword
        case let .api(_, errorCode, underlyingData, underlyingResponse):
            return classify(
                status: underlyingResponse.statusCode,
                body: underlyingData,
                sdkCode: errorCode.rawValue
            )
        default:
            return .requestFailed
        }
    }

    static func classify(
        status: Int,
        body: Data,
        sdkCode: String?
    ) -> SupabaseAuthRemoteError {
        let answer = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let code = readCode(sdkCode: sdkCode, answer: answer)
        switch code {
        case "weak_password":
            return .weakPassword
        case "user_already_exists", "email_exists":
            return .emailAlreadyRegistered
        case "over_request_rate_limit", "over_email_send_rate_limit":
            return .rateLimited
        case "request_timeout", "hook_timeout", "hook_timeout_after_retry":
            return .timeout
        default:
            break
        }
        switch status {
        case 429:
            return .rateLimited
        case 408:
            return .timeout
        case 500...599:
            return .server
        default:
            break
        }
        if code == nil, let answer, saysAlreadyRegistered(answer) {
            return .emailAlreadyRegistered
        }
        return (400...499).contains(status) ? .rejected : .requestFailed
    }

    /// What the SDK reports when it could not read the answer: not a code.
    private static let unreadCodes: Set<String> = ["unexpected_failure", "unknown"]

    private static func readCode(sdkCode: String?, answer: [String: Any]?) -> String? {
        if let sdkCode, !sdkCode.isEmpty, !unreadCodes.contains(sdkCode) {
            return sdkCode
        }
        guard let answer else { return nil }
        for key in ["error_code", "code"] {
            if let code = answer[key] as? String, !code.isEmpty {
                return code
            }
        }
        return answer["weak_password"] is [String: Any] ? "weak_password" : nil
    }

    private static func saysAlreadyRegistered(_ answer: [String: Any]) -> Bool {
        ["msg", "message", "error_description"].contains { key in
            guard let message = (answer[key] as? String)?.lowercased() else { return false }
            return message.contains("already registered")
                || message.contains("already been registered")
        }
    }
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
    func refresh(record: AuthenticationSessionRecord) async throws
        -> AuthenticationSessionRecord
    func revokeCurrentSession(accessToken: String) async
        -> RemoteRevocationOutcome
}

extension SupabaseAuthRemoteOperating {
    func refresh(record: AuthenticationSessionRecord) async throws
        -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }

    func revokeCurrentSession(accessToken: String) async
        -> RemoteRevocationOutcome {
        .unconfirmed
    }
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
        } catch let error as AuthError {
            // The server answered and refused: say which refusal it was.
            throw SupabaseSignUpRefusal.classify(error)
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

    func refresh(record: AuthenticationSessionRecord) async throws
        -> AuthenticationSessionRecord {
        try Task.checkCancellation()
        var components = URLComponents(
            url: configuration.authURL.appendingPathComponent("token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(
            name: "grant_type",
            value: "refresh_token"
        )]
        guard let url = components?.url, configuration.approves(url) else {
            throw SupabaseAuthRemoteError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.key, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(configuration.key)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RefreshGrant(refreshToken: record.refreshToken)
        )

        do {
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw SupabaseAuthRemoteError.invalidResponse
            }
            switch response.statusCode {
            case 200...299:
                let payload = try JSONDecoder().decode(
                    RefreshResponse.self,
                    from: data
                )
                let refreshed = try Self.makeRecord(from: payload)
                guard refreshed.userID == record.userID,
                      refreshed.email.caseInsensitiveCompare(record.email) == .orderedSame
                else {
                    throw SupabaseAuthRemoteError.invalidResponse
                }
                return AuthenticationSessionRecord(
                    userID: refreshed.userID,
                    email: refreshed.email,
                    isEmailConfirmed: refreshed.isEmailConfirmed,
                    isOnboardingCompleted: record.isOnboardingCompleted,
                    accessToken: refreshed.accessToken,
                    refreshToken: refreshed.refreshToken,
                    expiresAt: refreshed.expiresAt
                )
            case 400, 401:
                throw SupabaseAuthRemoteError.invalidGrant
            case 403:
                throw SupabaseAuthRemoteError.forbidden
            case 429:
                throw SupabaseAuthRemoteError.rateLimited
            case 500...599:
                throw SupabaseAuthRemoteError.server
            default:
                throw SupabaseAuthRemoteError.requestFailed
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SupabaseAuthRemoteError {
            throw error
        } catch SupabaseAuthNetworkError.timeout {
            throw SupabaseAuthRemoteError.timeout
        } catch {
            throw SupabaseAuthRemoteError.requestFailed
        }
    }

    func revokeCurrentSession(accessToken: String) async
        -> RemoteRevocationOutcome {
        guard !accessToken.isEmpty else { return .unconfirmed }
        var components = URLComponents(
            url: configuration.authURL.appendingPathComponent("logout"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "scope", value: "local")]
        guard let url = components?.url, configuration.approves(url) else {
            return .unconfirmed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await fetch(request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 204
            else { return .unconfirmed }
            return .confirmed
        } catch {
            return .unconfirmed
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

    private struct RefreshGrant: Encodable {
        let refreshToken: String

        private enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval
        let user: User

        struct User: Decodable {
            let id: UUID
            let email: String?
            let emailConfirmedAt: String?

            private enum CodingKeys: String, CodingKey {
                case id, email
                case emailConfirmedAt = "email_confirmed_at"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case user
        }
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

    private static func makeRecord(from response: RefreshResponse) throws
        -> AuthenticationSessionRecord {
        let userID = response.user.id.uuidString.lowercased()
        guard let email = response.user.email,
              isValid(email: email),
              response.user.emailConfirmedAt != nil,
              !response.accessToken.isEmpty,
              !response.refreshToken.isEmpty,
              response.expiresAt.isFinite,
              response.expiresAt > 0,
              accessTokenSubject(response.accessToken) == userID
        else {
            throw SupabaseAuthRemoteError.invalidResponse
        }
        return AuthenticationSessionRecord(
            userID: userID,
            email: email,
            isEmailConfirmed: true,
            isOnboardingCompleted: false,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date(timeIntervalSince1970: response.expiresAt)
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
    private let sessionStore: AuthenticationSessionStore?
    private let lifecycle: (any SessionLifecycleProviding)?

    init(
        remote: any SupabaseAuthRemoteOperating,
        sessionStore: AuthenticationSessionStore
    ) {
        self.remote = remote
        self.sessionStore = sessionStore
        lifecycle = nil
    }

    init(
        remote: any SupabaseAuthRemoteOperating,
        lifecycle: any SessionLifecycleProviding
    ) {
        self.remote = remote
        sessionStore = nil
        self.lifecycle = lifecycle
    }

    var description: String { "SupabaseAuthenticationService(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    func restoreSession() async throws -> AuthSession? {
        do {
            if let lifecycle {
                return try await lifecycle.restorePublicSession()
            }
            return try await sessionStore?.hydrate()
        } catch is CancellationError {
            throw CancellationError()
        } catch SessionLifecycleError.missingSession {
            return nil
        } catch SessionLifecycleError.refreshFailed,
                SessionLifecycleError.sessionSuperseded {
            throw AuthenticationError.serviceUnavailable
        } catch SessionLifecycleError.localInvalidationFailed {
            throw AuthenticationError.storageUnavailable
        } catch is AuthenticationSessionStoreError {
            throw AuthenticationError.storageUnavailable
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
            if let lifecycle {
                try await lifecycle.switch(to: record)
            } else if let sessionStore {
                try await sessionStore.replace(with: record)
            } else {
                throw AuthenticationSessionStoreError.storageUnavailable
            }
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
                if let lifecycle {
                    try await lifecycle.switch(to: record)
                } else if let sessionStore {
                    try await sessionStore.replace(with: record)
                } else {
                    throw AuthenticationSessionStoreError.storageUnavailable
                }
                return .authenticated(record.publicSession)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SupabaseAuthRemoteError {
            throw Self.mapSignUp(error)
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
        if let lifecycle {
            switch await lifecycle.signOut() {
            case .confirmed, .unconfirmed:
                return
            case .localInvalidationFailed:
                throw AuthenticationError.storageUnavailable
            }
        }
        do {
            guard let sessionStore else {
                throw AuthenticationSessionStoreError.storageUnavailable
            }
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

    /// Sign-in, session refresh and password recovery: unchanged. The three
    /// sign-up refusals never reach this map from those operations.
    private static func map(_ error: SupabaseAuthRemoteError) -> AuthenticationError {
        switch error {
        case .invalidCredentials:
            .invalidCredentials
        case .emailNotConfirmed:
            .confirmationRequired
        case .invalidResponse, .invalidGrant, .forbidden, .rateLimited,
             .server, .timeout, .requestFailed,
             .emailAlreadyRegistered, .weakPassword, .rejected:
            .serviceUnavailable
        }
    }

    /// Sign-up only: a refusal of what was sent has its own error, so the
    /// screen never reads it as a connection problem. A server, time or
    /// transport failure keeps the connection one.
    private static func mapSignUp(_ error: SupabaseAuthRemoteError) -> AuthenticationError {
        switch error {
        case .emailAlreadyRegistered:
            .emailAlreadyRegistered
        case .weakPassword:
            .weakPassword
        case .rejected:
            .signUpRejected
        case .rateLimited:
            .tooManyAttempts
        case .invalidCredentials, .emailNotConfirmed, .invalidResponse,
             .invalidGrant, .forbidden, .server, .timeout, .requestFailed:
            map(error)
        }
    }
}
