import UIKit
import XCTest

final class Prompt14AccessibilityUITests: XCTestCase {
    private let firstPublicationID =
        "10000000-0000-4000-8000-000000000001"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRevealGestureBudgetIsSharedAndNeverExceedsEight() {
        var budget = Prompt14RevealGestureBudget(requested: 16)

        XCTAssertEqual(budget.limit, 8)
        for _ in 0..<8 {
            XCTAssertTrue(budget.consume())
        }
        XCTAssertFalse(budget.consume())
        XCTAssertEqual(budget.used, 8)
    }

    func testOversizedInteractiveTargetsCannotUseSemanticRepresentative() {
        XCTAssertFalse(
            Prompt14UITestSupport.allowsSemanticRepresentative(for: .button)
        )
        XCTAssertFalse(
            Prompt14UITestSupport.allowsSemanticRepresentative(for: .link)
        )
        XCTAssertTrue(
            Prompt14UITestSupport.allowsSemanticRepresentative(for: .scrollView)
        )
        XCTAssertTrue(
            Prompt14UITestSupport.allowsSemanticRepresentative(for: .other)
        )
    }

    @MainActor
    func testFiveOriginalTabsRetainIndependentStacks() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        for identifier in [
            "tab.hoje",
            "tab.registrar",
            "tab.plano",
            "tab.progresso",
            "tab.perfil",
        ] {
            let tab = app.performeTabBar.buttons[identifier]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            support.assertMinimumTapTarget(tab)
        }
        assertSingleActiveBrand(in: app)

        support.openLibrary(in: app)
        XCTAssertTrue(
            support.element("screen.library", in: app)
                .waitForExistence(timeout: 5)
        )
        assertBrandHiddenOnPushedDestination(in: app)

        app.performeTabBar.buttons["tab.plano"].tap()
        let planDetail = support.element("plan.detail", in: app)
        support.reveal(planDetail, in: app)
        planDetail.tap()
        XCTAssertTrue(
            support.element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )
        assertBrandHiddenOnPushedDestination(in: app)

        app.performeTabBar.buttons["tab.registrar"].tap()
        XCTAssertTrue(
            support.element("screen.registrar", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)
        app.performeTabBar.buttons["tab.progresso"].tap()
        XCTAssertTrue(
            support.element("screen.progresso", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)
        app.performeTabBar.buttons["tab.perfil"].tap()
        XCTAssertTrue(
            support.element("screen.perfil", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)

        app.performeTabBar.buttons["tab.hoje"].tap()
        XCTAssertTrue(
            support.element("screen.library", in: app)
                .waitForExistence(timeout: 5)
        )
        assertBrandHiddenOnPushedDestination(in: app)
        app.performeTabBar.buttons["tab.plano"].tap()
        XCTAssertTrue(
            support.element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )
        assertBrandHiddenOnPushedDestination(in: app)
        support.captureEvidence(.finalSimulator, of: app)
    }

    @MainActor
    func testVoiceOverSemanticsExternalLinkAndMinimumTargets() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .markdownExternalLink)

        support.openLibrary(in: app)
        let all = support.element("library.selection.all", in: app)
        let saved = support.element("library.selection.saved", in: app)
        let category = support.element("library.category", in: app)
        for control in [all, saved, category] {
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            support.assertMinimumTapTarget(control)
        }

        support.openContentDetail(firstPublicationID, in: app)
        XCTAssertTrue(
            app.staticTexts["CONTEÚDO SINTÉTICO COM REFERÊNCIA"]
                .waitForExistence(timeout: 5)
        )
        let link = app.links["Referência externa"]
        support.reveal(link, in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.debugDescription.contains("Link externo"))
        XCTAssertFalse(app.staticTexts["[Referência externa]"].exists)

        let save = support.element("content-detail.save", in: app)
        support.reveal(save, in: app)
        support.assertMinimumTapTarget(save)
    }

    @MainActor
    func testCategoryDialogExposesTheCurrentSelection() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        support.openLibrary(in: app)
        let category = support.element("library.category", in: app)
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()

        let nutrition = app.buttons["Nutrição"]
        XCTAssertTrue(nutrition.waitForExistence(timeout: 3))
        nutrition.tap()
        XCTAssertTrue(
            category.waitForExistence(timeout: 5)
                && category.label == "Nutrição"
        )

        category.tap()
        let selectedNutrition = app.sheets["Selecionar categoria"]
            .buttons["Nutrição, selecionada"]
        XCTAssertTrue(selectedNutrition.waitForExistence(timeout: 3))
    }

    @MainActor
    func testDarkModeEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        let app = support.launch(scenario: .mascotFocusActive)

        let today = support.element("screen.hoje", in: app)
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertEqual(today.value as? String, "dark")
        let mascot = support.element("today.mascot", in: app)
        support.reveal(mascot, in: app)
        XCTAssertTrue(mascot.isHittable)
        support.captureEvidence(.darkMode, of: app)
    }

    @MainActor
    func testAccessibilityXXXLEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(
            scenario: .loaded,
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )

        support.openLibrary(in: app)
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertBrandHiddenOnPushedDestination(in: app)
        let navigationBar = app.navigationBars["Biblioteca"]
        let tabBar = app.performeTabBar
        let scrollView = app.scrollViews["screen.library"]
        for chrome in [navigationBar, tabBar, scrollView] {
            XCTAssertTrue(chrome.waitForExistence(timeout: 5))
        }
        let description = app.staticTexts[
            "Explore conteúdos educativos publicados para apoiar sua jornada."
        ]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        let selectionAll = support.element("library.selection.all", in: app)
        XCTAssertTrue(selectionAll.waitForExistence(timeout: 5))

        let category = support.element("library.category", in: app)
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(
            category.descendants(matching: .button).count,
            0,
            "The category control must not expose a nested interactive action"
        )
        let categoryLabels = category.descendants(matching: .staticText)
        XCTAssertEqual(
            categoryLabels.count,
            1,
            "The category control must expose one visible text label"
        )
        let categoryLabel = categoryLabels.element(boundBy: 0)
        XCTAssertTrue(
            category.frame.contains(categoryLabel.frame),
            "The visible category label \(categoryLabel.frame) must fit inside "
                + "its control \(category.frame)"
        )
        support.assertMinimumTapTarget(category)
        _ = support.revealFully(
            category,
            in: scrollView,
            within: window,
            below: [navigationBar],
            above: tabBar
        )
        let firstCard = support.element(
            "library.card.\(firstPublicationID)",
            in: app
        )
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        var viewport = support.revealFully(
            [category, firstCard],
            in: scrollView,
            within: window,
            below: [navigationBar],
            above: tabBar
        )
        let evidenceFrame = category.frame.union(firstCard.frame)
        XCTAssertLessThanOrEqual(
            evidenceFrame.height,
            viewport.height,
            "Category and first card union \(evidenceFrame) must fit inside "
                + "the shared viewport \(viewport)"
        )
        XCTAssertTrue(
            category.isHittable && viewport.contains(category.frame),
            "The category must remain fully contained before evidence capture"
        )
        XCTAssertTrue(
            firstCard.isHittable && viewport.contains(firstCard.frame),
            "The first card must be fully contained before evidence capture; "
                + "firstCard.maxY=\(firstCard.frame.maxY) must be <= "
                + "tabBar.minY=\(tabBar.frame.minY)"
        )
        XCTAssertTrue(category.frame.intersection(tabBar.frame).isNull)
        XCTAssertTrue(firstCard.frame.intersection(tabBar.frame).isNull)
        XCTAssertTrue(category.frame.intersection(navigationBar.frame).isNull)
        // On taller devices the shared category/card reveal may leave part of
        // the preceding selection row in the viewport. Its layout must still
        // end before the category instead of overlapping the evidence.
        XCTAssertLessThanOrEqual(
            selectionAll.frame.maxY,
            category.frame.minY,
            "The preceding selection control must not overlap the category"
        )
        XCTAssertLessThanOrEqual(
            description.frame.maxY,
            viewport.minY,
            "Primary copy must be outside the visible scroll viewport when evidence is captured"
        )
        support.captureEvidence(.accessibilityXXXL, of: app)

        viewport = support.revealFully(
            firstCard,
            in: scrollView,
            within: window,
            below: [navigationBar],
            above: tabBar
        )
        XCTAssertTrue(firstCard.isHittable)
        XCTAssertTrue(viewport.contains(firstCard.frame))
        support.assertAccessibilityOrder(
            [
                "NavigationBar,",
                "identifier: 'screen.library'",
                "identifier: 'library.category'",
                "identifier: 'library.card.\(firstPublicationID)'",
                "identifier: 'navigation.tab-bar'",
            ],
            in: app
        )
    }

    /// A live system appearance change (no relaunch, navigation or scroll)
    /// must reach the running app and must not disturb shell state: the
    /// selected tab, the pushed Library destination and its filter survive
    /// both directions, and every tab stays actionable.
    @MainActor
    func testLiveThemeSwitchPreservesShellStackAndLibraryState() {
        let support = Prompt14UITestSupport(testCase: self)
        XCUIDevice.shared.appearance = .light
        defer { XCUIDevice.shared.appearance = .light }
        let app = support.launch(scenario: .loaded)

        let today = support.element("screen.hoje", in: app)
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertEqual(today.value as? String, "light")
        XCUIDevice.shared.appearance = .dark
        assertEventually(today, "value == 'dark'")
        XCUIDevice.shared.appearance = .light
        assertEventually(today, "value == 'light'")

        support.openLibrary(in: app)
        let library = support.element("screen.library", in: app)
        let saved = support.element("library.selection.saved", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        assertEventually(saved, "selected == true")

        let tabIdentifiers = [
            "tab.hoje",
            "tab.registrar",
            "tab.plano",
            "tab.progresso",
            "tab.perfil",
        ]
        for appearance in [XCUIDevice.Appearance.dark, .light] {
            XCUIDevice.shared.appearance = appearance
            XCTAssertTrue(library.waitForExistence(timeout: 5))
            XCTAssertTrue(saved.isSelected)
            XCTAssertTrue(app.performeTabBar.buttons["tab.hoje"].isSelected)
            assertBrandHiddenOnPushedDestination(in: app)
            for identifier in tabIdentifiers {
                let tab = app.performeTabBar.buttons[identifier]
                XCTAssertTrue(tab.isHittable, "\(identifier) after \(appearance)")
                support.assertMinimumTapTarget(tab)
            }
        }
    }

    @MainActor
    private func assertEventually(
        _ element: XCUIElement,
        _ format: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: format),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "\(element.identifier) did not satisfy \(format)",
            file: file,
            line: line
        )
    }

    /// At AXXXL the central action remains reachable while the food value
    /// starts in the initial viewport; there is no repeated root wordmark.
    @MainActor
    func testCentralBrandKeepsContentReachableAtAccessibilityXXXL() {
        let support = Prompt14UITestSupport(testCase: self)
        for language in ["pt-BR", "en"] {
            let app = support.launch(scenario: .loaded, additionalArguments: [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                "-AppleLanguages", "(\(language))",
            ])
            let window = app.windows.firstMatch
            let brand = app.buttons["tab.registrar"]
            let navigationBar = app.navigationBars.firstMatch
            let tabBar = app.performeTabBar
            let remaining = support.element("today.energy.remaining-food", in: app)
            for item in [window, brand, navigationBar, tabBar, remaining] {
                XCTAssertTrue(item.waitForExistence(timeout: 5))
            }
            assertSingleActiveBrand(in: app)
            XCTAssertEqual(brand.label, language == "en" ? "Register" : "Registrar")
            XCTAssertTrue(window.frame.contains(brand.frame))
            XCTAssertTrue(brand.isHittable)
            XCTAssertGreaterThanOrEqual(brand.frame.width, 44)
            XCTAssertGreaterThanOrEqual(brand.frame.height, 44)
            XCTAssertTrue(brand.frame.intersection(navigationBar.frame).isNull)
            XCTAssertGreaterThanOrEqual(brand.frame.minY, navigationBar.frame.maxY)
            XCTAssertLessThan(remaining.frame.minY, tabBar.frame.minY)
            XCTAssertTrue(remaining.isHittable)
            app.terminate()
        }
    }

    /// Navigation scales through XXXL, then keeps its approved compact size;
    /// ordinary content must continue scaling through Accessibility XXXL.
    /// The companion FinalPolishAccessibility tests retain the native LCV
    /// hold/release and cross-tab drag gates; screenshots retain visual proof.
    @MainActor
    func testAuthenticatedBrandLayoutAcrossContentSizes() {
        let support = Prompt14UITestSupport(testCase: self)
        var previousRegularBrandHeight: CGFloat?
        var cappedBrandHeight: CGFloat?
        var cappedBarHeight: CGFloat?
        var previousAccessibilityContentHeight: CGFloat?
        let categories: [UIContentSizeCategory] = [
            .large,
            .extraExtraLarge,
            .extraExtraExtraLarge,
            .accessibilityExtraLarge,
            .accessibilityExtraExtraLarge,
            .accessibilityExtraExtraExtraLarge,
        ]
        let tabIdentifiers = [
            "tab.hoje", "tab.plano", "tab.registrar", "tab.progresso", "tab.perfil",
        ]

        for (index, category) in categories.enumerated() {
            let app = support.launch(
                scenario: .loaded,
                additionalArguments: [
                    "-UIPreferredContentSizeCategoryName", category.rawValue,
                    "-AppleLanguages", "(pt-BR)",
                    "-AppleLocale", "pt_BR",
                ]
            )
            let window = app.windows.element(boundBy: 0)
            let brand = app.buttons["tab.registrar"]
            let navigationBar = app.navigationBars["Hoje"]
            let tabBar = app.performeTabBar
            let screen = support.element("screen.hoje", in: app)
            let remaining = support.element("today.energy.remaining-food", in: app)
            for element in [window, brand, navigationBar, tabBar, screen, remaining] {
                XCTAssertTrue(
                    element.waitForExistence(timeout: 5),
                    "Missing layout element at \(category.rawValue)"
                )
            }

            assertSingleActiveBrand(in: app)
            XCTAssertEqual(brand.label, "Registrar")
            XCTAssertEqual(tabBar.buttons.count, 5)
            XCTAssertLessThanOrEqual(tabBar.frame.height, 96)
            for identifier in tabIdentifiers {
                let control = tabBar.buttons[identifier]
                XCTAssertTrue(control.isHittable, "\(identifier) at \(category.rawValue)")
                support.assertMinimumTapTarget(control)
                XCTAssertTrue(window.frame.contains(control.frame))
                XCTAssertTrue(tabBar.frame.contains(control.frame))
            }
            XCTAssertTrue(brand.frame.intersection(navigationBar.frame).isNull)
            XCTAssertGreaterThanOrEqual(brand.frame.minY, navigationBar.frame.maxY)

            let brandHeight = brand.frame.height
            if index < 3 {
                if let previousRegularBrandHeight {
                    XCTAssertGreaterThan(
                        brandHeight, previousRegularBrandHeight,
                        "Navigation must still grow before and up to XXXL: \(category.rawValue)"
                    )
                }
                previousRegularBrandHeight = brandHeight
                if category == .extraExtraExtraLarge {
                    cappedBrandHeight = brandHeight
                    cappedBarHeight = tabBar.frame.height
                }
            } else {
                guard let cappedBrandHeight, let cappedBarHeight else {
                    XCTFail("The XXXL navigation reference must be measured first")
                    return
                }
                // At most half a point for frame rounding, not another font step.
                XCTAssertEqual(brandHeight, cappedBrandHeight, accuracy: 0.5,
                               "Registrar must keep its XXXL cap at \(category.rawValue)")
                XCTAssertEqual(tabBar.frame.height, cappedBarHeight, accuracy: 0.5,
                               "The whole navigation bar must keep its XXXL cap")
            }

            // This cell has semantic fonts, no fixed height or scale factor.
            // Compare only AX categories, where the layout is already stacked;
            // changing from two columns to one is not a font-size regression.
            support.reveal(remaining, in: app)
            XCTAssertTrue(remaining.isHittable)
            XCTAssertEqual(remaining.value as? String,
                           "731 quilocalorias; exercício excluído")
            XCTAssertTrue(window.frame.contains(remaining.frame))
            XCTAssertGreaterThanOrEqual(remaining.frame.minY, navigationBar.frame.maxY)
            XCTAssertLessThanOrEqual(remaining.frame.maxY, tabBar.frame.minY)
            if index >= 3 {
                let contentHeight = remaining.frame.height
                if let previousAccessibilityContentHeight {
                    XCTAssertGreaterThan(
                        contentHeight, previousAccessibilityContentHeight,
                        "Screen content must keep scaling above the navigation cap: \(category.rawValue)"
                    )
                }
                previousAccessibilityContentHeight = contentHeight
            }
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "navigation-cap-and-content-\(category.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)

            support.reveal(support.element("today.library", in: app), in: app)
            support.openLibrary(in: app)
            XCTAssertTrue(
                support.element("screen.library", in: app)
                    .waitForExistence(timeout: 5)
            )
            assertBrandHiddenOnPushedDestination(in: app)
            app.terminate()
        }
    }

    @MainActor
    func testIncreaseContrastEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .progressCompleteDuplicateBadges)

        support.openProgress(in: app)
        let summary = support.element("progress.summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(summary.label.isEmpty)
        support.captureEvidence(.increaseContrast, of: app)
    }

    @MainActor
    func testDifferentiateWithoutColorEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .differentiateWithoutColor)

        let mascot = support.element("today.mascot", in: app)
        support.reveal(mascot, in: app)
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        XCTAssertTrue(mascot.label.contains("personalidade Equilibrada"))
        XCTAssertTrue(mascot.label.contains("estado Em repouso"))
        support.captureEvidence(.differentiateWithoutColor, of: app)
    }

    @MainActor
    func testReduceMotionEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .reduceMotion)

        let mascot = support.element("today.mascot", in: app)
        support.reveal(mascot, in: app)
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        mascot.tap()
        let refresh = support.element("mascot.refresh", in: app)
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(refresh)
        support.captureEvidence(.reduceMotion, of: app)
    }

    @MainActor
    private func assertSingleActiveBrand(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let brands = app.buttons.matching(identifier: "tab.registrar")
        XCTAssertEqual(app.staticTexts.matching(identifier: "brand.product-name").count, 0, file: file, line: line)
        XCTAssertEqual(brands.count, 1, file: file, line: line)
        XCTAssertTrue(
            brands.element(boundBy: 0).isHittable,
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertBrandHiddenOnPushedDestination(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            app.staticTexts.matching(identifier: "brand.product-name").count,
            0,
            "Pushed destinations own the navigation chrome and must not duplicate the shell wordmark",
            file: file,
            line: line
        )
    }
}
