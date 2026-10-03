import SwiftUI

enum BodyFlowMotion {
    static func duration(reduceMotion: Bool, disclosure: Bool) -> Double {
        reduceMotion ? 0 : 0.22
    }

    enum Kind: Sendable {
        /// State replacement and content fades (220 ms).
        case content
        /// Native disclosure expand/collapse (220 ms).
        case disclosure
        /// Card/row press feedback; critically damped so nothing overshoots.
        case press
        /// Button press and release: a short spring with a small settle, so
        /// the control answers the finger and springs back (Eduardo, 02/10:
        /// "não tem transição quando toco nos botões").
        case tap
        case brand
        /// A ring or meter filling to an official value when the data lands
        /// (direction v2: 600 ms spring, finite, event-driven).
        case sweep
        /// Navigation between tabs and bubbles arriving (direction v2: a
        /// 300 ms spring, finite, event-driven).
        case navigation
    }

    /// Scale applied to a pressed card/row. Reduce Motion removes it.
    static let pressedScale: CGFloat = 0.98
    /// Scale applied to a pressed button (slightly deeper than a row, which
    /// is a larger surface). Reduce Motion removes it.
    static let tapScale: CGFloat = 0.96

    /// `nil` means "no animation": callers pass it straight to
    /// `withAnimation` / `.animation(_:value:)` so Reduce Motion collapses
    /// every kind to an instant change.
    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch kind {
        case .content:
            return .easeOut(duration: duration(reduceMotion: false, disclosure: false))
        case .disclosure:
            return .easeInOut(duration: duration(reduceMotion: false, disclosure: true))
        case .press:
            return .easeOut(duration: 0.14)
        case .tap:
            return .spring(duration: 0.18, bounce: 0.25)
        case .brand:
            return .easeInOut(duration: 0.40)
        case .sweep:
            return .spring(duration: 0.60, bounce: 0.15)
        case .navigation:
            return .spring(duration: 0.30, bounce: 0.15)
        }
    }

    /// Transition for loading ↔ content ↔ state replacements.
    static func stateTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }
}
