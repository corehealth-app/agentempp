import SwiftUI

enum BodyFlowMotion {
    static func duration(reduceMotion: Bool, disclosure: Bool) -> Double {
        reduceMotion ? 0 : (disclosure ? 0.25 : 0.20)
    }

    enum Kind: Sendable {
        /// State replacement and content fades (≤200 ms).
        case content
        /// Native disclosure expand/collapse (≤250 ms).
        case disclosure
        /// Card/row press feedback; critically damped so nothing overshoots.
        case press
    }

    /// Scale applied to a pressed card/row. Reduce Motion removes it.
    static let pressedScale: CGFloat = 0.98

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
            return .spring(duration: duration(reduceMotion: false, disclosure: false), bounce: 0)
        }
    }

    /// Transition for loading ↔ content ↔ state replacements.
    static func stateTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }
}
