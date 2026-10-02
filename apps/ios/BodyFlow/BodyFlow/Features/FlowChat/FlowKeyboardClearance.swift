import SwiftUI
import UIKit

struct FlowKeyboardScreenFrame {
    private let value: CGRect
    private let screenID: ObjectIdentifier

    init?(frame: CGRect, screenID: ObjectIdentifier?) {
        guard let screenID else { return nil }
        value = frame
        self.screenID = screenID
    }

    func frame(on screenID: ObjectIdentifier) -> CGRect? {
        self.screenID == screenID ? value : nil
    }
}

/// Only the part of a docked keyboard still inside the proposed viewport.
/// UIKit supplies both rectangles in the observer's local coordinate space.
enum FlowKeyboardClearance {
    static func overlap(viewport: CGRect, keyboard: CGRect) -> CGFloat {
        func valid(_ rectangle: CGRect) -> Bool {
            !rectangle.isNull && !rectangle.isInfinite &&
                [rectangle.origin.x, rectangle.origin.y, rectangle.size.width, rectangle.size.height,
                 rectangle.minX, rectangle.maxX, rectangle.minY, rectangle.maxY].allSatisfy(\.isFinite) &&
                rectangle.size.width > 0 && rectangle.size.height > 0
        }
        guard valid(viewport), valid(keyboard),
              keyboard.minX <= viewport.minX, keyboard.maxX >= viewport.maxX,
              keyboard.maxY >= viewport.maxY else { return 0 }
        return min(viewport.height, max(0, viewport.maxY - max(viewport.minY, keyboard.minY)))
    }
}

/// Defers state publication out of UIKit layout and discards superseded samples.
@MainActor
final class FlowKeyboardClearanceDelivery {
    typealias Work = @MainActor @Sendable () -> Void
    private let schedule: (@escaping Work) -> Void
    private let publish: (CGFloat) -> Void
    private var revision: UInt = 0
    private var lastPublished: CGFloat?

    init(schedule: @escaping (@escaping Work) -> Void, publish: @escaping (CGFloat) -> Void) {
        self.schedule = schedule
        self.publish = publish
    }

    func submit(_ value: CGFloat) {
        revision &+= 1
        let sampleRevision = revision
        guard value.isFinite, value >= 0, value != lastPublished else { return }
        schedule { [weak self] in
            guard let self, self.revision == sampleRevision else { return }
            self.lastPublished = value
            self.publish(value)
        }
    }

    func cancelPending() { revision &+= 1 }

    func invalidate() {
        cancelPending()
        lastPublished = nil
    }
}

/// The observer fills the original viewport; padding is applied only to its
/// sibling content, so its measurement cannot oscillate with the correction.
struct FlowKeyboardClearanceObserver: UIViewRepresentable {
    let owner: ObjectIdentifier
    let changed: (CGFloat) -> Void

    func makeUIView(context: Context) -> ObserverView {
        ObserverView(owner: owner, changed: changed)
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.bind(owner: owner, changed: changed)
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) {
        view.invalidate()
    }

    final class ObserverView: UIView {
        private var owner: ObjectIdentifier
        private var changed: ((CGFloat) -> Void)?
        private var endFrameInScreen: FlowKeyboardScreenFrame?
        private lazy var delivery = FlowKeyboardClearanceDelivery(
            schedule: { work in DispatchQueue.main.async { work() } },
            publish: { [weak self] value in
                guard let self, self.window != nil else { return }
                self.changed?(value)
            }
        )

        init(owner: ObjectIdentifier, changed: @escaping (CGFloat) -> Void) {
            self.owner = owner
            self.changed = changed
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            // Software keys can disappear while the Done accessory remains.
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                name: UIResponder.keyboardDidHideNotification, object: nil)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func bind(owner: ObjectIdentifier, changed: @escaping (CGFloat) -> Void) {
            if self.owner != owner {
                delivery.invalidate()
                endFrameInScreen = nil
                self.owner = owner
            }
            self.changed = changed
            setNeedsLayout()
        }

        func invalidate() {
            delivery.invalidate()
            changed = nil
            endFrameInScreen = nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            delivery.invalidate()
            endFrameInScreen = nil
            setNeedsLayout()
        }

        @objc private func keyboardChanged(_ notification: Notification) {
            guard let window, window.isKeyWindow,
                  let screen = notification.object as? UIScreen, screen === window.screen,
                  let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
            endFrameInScreen = FlowKeyboardScreenFrame(
                frame: value.cgRectValue, screenID: ObjectIdentifier(screen)
            )
            delivery.cancelPending()
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window, changed != nil else { return }
            var clearance: CGFloat = 0
            if let frame = endFrameInScreen?.frame(on: ObjectIdentifier(window.screen)) {
                let keyboardInWindow = window.convert(frame, from: window.screen.coordinateSpace)
                // A floating keyboard does not move the whole bottom dock.
                if keyboardInWindow.maxY >= window.bounds.maxY {
                    clearance = FlowKeyboardClearance.overlap(
                        viewport: bounds, keyboard: convert(keyboardInWindow, from: window)
                    )
                }
            } else {
                endFrameInScreen = nil
            }
            delivery.submit(clearance)
        }
    }
}
