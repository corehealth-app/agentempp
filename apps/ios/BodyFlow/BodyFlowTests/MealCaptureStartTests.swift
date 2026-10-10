import Foundation
import Testing
import UIKit

@testable import BodyFlow

/// Asked for on 2026-10-10 (build 1.0 (3), real account): choosing Foto,
/// Texto or Áudio on the meal card opened a sheet that asked the same
/// question again. These are the decisions that send each way straight to
/// its own step, and keep every older path where it was.
@Suite("Where a meal capture starts")
@MainActor
struct MealCaptureStartTests {
    @Test("on a real account each way opens its own step; without media, the choice that says so")
    func directEntryChoosesItsOwnStep() {
        #expect(MealCaptureStart.liveChoice(entry: .text, supportsMedia: true) == .text)
        #expect(MealCaptureStart.liveChoice(entry: .text, supportsMedia: false) == .text)
        #expect(MealCaptureStart.liveChoice(entry: .photo, supportsMedia: true) == .photo)
        #expect(MealCaptureStart.liveChoice(entry: .audio, supportsMedia: true) == .record)
        // Locks: without media the person lands on the choice, which says
        // that media is not available; no entry is the full choice.
        #expect(MealCaptureStart.liveChoice(entry: .photo, supportsMedia: false) == nil)
        #expect(MealCaptureStart.liveChoice(entry: .audio, supportsMedia: false) == nil)
        #expect(MealCaptureStart.liveChoice(entry: nil, supportsMedia: true) == nil)
        #expect(MealCaptureStart.liveChoice(entry: nil, supportsMedia: false) == nil)
    }

    @Test("the local demonstration opens on its own samples; a real account never gets one")
    func demonstrationKeepsItsLocalSamples() {
        #expect(MealCaptureStart.demonstrationChoice(entry: .text, presentsLocalDemonstration: true) == .text)
        #expect(MealCaptureStart.demonstrationChoice(entry: .photo, presentsLocalDemonstration: true) == .photo)
        #expect(MealCaptureStart.demonstrationChoice(entry: .audio, presentsLocalDemonstration: true) == .audio)
        #expect(MealCaptureStart.demonstrationChoice(entry: .text, presentsLocalDemonstration: false) == .text)
        // Locks.
        #expect(MealCaptureStart.demonstrationChoice(entry: nil, presentsLocalDemonstration: true) == nil)
        #expect(MealCaptureStart.demonstrationChoice(entry: nil, presentsLocalDemonstration: false) == nil)
        #expect(MealCaptureStart.demonstrationChoice(entry: .photo, presentsLocalDemonstration: false) == nil)
        #expect(MealCaptureStart.demonstrationChoice(entry: .audio, presentsLocalDemonstration: false) == nil)
    }

    @Test("the text field takes the keyboard only on a sheet that has finished arriving")
    func textIsFocusedOnlyOnASettledSheet() {
        // A real account: the direct entry and "Escrever" alike.
        #expect(MealCaptureStart.focusesText(isTextStep: true, sheetSettled: true))
        #expect(!MealCaptureStart.focusesText(isTextStep: true, sheetSettled: false))
        #expect(!MealCaptureStart.focusesText(isTextStep: false, sheetSettled: true))
        #expect(!MealCaptureStart.focusesText(isTextStep: false, sheetSettled: false))
        // The local demonstration: only the direct entry.
        #expect(MealCaptureStart.focusesDemonstrationText(entry: .text, sheetSettled: true))
        #expect(!MealCaptureStart.focusesDemonstrationText(entry: .text, sheetSettled: false))
        #expect(!MealCaptureStart.focusesDemonstrationText(entry: nil, sheetSettled: true))
        #expect(!MealCaptureStart.focusesDemonstrationText(entry: .photo, sheetSettled: true))
        #expect(!MealCaptureStart.focusesDemonstrationText(entry: .audio, sheetSettled: true))
    }

    /// Lock: the sheet is the same sheet whatever the entry, so every test
    /// that waits for `sheet.registrar.refeicao` keeps meaning what it meant.
    @Test("the entry never changes the identity of the sheet")
    func sheetIdentifierIsUnchangedByTheEntry() {
        #expect(AppSheet.registration(.meal).id == "sheet.registrar.refeicao")
        for entry in MealCaptureEntry.allCases {
            #expect(AppSheet.registration(.meal, mealEntry: entry).id == "sheet.registrar.refeicao")
        }
        #expect(MealCaptureEntry.allCases.map(\.commandAccessibilityIdentifier) == [
            "register.refeicao.foto", "register.refeicao.texto", "register.refeicao.audio",
        ])
    }

    @Test("the sheet says it has arrived once, and only after it appeared")
    func settledProbeCallsBackOnceAndOnlyAfterTheScreenAppeared() {
        let calls = SettledCalls()
        let controller = MealSheetSettledProbeController { calls.count += 1 }
        controller.loadViewIfNeeded()

        controller.beginAppearanceTransition(true, animated: false)
        #expect(calls.count == 0, "Nothing is told while the sheet is still arriving")
        controller.endAppearanceTransition()
        #expect(calls.count == 1)

        // Coming back from a full-screen cover appears again: told once only.
        controller.beginAppearanceTransition(false, animated: false)
        controller.endAppearanceTransition()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        #expect(calls.count == 1)
    }

    #if DEBUG
    /// The synthetic capture is chosen by a pure function over the launch
    /// arguments (they are the process's, not the configuration's), so both
    /// build flavours are proven here and not by an empty pass.
    @Test("the synthetic capture offers media only when asked, and never in Release")
    func syntheticCaptureOffersMediaOnlyWhenAskedAndNeverInRelease() throws {
        let capture = "--ui-testing-meal-capture"
        let media = "--ui-testing-meal-capture-media"

        // Locks: Release ignores every combination.
        for arguments in [[], [capture], [media], [capture, media]] {
            #expect(DemoMealCaptureScenario.capability(
                arguments: arguments, mode: .releaseUnavailable
            ) == nil)
        }
        let release = AppDependencies.make(configuration: AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing", capture, media],
            buildFlavor: .release
        ))
        #expect(release.mealCapture == nil)

        // Locks: the demonstration without the capture argument has none,
        // and the capture argument alone reads text only, as before.
        #expect(DemoMealCaptureScenario.capability(arguments: [], mode: .demo) == nil)
        #expect(DemoMealCaptureScenario.capability(arguments: [media], mode: .demo) == nil)
        let textOnly = try #require(
            DemoMealCaptureScenario.capability(arguments: [capture], mode: .demo)
        )
        #expect(textOnly.media == nil)
        #expect(textOnly.uploader == nil)

        // New: asked for, the media entries are offered (and refuse to send).
        let withMedia = try #require(
            DemoMealCaptureScenario.capability(arguments: [capture, media], mode: .demo)
        )
        #expect(withMedia.media != nil)
        #expect(withMedia.uploader != nil)
    }

    /// The reader that never answers (so a UI test can look at the wait) is
    /// chosen by the same pure function: Debug demonstration only.
    @Test("the holding reader is Debug-demonstration only")
    func holdingReaderIsDebugDemoOnly() throws {
        let capture = "--ui-testing-meal-capture"
        let hold = "--ui-testing-meal-capture-hold"
        #expect(DemoMealCaptureScenario.capability(
            arguments: [capture, hold], mode: .releaseUnavailable
        ) == nil)
        #expect(DemoMealCaptureScenario.capability(arguments: [hold], mode: .demo) == nil)

        let plain = try #require(DemoMealCaptureScenario.capability(arguments: [capture], mode: .demo))
        #expect((plain.drafts as? DemoMealDraftProvider)?.holdsUntilCancelled == false)
        let holding = try #require(
            DemoMealCaptureScenario.capability(arguments: [capture, hold], mode: .demo)
        )
        #expect((holding.drafts as? DemoMealDraftProvider)?.holdsUntilCancelled == true)
    }
    #endif
}

@MainActor
private final class SettledCalls {
    var count = 0
}
