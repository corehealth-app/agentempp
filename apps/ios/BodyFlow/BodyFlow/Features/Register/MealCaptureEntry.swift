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
}
