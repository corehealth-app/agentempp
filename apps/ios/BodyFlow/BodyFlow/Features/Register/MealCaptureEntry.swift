import Foundation

/// The way of telling the meal that the person already chose on the Register
/// screen (the three buttons of the meal card). Everywhere else there is no
/// entry and the sheet opens on its full choice, as it always did.
enum MealCaptureEntry: String, CaseIterable, Hashable, Sendable {
    case photo, text, audio

    /// The identifier of the button of this way on the meal card.
    var commandAccessibilityIdentifier: String {
        switch self {
        case .photo: "register.refeicao.foto"
        case .text: "register.refeicao.texto"
        case .audio: "register.refeicao.audio"
        }
    }
}

/// Where a meal capture starts. Pure decisions, so each one is tested
/// without a screen.
enum MealCaptureStart {
    /// A real account: the step the capture opens on; `nil` is the full
    /// choice. Photo and audio need media: without it the person lands on
    /// the choice, which says that media is not available.
    static func liveChoice(
        entry: MealCaptureEntry?,
        supportsMedia: Bool
    ) -> MealLiveCaptureChoice? {
        switch entry {
        case .text: .text
        case .photo: supportsMedia ? .photo : nil
        case .audio: supportsMedia ? .record : nil
        case nil: nil
        }
    }

    /// The local demonstration opens on its own samples. Without the
    /// demonstration (a real account whose capture is not available) no
    /// local sample is ever offered: only text keeps its step.
    static func demonstrationChoice(
        entry: MealCaptureEntry?,
        presentsLocalDemonstration: Bool
    ) -> MealCaptureChoice? {
        switch entry {
        case .text: .text
        case .photo: presentsLocalDemonstration ? .photo : nil
        case .audio: presentsLocalDemonstration ? .audio : nil
        case nil: nil
        }
    }

    /// A real account: the text field takes the keyboard as soon as its step
    /// is on a sheet that has finished arriving — on the direct entry and
    /// after "Escrever" alike. Never while the sheet is still moving.
    static func focusesText(isTextStep: Bool, sheetSettled: Bool) -> Bool {
        isTextStep && sheetSettled
    }

    /// The local demonstration: only the direct entry raises the keyboard.
    /// Choosing "Texto" inside its choice keeps the sample text unfocused.
    static func focusesDemonstrationText(
        entry: MealCaptureEntry?,
        sheetSettled: Bool
    ) -> Bool {
        entry == .text && sheetSettled
    }

    /// "Foto" opens the camera by itself (asked for by the owner on
    /// 2026-10-10: "ao inves dele abrir direto, ele abre uma tela q pergunta
    /// novamente sobre isso"): once per sheet, only on the photo way's own
    /// step, only when there is a camera the person has not refused, and
    /// only on a sheet that has finished arriving.
    static func opensCameraByItself(
        entry: MealCaptureEntry?,
        step: MealLiveCaptureChoice?,
        cameraAvailable: Bool,
        permission: MealCameraAccess.Permission,
        sheetSettled: Bool,
        alreadyOpened: Bool
    ) -> Bool {
        entry == .photo && step == .photo && cameraAvailable
            && permission != .denied && sheetSettled && !alreadyOpened
    }

    /// The answer about the camera can come late (the system's prompt): the
    /// camera is presented only if it was allowed AND the person is still
    /// on the photo step with nothing else open and nothing being prepared.
    /// Otherwise nothing is presented, now or later.
    static func presentsCameraAfterAccess(
        granted: Bool,
        step: MealLiveCaptureChoice?,
        galleryShowing: Bool,
        importerShowing: Bool,
        phaseIsIdle: Bool
    ) -> Bool {
        granted && step == .photo && !galleryShowing && !importerShowing && phaseIsIdle
    }
}

/// What happened with the camera along ONE sheet. It lives with the sheet,
/// above the capture view, so a capture view that is built again on the same
/// sheet can never open the camera by itself a second time.
struct MealCameraLog: Equatable, Sendable {
    /// The camera was already asked for by itself on this sheet.
    var openedByItself = false
    /// How many times the camera was presented on this sheet.
    var presentations = 0

    /// Counts one more presentation of the camera and gives its number on
    /// the sheet (1, 2, …) — or `nil`, counting nothing, when the camera is
    /// already on screen: asking for it again while it shows (two quick
    /// touches on "Tirar foto", or a touch before the sheet settles followed
    /// by the opening by itself) never closes the camera to open it again.
    mutating func present(whileShowing showing: Bool) -> Int? {
        guard !showing else { return nil }
        presentations += 1
        return presentations
    }
}
