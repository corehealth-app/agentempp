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

    @Test("sign-up keyboard contract declares ordered Next, Next, Done actions")
    func signUpKeyboardContract() {
        #expect(SignUpKeyboardPolicy.fields == [
            .email,
            .password,
            .confirmation,
        ])
        #expect(
            SignUpKeyboardPolicy.presentation(for: .email)
                == SignUpKeyboardPresentation(
                    submitLabel: .next,
                    action: .focus(.password)
                )
        )
        #expect(
            SignUpKeyboardPolicy.presentation(for: .password)
                == SignUpKeyboardPresentation(
                    submitLabel: .next,
                    action: .focus(.confirmation)
                )
        )
        #expect(
            SignUpKeyboardPolicy.presentation(for: .confirmation)
                == SignUpKeyboardPresentation(
                    submitLabel: .done,
                    action: .submit
                )
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

    @Test("validation accessibility text keeps bounded hints and announcements")
    func validationAccessibilityText() {
        let messages = [
            AuthValidationIssue.emailRequired.message,
            AuthValidationIssue.passwordRequired.message,
        ]

        #expect(
            FormAccessibilityText.hint(for: messages.first)
                == "Erro: Informe seu e-mail."
        )
        #expect(
            FormAccessibilityText.validationAnnouncement(messages: messages)
                == "Erros no formulário: Informe seu e-mail. Informe sua senha."
        )
        #expect(FormAccessibilityText.hint(for: nil).isEmpty)
        #expect(
            FormAccessibilityText.validationAnnouncement(messages: []) == nil
        )
    }
}
