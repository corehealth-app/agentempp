import Testing

@testable import BodyFlow

@Suite("Auth form state")
struct AuthFormStateTests {
    @Test("whitespace-only sign-in fields are required in form order")
    func whitespaceOnlySignIn() {
        #expect(
            AuthInputValidator.signIn(email: " \n ", password: "\t")
                == [.emailRequired, .passwordRequired]
        )
    }

    @Test("reserved invalid top-level domain remains structurally valid")
    func structurallyValidEmail() {
        #expect(
            AuthInputValidator.signIn(
                email: "person@example.invalid",
                password: "local-pass"
            ).isEmpty
        )
    }

    @Test("malformed email is rejected")
    func malformedEmail() {
        #expect(
            AuthInputValidator.recovery(email: "person@")
                == [.emailMalformed]
        )
    }

    @Test("sign-up validation follows field order")
    func signUpFieldOrder() {
        #expect(
            AuthInputValidator.signUp(
                email: "not-an-email",
                password: " ",
                confirmation: " "
            ) == [
                .emailMalformed,
                .passwordRequired,
                .passwordConfirmationRequired,
            ]
        )
    }

    @Test("password confirmation must match without imposing provider policy")
    func passwordConfirmation() {
        #expect(
            AuthInputValidator.signUp(
                email: "person@example.invalid",
                password: "local-pass",
                confirmation: "different"
            ) == [.passwordsDoNotMatch]
        )
    }

    @Test("short non-empty matching password is accepted structurally")
    func noPasswordLengthPolicy() {
        #expect(
            AuthInputValidator.signUp(
                email: "person@example.invalid",
                password: "x",
                confirmation: "x"
            ).isEmpty
        )
    }
}
