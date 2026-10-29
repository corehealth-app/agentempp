import XCTest

/// Real taps/keyboard/navigation using the app's existing local demo service.
/// The service returns a fixed edit response: nutrition and remote persistence
/// are deliberately not claims of this UI test.
final class MealProposalListEditorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNamedWheyMeasureCanBeEditedAndSavedWithoutKnowingGrams() {
        let app = BodyFlowUITestSupport(testCase: self).launch(scenario: .loaded)
        let register = app.performeTabBar.buttons["tab.registrar"]
        XCTAssertTrue(register.waitForExistence(timeout: 5)); register.tap()
        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5)); meal.tap()
        let text = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap()
        let detect = app.buttons["registration.meal.detect"]
        XCTAssertTrue(detect.waitForExistence(timeout: 5)); detect.tap()
        let edit = app.buttons["registration.proposal.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let addButton = app.buttons["registration.proposal.edit.add-ingredient"]
        reveal(addButton, in: app); addButton.tap()
        let name = app.textFields["registration.proposal.edit.food-name"]
        let quantity = app.textFields["registration.proposal.edit.quantity"]
        let save = app.buttons["registration.proposal.edit.save"]
        XCTAssertFalse(save.isEnabled)
        replace(name, with: "1 medida de whey")
        XCTAssertEqual(quantity.value as? String, "1")
        dismissKeyboard(app)
        let equivalence = app.staticTexts["registration.proposal.edit.equivalence"]
        XCTAssertTrue(equivalence.waitForExistence(timeout: 3))
        XCTAssertTrue(equivalence.label.contains("30 g"))
        XCTAssertTrue(save.isEnabled)
        replace(quantity, with: "")
        XCTAssertFalse(save.isEnabled) // no silent refill of an erased quantity
        replace(quantity, with: "0,5")
        dismissKeyboard(app)
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(equivalence.label.contains("15 g"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "new-whey-half-measure-editable-reference"
        attachment.lifetime = .keepAlways
        add(attachment)
        save.tap()
        XCTAssertTrue(app.staticTexts["Substituição completa predefinida"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["registration.proposal.confirmed"].exists)
        // Demo proves gestures/navigation only. BFF tests use the real
        // calculator and writer; connected QA is a separate delivery gate.
    }

    @MainActor
    func testTwoEditsRemoveUndoAndOneSaveStayInTheSameProposal() {
        let app = BodyFlowUITestSupport(testCase: self).launch(scenario: .loaded)
        let register = app.performeTabBar.buttons["tab.registrar"]
        XCTAssertTrue(register.waitForExistence(timeout: 5)); register.tap()
        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5)); meal.tap()
        let text = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap()
        XCTAssertTrue(app.textFields["registration.meal.text"].waitForExistence(timeout: 5))
        let detect = app.buttons["registration.meal.detect"]
        XCTAssertTrue(detect.waitForExistence(timeout: 5)); detect.tap()
        let edit = app.buttons["registration.proposal.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()

        let name = app.textFields["registration.proposal.edit.food-name"]
        let quantity = app.textFields["registration.proposal.edit.quantity"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replace(name, with: "QA primeiro")
        replace(quantity, with: "100")
        dismissKeyboard(app)

        let addButton = app.buttons["registration.proposal.edit.add-ingredient"]
        reveal(addButton, in: app); addButton.tap()
        let emptyName = name.value as? String ?? ""
        XCTAssertTrue(emptyName.isEmpty || emptyName == name.placeholderValue)
        XCTAssertFalse(app.buttons["registration.proposal.edit.save"].isEnabled)
        replace(name, with: "QA segundo")
        replace(quantity, with: "20")
        dismissKeyboard(app)
        let first = selectedFood("QA primeiro", in: app)
        reveal(first, in: app); first.tap()
        XCTAssertEqual(name.value as? String, "QA primeiro")
        XCTAssertEqual(quantity.value as? String, "100")

        let second = selectedFood("QA segundo", in: app)
        reveal(second, in: app); second.tap()
        XCTAssertEqual(name.value as? String, "QA segundo")
        XCTAssertEqual(quantity.value as? String, "20")
        dismissKeyboard(app)
        let remove = app.buttons["registration.proposal.edit.remove-ingredient"]
        reveal(remove, in: app); remove.tap()
        XCTAssertEqual(name.value as? String, "QA primeiro")
        let undo = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label CONTAINS %@", "registration.proposal.edit.undo.", "QA segundo")).firstMatch
        reveal(undo, in: app); undo.tap()
        XCTAssertEqual(name.value as? String, "QA segundo")
        XCTAssertEqual(quantity.value as? String, "20")
        dismissKeyboard(app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "same-proposal-two-edits-and-undo"
        attachment.lifetime = .keepAlways
        add(attachment)

        let save = app.buttons["registration.proposal.edit.save"]
        XCTAssertTrue(save.isEnabled); save.tap()
        // Fixed local response proves navigation after this Save gesture.
        // Model tests independently verify the multi-food request body;
        // this UI test does not count requests or prove remote idempotency.
        XCTAssertTrue(app.staticTexts["Substituição completa predefinida"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["registration.proposal.confirmed"].exists)
    }

    @MainActor
    private func selectedFood(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "registration.proposal.edit.select.", name)).firstMatch
    }

    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap()
        let old = field.value as? String ?? ""
        let placeholder = field.placeholderValue ?? ""
        if old != placeholder { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(text)
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            let done = app.buttons["keyboard.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            XCTAssertEqual(app.buttons.matching(identifier: "keyboard.done").count, 1)
            done.tap()
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "The editor action must be reachable by scrolling")
    }
}
