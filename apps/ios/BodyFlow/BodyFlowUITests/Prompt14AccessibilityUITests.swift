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
            let tab = app.tabBars.buttons[identifier]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            support.assertMinimumTapTarget(tab)
        }
        assertSingleActiveBrand(in: app)

        support.openLibrary(in: app)
        XCTAssertTrue(
            support.element("screen.library", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)

        app.tabBars.buttons["tab.plano"].tap()
        let planDetail = support.element("plan.detail", in: app)
        support.reveal(planDetail, in: app)
        planDetail.tap()
        XCTAssertTrue(
            support.element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)

        app.tabBars.buttons["tab.registrar"].tap()
        XCTAssertTrue(
            support.element("screen.registrar", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)
        app.tabBars.buttons["tab.progresso"].tap()
        XCTAssertTrue(
            support.element("screen.progresso", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)
        app.tabBars.buttons["tab.perfil"].tap()
        XCTAssertTrue(
            support.element("screen.perfil", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)

        app.tabBars.buttons["tab.hoje"].tap()
        XCTAssertTrue(
            support.element("screen.library", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)
        app.tabBars.buttons["tab.plano"].tap()
        XCTAssertTrue(
            support.element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )
        assertSingleActiveBrand(in: app)
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
        let brands = app.staticTexts.matching(
            identifier: "brand.product-name"
        )
        XCTAssertEqual(
            brands.count,
            1,
            "Only the active authenticated tab may expose the BodyFlow brand"
        )
        let brand = brands.element(boundBy: 0)
        let navigationBar = app.navigationBars["Biblioteca"]
        let tabBar = app.tabBars.element(boundBy: 0)
        let scrollView = app.scrollViews["screen.library"]
        for chrome in [brand, navigationBar, tabBar, scrollView] {
            XCTAssertTrue(chrome.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(
            brand.isHittable,
            "The reserved BodyFlow brand must remain visually exposed"
        )
        XCTAssertTrue(
            brand.frame.intersection(navigationBar.frame).isNull,
            "The brand must reserve real space above the Library navigation bar"
        )
        XCTAssertGreaterThanOrEqual(
            navigationBar.frame.minY,
            brand.frame.maxY,
            "The Library navigation bar must start below the brand"
        )
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
        var viewport = support.revealFully(
            category,
            in: scrollView,
            within: window,
            below: [brand, navigationBar],
            above: tabBar,
            clearingUpperChromeFor: selectionAll
        )
        XCTAssertTrue(category.isHittable)
        XCTAssertTrue(viewport.contains(category.frame))
        XCTAssertTrue(category.frame.intersection(brand.frame).isNull)
        XCTAssertTrue(category.frame.intersection(navigationBar.frame).isNull)
        XCTAssertLessThanOrEqual(
            selectionAll.frame.maxY,
            viewport.minY,
            "The preceding selection control must be fully outside the visible viewport"
        )
        XCTAssertLessThanOrEqual(
            description.frame.maxY,
            navigationBar.frame.minY,
            "Primary copy must be outside the visible navigation viewport when evidence is captured"
        )
        XCTAssertTrue(
            description.frame.intersection(navigationBar.frame).isNull
        )
        support.captureEvidence(.accessibilityXXXL, of: app)

        let firstCard = support.element(
            "library.card.\(firstPublicationID)",
            in: app
        )
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        viewport = support.revealFully(
            firstCard,
            in: scrollView,
            within: window,
            below: [brand, navigationBar],
            above: tabBar
        )
        XCTAssertTrue(firstCard.isHittable)
        XCTAssertTrue(viewport.contains(firstCard.frame))
        support.assertAccessibilityOrder(
            [
                "identifier: 'brand.product-name'",
                "NavigationBar,",
                "identifier: 'screen.library'",
                "identifier: 'library.category'",
                "identifier: 'library.card.\(firstPublicationID)'",
                "TabBar,",
            ],
            in: app
        )
    }

    @MainActor
    func testAuthenticatedBrandLayoutAcrossContentSizes() {
        let support = Prompt14UITestSupport(testCase: self)
        var previousBrandHeight: CGFloat?

        for contentSizeCategory in [
            "UICTContentSizeCategoryLarge",
            "UICTContentSizeCategoryAccessibilityXL",
            "UICTContentSizeCategoryAccessibilityXXL",
        ] {
            let app = support.launch(
                scenario: .loaded,
                additionalArguments: [
                    "-UIPreferredContentSizeCategoryName",
                    contentSizeCategory,
                ]
            )
            support.openLibrary(in: app)

            let window = app.windows.element(boundBy: 0)
            let brand = app.staticTexts["brand.product-name"]
            let navigationBar = app.navigationBars["Biblioteca"]
            let tabBar = app.tabBars.element(boundBy: 0)
            let scrollView = app.scrollViews["screen.library"]
            let category = support.element("library.category", in: app)
            for element in [
                window,
                brand,
                navigationBar,
                tabBar,
                category,
            ] {
                XCTAssertTrue(
                    element.waitForExistence(timeout: 5),
                    "Missing layout element at \(contentSizeCategory)"
                )
            }

            assertSingleActiveBrand(in: app)
            XCTAssertTrue(brand.isHittable)
            if let previousBrandHeight {
                XCTAssertGreaterThan(
                    brand.frame.height,
                    previousBrandHeight,
                    "The requested content size must increase brand height at "
                        + contentSizeCategory
                )
            }
            previousBrandHeight = brand.frame.height
            XCTAssertTrue(
                brand.frame.intersection(navigationBar.frame).isNull
            )
            XCTAssertGreaterThanOrEqual(
                navigationBar.frame.minY,
                brand.frame.maxY
            )
            XCTAssertEqual(
                category.descendants(matching: .button).count,
                0
            )
            let categoryLabels = category.descendants(matching: .staticText)
            XCTAssertEqual(categoryLabels.count, 1)
            XCTAssertTrue(
                category.frame.contains(
                    categoryLabels.element(boundBy: 0).frame
                )
            )
            let viewport: CGRect
            if scrollView.exists {
                viewport = support.revealFully(
                    category,
                    in: scrollView,
                    within: window,
                    below: [brand, navigationBar],
                    above: tabBar
                )
            } else {
                viewport = support.usableViewport(
                    within: window,
                    below: [brand, navigationBar],
                    above: tabBar
                )
            }
            XCTAssertTrue(category.isHittable)
            XCTAssertTrue(viewport.contains(category.frame))
            XCTAssertTrue(category.frame.intersection(brand.frame).isNull)
            XCTAssertTrue(
                category.frame.intersection(navigationBar.frame).isNull
            )
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
        let brands = app.staticTexts.matching(
            identifier: "brand.product-name"
        )
        XCTAssertEqual(brands.count, 1, file: file, line: line)
        XCTAssertTrue(
            brands.element(boundBy: 0).isHittable,
            file: file,
            line: line
        )
    }
}
