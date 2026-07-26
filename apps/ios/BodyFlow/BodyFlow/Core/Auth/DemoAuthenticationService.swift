import Foundation

enum DemoOperationBehavior<Failure: Error & Sendable>: Sendable {
    case succeed(after: Duration?)
    case fail(Failure, after: Duration?)
}

enum DemoUser {
    static let id = "demo-user-v1"
    static let email = "demo-user@fixture.invalid"
}

actor DemoAuthenticationService: AuthenticationService {
    private let stateStore: DemoStateStore
    private let configuration: AppLaunchConfiguration
    private var hasAppliedInitialReset = false
    private var pendingEmail: String?

    init(
        stateStore: DemoStateStore,
        configuration: AppLaunchConfiguration
    ) {
        self.stateStore = stateStore
        self.configuration = configuration
    }

    func restoreSession() async throws -> AuthSession? {
        try await applyInitialResetIfNeeded()

        if configuration.startsWithCompletedFixture {
            return completedFixtureSession
        }

        do {
            return try await stateStore.loadSession()
        } catch {
            throw AuthenticationError.storageUnavailable
        }
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        guard isStructurallyValid(email: email), !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthenticationError.invalidInput
        }

        try await apply(configuration.authBehavior)

        let completed: Bool
        do {
            completed = try await stateStore.loadSession()?.isOnboardingCompleted ?? false
        } catch {
            throw AuthenticationError.storageUnavailable
        }

        let session = AuthSession(
            userID: DemoUser.id,
            email: normalized(email),
            isEmailConfirmed: true,
            isOnboardingCompleted: completed
        )
        try Task.checkCancellation()

        do {
            try await stateStore.saveSession(session)
        } catch {
            throw AuthenticationError.storageUnavailable
        }

        return session
    }

    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        guard isStructurallyValid(email: email), !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthenticationError.invalidInput
        }

        try await apply(configuration.authBehavior)
        let normalizedEmail = normalized(email)
        pendingEmail = normalizedEmail
        return .confirmationRequired(email: normalizedEmail)
    }

    func confirmEmailForDevelopment() async throws -> AuthSession {
        guard configuration.mode == .demo else {
            throw AuthenticationError.operationUnavailable
        }
        guard let pendingEmail else {
            throw AuthenticationError.invalidInput
        }

        try await apply(configuration.authBehavior)
        let session = AuthSession(
            userID: DemoUser.id,
            email: pendingEmail,
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        try Task.checkCancellation()

        do {
            try await stateStore.saveSession(session)
        } catch {
            throw AuthenticationError.storageUnavailable
        }

        return session
    }

    func requestPasswordRecovery(email: String) async throws {
        guard isStructurallyValid(email: email) else {
            throw AuthenticationError.invalidInput
        }

        try await apply(configuration.authBehavior)
    }

    func signOut() async throws {
        try await apply(configuration.authBehavior)
        try Task.checkCancellation()

        do {
            try await stateStore.clearSession()
        } catch {
            throw AuthenticationError.storageUnavailable
        }
    }

    private var completedFixtureSession: AuthSession {
        AuthSession(
            userID: DemoUser.id,
            email: DemoUser.email,
            isEmailConfirmed: true,
            isOnboardingCompleted: true
        )
    }

    private func applyInitialResetIfNeeded() async throws {
        guard !hasAppliedInitialReset else {
            return
        }

        hasAppliedInitialReset = true
        guard configuration.shouldResetDemoState else {
            return
        }

        try Task.checkCancellation()
        do {
            try await stateStore.clearAll()
            try Task.checkCancellation()
            try await stateStore.clearCoachPersona(for: DemoUser.id)
        } catch {
            throw AuthenticationError.storageUnavailable
        }
    }

    private func apply(
        _ behavior: DemoOperationBehavior<AuthenticationError>
    ) async throws {
        switch behavior {
        case .succeed(let delay):
            if let delay { try await Task.sleep(for: delay) }
        case .fail(let error, let delay):
            if let delay { try await Task.sleep(for: delay) }
            try Task.checkCancellation()
            throw error
        }
    }

    private func isStructurallyValid(email: String) -> Bool {
        let candidate = normalized(email)
        return !candidate.isEmpty && candidate.contains("@")
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
