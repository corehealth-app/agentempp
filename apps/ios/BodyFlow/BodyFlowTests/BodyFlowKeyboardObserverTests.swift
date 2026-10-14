import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class BodyFlowKeyboardObserverTests: XCTestCase {
    func testHideNotificationWithVisibleAccessoryKeepsNavigationHiddenUntilDone() throws {
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first(where: \.isKeyWindow))
        let field = UITextField(frame: CGRect(x: 20, y: 100, width: 100, height: 44))
        window.addSubview(field)
        defer {
            field.resignFirstResponder()
            field.removeFromSuperview()
        }
        guard field.becomeFirstResponder(), field.isFirstResponder else {
            XCTFail("SETUP: a genuinely focused own-window input must own the visible accessory")
            return
        }
        var visible = false
        let observer = BodyFlowKeyboardObserver.ObserverView { visible = $0 }
        window.addSubview(observer)
        defer { observer.removeFromSuperview() }

        func post(_ name: Notification.Name, height: CGFloat) {
            let frame = CGRect(x: window.bounds.minX, y: window.bounds.maxY - height,
                               width: window.bounds.width, height: height)
            let screenFrame = window.convert(frame, to: window.screen.coordinateSpace)
            NotificationCenter.default.post(name: name, object: nil, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: screenFrame)
            ])
        }
        // iOS 27 trace: QWERTY 376pt -> accessory 82pt -> didHide(82pt).
        // Hiding the software keys does not dismiss the input accessory.
        post(UIResponder.keyboardWillChangeFrameNotification, height: 376)
        XCTAssertTrue(visible)
        post(UIResponder.keyboardWillChangeFrameNotification, height: 82)
        XCTAssertTrue(visible)
        post(UIResponder.keyboardDidHideNotification, height: 82)
        XCTAssertTrue(visible, "A visible Done accessory must not reintroduce the tab bar")

        guard field.resignFirstResponder(), !field.isFirstResponder else {
            XCTFail("SETUP: Done must release the actual own-window input")
            return
        }
        // Done actually dismisses the accessory; navigation must return.
        post(UIResponder.keyboardWillChangeFrameNotification, height: 0)
        XCTAssertFalse(visible)
        post(UIResponder.keyboardDidHideNotification, height: 0)
        XCTAssertFalse(visible)
    }

    func testDoneWithoutOwnResponderClearsResidualAccessory82OnDidHide() throws {
        let window = try ownKeyWindow()
        let field = UITextField(frame: CGRect(x: 20, y: 100, width: 100, height: 44))
        var visible = false
        let observer = BodyFlowKeyboardObserver.ObserverView { visible = $0 }
        window.addSubview(field)
        window.addSubview(observer)
        defer {
            field.resignFirstResponder()
            observer.removeFromSuperview()
            field.removeFromSuperview()
        }
        guard field.becomeFirstResponder(), field.isFirstResponder else {
            XCTFail("SETUP: actual own-window text field must acquire first responder")
            return
        }
        postKeyboard(UIResponder.keyboardWillChangeFrameNotification, height: 383, window: window)
        XCTAssertTrue(visible)
        postKeyboard(UIResponder.keyboardWillChangeFrameNotification, height: 82, window: window)
        XCTAssertTrue(visible)
        postKeyboard(UIResponder.keyboardDidHideNotification, height: 82, window: window)
        XCTAssertTrue(visible, "Hiding software keys with a focused accessory preserves occupied space")

        guard field.resignFirstResponder(), !field.isFirstResponder else {
            XCTFail("SETUP: actual own-window text field must release first responder")
            return
        }
        // The actual I2 trace supplies residual 82, not a terminal zero frame,
        // after Done has removed the field's focus. Observe this post directly;
        // do not await another UIKit hide event to make the assertion pass.
        postKeyboard(UIResponder.keyboardDidHideNotification, height: 82, window: window)
        XCTAssertFalse(visible, "Residual accessory frame must not latch navigation hidden after Done")
    }

    func testWillChangeFrameWithoutOwnResponderDoesNotPretendDismissal() throws {
        let window = try ownKeyWindow()
        let field = UITextField(frame: CGRect(x: 20, y: 100, width: 100, height: 44))
        var visible = false
        let observer = BodyFlowKeyboardObserver.ObserverView { visible = $0 }
        window.addSubview(field)
        window.addSubview(observer)
        defer {
            field.resignFirstResponder()
            observer.removeFromSuperview()
            field.removeFromSuperview()
        }
        guard field.becomeFirstResponder(), field.isFirstResponder,
              field.resignFirstResponder(), !field.isFirstResponder else {
            XCTFail("SETUP: actual own-window responder must acquire then release focus")
            return
        }
        // A will-change event is not a completed hide. Keep its positive frame
        // even while the new responder is between focus assignments.
        postKeyboard(UIResponder.keyboardWillChangeFrameNotification, height: 82, window: window)
        XCTAssertTrue(visible)
    }

    func testOwnControllerResponderKeepsAccessory82OccupiedOnDidHide() throws {
        let originalWindow = try ownKeyWindow()
        let scene = try XCTUnwrap(originalWindow.windowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = originalWindow.frame
        let owner = AccessoryController()
        window.rootViewController = owner
        window.makeKeyAndVisible()
        var visible = false
        let observer = BodyFlowKeyboardObserver.ObserverView { visible = $0 }
        window.addSubview(observer)
        defer {
            owner.resignFirstResponder()
            observer.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
            originalWindow.makeKey()
        }
        guard window.isKeyWindow, owner.view.window === window, owner.view.next === owner,
              owner.becomeFirstResponder(), owner.isFirstResponder else {
            XCTFail("SETUP: controller owning a view in our window must acquire first responder")
            return
        }
        XCTAssertFalse(owner.view.isFirstResponder, "Controller ownership is distinct from UIView focus")
        postKeyboard(UIResponder.keyboardDidHideNotification, height: 82, window: window)
        XCTAssertTrue(visible, "An own-window controller can keep an accessory active")
    }

    private final class AccessoryController: UIViewController {
        override var canBecomeFirstResponder: Bool { true }
    }

    private func ownKeyWindow() throws -> UIWindow {
        try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first(where: \.isKeyWindow))
    }

    private func postKeyboard(_ name: Notification.Name, height: CGFloat, window: UIWindow) {
        let frame = CGRect(x: window.bounds.minX, y: window.bounds.maxY - height,
                           width: window.bounds.width, height: height)
        NotificationCenter.default.post(name: name, object: nil, userInfo: [
            UIResponder.keyboardFrameEndUserInfoKey:
                NSValue(cgRect: window.convert(frame, to: window.screen.coordinateSpace))
        ])
    }
}
