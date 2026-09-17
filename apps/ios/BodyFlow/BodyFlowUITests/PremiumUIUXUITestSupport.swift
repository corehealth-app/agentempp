import XCTest

@MainActor
struct PremiumUIUXUITestSupport {
    let testCase: XCTestCase

    func launch(arguments: [String], language: String, dark: Bool,
                category: String = "UICTContentSizeCategoryL") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + [
            "-AppleLanguages", "(\(language))", "-AppleLocale",
            language == "pt-BR" ? "pt_BR" : "en_US",
            "-AppleInterfaceStyle", dark ? "Dark" : "Light",
            "-UIPreferredContentSizeCategoryName", category,
        ]
        app.launch()
        return app
    }

    func element(_ id: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func assertTarget(_ element: XCUIElement) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }

    // Future consumers must capture only empty/synthetic fields, never credentials.
    func capture(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        testCase.add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-hierarchy"
        tree.lifetime = .keepAlways
        testCase.add(tree)
    }
}
