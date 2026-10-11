import SwiftUI
import UIKit

/// Which password of a screen: the password itself or its confirmation.
enum AuthPasswordSlot: Hashable, Sendable {
    case password
    case confirmation
}

/// Which passwords of a screen are shown as typed. Pure, so every rule of
/// the "eye" is tested without a screen.
///
/// Asked for by the first tester on 2026-10-10 (build 1.0 (3)): "Deveria ter
/// aquele olho pra mostrar as senhas pra conferir".
struct AuthPasswordVisibility: Equatable, Sendable {
    private(set) var revealed: Set<AuthPasswordSlot>

    /// Every password starts hidden.
    init(revealed: Set<AuthPasswordSlot> = []) {
        self.revealed = revealed
    }

    func isRevealed(_ slot: AuthPasswordSlot) -> Bool {
        revealed.contains(slot)
    }

    /// Shows a hidden password, hides a shown one. Each field is its own.
    mutating func toggle(_ slot: AuthPasswordSlot) {
        if revealed.contains(slot) {
            revealed.remove(slot)
        } else {
            revealed.insert(slot)
        }
    }

    /// Sending the form, leaving the screen, the app leaving the foreground:
    /// no password stays readable.
    mutating func hideAll() {
        revealed = []
    }

    /// What the control of a field says: "show" while hidden, "hide" while
    /// shown.
    func controlLabelKey(for slot: AuthPasswordSlot) -> String {
        switch (slot, isRevealed(slot)) {
        case (.password, false): "auth.password.show"
        case (.password, true): "auth.password.hide"
        case (.confirmation, false): "auth.password-confirmation.show"
        case (.confirmation, true): "auth.password-confirmation.hide"
        }
    }

    /// The same sentence in Portuguese, for a catalog that cannot be read.
    func controlLabelFallback(for slot: AuthPasswordSlot) -> String {
        switch (slot, isRevealed(slot)) {
        case (.password, false): "Mostrar senha"
        case (.password, true): "Ocultar senha"
        case (.confirmation, false): "Mostrar confirmação da senha"
        case (.confirmation, true): "Ocultar confirmação da senha"
        }
    }

    func controlSymbol(for slot: AuthPasswordSlot) -> BodyFlowSymbol {
        isRevealed(slot) ? .hidePassword : .showPassword
    }
}

/// A password field with its "eye".
///
/// The field that is typed in is ALWAYS the `SecureField` the screens had:
/// the eye never replaces it and never changes how it is drawn. Shown, the
/// field's own surface is laid over everything that secure field draws —
/// its bullets, its caret — and the same text is drawn readable on top. So
/// the keyboard, the focus, the content type, the system's password offers
/// and the text never change with the eye — and what is typed can never be
/// rewritten by smart quotes, smart dashes or autocorrection, which a secure
/// field does not have.
///
/// Engineer's choice, taken after the first design was seen failing (see
/// the record of 2026-10-10): the plan swapped the secure field for a plain
/// one while shown. Hosted and UI tests showed that swap losing the order of
/// focus events and, once, leaving the plain field on screen after "hide".
/// The decision between designs stays the orchestrator's (E-1).
///
/// Review of 2026-10-11: the bullets used to be taken off the screen by
/// asking the secure field to draw its own text transparent. With the eye
/// touched on an EMPTY field and the password typed afterwards the bullets
/// stayed, black, over the readable text (why that request was not obeyed
/// there was not established). Nothing is asked of the secure field any
/// more: what it draws is covered, whatever it draws and whenever.
///
/// > RC U1B-E3 — shown, the password is read by VoiceOver and appears in a
/// > screen recording or mirroring. It cannot be copied (it is drawn, not
/// > editable).
@MainActor
struct AuthPasswordField<Focus: Hashable>: View {
    let slot: AuthPasswordSlot
    /// The placeholder and the spoken label of the field.
    let title: String
    @Binding var text: String
    @Binding var visibility: AuthPasswordVisibility
    let contentType: UITextContentType
    let submitLabel: SubmitLabel
    let focus: FocusState<Focus?>.Binding
    let focusValue: Focus
    let hint: String
    /// The field's identifier. Its control is `<identifier>.visibility` and
    /// the readable text, while shown, `<identifier>.shown`.
    let identifier: String
    let onSubmit: @MainActor () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: BodyFlowSpacing.xs) {
            ZStack(alignment: .leading) {
                SecureField(title, text: $text)
                    .textContentType(contentType)
                    .submitLabel(submitLabel)
                    .focused(focus, equals: focusValue)
                    .onSubmit(onSubmit)
                    // Shown: the caret and the selection handles step aside.
                    .tint(showsTypedText ? Color.clear : nil)
                    .accessibilityLabel(title)
                    .accessibilityHint(hint)
                    .accessibilityIdentifier(identifier)
                    .overlay {
                        if showsTypedText {
                            // Shown: the field's own surface, over all the
                            // secure field draws. It takes no touch — the
                            // field underneath is still the one touched.
                            BodyFlowFieldStyle.fill(isEnabled: isEnabled)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                if showsTypedText {
                    // Never cut: a long password wraps and the field grows.
                    Text(verbatim: text)
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(textColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                        .accessibilityLabel(title)
                        .accessibilityValue(text)
                        .accessibilityIdentifier(identifier + ".shown")
                }
            }
            // Reserves the width of the control inside the field, and none
            // of its height: the field is as tall as it always was.
            glyph
                .hidden()
                .frame(minWidth: BodyFlowSpacing.minimumTapTarget)
                .frame(height: 0)
        }
        .bodyFlowField()
        .overlay(alignment: .trailing) {
            eye.padding(.trailing, BodyFlowSpacing.md)
        }
    }

    /// The readable text is on screen only when there is something to read:
    /// an empty field keeps its placeholder.
    private var showsTypedText: Bool {
        visibility.isRevealed(slot) && !text.isEmpty
    }

    private var textColor: Color {
        BodyFlowColor.color(isEnabled ? .textPrimary : .disabledText)
    }

    private var eye: some View {
        Button {
            visibility.toggle(slot)
        } label: {
            glyph
                .frame(
                    minWidth: BodyFlowSpacing.minimumTapTarget,
                    minHeight: BodyFlowSpacing.minimumTapTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRow)
        .accessibilityLabel(PremiumPresentationCopy.string(
            String.LocalizationValue(visibility.controlLabelKey(for: slot)),
            locale: locale,
            fallback: visibility.controlLabelFallback(for: slot)
        ))
        .accessibilityIdentifier(identifier + ".visibility")
    }

    /// The two glyphs share one box, so the control is the same size shown
    /// or hidden and never moves when touched.
    private var glyph: some View {
        ZStack {
            ForEach([BodyFlowSymbol.showPassword, .hidePassword], id: \.self) { symbol in
                Image(symbol: symbol)
                    .opacity(symbol == visibility.controlSymbol(for: slot) ? 1 : 0)
            }
        }
        .font(BodyFlowTypography.body)
        .foregroundStyle(BodyFlowColor.secondaryText)
        .accessibilityHidden(true)
    }
}
