import XCTest

/// Native VoiceOver coverage, available when running on iOS 27 or later.
/// No product hook is used to move VoiceOver. Native focus, order and speech
/// are covered here. Activation is a separate manual gate: calibration on an
/// ordinary SwiftUI button showed XCTest doubleTap activating its coordinate
/// target instead of the VoiceOver-focused element. See the implementation
/// handoff for the preserved failed calibration and its independent review.
final class PerformeVoiceOverNavigationUITests: XCTestCase {
    private struct Destination: Sendable {
        let id: String
        let label: String
        let screen: String
    }

    private static let destinations: [Destination] = [
        .init(id: "tab.hoje", label: "Today", screen: "screen.hoje"),
        .init(id: "tab.plano", label: "Plan", screen: "screen.plano"),
        .init(id: "tab.registrar", label: "Register", screen: "screen.registrar"),
        .init(id: "tab.progresso", label: "Progress", screen: "screen.progresso"),
        .init(id: "tab.perfil", label: "Profile", screen: "screen.perfil"),
    ]

    private enum ProbeFailure: Error {
        case invalidPrecondition(String)
        case focusNotReached(String)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testVoiceOverSpeechParserRecognizesExactIOS27Transcript() {
        // The app uses English labels while the service announces roles in
        // Portuguese. This is the complete five-button excerpt from the RED.
        let transcript = [
            "selecionado Today Botão", "Plan Botão", "Register Botão",
            "Progress Botão", "Profile Botão",
        ]
        for (index, speech) in transcript.enumerated() {
            XCTAssertTrue(isButtonSpeech(speech, for: Self.destinations[index]), speech)
            XCTAssertEqual(hasSelectedAnnouncement(speech), index == 0, speech)
        }
    }

    func testVoiceOverSpeechParserRequiresExactTabAndNativeButtonRole() {
        let plan = Self.destinations[1]
        for speech in ["Plan, Button", "Selected; Plan; Button", "Plan, selected, Button", "Plan\nButton\nselected"] {
            XCTAssertTrue(isButtonSpeech(speech, for: plan), speech)
        }
        for speech in [
            "View Plan Botão", "View Plan, Button", "Plan details Button",
            "Planning Button", "Plan Título", "Plan", "Button", "Plan Button Button",
        ] {
            XCTAssertFalse(isButtonSpeech(speech, for: plan), speech)
        }
    }

    func testVoiceOverSpeechParserDoesNotTreatNegationAsSelected() {
        let plan = Self.destinations[1]
        for speech in [
            "Not selected Plan Button", "Plan, Button, not selected",
            "não selecionado Plan Botão", "nao selecionada Plan Botão",
        ] {
            XCTAssertTrue(isButtonSpeech(speech, for: plan), speech)
            XCTAssertFalse(hasSelectedAnnouncement(speech), speech)
        }
    }

    @MainActor
    func testVoiceOverReadsFiveTabsInOrderAndPreservesSelectionOnIOS27() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("XCUIVoiceOverService is available on iOS 27 or later; the dedicated iOS 27 focus gate requires one passed native test and zero skips")
        }
        try withVoiceOver { app, voiceOver in
            try self.assertVoiceOverNavigation(app: app, voiceOver: voiceOver)
        }
    }

    @MainActor
    func testBlockMetricsRemainCompleteAndLocalized() throws {
        let cases: [(language: String, locale: String, statements: [String])] = [
            ("en-US", "en_US", [
                "Target 7 700 kcal", "Current 2 500 kcal", "Block percentage 32%",
                "Completed blocks 1", "Total credited 10 200 kcal", "Available",
            ]),
            ("pt-BR", "pt_BR", [
                "Meta 7 700 kcal", "Atual 2 500 kcal", "Percentual do bloco 32%",
                "Blocos concluídos 1", "Total creditado 10 200 kcal", "Disponível",
            ]),
        ]
        let app = XCUIApplication()
        defer { app.terminate() }
        for fixture in cases {
            app.launchArguments = [
                "--ui-testing", "--ui-testing-prompt13-loaded",
                "--ui-testing-block-currentRecomposition",
                "-AppleLanguages", "(\(fixture.language))", "-AppleLocale", fixture.locale,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            ]
            app.launch()
            let metrics = app.descendants(matching: .any)
                .matching(identifier: "today.block.metrics")
            try require(metrics.firstMatch.waitForExistence(timeout: 8),
                        "The block must expose its complete passive metrics as one reading group")
            try require(metrics.count == 1, "Block metrics must not be duplicated")
            let label = metrics.firstMatch.label
            attach("block-metrics-\(fixture.language)", label)
            let words: (String) -> String = { value in
                value.lowercased().split {
                    !$0.isLetter && !$0.isNumber && $0 != "%" && $0 != "-" && $0 != "−"
                }
                    .joined(separator: " ")
            }
            try require(words(label) == words(fixture.statements.joined(separator: " ")),
                        "Block metrics must preserve every exact value and status in \(fixture.language); label=\(label)")
            app.terminate()
        }
    }

    @MainActor
    func testVoiceOverReadsFiveTabsInRichRecompositionAndPreservesSelectionOnIOS27() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("XCUIVoiceOverService is available on iOS 27 or later; the dedicated iOS 27 focus gate requires one passed native test and zero skips")
        }
        try withVoiceOver(launchArguments: ["--ui-testing-block-currentRecomposition"]) { app, voiceOver in
            // Prove this is the richer tree from the historical failure, not
            // the legacy fixture that now hides the recomposition block.
            try self.require(app.descendants(matching: .any).matching(identifier: "today.block").firstMatch.exists,
                             "The recomposition fixture must expose the 7,700 block")
            try self.assertVoiceOverNavigation(app: app, voiceOver: voiceOver)
        }
    }

    @available(iOS 27.0, *)
    @MainActor
    private func assertVoiceOverNavigation(app: XCUIApplication, voiceOver: XCUIVoiceOverService) throws {
        let today = Self.destinations[0]
        try self.assertNavigation(app, selected: today)
        let first = try self.seekButton(today, voiceOver: voiceOver)
        try self.require(self.hasSelectedAnnouncement(first),
                         "VoiceOver must announce the selected Today button")

        // Once the first button is reached, no unexpected nodes may be
        // filtered out: the next four focus moves must be these buttons.
        for destination in Self.destinations.dropFirst() {
            let speech = try voiceOver.moveForward().utterance
            self.record("forward-\(destination.id)", speech: speech, app: app)
            try self.require(self.isButtonSpeech(speech, for: destination),
                             "Unexpected next VoiceOver node before \(destination.id): \(speech)")
            try self.assertNavigation(app, selected: today)
        }
        for destination in Self.destinations.dropLast().reversed() {
            let speech = try voiceOver.moveBackward().utterance
            self.record("backward-\(destination.id)", speech: speech, app: app)
            try self.require(self.isButtonSpeech(speech, for: destination),
                             "Unexpected previous VoiceOver node before \(destination.id): \(speech)")
            try self.assertNavigation(app, selected: today)
        }
    }

    @available(iOS 27.0, *)
    @MainActor
    private func withVoiceOver(
        launchArguments: [String] = [],
        _ operation: (XCUIApplication, XCUIVoiceOverService) throws -> Void
    ) throws {
        let device = XCUIDevice.shared
        let voiceOver = device.voiceOverService
        let originalEnabled = voiceOver.isEnabled
        let originalAppearance = device.appearance

        // Register restoration before enabling or launching. A failed cleanup
        // fails the test; a caller must stop subsequent runs on this destination.
        addTeardownBlock {
            await MainActor.run {
                var restorationError: Error?
                do {
                    if originalEnabled { try voiceOver.enable() }
                    else { try voiceOver.disable() }
                } catch {
                    restorationError = error
                }
                // Attempt both restorations before recording any assertion,
                // because continueAfterFailure is false for this test case.
                device.appearance = originalAppearance
                if let restorationError {
                    XCTFail("VoiceOver restoration failed: \(restorationError)")
                }
                XCTAssertEqual(voiceOver.isEnabled, originalEnabled,
                               "VoiceOver original state was not restored")
                XCTAssertEqual(device.appearance, originalAppearance)
            }
        }

        let app = XCUIApplication()
        addTeardownBlock {
            await MainActor.run { app.terminate() }
        }
        device.appearance = .light
        app.launchArguments = [
            "--ui-testing", "--ui-testing-prompt13-loaded",
            "-AppleLanguages", "(en-US)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launchArguments += launchArguments
        app.launch()
        try require(screen(Self.destinations[0], in: app).waitForExistence(timeout: 8),
                    "The local Today fixture must load")

        // A service speech/navigation call requires enable() on this service,
        // even when the device reports that VoiceOver was already enabled.
        try voiceOver.enable()
        try require(voiceOver.isEnabled, "VoiceOver did not enable")
        record("voiceover-enabled", speech: "originalEnabled=\(originalEnabled)", app: app)
        do {
            try operation(app, voiceOver)
        } catch {
            record("voiceover-failure", speech: String(describing: error), app: app)
            throw error
        }
    }

    @available(iOS 27.0, *)
    @MainActor
    private func seekButton(_ destination: Destination, voiceOver: XCUIVoiceOverService) throws -> String {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        var speech = try voiceOver.currentSpeech().utterance
        let targetIndex = Self.destinations.firstIndex { $0.id == destination.id }!
        let focusedIndex = Self.destinations.firstIndex { isButtonSpeech(speech, for: $0) }
        // VoiceOver does not promise wraparound. When already on a known
        // navigation button, move toward the target in the approved order.
        // This explicitly covers Profile -> Today at the end of the journey.
        let backward = focusedIndex.map { $0 > targetIndex } ?? false
        var transcript = ["direction=\(backward ? "backward" : "forward")", speech]
        for step in 0...80 {
            // Calls are synchronous; reject success returned after the budget.
            // The XCTest runner still needs its external execution timeout.
            if clock.now >= deadline { break }
            if isButtonSpeech(speech, for: destination) {
                attach("seek-\(destination.id)", transcript.joined(separator: "\n"))
                return speech
            }
            if step == 80 { break }
            if backward { speech = try voiceOver.moveBackward().utterance }
            else { speech = try voiceOver.moveForward().utterance }
            transcript.append(speech)
        }
        attach("unreachable-\(destination.id)", transcript.joined(separator: "\n"))
        XCTFail("VoiceOver did not reach button \(destination.label) within the bounded search")
        throw ProbeFailure.focusNotReached(destination.id)
    }

    @MainActor
    private func assertNavigation(_ app: XCUIApplication, selected: Destination) throws {
        let navigation = bar(in: app)
        try require(navigation.exists && navigation.buttons.count == 5,
                    "Navigation must expose exactly five real buttons")
        let window = app.windows.firstMatch.frame
        for destination in Self.destinations {
            let matches = navigation.buttons.matching(identifier: destination.id)
            try require(matches.count == 1, "Navigation ID must be unique: \(destination.id)")
            let button = matches.firstMatch
            try require(button.label == destination.label, "Unexpected label for \(destination.id)")
            try require(button.frame.width >= 44 && button.frame.height >= 44,
                        "Navigation target must be at least 44 pt")
            try require(window.contains(button.frame), "Navigation target must be fully visible")
            try require(button.isSelected == (destination.id == selected.id),
                        "Incorrect selection for \(destination.id); expected \(selected.id)")
        }
    }

    @MainActor
    private func bar(in app: XCUIApplication) -> XCUIElement {
        app.otherElements["navigation.tab-bar"].firstMatch
    }

    @MainActor
    private func screen(_ destination: Destination, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: destination.screen).firstMatch
    }

    private func isButtonSpeech(_ utterance: String, for destination: Destination) -> Bool {
        // Native speech may separate label/status/role only with spaces, even
        // with English app labels and Portuguese service role words. Remove
        // only recognized status words; the remaining label must match fully.
        let words = utterance.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let selectionWords = ["selected", "selecionado", "selecionada"]
        var labelAndRole: [String] = []
        for index in words.indices {
            if selectionWords.contains(words[index]) { continue }
            if ["not", "não", "nao"].contains(words[index]),
               index + 1 < words.count, selectionWords.contains(words[index + 1]) { continue }
            labelAndRole.append(words[index])
        }
        guard let role = labelAndRole.popLast(), ["button", "botão"].contains(role) else { return false }
        let label = destination.label.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return labelAndRole == label
    }

    private func hasSelectedAnnouncement(_ utterance: String) -> Bool {
        let tokens = utterance.lowercased().split { !$0.isLetter && !$0.isNumber }
        let selectionWords = ["selected", "selecionado", "selecionada"]
        for index in tokens.indices where selectionWords.contains(String(tokens[index])) {
            if index > tokens.startIndex && ["not", "não", "nao"].contains(String(tokens[index - 1])) {
                return false
            }
            return true
        }
        return false
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            XCTFail(message)
            throw ProbeFailure.invalidPrecondition(message)
        }
    }

    @MainActor
    private func attach(_ name: String, _ value: String) {
        let attachment = XCTAttachment(string: value)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func record(_ name: String, speech: String, app: XCUIApplication) {
        attach(name + "-speech", speech)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
