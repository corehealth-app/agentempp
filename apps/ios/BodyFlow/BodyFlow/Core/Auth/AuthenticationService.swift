struct AuthSession: Codable, Equatable, Sendable {
    let userID: String
    let email: String
    let isEmailConfirmed: Bool
    let isOnboardingCompleted: Bool
}

enum AuthSignUpResult: Equatable, Sendable {
    case confirmationRequired(email: String)
    case authenticated(AuthSession)
}

enum AuthenticationError: Error, Equatable, Sendable {
    case invalidInput
    case invalidCredentials
    case confirmationRequired
    case operationUnavailable
    case serviceUnavailable
    case storageUnavailable
}

protocol AuthenticationService: Sendable {
    func restoreSession() async throws -> AuthSession?
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(email: String, password: String) async throws -> AuthSignUpResult
    func confirmEmailForDevelopment() async throws -> AuthSession
    func requestPasswordRecovery(email: String) async throws
    func signOut() async throws
}

struct UnavailableAuthenticationService: AuthenticationService {
    func restoreSession() async throws -> AuthSession? {
        throw AuthenticationError.operationUnavailable
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        throw AuthenticationError.operationUnavailable
    }

    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        throw AuthenticationError.operationUnavailable
    }

    func confirmEmailForDevelopment() async throws -> AuthSession {
        throw AuthenticationError.operationUnavailable
    }

    func requestPasswordRecovery(email: String) async throws {
        throw AuthenticationError.operationUnavailable
    }

    func signOut() async throws {
        throw AuthenticationError.operationUnavailable
    }
}
