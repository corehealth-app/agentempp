import SwiftUI

/// Press feedback for card and row links (`NavigationLink`/`Button` wrapping a
/// `BodyFlowCard`): a light dim plus a subtle scale, limited to the content
/// motion duration. Reduce Motion keeps the dim and drops the scale, so the
/// pressed state stays visible without movement.
struct BodyFlowRowButtonStyle: ButtonStyle {
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    /// A row that is a primary action (the Flow shortcut) answers with a
    /// light tap; plain navigation rows stay silent.
    var playsTapFeedback = false

    static func pressedScale(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : BodyFlowMotion.pressedScale
    }

    static func pressedOpacity(isPressed: Bool) -> Double {
        isPressed ? BodyFlowOpacity.pressed : 1
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(Self.pressedOpacity(isPressed: configuration.isPressed))
            .scaleEffect(
                configuration.isPressed
                    ? Self.pressedScale(reduceMotion: reduceMotion)
                    : 1
            )
            .animation(
                BodyFlowMotion.animation(.tap, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
            .sensoryFeedback(trigger: configuration.isPressed) { _, pressed in
                pressed && playsTapFeedback ? BodyFlowHaptics.Tap.action : nil
            }
    }
}

extension ButtonStyle where Self == BodyFlowRowButtonStyle {
    static var bodyFlowRow: BodyFlowRowButtonStyle { BodyFlowRowButtonStyle() }
    /// A primary action laid out as a row.
    static var bodyFlowRowAction: BodyFlowRowButtonStyle { BodyFlowRowButtonStyle(playsTapFeedback: true) }
}
