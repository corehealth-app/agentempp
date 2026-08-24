import Foundation

struct AuthenticationSessionRecord: Codable, Equatable, Sendable,
    CustomStringConvertible, CustomReflectable {
    let schemaVersion: Int
    let userID: String
    let email: String
    let isEmailConfirmed: Bool
    let isOnboardingCompleted: Bool
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    init(
        userID: String,
        email: String,
        isEmailConfirmed: Bool,
        isOnboardingCompleted: Bool,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date
    ) {
        schemaVersion = 1
        self.userID = userID
        self.email = email
        self.isEmailConfirmed = isEmailConfirmed
        self.isOnboardingCompleted = isOnboardingCompleted
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    var publicSession: AuthSession {
        AuthSession(
            userID: userID,
            email: email,
            isEmailConfirmed: isEmailConfirmed,
            isOnboardingCompleted: isOnboardingCompleted
        )
    }

    var description: String { "AuthenticationSessionRecord(redacted)" }

    var customMirror: Mirror {
        Mirror(self, children: [:], displayStyle: .struct)
    }
}
