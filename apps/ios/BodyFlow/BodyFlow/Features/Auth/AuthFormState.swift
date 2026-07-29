import Foundation

enum AuthValidationIssue: Equatable, Sendable {
    case emailRequired
    case emailMalformed
    case passwordRequired
    case passwordConfirmationRequired
    case passwordsDoNotMatch
}

enum AuthOperationState: Equatable, Sendable {
    case idle
    case submitting
    case recoveryConfirmation
    case failed(AppPresentationError)
}

enum AuthInputValidator {
    static func signIn(
        email: String,
        password: String
    ) -> [AuthValidationIssue] {
        emailIssues(for: email) + passwordIssues(for: password)
    }

    static func signUp(
        email: String,
        password: String,
        confirmation: String
    ) -> [AuthValidationIssue] {
        var issues = emailIssues(for: email) + passwordIssues(for: password)
        let confirmationIsEmpty = confirmation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        if confirmationIsEmpty {
            issues.append(.passwordConfirmationRequired)
        } else if !password
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty,
            password != confirmation {
            issues.append(.passwordsDoNotMatch)
        }

        return issues
    }

    static func recovery(email: String) -> [AuthValidationIssue] {
        emailIssues(for: email)
    }

    private static func emailIssues(
        for email: String
    ) -> [AuthValidationIssue] {
        let candidate = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            return [.emailRequired]
        }

        let components = candidate.split(
            separator: "@",
            omittingEmptySubsequences: false
        )
        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty,
              components[1].contains("."),
              !candidate.contains(where: \Character.isWhitespace) else {
            return [.emailMalformed]
        }

        return []
    }

    private static func passwordIssues(
        for password: String
    ) -> [AuthValidationIssue] {
        password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [.passwordRequired]
            : []
    }
}
