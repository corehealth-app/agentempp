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

    @Test("Today meal context is scoped to its sheet and never changes the sheet identity")
    func explicitMealContextIsScopedToMealSheets() {
        for type in MealType.allCases {
            let sheet = AppSheet.registration(.meal, mealType: type)
            #expect(sheet.selectedMealType == type)
            #expect(sheet.id == "sheet.registrar.refeicao")
        }
        #expect(AppSheet.registration(.meal).selectedMealType == nil)
        #expect(AppSheet.registration(.training, mealType: .breakfast).selectedMealType == nil)
        #expect(AppSheet.registration(.weight).selectedMealType == nil)
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

    // MARK: Second update (2026-10-10) — Foto opens the camera by itself
    //
    // The owner, on build 1.0 (3): "mesmo quando eu coloco pra registrar a
    // refeição em audio ou foto, ao inves dele abrir direto, ele abre uma
    // tela q pergunta novamente sobre isso" (RC U1-A1 of the first update).

    @Test("the photo way opens the camera once, by itself, only on a settled sheet")
    func photoWayOpensTheCameraOnceByItselfOnlyOnASettledSheet() {
        func opens(
            entry: MealCaptureEntry? = .photo,
            step: MealLiveCaptureChoice? = .photo,
            cameraAvailable: Bool = true,
            permission: MealCameraAccess.Permission = .notAsked,
            sheetSettled: Bool = true,
            alreadyOpened: Bool = false
        ) -> Bool {
            MealCaptureStart.opensCameraByItself(
                entry: entry, step: step, cameraAvailable: cameraAvailable,
                permission: permission, sheetSettled: sheetSettled, alreadyOpened: alreadyOpened
            )
        }
        // The one case: the photo way, on its step, a camera that was not
        // refused, a sheet that has arrived, nothing opened yet.
        #expect(opens())
        #expect(opens(permission: .authorized))
        // Locks: everything else leaves the step as it is.
        #expect(!opens(sheetSettled: false), "Never while the sheet is still arriving")
        #expect(!opens(cameraAvailable: false), "No camera")
        #expect(!opens(permission: .denied), "A refused camera is not asked again by itself")
        #expect(!opens(alreadyOpened: true), "Once per sheet")
        #expect(!opens(entry: .text))
        #expect(!opens(entry: .audio))
        #expect(!opens(entry: nil), "The card's title and Today's shortcut open the full choice")
        #expect(!opens(step: nil), "After Voltar the full choice is on screen")
        #expect(!opens(step: .text))
        #expect(!opens(step: .record))
        #expect(!opens(entry: .text, step: .text))
        #expect(!opens(entry: .audio, step: .record))
    }

    @Test("after the answer about the camera it is presented only if the photo step is still there")
    func cameraIsPresentedAfterAccessOnlyIfThePhotoStepIsStillThere() {
        func presents(
            granted: Bool = true,
            step: MealLiveCaptureChoice? = .photo,
            galleryShowing: Bool = false,
            importerShowing: Bool = false,
            phaseIsIdle: Bool = true
        ) -> Bool {
            MealCaptureStart.presentsCameraAfterAccess(
                granted: granted, step: step, galleryShowing: galleryShowing,
                importerShowing: importerShowing, phaseIsIdle: phaseIsIdle
            )
        }
        #expect(presents())
        // Locks: nothing is presented, now or later.
        #expect(!presents(granted: false), "Refused at the system's prompt")
        #expect(!presents(step: nil), "The person went back to the full choice")
        #expect(!presents(step: .text))
        #expect(!presents(step: .record))
        #expect(!presents(galleryShowing: true))
        #expect(!presents(importerShowing: true))
        #expect(!presents(phaseIsIdle: false), "A capture is already being prepared or read")
    }

    /// Review of 2026-10-11 (read, not reproduced): two quick touches on
    /// "Tirar foto", or a touch on it before the sheet settles followed by
    /// the opening by itself, asked for the camera twice — and a second
    /// number on a camera that is already on screen closes it to open it
    /// again. Every presentation goes through this one count.
    @Test("a camera that is already on screen is never presented again")
    func aCameraAlreadyOnScreenIsNeverPresentedAgain() {
        var log = MealCameraLog()
        #expect(log.present(whileShowing: false) == 1)
        #expect(log.presentations == 1)

        // Asked for again while it shows: nothing is presented, nothing is
        // counted — however many times.
        #expect(log.present(whileShowing: true) == nil)
        #expect(log.present(whileShowing: true) == nil)
        #expect(log.presentations == 1)

        // Lock: once it has left the screen, "Tirar foto" opens it again,
        // and that is the second time.
        #expect(log.present(whileShowing: false) == 2)
        #expect(log.presentations == 2)
        #expect(!log.openedByItself, "Presenting never writes the mark of the opening by itself")
    }

    /// The sheet's record starts empty: nothing opened, nothing presented.
    @Test("a new sheet has not opened the camera yet")
    func aNewSheetHasNotOpenedTheCameraYet() {
        #expect(MealCameraLog() == MealCameraLog(openedByItself: false, presentations: 0))
        #expect(MealCameraAccess.unavailable.origin == .none)
        #expect(!MealCameraAccess.unavailable.isAvailable())
        #expect(MealCameraAccess.unavailable.permission() == .denied)
    }

    #if DEBUG
    @Test("the synthetic camera exists only when asked with capture and media, and never in Release")
    func syntheticCameraOnlyWhenAskedAndNeverInRelease() async throws {
        let capture = "--ui-testing-meal-capture"
        let media = "--ui-testing-meal-capture-media"
        let camera = "--ui-testing-meal-capture-camera"
        #expect(DemoMealCaptureScenario.cameraArgument == camera)

        // Locks: Release ignores every combination.
        for arguments in [[camera], [capture, camera], [capture, media, camera]] {
            #expect(DemoMealCaptureScenario.capability(
                arguments: arguments, mode: .releaseUnavailable
            ) == nil)
        }
        let release = AppDependencies.make(configuration: AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing", capture, media, camera],
            buildFlavor: .release
        ))
        #expect(release.mealCapture == nil)

        // Locks: without the camera argument the synthetic capture has no
        // camera, so no test raises the system's camera by accident.
        let textOnly = try #require(DemoMealCaptureScenario.capability(arguments: [capture], mode: .demo))
        #expect(textOnly.camera.origin == .none)
        let withMedia = try #require(
            DemoMealCaptureScenario.capability(arguments: [capture, media], mode: .demo)
        )
        #expect(withMedia.camera.origin == .none)
        #expect(!withMedia.camera.isAvailable())
        // Lock: a camera needs the media it would feed.
        let cameraWithoutMedia = try #require(
            DemoMealCaptureScenario.capability(arguments: [capture, camera], mode: .demo)
        )
        #expect(cameraWithoutMedia.camera.origin == .none)

        // New: asked for with capture and media, the stand-in is there and
        // allowed.
        let withCamera = try #require(
            DemoMealCaptureScenario.capability(arguments: [capture, media, camera], mode: .demo)
        )
        #expect(withCamera.camera.origin == .synthetic)
        #expect(withCamera.camera.isAvailable())
        #expect(withCamera.camera.permission() == .authorized)
        let allowed = await withCamera.camera.requestAccess()
        #expect(allowed)
        #expect(withCamera.media != nil)
    }

    /// What the stand-in camera "takes" must reach the upload: a real image,
    /// which the same preparation a real photo goes through accepts.
    @Test("the synthetic camera's photo is a real image")
    func syntheticCameraPhotoIsARealImage() throws {
        let photo = DemoMealCamera.samplePhoto()
        #expect(!photo.isEmpty)
        var normalized: Data?
        var failure: (any Error)?
        do {
            normalized = try MealPhotoNormalizer.normalizedJPEG(from: photo)
        } catch {
            failure = error
        }
        #expect(failure == nil, "The preparation refused the photo: \(String(describing: failure))")
        #expect((normalized?.count ?? 0) > 0)

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("synthetic-camera-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let stager = MealMediaStager(staging: MediaStagingStore(temporaryDirectory: base))
        let staged = try? stager.stagePhoto(photo, channel: .camera)
        #expect((staged?.sizeBytes ?? 0) > 0, "The photo of the stand-in camera is staged as a camera photo")
        #expect(staged?.channel == .camera)
        #expect(staged?.mimeType == "image/jpeg")
    }
    #endif

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
