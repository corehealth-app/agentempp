import XCTest

extension XCUIApplication {
    /// The custom SwiftUI bar exposes an identified `Other` container.
    /// Its UIKit interaction overlay owns the accessible navigation actions.
    /// Its five real buttons keep the same IDs, labels and selected traits.
    var performeTabBar: XCUIElement {
        otherElements["navigation.tab-bar"].firstMatch
    }
}
