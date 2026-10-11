import SwiftUI
import UIKit

/// Reads a hosted sign-up view the way VoiceOver and a UI test do: every
/// accessibility node with its identifier, label, hint, traits and frame.
///
/// `PremiumRenderingTestSupport.accessibilityProbe` reads the identifier
/// through `UIAccessibilityIdentification`, which SwiftUI's nodes do not
/// always adopt; here it is asked by selector (as
/// `RealAccountSampleDataTests.accessibilityTree` does), and the node keeps
/// the identifier TOGETHER with its label and frame.
///
/// What it cannot read: the content of a SwiftUI `ScrollView`. Measured on
/// 2026-10-11 with this walk and with the two older ones — a step drawn by
/// itself reads whole, the same step inside a `ScrollView` reads as zero
/// nodes, with or without a `NavigationStack`, as a bare view or at the root
/// of its own window. So a step is hosted by itself, and of the sign-up
/// container the walk reads exactly what sits OUTSIDE the scrolling column
/// (the column itself is read by the UI tests and, as geometry, through
/// `Host.scrollViews()`).
@MainActor
enum SignUpRenderingProbe {
    struct Node: CustomStringConvertible {
        let identifier: String
        let isElement: Bool
        let label: String
        let hint: String
        let isButton: Bool
        let isSelected: Bool
        let isEnabled: Bool
        let frame: CGRect

        var description: String {
            let traits = [isButton ? "button" : nil, isSelected ? "selected" : nil, isEnabled ? nil : "disabled"]
                .compactMap { $0 }.joined(separator: ",")
            let place = "(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))"
            return "«\(label)»[\(identifier)]{\(traits)}\(place)"
        }
    }

    /// One hosted view that a test can read more than once (after a model
    /// change, after scrolling).
    @MainActor
    final class Host {
        private let controller: UIViewController
        let width: CGFloat

        fileprivate init(controller: UIViewController, width: CGFloat) {
            self.controller = controller
            self.width = width
        }

        func settle() {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            controller.view.layoutIfNeeded()
        }

        func nodes() -> [Node] {
            settle()
            UIAccessibility.post(notification: .screenChanged, argument: controller.view)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            return SignUpRenderingProbe.nodes(in: controller.view)
        }

        /// The scroll views SwiftUI made for the hosted view.
        func scrollViews() -> [UIScrollView] {
            settle()
            var found: [UIScrollView] = []
            func collect(_ view: UIView) {
                if let scroll = view as? UIScrollView { found.append(scroll) }
                view.subviews.forEach(collect)
            }
            collect(controller.view)
            return found
        }

        func detach() { controller.view.removeFromSuperview() }
    }

    static func host<V: View>(
        _ view: V,
        width: CGFloat,
        height: CGFloat = 800,
        size: DynamicTypeSize = .large,
        dark: Bool = false
    ) -> Host {
        let controller = UIHostingController(rootView: view.frame(width: width)
            .ignoresSafeArea()
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.accessibilityEnabled, true))
        controller.traitOverrides.preferredContentSizeCategory = category(for: size)
        controller.traitOverrides.userInterfaceStyle = dark ? .dark : .light
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            preconditionFailure("Native hosting window required")
        }
        window.addSubview(controller.view)
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        controller.view.layoutIfNeeded()
        return Host(controller: controller, width: width)
    }

    /// Hosts, reads once and detaches.
    static func nodes<V: View>(
        _ view: V,
        width: CGFloat,
        height: CGFloat = 800,
        size: DynamicTypeSize = .large,
        dark: Bool = false
    ) -> [Node] {
        let host = host(view, width: width, height: height, size: size, dark: dark)
        defer { host.detach() }
        return host.nodes()
    }

    fileprivate static func nodes(in root: UIView) -> [Node] {
        var nodes: [Node] = []
        var visited: Set<ObjectIdentifier> = []
        let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
        func collect(_ object: NSObject, depth: Int = 0) {
            guard depth < 48, visited.insert(ObjectIdentifier(object)).inserted else { return }
            var identifier = ""
            if object.responds(to: identifierSelector),
               let value = object.perform(identifierSelector)?.takeUnretainedValue() as? String {
                identifier = value
            }
            if object.isAccessibilityElement || !identifier.isEmpty {
                let traits = object.accessibilityTraits
                nodes.append(Node(
                    identifier: identifier,
                    isElement: object.isAccessibilityElement,
                    label: object.accessibilityLabel ?? "",
                    hint: object.accessibilityHint ?? "",
                    isButton: traits.contains(.button),
                    isSelected: traits.contains(.selected),
                    isEnabled: !traits.contains(.notEnabled),
                    frame: object.accessibilityFrame
                ))
            }
            if let elements = object.accessibilityElements {
                for case let element as NSObject in elements { collect(element, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count > 0 && count < 2_000 {
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
        return nodes
    }

    private static func category(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: preconditionFailure("Unrecognized font category")
        }
    }
}
