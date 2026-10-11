import Observation
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// The password field with its "eye", hosted in the window: what the system
/// reads from the native control in each state, and where the control sits.
///
/// Asked for by the first tester on 2026-10-10 (build 1.0 (3)): "Deveria ter
/// aquele olho pra mostrar as senhas pra conferir".
@MainActor
final class AuthPasswordFieldRenderingTests: XCTestCase {
    private typealias Probe = PremiumRenderingTestSupport.AccessibilityProbe

    private struct Form {
        let name: String
        let contentType: UITextContentType
        static let signUp = Form(name: "Criar conta", contentType: .newPassword)
        static let signIn = Form(name: "Entrar", contentType: .password)
    }

    /// The field that is typed in is the same secure field, shown or hidden:
    /// the eye never replaces it. So what is typed can never be rewritten —
    /// a secure field has no smart quotes, smart dashes or autocorrection —
    /// and the system keeps seeing the field it always saw. Shown, the same
    /// text is on screen, readable.
    func testTheFieldThatIsTypedInIsTheSameSecureFieldShownOrHidden() throws {
        for form in [Form.signUp, .signIn] {
            let box = EyeBox(text: "local-pass")
            let live = host(box, form)
            defer { live.detach() }

            let hiddenFields = live.nativeViews(UITextField.self)
            XCTAssertEqual(hiddenFields.count, 1, "\(form.name): exactly one native field while hidden")
            let field = try XCTUnwrap(hiddenFields.first, form.name)
            XCTAssertTrue(field.isSecureTextEntry, "\(form.name): hidden is a secure field")
            XCTAssertEqual(field.textContentType, form.contentType, form.name)
            XCTAssertEqual(field.placeholder, "Senha", form.name)
            XCTAssertEqual(field.text, "local-pass", form.name)
            let keyboard = field.keyboardType
            let returnKey = field.returnKeyType
            XCTAssertNil(shownText(live.probe()), "\(form.name): nothing readable while hidden")

            box.touchEye()
            let readable = try XCTUnwrap(
                shownText(live.probe()),
                "\(form.name): a touch on the eye shows what was typed: \(live.probe())"
            )
            XCTAssertEqual(readable.value, "local-pass", form.name)
            XCTAssertFalse(readable.isButton, form.name)
            let shownFields = live.nativeViews(UITextField.self)
            XCTAssertEqual(shownFields.count, 1, "\(form.name): exactly one native field while shown")
            let shown = try XCTUnwrap(shownFields.first, form.name)
            XCTAssertTrue(shown === field, "\(form.name): the control is never replaced")
            XCTAssertTrue(shown.isSecureTextEntry, "\(form.name): what is typed still goes into a secure field")
            XCTAssertEqual(shown.textContentType, form.contentType, form.name)
            XCTAssertEqual(shown.placeholder, "Senha", form.name)
            XCTAssertEqual(shown.keyboardType, keyboard, form.name)
            XCTAssertEqual(shown.returnKeyType, returnKey, form.name)
            XCTAssertEqual(shown.text, "local-pass", form.name)

            // Text arriving through the binding is what is read.
            box.text = "local-pass1"
            XCTAssertEqual(shownText(live.probe())?.value, "local-pass1", form.name)
            XCTAssertTrue(live.nativeViews(UITextField.self).first === field, form.name)
            XCTAssertEqual(field.text, "local-pass1", form.name)

            box.touchEye()
            XCTAssertNil(shownText(live.probe()), "\(form.name): a second touch hides it again")
            XCTAssertTrue(live.nativeViews(UITextField.self).first === field, form.name)
            XCTAssertTrue(field.isSecureTextEntry, form.name)

            // Leaving the screen, sending, leaving the foreground.
            box.touchEye()
            XCTAssertNotNil(shownText(live.probe()), form.name)
            box.visibility.hideAll()
            XCTAssertNil(shownText(live.probe()), "\(form.name): hiding everything leaves nothing readable")
        }
    }

    /// An empty field that is "shown" keeps its placeholder: there is
    /// nothing to read yet.
    func testAnEmptyShownFieldShowsNothing() throws {
        let box = EyeBox(text: "", revealed: [.password])
        let live = host(box, .signUp)
        defer { live.detach() }
        XCTAssertNil(shownText(live.probe()))
        let field = try XCTUnwrap(live.nativeViews(UITextField.self).first)
        XCTAssertTrue(field.isSecureTextEntry)
        XCTAssertEqual(field.placeholder, "Senha")
        box.text = "a"
        XCTAssertEqual(shownText(live.probe())?.value, "a")
    }

    /// The control: one button per field, with its spoken label in the two
    /// languages, never smaller than the minimum target. (Its identifier is
    /// read where it can be: by the UI tests, which find it by that name.)
    func testEyeIsOneLabelledButtonWithTheMinimumTarget() throws {
        let rows: [(AuthPasswordSlot, Bool, String, String)] = [
            (.password, false, "Mostrar senha", "Show password"),
            (.password, true, "Ocultar senha", "Hide password"),
            (.confirmation, false, "Mostrar confirmação da senha", "Show password confirmation"),
            (.confirmation, true, "Ocultar confirmação da senha", "Hide password confirmation"),
        ]
        for (language, locale) in [("pt-BR", Locale(identifier: "pt-BR")), ("en", Locale(identifier: "en"))] {
            for size in [DynamicTypeSize.large, .accessibility5] {
                for (slot, revealed, pt, en) in rows {
                    let label = language == "pt-BR" ? pt : en
                    let context = "\(label) (\(language), \(size))"
                    let box = EyeBox(text: "local-pass", revealed: revealed ? [slot] : [])
                    let probes = PremiumRenderingTestSupport.accessibilityProbe(
                        EyeHarness(box: box, slot: slot, contentType: .newPassword)
                            .environment(\.locale, locale),
                        width: 393, size: size
                    )
                    let buttons = probes.filter(\.isButton)
                    XCTAssertEqual(buttons.count, 1, "One control: \(context): \(probes)")
                    let eye = try XCTUnwrap(
                        buttons.first { $0.label == label },
                        "No control saying «\(label)»: \(context): \(probes)"
                    )
                    XCTAssertTrue(eye.isEnabled, context)
                    XCTAssertGreaterThanOrEqual(eye.frame.width, BodyFlowSpacing.minimumTapTarget, context)
                    XCTAssertGreaterThanOrEqual(eye.frame.height, BodyFlowSpacing.minimumTapTarget, context)
                    XCTAssertGreaterThanOrEqual(eye.frame.minX, -0.5, context)
                    XCTAssertLessThanOrEqual(eye.frame.maxX, 393.5, context)
                }
            }
        }
    }

    /// The control lives inside the field: the field is as tall as the
    /// plain secure field it replaces, shown or hidden.
    func testEyeDoesNotGrowTheField() throws {
        let locale = Locale(identifier: "pt-BR")
        for size in [DynamicTypeSize.large, .accessibility5] {
            let reference = PremiumRenderingTestSupport.fittingSize(
                SecureField("Senha", text: .constant("local-pass"))
                    .textContentType(.newPassword)
                    .bodyFlowField(),
                width: 375, dark: false, size: size, locale: locale
            )
            for revealed in [false, true] {
                let context = "\(size) revealed=\(revealed)"
                let box = EyeBox(text: "local-pass", revealed: revealed ? [.password] : [])
                // Without the control this would prove nothing.
                let probes = PremiumRenderingTestSupport.accessibilityProbe(
                    EyeHarness(box: box, slot: .password, contentType: .newPassword)
                        .environment(\.locale, locale),
                    width: 375, size: size
                )
                _ = try XCTUnwrap(
                    probes.first { $0.isButton && $0.label == (revealed ? "Ocultar senha" : "Mostrar senha") },
                    "The field has no control: \(context): \(probes)"
                )
                let field = PremiumRenderingTestSupport.fittingSize(
                    EyeHarness(box: box, slot: .password, contentType: .newPassword),
                    width: 375, dark: false, size: size, locale: locale
                )
                XCTAssertEqual(field.height, reference.height, accuracy: 1, context)
                XCTAssertGreaterThanOrEqual(field.height, BodyFlowSpacing.minimumTapTarget, context)
                XCTAssertLessThanOrEqual(field.width, 375.5, context)
            }
        }
    }

    /// The keyboard stays where it was: touching the eye of the field being
    /// typed in leaves that very field with the keyboard, shown and hidden.
    func testTheKeyboardStaysOnTheFieldWhenTheEyeIsTouched() throws {
        let box = EyeBox(text: "local-pass")
        let live = host(box, .signIn)
        defer {
            live.endEditing()
            live.detach()
        }

        box.wantsFocus = true
        let field = try XCTUnwrap(live.nativeViews(UITextField.self).first)
        pump(until: { field.isFirstResponder && box.focused == .password })
        XCTAssertTrue(field.isFirstResponder, "Precondition: the hidden field has the keyboard")
        XCTAssertEqual(box.focused, .password)

        box.touchEye()
        XCTAssertNotNil(shownText(live.probe()), "The touch shows the password")
        XCTAssertTrue(live.nativeViews(UITextField.self).first === field)
        XCTAssertTrue(field.isFirstResponder, "The keyboard stays on the field while it is shown")
        XCTAssertEqual(box.focused, .password)
        XCTAssertEqual(field.text, "local-pass")

        box.touchEye()
        XCTAssertNil(shownText(live.probe()), "A second touch hides it again")
        XCTAssertTrue(live.nativeViews(UITextField.self).first === field)
        XCTAssertTrue(field.isFirstResponder, "The keyboard stays on the field when it is hidden again")
        XCTAssertEqual(box.focused, .password)
        XCTAssertEqual(field.text, "local-pass")
    }

    /// A shown password is there to be checked: a long one, at the largest
    /// text size on the narrowest phone, wraps and is never cut.
    func testALongShownPasswordWrapsAndIsNeverCut() throws {
        let long = String(repeating: "Abc-123_", count: 5)
        let locale = Locale(identifier: "pt-BR")
        for size in [DynamicTypeSize.large, .accessibility5] {
            let hidden = PremiumRenderingTestSupport.fittingSize(
                EyeHarness(box: EyeBox(text: long), slot: .password, contentType: .newPassword),
                width: 320, dark: false, size: size, locale: locale
            )
            let shownBox = EyeBox(text: long, revealed: [.password])
            let shown = PremiumRenderingTestSupport.fittingSize(
                EyeHarness(box: shownBox, slot: .password, contentType: .newPassword),
                width: 320, dark: false, size: size, locale: locale
            )
            XCTAssertLessThanOrEqual(shown.width, 320.5, "\(size)")
            XCTAssertGreaterThan(
                shown.height, hidden.height + 1,
                "40 characters do not fit one line at 320 pt: the field grows (\(size))"
            )
            let live = PremiumRenderingTestSupport.liveAccessibilityHost(
                EyeHarness(box: shownBox, slot: .password, contentType: .newPassword)
                    .environment(\.locale, locale),
                width: 320, size: size
            )
            defer { live.detach() }
            let readable = try XCTUnwrap(shownText(live.probe()), "\(size)")
            XCTAssertEqual(readable.value, long, "\(size)")
            XCTAssertGreaterThanOrEqual(readable.frame.minX, -0.5, "\(size)")
            XCTAssertLessThanOrEqual(readable.frame.maxX, 320.5, "\(size)")
        }
    }

    // MARK: Review of 2026-10-11 — the eye is touched BEFORE the password is typed
    //
    // Seen by the adversarial review in the frames of the run
    // u1b-rev1-08-green-auth-ui (00:54:12 to 00:54:16): on "Entrar", pt-BR,
    // light — touch the empty "Senha" field, touch the eye (it says "Ocultar
    // senha"), type a'b"c--d. The eight bullets of the secure field stayed on
    // screen, black, over the eight readable characters: the shown password
    // could not be read. Typed BEFORE the eye was touched, the same password
    // read clean. The component is the password of "Criar conta" too.
    //
    // No picture a test can take contains the bullets of a secure field: not
    // the picture drawn in process (run u1b-fix1-02-red-run: the same view
    // drew the same pixels with the field switched off, hidden, with eight
    // characters in it) and not XCUITest's screenshot (same run: a UI test
    // of this very scenario compared the two orders by their ink and PASSED
    // over the defect). So what the secure field draws is made visible by a
    // marker laid inside the native field, exactly where its bullets are.

    /// Shown, nothing the secure field itself draws reaches the screen —
    /// whichever came first, the eye or the typing.
    func testNothingTheSecureFieldDrawsReachesTheScreenWhileThePasswordIsShown() throws {
        let typed = "a'b\"c--d"
        for form in [Form.signUp, .signIn] {
            // The reported order first; then the order that read clean.
            for eyeFirst in [true, false] {
                let order = "\(form.name), \(eyeFirst ? "the eye, then a'b\"c--d" : "a'b\"c--d, then the eye")"
                let drawn = try drawnWhenShown(form, typing: typed, eyeFirst: eyeFirst)
                XCTAssertGreaterThan(
                    drawn.markerWhileHidden, 0,
                    "\(order): control — hidden, what the secure field draws IS on screen and the marker shows it"
                )
                XCTAssertGreaterThan(
                    drawn.readableInk, 0,
                    "\(order): the typed password is drawn where it is read"
                )
                XCTAssertEqual(
                    drawn.markerWhileShown, 0,
                    "\(order): shown, the secure field's own drawing — where its bullets are — still "
                        + "reaches the screen (\(drawn.nativeText))"
                )
            }
        }
    }

    /// An empty field that is "shown" is still the field the person knows:
    /// its placeholder is on screen, drawn by the secure field itself.
    func testAnEmptyShownFieldKeepsItsPlaceholderOnScreen() throws {
        for form in [Form.signUp, .signIn] {
            let box = EyeBox(revealed: [.password])
            let live = host(box, form)
            defer { live.detach() }
            let field = try XCTUnwrap(live.nativeViews(UITextField.self).first, form.name)
            XCTAssertEqual(field.placeholder, "Senha", form.name)
            let empty = try Pixels(live.image())
            let alpha = field.alpha
            field.alpha = 0
            let withoutTheField = try Pixels(live.image())
            XCTAssertEqual(field.alpha, 0, "\(form.name): the probe's own switch was undone under it")
            field.alpha = alpha
            XCTAssertGreaterThan(
                empty.differing(from: withoutTheField), 0,
                "\(form.name): shown and empty, the placeholder left the screen"
            )
        }
    }

    // MARK: Support

    private struct ShownPicture {
        /// How much is drawn dark where the readable password is read.
        let readableInk: Int
        /// How many pixels of the marker laid inside the native field reach
        /// the screen while the password is shown.
        let markerWhileShown: Int
        /// Control: the same marker with the password hidden again.
        let markerWhileHidden: Int
        /// What the native field said of its own text while shown — read
        /// only when an assertion fails.
        let nativeText: String
    }

    /// The field of a form, touched while empty, with `typed` typed key by
    /// key and the eye touched before the first key (the reported order) or
    /// after the last one.
    private func drawnWhenShown(_ form: Form, typing typed: String, eyeFirst: Bool) throws -> ShownPicture {
        let order = "\(form.name), \(eyeFirst ? "eye first" : "typed first")"
        let box = EyeBox()
        let live = host(box, form)
        defer {
            live.endEditing()
            live.detach()
        }
        let field = try XCTUnwrap(live.nativeViews(UITextField.self).first, order)

        // The empty field is touched: it has the keyboard.
        box.wantsFocus = true
        pump(until: { field.isFirstResponder })
        XCTAssertTrue(field.isFirstResponder, "\(order): precondition — the empty field has the keyboard")

        if eyeFirst {
            box.touchEye()
            XCTAssertNil(shownText(live.probe()), "\(order): nothing to read yet")
        }
        for character in typed {
            press(String(character), on: field)
        }
        if !eyeFirst {
            XCTAssertNil(shownText(live.probe()), "\(order): hidden while it is typed")
            box.touchEye()
        }
        let readable = try XCTUnwrap(shownText(live.probe()), "\(order): the typed password is readable")
        XCTAssertEqual(readable.value, typed, order)
        XCTAssertEqual(box.text, typed, order)
        XCTAssertEqual(field.text, typed, order)
        XCTAssertTrue(field.isSecureTextEntry, order)
        XCTAssertTrue(field.isFirstResponder, "\(order): the keyboard is still on the field")

        let readableInk = try Pixels(live.image()).dark(in: readable.frame)
        let attributed = field.attributedText.flatMap { $0.length > 0 ? $0 : nil }
        let firstCharacterColor = attributed?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        let nativeText = "native field: text colour alpha "
            + "\(field.textColor.map { String(describing: $0.cgColor.alpha) } ?? "nil"), "
            + "first character's own colour alpha "
            + "\(firstCharacterColor.map { String(describing: $0.cgColor.alpha) } ?? "nil")"

        // The marker: the native field's own area, in a colour nothing else
        // on screen has.
        let marker = UIView(frame: field.bounds)
        marker.backgroundColor = Pixels.markerColor
        marker.isUserInteractionEnabled = false
        marker.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        field.addSubview(marker)
        defer { marker.removeFromSuperview() }
        let markerWhileShown = try Pixels(live.image()).marker()
        XCTAssertTrue(marker.superview === field, "\(order): the marker was taken out of the field under the test")

        // Control, on the same host with the same marker: hidden again, what
        // the secure field draws is on screen.
        box.touchEye()
        live.endEditing()
        XCTAssertNil(shownText(live.probe()), "\(order): hidden again")
        let markerWhileHidden = try Pixels(live.image()).marker()
        return ShownPicture(
            readableInk: readableInk,
            markerWhileShown: markerWhileShown,
            markerWhileHidden: markerWhileHidden,
            nativeText: nativeText
        )
    }

    /// One key, as the keyboard sends it: the field's delegate is asked,
    /// then the character goes into the field — which is what tells SwiftUI
    /// that the text changed.
    private func press(_ character: String, on field: UITextField) {
        let end = NSRange(location: (field.text ?? "").utf16.count, length: 0)
        let allowed = field.delegate?.textField?(
            field, shouldChangeCharactersIn: end, replacementString: character
        ) ?? true
        guard allowed else { return }
        field.insertText(character)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    /// The readable text of the field: not a button, spoken as the field's
    /// own name with the typed text as its value.
    private func shownText(_ probes: [Probe]) -> Probe? {
        probes.first { !$0.isButton && $0.label == "Senha" && !$0.value.isEmpty }
    }

    private func host(_ box: EyeBox, _ form: Form) -> PremiumRenderingTestSupport.LiveAccessibilityHost {
        PremiumRenderingTestSupport.liveAccessibilityHost(
            EyeHarness(box: box, slot: .password, contentType: form.contentType)
                .environment(\.locale, Locale(identifier: "pt-BR")),
            width: 393
        )
    }

    /// Lets the main run loop turn until `condition` holds, for at most two
    /// seconds; the assertions that follow say what was expected.
    private func pump(until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }
}

/// The pixels of a picture of the hosted field: two pictures are compared
/// pixel by pixel, and what is drawn dark inside a frame is counted.
private struct Pixels {
    let width: Int
    let height: Int
    private let scale: CGFloat
    private let bytes: [UInt8]

    init(_ image: UIImage) throws {
        let source = try XCTUnwrap(image.cgImage, "The picture has no bitmap")
        let width = source.width
        let height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drew, "The picture could not be read")
        self.width = width
        self.height = height
        self.scale = image.scale
        self.bytes = bytes
    }

    /// How many pixels are not the same in the two pictures (a channel apart
    /// by more than a rounding step). Pictures of different sizes share no
    /// pixel.
    func differing(from other: Pixels) -> Int {
        guard width == other.width, height == other.height else {
            return max(bytes.count, other.bytes.count) / 4
        }
        if bytes == other.bytes { return 0 }
        return bytes.withUnsafeBufferPointer { mine -> Int in
            other.bytes.withUnsafeBufferPointer { theirs -> Int in
                var count = 0
                var offset = 0
                while offset < mine.count {
                    for channel in 0..<4
                    where abs(Int(mine[offset + channel]) - Int(theirs[offset + channel])) > 8 {
                        count += 1
                        break
                    }
                    offset += 4
                }
                return count
            }
        }
    }

    /// The colour of the marker a test lays inside a native view: pure
    /// magenta, which no token of the app is.
    static var markerColor: UIColor { UIColor(red: 1, green: 0, blue: 1, alpha: 1) }

    /// How many pixels of the picture are the marker's colour.
    func marker() -> Int {
        bytes.withUnsafeBufferPointer { pixels -> Int in
            var count = 0
            var offset = 0
            while offset < pixels.count {
                if pixels[offset] > 200, pixels[offset + 1] < 90, pixels[offset + 2] > 200 { count += 1 }
                offset += 4
            }
            return count
        }
    }

    /// How many pixels inside `frame` (in points, from the picture's top
    /// left) are drawn dark: text on the light field.
    func dark(in frame: CGRect) -> Int {
        let firstColumn = max(0, Int((frame.minX * scale).rounded(.down)))
        let lastColumn = min(width, Int((frame.maxX * scale).rounded(.up)))
        let firstRow = max(0, Int((frame.minY * scale).rounded(.down)))
        let lastRow = min(height, Int((frame.maxY * scale).rounded(.up)))
        guard firstColumn < lastColumn, firstRow < lastRow else { return 0 }
        var count = 0
        for row in firstRow..<lastRow {
            for column in firstColumn..<lastColumn {
                let offset = (row * width + column) * 4
                let luminance = 0.2126 * Double(bytes[offset])
                    + 0.7152 * Double(bytes[offset + 1])
                    + 0.0722 * Double(bytes[offset + 2])
                if luminance < 128 { count += 1 }
            }
        }
        return count
    }
}

/// What a test drives and reads of the hosted field.
@MainActor
@Observable
final class EyeBox {
    var text: String
    var visibility: AuthPasswordVisibility
    var wantsFocus = false
    var focused: AuthPasswordSlot?

    init(text: String = "", revealed: Set<AuthPasswordSlot> = []) {
        self.text = text
        visibility = AuthPasswordVisibility(revealed: revealed)
    }

    /// What the control does when touched.
    func touchEye(_ slot: AuthPasswordSlot = .password) {
        visibility.toggle(slot)
    }
}

/// The field as a screen composes it: its text, its visibility and its focus
/// owned by the host.
private struct EyeHarness: View {
    @Bindable var box: EyeBox
    let slot: AuthPasswordSlot
    let contentType: UITextContentType
    @FocusState private var focus: AuthPasswordSlot?

    var body: some View {
        AuthPasswordField(
            slot: slot,
            title: slot == .password ? "Senha" : "Confirmar senha",
            text: $box.text,
            visibility: $box.visibility,
            contentType: contentType,
            submitLabel: .next,
            focus: $focus,
            focusValue: slot,
            hint: "",
            identifier: slot == .password ? "auth.password" : "auth.password-confirmation",
            onSubmit: {}
        )
        .onChange(of: box.wantsFocus) { _, wants in
            focus = wants ? slot : nil
        }
        .onChange(of: focus) { _, current in
            box.focused = current
        }
    }
}
