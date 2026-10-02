import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class BodyFlowKeyboardObserverTests: XCTestCase {
    func testHideNotificationWithVisibleAccessoryKeepsNavigationHiddenUntilDone() throws {
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first(where: \.isKeyWindow))
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

        // Done actually dismisses the accessory; navigation must return.
        post(UIResponder.keyboardWillChangeFrameNotification, height: 0)
        XCTAssertFalse(visible)
        post(UIResponder.keyboardDidHideNotification, height: 0)
        XCTAssertFalse(visible)
    }
}
