import SwiftUI
import UIKit

@MainActor
enum PremiumRenderingTestSupport {
    static func image<V: View>(_ view: V, width: CGFloat, dark: Bool,
                              size: DynamicTypeSize) -> UIImage {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, size)
            .frame(width: width))
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            preconditionFailure("Native test render failed")
        }
        return image
    }

    static func fittingSize<V: View>(_ view: V, width: CGFloat, dark: Bool,
                                    size: DynamicTypeSize, locale: Locale) -> CGSize {
        let host = UIHostingController(rootView: view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, size)
            .environment(\.locale, locale))
        configureTraits(host, size: size, dark: dark)
        host.loadViewIfNeeded()
        let measured = host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        host.view.frame = CGRect(origin: .zero, size: measured)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return measured
    }

    struct AccessibilityProbe: CustomStringConvertible {
        let label: String
        let isButton: Bool
        let isEnabled: Bool
        let frame: CGRect
        let nativeBounds: CGRect?
        /// What VoiceOver reads after the label (`accessibilityValue`).
        var value: String = ""
        /// The spoken hint (`accessibilityHint`).
        var hint: String = ""
        /// The element's `accessibilityIdentifier`, when it has one.
        var identifier: String = ""
        var description: String { "\(label): button=\(isButton), frame=\(frame)" }
    }

    static func nativeImage<V: View>(_ view: V, width: CGFloat, dark: Bool,
                                    size: DynamicTypeSize, locale: Locale) -> UIImage {
        let host = UIHostingController(rootView: view
            .ignoresSafeArea()
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, size)
            .environment(\.locale, locale))
        configureTraits(host, size: size, dark: dark)
        host.loadViewIfNeeded()
        let measured = host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        nativeWindow().addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: ceil(measured.height))
        defer { detach(host) }
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        return UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: false)
        }
    }

    static func accessibilityProbe<V: View>(_ view: V, width: CGFloat,
                                           size: DynamicTypeSize = .large) -> [AccessibilityProbe] {
        let host = UIHostingController(rootView: view.frame(width: width)
            .ignoresSafeArea()
            .environment(\.dynamicTypeSize, size)
            .environment(\.accessibilityEnabled, true))
        configureTraits(host, size: size, dark: false)
        nativeWindow().addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        defer { detach(host) }
        host.view.layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: host.view)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        return accessibilityProbes(in: host.view)
    }

    /// Walks the accessibility tree under `root`, as `accessibilityProbe`
    /// always did; shared with the live host below.
    private static func accessibilityProbes(in root: UIView) -> [AccessibilityProbe] {
        var probes: [AccessibilityProbe] = []
        var visited: Set<ObjectIdentifier> = []
        func collect(_ object: NSObject, depth: Int = 0) {
            guard depth < 32, visited.insert(ObjectIdentifier(object)).inserted else { return }
            if object.isAccessibilityElement {
                probes.append(AccessibilityProbe(
                    label: object.accessibilityLabel ?? "",
                    isButton: object.accessibilityTraits.contains(.button),
                    isEnabled: !object.accessibilityTraits.contains(.notEnabled),
                    frame: object.accessibilityFrame,
                    nativeBounds: (object as? UIView)?.bounds,
                    value: object.accessibilityValue ?? "",
                    hint: object.accessibilityHint ?? "",
                    identifier: (object as? UIAccessibilityIdentification)?
                        .accessibilityIdentifier ?? ""
                ))
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
            if let nativeView = object as? UIView {
                nativeView.subviews.forEach { collect($0, depth: depth + 1) }
            }
        }
        collect(root)
        return probes
    }

    /// One view hosted once and probed at several moments, so a test can
    /// follow the SAME live view through the states of its model (a fresh
    /// host per state would not show a block being kept or replaced).
    @MainActor
    final class LiveAccessibilityHost {
        private let host: UIViewController

        fileprivate init(host: UIViewController) { self.host = host }

        /// Lets SwiftUI apply the pending state changes, then reads the tree
        /// with the same recipe `accessibilityProbe` uses.
        func probe() -> [AccessibilityProbe] {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            UIAccessibility.post(notification: .screenChanged, argument: host.view)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            host.view.layoutIfNeeded()
            return PremiumRenderingTestSupport.accessibilityProbes(in: host.view)
        }

        func detach() { host.view.removeFromSuperview() }

        /// Lets SwiftUI apply the pending state changes, without reading
        /// the accessibility tree.
        func settle() {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            host.view.layoutIfNeeded()
        }

        /// The native views of one type that SwiftUI made for the hosted
        /// view, in the order they are found (second update, 2026-10-10:
        /// the traits of a text field, the loop of a loader, the size of
        /// an editable field).
        func nativeViews<Native: UIView>(_ type: Native.Type) -> [Native] {
            settle()
            var found: [Native] = []
            func collect(_ view: UIView) {
                if let native = view as? Native { found.append(native) }
                view.subviews.forEach(collect)
            }
            collect(host.view)
            return found
        }

        /// Takes the keyboard away from whatever a test focused.
        func endEditing() { host.view.endEditing(true) }

        /// What the hosted view draws right now.
        func image() -> UIImage {
            settle()
            return UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
        }
    }

    static func liveAccessibilityHost<V: View>(_ view: V, width: CGFloat,
                                              size: DynamicTypeSize = .large) -> LiveAccessibilityHost {
        let host = UIHostingController(rootView: view.frame(width: width)
            .ignoresSafeArea()
            .environment(\.dynamicTypeSize, size)
            .environment(\.accessibilityEnabled, true))
        configureTraits(host, size: size, dark: false)
        nativeWindow().addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        host.view.layoutIfNeeded()
        return LiveAccessibilityHost(host: host)
    }

    struct FieldMetadata: CustomStringConvertible {
        let placeholder: String?
        let keyboardType: UIKeyboardType
        let contentType: UITextContentType?
        let bounds: CGRect
        let fontSize: CGFloat
        let isEnabled: Bool
        let isSecure: Bool
        let isAccessibilityElement: Bool
        let accessibilityLabel: String?
        let traits: UIAccessibilityTraits
        var description: String { "placeholder=\(placeholder ?? "nil"), bounds=\(bounds), font=\(fontSize)" }
    }

    static func nativeFields<V: View>(_ view: V, width: CGFloat,
                                     size: DynamicTypeSize) -> [FieldMetadata] {
        let host = UIHostingController(rootView: view.frame(width: width)
            .ignoresSafeArea().environment(\.dynamicTypeSize, size))
        configureTraits(host, size: size, dark: false)
        nativeWindow().addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        defer { detach(host) }
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        var fields: [FieldMetadata] = []
        func collect(_ view: UIView) {
            if let field = view as? UITextField {
                fields.append(FieldMetadata(placeholder: field.placeholder,
                    keyboardType: field.keyboardType, contentType: field.textContentType,
                    bounds: field.bounds, fontSize: field.font?.pointSize ?? 0,
                    isEnabled: field.isEnabled, isSecure: field.isSecureTextEntry,
                    isAccessibilityElement: field.isAccessibilityElement,
                    accessibilityLabel: field.accessibilityLabel, traits: field.accessibilityTraits))
            }
            view.subviews.forEach(collect)
        }
        collect(host.view)
        return fields
    }

    private static func configureTraits(_ host: UIViewController, size: DynamicTypeSize, dark: Bool) {
        let category: UIContentSizeCategory
        switch size {
        case .xSmall: category = .extraSmall
        case .small: category = .small
        case .medium: category = .medium
        case .large: category = .large
        case .xLarge: category = .extraLarge
        case .xxLarge: category = .extraExtraLarge
        case .xxxLarge: category = .extraExtraExtraLarge
        case .accessibility1: category = .accessibilityMedium
        case .accessibility2: category = .accessibilityLarge
        case .accessibility3: category = .accessibilityExtraLarge
        case .accessibility4: category = .accessibilityExtraExtraLarge
        case .accessibility5: category = .accessibilityExtraExtraExtraLarge
        @unknown default: preconditionFailure("Unrecognized font category")
        }
        host.traitOverrides.preferredContentSizeCategory = category
        host.traitOverrides.userInterfaceStyle = dark ? .dark : .light
    }

    private static func nativeWindow() -> UIWindow {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            preconditionFailure("Native hosting window required")
        }
        return window
    }

    private static func detach(_ host: UIViewController) {
        host.view.removeFromSuperview()
    }
}
