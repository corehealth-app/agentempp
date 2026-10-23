import Foundation
import SwiftUI
import UIKit
import Vision
import XCTest

@testable import BodyFlow

@MainActor
final class MealCompositeEditorRenderingTests: XCTestCase {
    func testSameProposalEditorOffersIngredientActionsInBothLanguages() throws {
        let response = try JSONDecoder().decode(RegistrationProposalResponse.self,
            from: MealCompositeRecoveryCharacterizationTests.responseJSON)
        for language in SupportedAppLanguage.allCases {
            let editor = NavigationStack {
                MealProposalEditorView(registration: response.data,
                    initialConsumedAt: Date(timeIntervalSince1970: 1_792_773_000),
                    isSubmitting: false, editedIndex: 1, save: { _ in })
            }.environment(\.locale, language.formattingLocale)
            let host = try CompositeEditorHost(editor, size: .large, height: 667)
            defer { host.detach() }
            _ = host.scrollToBottom()
            let image = host.image()
            let attachment = XCTAttachment(image: image)
            attachment.name = "same-proposal-list-actions-\(language.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let text = normalized(try recognizedText(in: image, language: language))
            let addTitle = language == .portugueseBrazil ? "Adicionar ingrediente" : "Add ingredient"
            XCTAssertTrue(text.contains(normalized(addTitle)), "Same-proposal recovery needs an actionable way to add a separately measured ingredient. OCR: \(text)")
            XCTAssertTrue(text.contains(normalized("macarrão espaguete cozido")), "The list must retain the other food. OCR: \(text)")
        }
    }

    func testSubmittingLocksSaveAndTheNativeFoodFields() throws {
        let response = try JSONDecoder().decode(RegistrationProposalResponse.self,
            from: MealCompositeRecoveryCharacterizationTests.responseJSON)
        let editor = NavigationStack {
            MealProposalEditorView(registration: response.data,
                initialConsumedAt: Date(timeIntervalSince1970: 1_792_773_000),
                isSubmitting: true, editedIndex: 1, save: { _ in })
        }.environment(\.locale, SupportedAppLanguage.portugueseBrazil.formattingLocale)
        let host = try CompositeEditorHost(editor, size: .large)
        defer { host.detach() }
        let nameTitle = RegistrationCopy.string("registration.editor.food", language: .portugueseBrazil)
        let name = try XCTUnwrap(host.nativeFields().first { $0.placeholder == nameTitle })
        XCTAssertFalse(name.isEnabled)
        let saveTitle = RegistrationCopy.string("registration.editor.save", language: .portugueseBrazil)
        let save = try XCTUnwrap(host.probe().first { $0.label == saveTitle && $0.isButton })
        XCTAssertFalse(save.isEnabled)
    }

    func testUnchangedAIProposalNamesTheBlockedFoodAndOffersOneDirectCorrection() throws {
        let response = try JSONDecoder().decode(RegistrationProposalResponse.self,
            from: MealCompositeRecoveryCharacterizationTests.responseJSON)
        for language in SupportedAppLanguage.allCases {
            let view = NavigationStack {
                ScrollView {
                    MealProposalView(proposal: .init(registration: response.data), isSubmitting: false,
                        edit: {}, editItem: { _ in }, confirm: {}, cancel: {})
                        .padding(BodyFlowSpacing.lg)
                }
            }.environment(\.locale, language.formattingLocale)
            let host = try CompositeEditorHost(view, size: .large, height: 667)
            defer { host.detach() }
            XCTAssertTrue(host.isMounted, host.geometryDescription)
            let initialImage = XCTAttachment(image: host.image())
            initialImage.name = "unchanged-proposal-\(language.rawValue)-before-scroll"
            initialImage.lifetime = .keepAlways
            add(initialImage)
            XCTAssertTrue(host.scrollToBottom(), "Exercise the actual scroll before probing the final action. \(host.geometryDescription)")
            let image = host.image()
            let rendered = XCTAttachment(image: image)
            rendered.name = "unchanged-proposal-\(language.rawValue)-final-action"
            rendered.lifetime = .keepAlways
            add(rendered)
            // R8 painted the exact content but this isolated SwiftUI AX
            // collector returned an empty tree. Verify rendered pixels with
            // local Vision OCR instead of treating that tree as UI absence.
            // VoiceOver, tapping and server persistence remain separate QA.
            let text = try recognizedText(in: image, language: language)
            let expected = language == .portugueseBrazil
                ? "Ainda não é possível registrar: falta calcular a nutrição de carne desfiada com molho e milho. Corrija o nome, o preparo ou a quantidade para recalcular. Os outros alimentos serão mantidos."
                : "This meal cannot be recorded yet: nutrition has not been calculated for carne desfiada com molho e milho. Correct the name, preparation or amount to recalculate. Your other foods will be kept."
            XCTAssertTrue(normalized(text).contains(normalized(expected)), "The rendered final action needs the item and an actionable reason. OCR: \(text)")
            XCTAssertFalse(normalized(text).contains(normalized("Peça pro paciente")))
            let fixTitle = language == .portugueseBrazil ? "Corrigir este item" : "Fix this item"
            XCTAssertEqual(normalized(text).components(separatedBy: normalized(fixTitle)).count - 1, 1)
            let confirm = RegistrationCopy.string("registration.proposal.confirm", language: language)
            XCTAssertFalse(normalized(text).split(separator: " ").contains(Substring(normalized(confirm))))
        }
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func recognizedText(in image: UIImage, language: SupportedAppLanguage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        let preferred = language == .portugueseBrazil ? "pt" : "en"
        request.recognitionLanguages = [try XCTUnwrap(supported.first { $0.hasPrefix(preferred) })]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage), options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    func testOpeningRejectedSecondItemShowsNativeEditableFieldsAndEnabledSaveWithoutManualCalories() throws {
        let response = try JSONDecoder().decode(
            RegistrationProposalResponse.self,
            from: MealCompositeRecoveryCharacterizationTests.responseJSON
        )
        for language in SupportedAppLanguage.allCases {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let editor = NavigationStack {
                    MealProposalEditorView(
                        registration: response.data,
                        initialConsumedAt: Date(timeIntervalSince1970: 1_792_773_000),
                        isSubmitting: false,
                        editedIndex: 1,
                        save: { _ in }
                    )
                }
                .environment(\.locale, language.formattingLocale)

                let host = try CompositeEditorHost(editor, size: size)
                defer { host.detach() }
                XCTAssertTrue(host.isMounted, "The navigation host must have UIKit containment and a visible window before probing.")
                let probes = host.probe()
                let fields = host.nativeFields()
                let image = XCTAttachment(image: host.image())
                image.name = "composite-editor-\(language.rawValue)-\(size == .large ? "regular" : "axxxl")"
                image.lifetime = .keepAlways
                add(image)
                // R4 proved these native fields are painted and editable,
                // while this isolated AX collector exposes none of their
                // identifiers. Read the real UIKit controls for render/field
                // metrology; this is not a VoiceOver verification.
                let nameTitle = RegistrationCopy.string("registration.editor.food", language: language)
                let quantityTitle = RegistrationCopy.string("registration.editor.quantity", language: language)
                let kcalTitle = RegistrationCopy.string("registration.editor.user-kcal", language: language)
                let name = try XCTUnwrap(fields.first { $0.placeholder == nameTitle })
                let quantity = try XCTUnwrap(fields.first { $0.placeholder == quantityTitle })
                let kcal = try XCTUnwrap(fields.first { $0.placeholder == kcalTitle })
                for title in [nameTitle, quantityTitle, kcalTitle] {
                    XCTAssertEqual(fields.filter { $0.placeholder == title }.count, 1)
                }
                for field in [name, quantity, kcal] {
                    XCTAssertNotNil(field.window)
                    XCTAssertTrue(field.isEnabled && field.isUserInteractionEnabled)
                    XCTAssertFalse(field.bounds.isEmpty)
                }
                XCTAssertEqual(name.text, "carne desfiada com molho e milho")
                XCTAssertEqual(quantity.text, "180")
                XCTAssertEqual(kcal.text ?? "", "")
                let saveTitle = RegistrationCopy.string("registration.editor.save", language: language)
                let saves = probes.filter { $0.isButton && $0.label == saveTitle }
                XCTAssertEqual(saves.count, 1)
                let save = try XCTUnwrap(saves.first)
                XCTAssertTrue(save.isButton)
                // Announced accessibility state only; this does not tap Save
                // or prove that a server recalculation succeeds.
                XCTAssertTrue(save.isEnabled, "A complete DTO must not require manual calories to save an edit.")
                let viewport = host.screenViewport()
                XCTAssertFalse(viewport.isEmpty)
                let nameFrame = UIAccessibility.convertToScreenCoordinates(name.bounds, in: name)
                XCTAssertFalse(nameFrame.isEmpty)
                XCTAssertTrue(viewport.contains(nameFrame), "The food being corrected must be fully visible on opening.")
                // At Accessibility XXXL the rest can be reached by scrolling;
                // do not require the whole Form to fit a single viewport.
                if size == .large {
                    let quantityFrame = UIAccessibility.convertToScreenCoordinates(quantity.bounds, in: quantity)
                    XCTAssertFalse(quantityFrame.isEmpty)
                    XCTAssertTrue(viewport.contains(quantityFrame))
                }
            }
        }
    }

    func testSaveStateProbeDistinguishesMissingProvenanceFromCompleteDTO() throws {
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(
            with: MealCompositeRecoveryCharacterizationTests.responseJSON) as? [String: Any])
        var data = try XCTUnwrap(envelope["data"] as? [String: Any])
        var proposal = try XCTUnwrap(data["proposal"] as? [String: Any])
        var items = try XCTUnwrap(proposal["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "user_kcal")
        proposal["items"] = items; data["proposal"] = proposal; envelope["data"] = data
        let response = try JSONDecoder().decode(RegistrationProposalResponse.self,
            from: JSONSerialization.data(withJSONObject: envelope))
        let view = NavigationStack {
            MealProposalEditorView(registration: response.data,
                initialConsumedAt: Date(timeIntervalSince1970: 1_792_773_000),
                isSubmitting: false, editedIndex: 1, save: { _ in })
        }.environment(\.locale, SupportedAppLanguage.portugueseBrazil.formattingLocale)
        let host = try CompositeEditorHost(view, size: .large)
        defer { host.detach() }
        let saves = host.probe().filter { $0.isButton && $0.label == "Salvar" }
        XCTAssertEqual(saves.count, 1)
        XCTAssertFalse(try XCTUnwrap(saves.first).isEnabled,
            "The positive Save assertion must not pass just because this probe always reports enabled.")
    }
}

/// A real navigation controller needs containment and appearance callbacks;
/// adding its view under the app's existing hosting view does not supply those.
/// This host owns only its temporary window and always restores the prior one.
@MainActor
private final class CompositeEditorHost {
    private let host: UIViewController
    private let container = UIViewController()
    private let window: UIWindow
    private weak var previousWindow: UIWindow?
    private var detached = false

    init<V: View>(_ view: V, size: DynamicTypeSize, height: CGFloat = 800) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        previousWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: height)
        let controller = UIHostingController(rootView: view
            .environment(\.dynamicTypeSize, size)
            .environment(\.accessibilityEnabled, true))
        controller.traitOverrides.preferredContentSizeCategory = size == .large
            ? .large : .accessibilityExtraExtraExtraLarge
        controller.traitOverrides.userInterfaceStyle = .light
        host = controller
        window.rootViewController = container
        container.view.frame = window.bounds
        container.addChild(controller)
        container.view.addSubview(controller.view)
        controller.view.frame = container.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.didMove(toParent: container)
        window.makeKeyAndVisible()
        settle()
    }

    var isMounted: Bool {
        host.parent === container && host.view.window === window && !window.isHidden
            && host.view.bounds.width.isFinite && host.view.bounds.height.isFinite
            && host.view.bounds.width > 0 && host.view.bounds.height > 0
    }

    var geometryDescription: String {
        var values = ["host=\(host.view.bounds)", "container=\(container.view.bounds)", "window=\(window.bounds)"]
        func collect(_ view: UIView) {
            if let scroll = view as? UIScrollView {
                values.append("scroll bounds=\(scroll.bounds) content=\(scroll.contentSize) inset=\(scroll.adjustedContentInset) offset=\(scroll.contentOffset)")
            }
            view.subviews.forEach(collect)
        }
        collect(host.view)
        return values.joined(separator: "; ")
    }

    private func settle() {
        window.layoutIfNeeded()
        container.view.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        host.view.layoutIfNeeded()
    }

    func screenViewport() -> CGRect {
        settle()
        return UIAccessibility.convertToScreenCoordinates(host.view.bounds, in: host.view)
    }

    func nativeFields() -> [UITextField] {
        settle()
        var fields: [UITextField] = []
        func collect(_ view: UIView) {
            if let field = view as? UITextField { fields.append(field) }
            view.subviews.forEach(collect)
        }
        collect(host.view)
        return fields
    }

    func scrollToBottom() -> Bool {
        settle()
        var scrolls: [UIScrollView] = []
        func collect(_ view: UIView) {
            if let scroll = view as? UIScrollView { scrolls.append(scroll) }
            view.subviews.forEach(collect)
        }
        collect(host.view)
        guard let scroll = scrolls.first(where: { $0.contentSize.height > $0.bounds.height }) else { return false }
        let bottom = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: bottom), animated: false)
        settle()
        return abs(scroll.contentOffset.y - bottom) < 2
    }

    func image() -> UIImage {
        settle()
        return UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
    }

    func probe() -> [PremiumRenderingTestSupport.AccessibilityProbe] {
        UIAccessibility.post(notification: .screenChanged, argument: host.view)
        settle()
        var probes: [PremiumRenderingTestSupport.AccessibilityProbe] = []
        var visited = Set<ObjectIdentifier>()
        func collect(_ object: NSObject, depth: Int = 0) {
            guard depth < 32, visited.insert(ObjectIdentifier(object)).inserted else { return }
            if object.isAccessibilityElement {
                probes.append(.init(label: object.accessibilityLabel ?? "",
                    isButton: object.accessibilityTraits.contains(.button),
                    isEnabled: !object.accessibilityTraits.contains(.notEnabled),
                    frame: object.accessibilityFrame, nativeBounds: (object as? UIView)?.bounds,
                    value: object.accessibilityValue ?? "", hint: object.accessibilityHint ?? "",
                    identifier: (object as? UIAccessibilityIdentification)?.accessibilityIdentifier ?? ""))
            }
            if let elements = object.accessibilityElements {
                for case let element as NSObject in elements { collect(element, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count > 0 && count < 1000 {
                    for index in 0..<count {
                        if let element = object.accessibilityElement(at: index) as? NSObject {
                            collect(element, depth: depth + 1)
                        }
                    }
                }
            }
            if let view = object as? UIView { view.subviews.forEach { collect($0, depth: depth + 1) } }
        }
        collect(host.view)
        return probes
    }

    func detach() {
        guard !detached else { return }
        detached = true
        host.view.endEditing(true)
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        window.isHidden = true
        window.rootViewController = nil
        previousWindow?.makeKey()
    }
}
