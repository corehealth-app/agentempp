import Testing

@testable import BodyFlow

/// Asked for by the first tester on 2026-10-10 (build 1.0 (3)): "Deveria ter
/// aquele olho pra mostrar as senhas pra conferir". These are the rules of
/// that control, without a screen.
@Suite("Password visibility (the eye)")
struct AuthPasswordVisibilityTests {
    @Test("passwords start hidden, each field toggles by itself, and leaving hides them all")
    func passwordsStartHiddenToggleOneFieldAtATimeAndHideOnLeaving() {
        var visibility = AuthPasswordVisibility()
        #expect(!visibility.isRevealed(.password))
        #expect(!visibility.isRevealed(.confirmation))
        // Hidden: the control offers to show.
        #expect(visibility.controlLabelKey(for: .password) == "auth.password.show")
        #expect(visibility.controlLabelKey(for: .confirmation) == "auth.password-confirmation.show")
        #expect(visibility.controlLabelFallback(for: .password) == "Mostrar senha")
        #expect(visibility.controlLabelFallback(for: .confirmation) == "Mostrar confirmação da senha")

        visibility.toggle(.password)
        #expect(visibility.isRevealed(.password))
        #expect(!visibility.isRevealed(.confirmation), "The confirmation is its own field")
        // Shown: the control offers to hide; the other one is unchanged.
        #expect(visibility.controlLabelKey(for: .password) == "auth.password.hide")
        #expect(visibility.controlLabelFallback(for: .password) == "Ocultar senha")
        #expect(visibility.controlLabelKey(for: .confirmation) == "auth.password-confirmation.show")

        visibility.toggle(.password)
        #expect(!visibility.isRevealed(.password), "A second touch hides it again")

        visibility.toggle(.confirmation)
        #expect(visibility.isRevealed(.confirmation))
        #expect(!visibility.isRevealed(.password))
        #expect(visibility.controlLabelKey(for: .confirmation) == "auth.password-confirmation.hide")
        #expect(visibility.controlLabelFallback(for: .confirmation) == "Ocultar confirmação da senha")

        visibility.toggle(.password)
        #expect(visibility.isRevealed(.password) && visibility.isRevealed(.confirmation))

        // Sending, leaving the screen, leaving the foreground.
        visibility.hideAll()
        #expect(!visibility.isRevealed(.password))
        #expect(!visibility.isRevealed(.confirmation))
        #expect(visibility == AuthPasswordVisibility())
    }
}
